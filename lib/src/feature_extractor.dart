import 'dart:math';

/// Feature vector for model input
class FeatureVector {
  final List<double> values; // schema order
  final Map<String, double> namedFeatures; // named features for debugging
  const FeatureVector(this.values, this.namedFeatures);
}

/// Feature extractor for Focus detection
/// 
/// Extracts top 6 features used in focus training (matching Python SDK):
/// 1. MEDIAN_RR - Median RR interval
/// 2. HR - Heart rate (mean)
/// 3. MEAN_RR - Mean RR interval
/// 4. SDRR_RMSSD - Standard deviation of RR intervals (SDNN)
/// 5. pNN25 - Percentage of NN intervals differing by >25ms
/// 6. higuci - Higuchi fractal dimension (HRV complexity measure)
class FeatureExtractor {
  /// Feature schema matching Python SDK training script order
  static const schema = [
    "MEDIAN_RR",
    "HR",
    "MEAN_RR",
    "SDRR_RMSSD",
    "pNN25",
    "higuci",
  ];

  // Constants matching Python SDK FeatureExtractor
  static const double minValidRrMs = 300.0;  // 300ms = 200 BPM
  static const double maxValidRrMs = 2000.0; // 2000ms = 30 BPM
  static const double maxRrJumpMs = 250.0;  // Maximum allowed jump between successive RR intervals
  static const double minValidHr = 30.0;     // Minimum valid HR in BPM
  static const double maxValidHr = 300.0;    // Maximum valid HR in BPM

  /// Generate features expected by the Focus model
  ///
  /// Returns `null` when insufficient RR data is available to compute the
  /// required HRV features.
  /// 
  /// Matches Python SDK FeatureExtractor.extract_features() logic
  FeatureVector? toFeatures({
    required List<double> rrIntervalsMs,
    required double hrMean,
    double? motionMagnitude,
  }) {
    // Validate HR
    if (hrMean < minValidHr || hrMean > maxValidHr) {
      return null;
    }

    if (rrIntervalsMs.isEmpty) {
      return null;
    }

    // Clean RR intervals (matching Python SDK _clean_rr_intervals)
    final cleanedRr = _cleanRrIntervals(rrIntervalsMs);
    
    // Need at least some RR intervals (Python SDK doesn't enforce minimum here,
    // but we'll check in the engine for min_rr_count)
    if (cleanedRr.isEmpty) {
      return null;
    }

    // Extract features matching Python SDK FeatureExtractor.extract_features()
    // 1. MEDIAN_RR
    final medianRr = _computeMedian(cleanedRr);

    // 2. HR (mean of HR values - already provided as hrMean)
    final hr = hrMean;

    // 3. MEAN_RR
    final meanRr = cleanedRr.reduce((a, b) => a + b) / cleanedRr.length;

    // 4. SDRR_RMSSD (using SDNN as SDRR, matching Python SDK)
    // Python SDK uses: extract_sdnn() for SDRR_RMSSD
    final sdrrRmssd = _computeSdnn(cleanedRr);

    // 5. pNN25
    final pnn25 = _computePnn25(cleanedRr);

    // 6. higuci (Higuchi fractal dimension)
    final higuci = _computeHiguchi(cleanedRr);

    // Validate all features
    if (medianRr.isNaN || hr.isNaN || meanRr.isNaN || 
        sdrrRmssd.isNaN || pnn25.isNaN || higuci.isNaN) {
      return null;
    }

    final values = [
      medianRr,
      hr,
      meanRr,
      sdrrRmssd,
      pnn25,
      higuci,
    ];

    final namedFeatures = {
      'MEDIAN_RR': medianRr,
      'HR': hr,
      'MEAN_RR': meanRr,
      'SDRR_RMSSD': sdrrRmssd,
      'pNN25': pnn25,
      'higuci': higuci,
    };

    return FeatureVector(values, namedFeatures);
  }

