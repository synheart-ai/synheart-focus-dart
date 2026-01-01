import 'dart:math' as math;

/// Feature vector for model input (24 features)
class HRVFeatureVector {
  final List<double> values; // schema order (24 features)
  final Map<String, double> namedFeatures; // named features for debugging
  const HRVFeatureVector(this.values, this.namedFeatures);
}

/// HRV Feature extractor matching Python HRVInference.extract_hrv_features()
///
/// ⚠️ IMPORTANT SCIENTIFIC NOTES:
///
/// 1. Normalization Order: This extractor expects NORMALIZED IBIs (z-score normalized).
///    Features extracted from normalized IBIs are dimensionless and lose physiological units.
///    This matches the Python training pipeline but has scientific limitations.
///
/// 2. NN50/pNN50: With HR-derived IBIs at 1 Hz sampling, NN50 becomes noisy and unreliable.
///    These features are included for model compatibility but should be interpreted cautiously.
///
/// 3. Frequency Domain: Properly interpolates irregular IBI intervals to uniform 4 Hz grid
///    before applying Welch's method for PSD estimation.
///
/// 4. UHF Band (0.40-1.00 Hz): Included for model compatibility, but UHF is mostly noise
///    with HR-derived IBIs and is rarely used in ECG-grade HRV analysis.
///
/// Extracts 24 features:
/// - Time domain (9): mean_rr, std_rr, min_rr, max_rr, range_rr, rmssd, sdnn, nn50, pnn50
/// - Frequency domain (11): VLF, LF, HF, UHF powers, total_power, lf_hf_ratio, normalized powers
/// - Statistical (4): skewness, kurtosis, median_rr, iqr
class HRVFeatureExtractor24 {
  /// Sampling frequency for frequency domain analysis (Hz)
  static const double fs = 4.0;

  /// Frequency bands matching Python implementation
  static const Map<String, List<double>> freqBands = {
    'VLF': [0.003, 0.04],
    'LF': [0.04, 0.15],
    'HF': [0.15, 0.40],
    'UHF': [0.40, 1.00],
  };

  /// Feature schema matching Python metadata
  static const schema = [
    "mean_rr",
    "std_rr",
    "min_rr",
    "max_rr",
    "range_rr",
    "rmssd",
    "sdnn",
    "nn50",
    "pnn50",
    "vlf_power",
    "lf_power",
    "hf_power",
    "uhf_power",
    "total_power",
    "lf_hf_ratio",
    "vlf_norm",
    "lf_norm",
    "hf_norm",
    "uhf_norm",
    "normalized_lf",
    "skewness",
    "kurtosis_val",
    "median_rr",
    "iqr",
  ];

  /// Extract 24 HRV features from IBI intervals (in milliseconds)
  ///
  /// Input: ibi_ms - list of inter-beat intervals in milliseconds
  /// Returns: HRVFeatureVector with 24 features
  HRVFeatureVector extractHRVFeatures(List<double> ibiMs) {
    // Convert IBI from ms to seconds (rr)
    final rr = ibiMs.map((x) => x / 1000.0).toList();

    if (rr.isEmpty) {
      throw ArgumentError('Empty RR intervals');
    }

    final diffRr = <double>[];
    for (int i = 1; i < rr.length; i++) {
      diffRr.add(rr[i] - rr[i - 1]);
    }

    // ---------------- TIME DOMAIN (9) ----------------
    final meanRr = _mean(rr);
    final stdRr = _std(rr);
    final minRr = rr.reduce((a, b) => a < b ? a : b);
    final maxRr = rr.reduce((a, b) => a > b ? a : b);
    final rangeRr = maxRr - minRr;

    // RMSSD: Root mean square of successive differences
    final rmssd = diffRr.isEmpty
        ? 0.0
        : math.sqrt(
            diffRr.map((d) => d * d).reduce((a, b) => a + b) / diffRr.length,
          );

    // SDNN: Standard deviation of RR intervals (same as std_rr)
    final sdnn = stdRr;

    // NN50: Number of pairs of successive NN intervals differing by more than 50ms
    // ⚠️ NOTE: With HR-derived IBIs at 1 Hz sampling, NN50 is noisy and unreliable.
    // This is included for model compatibility but should be interpreted cautiously.
    final nn50 = diffRr.where((d) => d.abs() > 0.05).length;

    // pNN50: Percentage of NN50
    final pnn50 = diffRr.isEmpty ? 0.0 : (nn50 / diffRr.length) * 100.0;

    final timeFeats = [
      meanRr,
      stdRr,
      minRr,
      maxRr,
      rangeRr,
      rmssd,
      sdnn,
      nn50.toDouble(),
      pnn50,
    ];

    // ---------------- FREQUENCY DOMAIN (11) ----------------
    // Resample RR intervals to uniform time grid at 4 Hz
    // This is REQUIRED: irregular IBI intervals must be interpolated
    // to a uniform grid before applying Welch's method for PSD estimation.
    final t = <double>[0.0];
    for (int i = 1; i < rr.length; i++) {
      t.add(t[i - 1] + rr[i - 1]);
    }

    if (t.isEmpty || t.last <= 0) {
      // Fallback: use zero power for all bands
      final freqFeats = List.filled(11, 0.0);
      final statFeats = _computeStatisticalFeatures(rr);
      final allFeats = [...timeFeats, ...freqFeats, ...statFeats];
      return _createFeatureVector(allFeats);
    }

    // Create uniform time grid at fs Hz
    final uniformT = <double>[];
    for (double time = 0.0; time < t.last; time += 1.0 / fs) {
      uniformT.add(time);
    }

    if (uniformT.isEmpty) {
      final freqFeats = List.filled(11, 0.0);
      final statFeats = _computeStatisticalFeatures(rr);
      final allFeats = [...timeFeats, ...freqFeats, ...statFeats];
      return _createFeatureVector(allFeats);
    }

    // Interpolate RR values to uniform grid
    final interpRr = _interpolate(t, rr, uniformT);

    // Remove mean (detrend)
    final meanInterp = _mean(interpRr);
    final detrendedRr = interpRr.map((x) => x - meanInterp).toList();

    // Compute power spectral density using Welch's method
    final psdResult = _welch(
      detrendedRr,
      fs: fs,
      nperseg: math.min(256, detrendedRr.length),
    );
    final freqs = psdResult['freqs'] as List<double>;
    final psd = psdResult['psd'] as List<double>;

    // Compute power in each frequency band
    final powers = <String, double>{};
    for (final entry in freqBands.entries) {
      final band = entry.key;
      final lo = entry.value[0];
      final hi = entry.value[1];

      // ⚠️ NOTE: UHF band (0.40-1.00 Hz) is included for model compatibility,
      // but is mostly noise with HR-derived IBIs and rarely used in ECG-grade HRV analysis.

      double power = 0.0;
      for (int i = 0; i < freqs.length; i++) {
        if (freqs[i] >= lo && freqs[i] <= hi) {
          // Trapezoidal integration
          if (i > 0) {
            final df = freqs[i] - freqs[i - 1];
            power += (psd[i] + psd[i - 1]) * df / 2.0;
          }
        }
      }
      powers[band] = power;
    }

    final totalPower = powers.values.fold(0.0, (a, b) => a + b);
    final lfHfRatio = powers['HF']! > 0 ? powers['LF']! / powers['HF']! : 0.0;

    final freqFeats = [
      powers['VLF']!,
      powers['LF']!,
      powers['HF']!,
      powers['UHF']!,
      totalPower,
      lfHfRatio,
      totalPower > 0 ? (powers['VLF']! / totalPower) * 100.0 : 0.0,
      totalPower > 0 ? (powers['LF']! / totalPower) * 100.0 : 0.0,
      totalPower > 0 ? (powers['HF']! / totalPower) * 100.0 : 0.0,
      totalPower > 0 ? (powers['UHF']! / totalPower) * 100.0 : 0.0,
      (powers['LF']! + powers['HF']!) > 0
          ? (powers['LF']! / (powers['LF']! + powers['HF']!)) * 100.0
          : 0.0,
    ];

    // ---------------- STATISTICAL (4) ----------------
    final statFeats = _computeStatisticalFeatures(rr);

    final allFeats = [...timeFeats, ...freqFeats, ...statFeats];

    if (allFeats.length != 24) {
      throw StateError('Expected 24 features, got ${allFeats.length}');
    }

    return _createFeatureVector(allFeats);
  }