  /// Clean RR intervals by removing invalid values and artifacts
  /// Matching Python SDK FeatureExtractor._clean_rr_intervals()
  List<double> _cleanRrIntervals(List<double> rrIntervalsMs) {
    if (rrIntervalsMs.isEmpty) return [];

    final cleaned = <double>[];
    double? prevValue;

    for (final rr in rrIntervalsMs) {
      // Skip outliers outside physiological range
      if (rr < minValidRrMs || rr > maxValidRrMs) {
        continue;
      }

      // Skip large jumps that likely indicate artifacts
      if (prevValue != null && (rr - prevValue).abs() > maxRrJumpMs) {
        continue;
      }

      cleaned.add(rr);
      prevValue = rr;
    }

    return cleaned;
  }

  /// Compute SDNN (standard deviation of NN intervals)
  /// Matching Python SDK FeatureExtractor.extract_sdnn()
  /// Uses sample std (N-1 denominator)
  double _computeSdnn(List<double> rrIntervalsMs) {
    if (rrIntervalsMs.length < 2) return 0.0;

    final mean = rrIntervalsMs.reduce((a, b) => a + b) / rrIntervalsMs.length;
    final variance = rrIntervalsMs
        .map((x) => (x - mean) * (x - mean))
        .reduce((a, b) => a + b) / (rrIntervalsMs.length - 1); // Sample std (N-1)

    return sqrt(variance);
  }

  /// Compute median of a list
  /// Matching Python SDK np.median()
  double _computeMedian(List<double> values) {
    if (values.isEmpty) return 0.0;
    
    final sorted = List<double>.from(values)..sort();
    final n = sorted.length;
    if (n % 2 == 1) {
      return sorted[n ~/ 2];
    } else {
      return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
    }
  }

  /// Compute pNN25 - percentage of NN intervals differing by >25ms
  double _computePnn25(List<double> rr) {
    if (rr.length < 2) return 0.0;
    int count = 0;
    for (var i = 1; i < rr.length; i++) {
      if ((rr[i] - rr[i - 1]).abs() > 25.0) {
        count++;
      }
    }
    return (count / (rr.length - 1)) * 100.0;
  }

  /// Compute Higuchi fractal dimension
  /// 
  /// Measures the complexity/fractal dimension of the RR interval series.
  /// Higher values indicate more complex/irregular patterns.
  double _computeHiguchi(List<double> rr, {int maxK = 10}) {
    if (rr.length < maxK) return 0.0;
    
    final n = rr.length;
    final lk = <double>[];
    
    for (int k = 1; k <= maxK; k++) {
      double sum = 0.0;
      for (int m = 1; m <= k; m++) {
        double lmk = 0.0;
        int count = 0;
        
        for (int i = 1; i <= ((n - m) / k).floor(); i++) {
          final idx = m + (i - 1) * k;
          if (idx < n && idx - k >= 0) {
            lmk += (rr[idx] - rr[idx - k]).abs();
            count++;
          }
        }
        
        if (count > 0) {
          lmk = lmk * (n - 1) / (count * k * k);
          sum += lmk;
        }
      }
      
      if (k > 0) {
        lk.add(sum / k);
      }
    }
    
    if (lk.isEmpty) return 0.0;
    
    // Compute fractal dimension using linear regression on log-log plot
    // HFD = slope of log(L(k)) vs log(1/k)
    final logK = lk.asMap().entries.map((e) => 
        log(1.0 / (e.key + 1))).toList();
    final logL = lk.map((l) => log(l > 0 ? l : 0.001)).toList();
    
    // Simple linear regression
    final nPoints = logK.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    
    for (int i = 0; i < nPoints; i++) {
      sumX += logK[i];
      sumY += logL[i];
      sumXY += logK[i] * logL[i];
      sumX2 += logK[i] * logK[i];
    }
    
    final denominator = nPoints * sumX2 - sumX * sumX;
    if (denominator.abs() < 1e-10) return 0.0;
    
    final slope = (nPoints * sumXY - sumX * sumY) / denominator;
    
    // Higuchi fractal dimension
    return slope.abs();
  }
}