  /// Compute statistical features: skewness, kurtosis, median, IQR
  List<double> _computeStatisticalFeatures(List<double> rr) {
    final sortedRr = List<double>.from(rr)..sort();

    // Skewness
    final mean = _mean(rr);
    final std = _std(rr);
    final skewness = std > 0
        ? rr.map((x) => math.pow((x - mean) / std, 3)).reduce((a, b) => a + b) /
            rr.length
        : 0.0;

    // Kurtosis
    final kurtosis = std > 0
        ? rr.map((x) => math.pow((x - mean) / std, 4)).reduce((a, b) => a + b) /
                rr.length -
            3.0
        : 0.0;

    // Median
    final median = sortedRr.length % 2 == 1
        ? sortedRr[sortedRr.length ~/ 2]
        : (sortedRr[sortedRr.length ~/ 2 - 1] +
                sortedRr[sortedRr.length ~/ 2]) /
            2.0;

    // IQR (Interquartile Range)
    final q1Idx = sortedRr.length ~/ 4;
    final q3Idx = (3 * sortedRr.length) ~/ 4;
    final q1 = sortedRr[q1Idx];
    final q3 = sortedRr[q3Idx];
    final iqr = q3 - q1;

    return [skewness, kurtosis, median, iqr];
  }

  /// Create feature vector with named features
  HRVFeatureVector _createFeatureVector(List<double> features) {
    final namedFeatures = <String, double>{};
    for (int i = 0; i < schema.length && i < features.length; i++) {
      namedFeatures[schema[i]] = features[i];
    }
    return HRVFeatureVector(features, namedFeatures);
  }

  /// Compute mean
  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Compute standard deviation
  double _std(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = _mean(values);
    final variance =
        values.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) /
            (values.length - 1);
    return math.sqrt(variance);
  }

  /// Linear interpolation
  List<double> _interpolate(List<double> x, List<double> y, List<double> xNew) {
    if (x.length != y.length || x.length < 2) {
      throw ArgumentError('Invalid interpolation input');
    }

    final yNew = <double>[];
    for (final xVal in xNew) {
      if (xVal <= x.first) {
        yNew.add(y.first);
      } else if (xVal >= x.last) {
        yNew.add(y.last);
      } else {
        // Find surrounding points
        int i = 0;
        while (i < x.length - 1 && x[i + 1] < xVal) {
          i++;
        }
        // Linear interpolation
        final x0 = x[i];
        final x1 = x[i + 1];
        final y0 = y[i];
        final y1 = y[i + 1];
        final t = (xVal - x0) / (x1 - x0);
        yNew.add(y0 + t * (y1 - y0));
      }
    }
    return yNew;
  }

  /// Welch's method for power spectral density estimation
  /// Simplified implementation matching scipy.signal.welch
  Map<String, List<double>> _welch(
    List<double> data, {
    required double fs,
    int nperseg = 256,
  }) {
    if (data.length < nperseg) {
      nperseg = data.length;
    }
    if (nperseg < 4) {
      // Too short for FFT, return zero PSD
      return {
        'freqs': [0.0],
        'psd': [0.0],
      };
    }

    // Use FFT to compute power spectral density
    // Simplified: use single segment with Hann window
    final windowed = _applyHannWindow(data.take(nperseg).toList());
    final fftResult = _fft(windowed, fs: fs);
    final freqs = fftResult['freqs'] as List<double>;
    final psd = fftResult['psd'] as List<double>;

    // Scale by sampling frequency
    final scaledPsd = psd.map((p) => p / fs).toList();

    return {'freqs': freqs, 'psd': scaledPsd};
  }

  /// Apply Hann window
  List<double> _applyHannWindow(List<double> data) {
    final n = data.length;
    final windowed = <double>[];
    for (int i = 0; i < n; i++) {
      final window = 0.5 * (1 - math.cos(2 * math.pi * i / (n - 1)));
      windowed.add(data[i] * window);
    }
    return windowed;
  }

  /// Simplified FFT for power spectral density
  /// Returns frequencies and power spectral density
  Map<String, List<double>> _fft(List<double> data, {required double fs}) {
    final n = data.length;
    final freqs = <double>[];
    final psd = <double>[];

    // Compute DFT (simplified, not optimized)
    for (int k = 0; k < n ~/ 2 + 1; k++) {
      final freq = k * fs / n;
      freqs.add(freq);

      double real = 0.0;
      double imag = 0.0;
      for (int j = 0; j < n; j++) {
        final angle = -2 * math.pi * k * j / n;
        real += data[j] * math.cos(angle);
        imag += data[j] * math.sin(angle);
      }

      // Power = |FFT|^2 / n
      final power = (real * real + imag * imag) / n;
      psd.add(power);
    }

    return {'freqs': freqs, 'psd': psd};
  }
}
