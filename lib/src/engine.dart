import 'dart:async';
import 'dart:math' as math;
import 'scorer.dart';
import 'config.dart';
import 'models/on_device_model.dart';
import 'models/model_factory.dart';
import 'models/onnx_runtime.dart';
import 'feature_extractor.dart';
import 'hrv_feature_extractor_24.dart';
import 'models.dart';

/// Helper class for timestamped values
class _TimestampedValue {
  final DateTime timestamp;
  final double value;
  _TimestampedValue(this.timestamp, this.value);
}

/// Core engine for cognitive concentration inference
///
/// Merges functionality from both focus-core-dart and synheart-focus-dart
class FocusEngine {
  final FocusConfig config;

  double? _previousScore;
  DateTime _lastUpdate = DateTime.now().toUtc();

  /// Callback for logging/debugging
  void Function(String level, String message, {Map<String, dynamic>? context})?
      onLog;

  /// Model for inference
  OnDeviceModel? _model;

  /// Feature extractor (old 6-feature extractor)
  final FeatureExtractor _featureExtractor = FeatureExtractor();

  /// HRV feature extractor (new 24-feature extractor)
  final HRVFeatureExtractor24 _hrvFeatureExtractor = HRVFeatureExtractor24();

  /// Window buffer for HR data (stores timestamped HR values)
  final List<_TimestampedValue> _hrBuffer = [];
  DateTime? _lastWindowTime;
  DateTime? _firstDataTime; // Track when we started collecting data

  /// Subject-specific statistics for z-score normalization
  final List<double> _subjectIbiHistory = [];

  /// Stream controller for updates (from synheart-focus-dart)
  final StreamController<FocusState> _updateController =
      StreamController<FocusState>.broadcast();

  FocusEngine({FocusConfig? config, this.onLog})
      : config = config ?? FocusConfig.defaultConfig;

  /// Stream of focus state updates (from synheart-focus-dart)
  Stream<FocusState> get onUpdate => _updateController.stream;

  /// Initialize the engine with a model
  Future<void> initialize({String? modelPath, String backend = 'onnx'}) async {
    try {
      final modelRef = modelPath ?? 'assets/models/Gradient_Boosting.onnx';
      _model = await ModelFactory.load(backend: backend, modelRef: modelRef);
      _log('info', 'Model loaded: ${_model!.info.id}');
    } catch (e) {
      _log('error', 'Failed to load model: $e');
      rethrow;
    }
  }

  /// Compute Focus Score from model probabilities
  ///
  /// Uses linear composite algorithm: maps model probabilities to Focus Score (0-100)
  /// Matching Python SDK FocusResult.from_inference() approach
  ///
  /// Focus Score calculation (linear composite):
  /// - Focused: 70.0 + (confidence * 30.0) → 70-100
  /// - time pressure: 40.0 + (confidence * 30.0) → 40-70
  /// - Distracted: confidence * 40.0 → 0-40
  FocusResult computeScore({
    required Map<String, double>
        probabilities, // All class probabilities from model
    required Map<String, double> features, // Extracted features
    required ModelInfo modelInfo, // Model metadata
  }) {
    // Create result using linear composite algorithm (matching Python SDK)
    final result = FocusResult.fromInference(
      timestamp: DateTime.now().toUtc(),
      probabilities: probabilities,
      features: features,
      model: {
        'id': modelInfo.id,
        'version': '1.0',
        'type': modelInfo.type,
        'labels':
            modelInfo.classNames ?? ['Focused', 'time pressure', 'Distracted'],
        'feature_names': modelInfo.inputSchema,
        'num_classes': (modelInfo.classNames ?? []).length,
        'num_features': modelInfo.inputSchema.length,
      },
    );

    // Apply smoothing if enabled
    double finalScore = result.focusScore;
    if (config.enableSmoothing && _previousScore != null) {
      finalScore = _smoothScore(
        result.focusScore,
        _previousScore!,
        lambda: config.smoothingLambda,
      );
      _previousScore = finalScore;
    } else {
      _previousScore = finalScore;
    }

    // Log the computation
    _log(
      'info',
      'Computed Focus score: ${finalScore.toStringAsFixed(1)}, '
          'state: ${result.focusState}, '
          'confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
    );

    // Update timestamp
    _lastUpdate = DateTime.now().toUtc();

    // Emit update to stream (synheart-focus-dart compatibility)
    final focusState = FocusState(
      focusScore: finalScore / 100.0, // Convert 0-100 to 0-1
      focusLabel: _getFocusLabel(finalScore / 100.0),
      confidence: result.confidence,
      timestamp: result.timestamp,
      metadata: {
        'probabilities': result.probabilities,
        'features': result.features,
      },
    );
    _updateController.add(focusState);

    // Return result with smoothed score
    return FocusResult(
      timestamp: result.timestamp,
      focusState: result.focusState,
      focusScore: finalScore,
      confidence: result.confidence,
      probabilities: result.probabilities,
      features: result.features,
      model: result.model,
    );
  }

  /// Perform inference on input data (from synheart-focus-dart)
  Future<FocusState> infer(HSIData hsiData, BehaviorData behaviorData) async {
    // Calculate HSI-based focus score
    final hsiScore = _calculateHSIScore(hsiData);

    // Calculate behavior-based focus score
    final behaviorScore = _calculateBehaviorScore(behaviorData);

    // Weighted combination
    final rawScore =
        (hsiScore * config.hsiWeight) + (behaviorScore * config.behaviorWeight);

    // Apply temporal smoothing if we have previous data
    final smoothedScore = _previousScore != null
        ? (rawScore * (1 - config.smoothingFactor)) +
            (_previousScore! / 100.0 * config.smoothingFactor)
        : rawScore;

    _previousScore = smoothedScore * 100.0;

    // Clamp to valid range
    final focusScore = smoothedScore.clamp(0.0, 1.0);

    // Determine focus label
    final focusLabel = _getFocusLabel(focusScore);

    // Calculate confidence based on data quality
    final confidence = _calculateConfidence(hsiData, behaviorData);

    final focusState = FocusState(
      focusScore: focusScore,
      focusLabel: focusLabel,
      confidence: confidence,
      timestamp: DateTime.now(),
      metadata: {
        'hsiScore': hsiScore,
        'behaviorScore': behaviorScore,
        'rawScore': rawScore,
      },
    );

    if (config.enableDebugLogging) {
      _log('debug', '[FocusEngine] $focusState');
    }

    // Emit update
    _updateController.add(focusState);

    return focusState;
  }

  /// Perform inference using ONNX model (from focus-core-dart)
  Future<FocusResult?> inferFromRrIntervals({
    required List<double> rrIntervalsMs,
    required double hrMean,
    double? motionMagnitude,
  }) async {
    if (_model == null) {
      throw Exception('Model not initialized. Call initialize() first.');
    }

    // Extract features
    final featureVector = _featureExtractor.toFeatures(
      rrIntervalsMs: rrIntervalsMs,
      hrMean: hrMean,
      motionMagnitude: motionMagnitude,
    );

    if (featureVector == null) {
      _log('warning', 'Failed to extract features - insufficient data');
      return null;
    }

    // Check minimum RR count
    if (rrIntervalsMs.length < config.minRrCount) {
      _log(
        'warning',
        'Insufficient RR intervals: ${rrIntervalsMs.length} < ${config.minRrCount}',
      );
      return null;
    }

    // Get probabilities from model
    Map<String, double> probabilities;
    if (_model is ONNXRuntimeModel) {
      final onnxModel = _model as ONNXRuntimeModel;
      probabilities = await onnxModel.predictProbabilities(
        featureVector.values,
      );
    } else {
      // Fallback for other model types
      final prob = await _model!.predict(featureVector.values);
      probabilities = {
        'Focused': prob,
        'time pressure': (1.0 - prob) / 2.0,
        'Distracted': (1.0 - prob) / 2.0,
      };
    }

    // Compute score
    return computeScore(
      probabilities: probabilities,
      features: featureVector.namedFeatures,
      modelInfo: _model!.info,
    );
  }

  /// Convert HR (BPM) to IBI (ms) matching Python hr_to_ibi
  List<double> _hrToIbi(List<double> hrBpm) {
    final ibi = <double>[];
    for (final hr in hrBpm) {
      // Filter invalid HR values
      if (hr <= 0 || hr > 220) {
        continue; // Skip invalid values
      }
      ibi.add(60000.0 / hr);
    }

    // Interpolate missing values if needed
    if (ibi.isEmpty) return [];

    // Simple interpolation for any gaps (if we had NaN handling)
    return ibi;
  }

  /// Z-score normalization (subject-specific) matching Python zscore_normalize
  List<double> _zscoreNormalize(List<double> values) {
    if (values.isEmpty) return values;

    // Update subject statistics
    _subjectIbiHistory.addAll(values);
    if (_subjectIbiHistory.length > 1000) {
      // Keep only recent history
      _subjectIbiHistory.removeRange(0, _subjectIbiHistory.length - 1000);
    }

    // Compute mean and std from subject history
    final mean =
        _subjectIbiHistory.reduce((a, b) => a + b) / _subjectIbiHistory.length;
    final variance = _subjectIbiHistory
            .map((x) => math.pow(x - mean, 2))
            .reduce((a, b) => a + b) /
        _subjectIbiHistory.length;
    final std = math.sqrt(variance);

    // Normalize
    if (std > 0) {
      return values.map((x) => (x - mean) / std).toList();
    } else {
      return values;
    }
  }

  /// Perform inference from HR data (BPM) with windowing
  ///
  /// This method:
  /// 1. Buffers HR data in a sliding window
  /// 2. Converts HR to IBI (ms)
  /// 3. Applies subject-specific z-score normalization
  /// 4. Extracts 24 HRV features
  /// 5. Runs inference using the Gradient Boosting model
  ///
  /// Returns null if insufficient data is available
  Future<FocusResult?> inferFromHrData({
    required double hrBpm,
    required DateTime timestamp,
  }) async {
    if (_model == null) {
      throw Exception('Model not initialized. Call initialize() first.');
    }

    // Track first data point
    if (_firstDataTime == null) {
      _firstDataTime = timestamp;
    }

    // Add HR to buffer with timestamp
    _hrBuffer.add(_TimestampedValue(timestamp, hrBpm));

    // Remove old data outside window (data older than 60 seconds)
    final windowDuration = Duration(seconds: config.windowSeconds);
    _hrBuffer.removeWhere(
      (v) => timestamp.difference(v.timestamp) > windowDuration,
    );

    // Calculate the time span of data currently in buffer
    if (_hrBuffer.isEmpty) {
      return null;
    }

    final bufferStartTime = _hrBuffer.first.timestamp;
    final bufferEndTime = _hrBuffer.last.timestamp;
    final bufferDuration = bufferEndTime.difference(bufferStartTime);
    final bufferDurationTotalSeconds =
        bufferDuration.inMilliseconds / 1000.0; // More precise

    // Also check time since first data point was collected
    final timeSinceFirstData = timestamp.difference(_firstDataTime!);
    final timeSinceFirstDataSeconds =
        timeSinceFirstData.inMilliseconds / 1000.0;

    // First inference: wait until we have at least 60 seconds since first data point
    if (_lastWindowTime == null) {
      // Check if 60 seconds have passed since we started collecting data
      if (timeSinceFirstDataSeconds < config.windowSeconds) {
        // Still collecting data for first window
        _log(
          'debug',
          'Collecting data: ${timeSinceFirstDataSeconds.toStringAsFixed(2)}s / ${config.windowSeconds}s (${_hrBuffer.length} points, buffer span: ${bufferDurationTotalSeconds.toStringAsFixed(2)}s)',
        );
        return null;
      }
      // We have at least 60 seconds since first data, do first inference
      _log(
        'info',
        'First inference: 60-second window complete (${_hrBuffer.length} data points, elapsed: ${timeSinceFirstDataSeconds.toStringAsFixed(2)}s, buffer span: ${bufferDurationTotalSeconds.toStringAsFixed(2)}s)',
      );
    } else {
      // Subsequent inferences: every 5 seconds, using last 60 seconds
      final timeSinceLastWindow = timestamp.difference(_lastWindowTime!);
      if (timeSinceLastWindow.inSeconds < config.stepSeconds) {
        // Not time for next inference yet
        return null;
      }
      // We have 5 seconds since last inference, process last 60 seconds
      _log(
        'debug',
        'Sliding window inference: processing last 60 seconds (${_hrBuffer.length} data points, ${bufferDurationTotalSeconds.toStringAsFixed(2)}s)',
      );
    }

    // Check minimum data requirement
    if (_hrBuffer.length < config.minRrCount) {
      _log(
        'warning',
        'Insufficient data points: ${_hrBuffer.length} < ${config.minRrCount}',
      );
      return null;
    }

    // Verify we have enough data points (at least minRrCount, which is already checked above)
    // For first inference, we just need 60 seconds to have passed since first data
    // For subsequent inferences, the buffer should have ~60 seconds of data

    // Log that we're proceeding with inference
    _log(
      'info',
      'Proceeding with inference: buffer has ${_hrBuffer.length} points spanning ${bufferDurationTotalSeconds.toStringAsFixed(2)}s (elapsed: ${timeSinceFirstDataSeconds.toStringAsFixed(2)}s)',
    );

    // Extract HR values from buffer
    final hrValues = _hrBuffer.map((v) => v.value).toList();

    // Convert HR to IBI
    final ibi = _hrToIbi(hrValues);

    if (ibi.length < config.minRrCount) {
      _log('warning', 'Insufficient IBI data after conversion: ${ibi.length}');
      return null;
    }

    // Apply z-score normalization (subject-specific, REQUIRED)
    // ⚠️ SCIENTIFIC NOTE: Normalizing IBIs before feature extraction makes features
    // dimensionless and loses physiological units. This matches the Python training
    // pipeline, but a more scientifically sound approach would normalize features after
    // extraction. However, we must match the training pipeline for model compatibility.
    final normalizedIbi = _zscoreNormalize(ibi);

    // Extract 24 HRV features from normalized IBIs
    // Note: Features will be dimensionless (mean_rr ≈ 0, std_rr ≈ 1 by definition)
    HRVFeatureVector featureVector;
    try {
      featureVector = _hrvFeatureExtractor.extractHRVFeatures(normalizedIbi);
    } catch (e) {
      _log('error', 'Failed to extract HRV features: $e');
      return null;
    }

    // Get probabilities from model
    Map<String, double> probabilities;
    if (_model is ONNXRuntimeModel) {
      final onnxModel = _model as ONNXRuntimeModel;
      // Features should already be normalized (z-score), no scaler needed
      probabilities = await onnxModel.predictProbabilities(
        featureVector.values,
      );
    } else {
      // Fallback for other model types
      final prob = await _model!.predict(featureVector.values);
      probabilities = {
        'Bored': prob / 4.0,
        'Focused': prob,
        'Anxious': prob / 4.0,
        'Overload': prob / 4.0,
      };
    }

    // Update last window time
    _lastWindowTime = timestamp;

    // Compute score
    return computeScore(
      probabilities: probabilities,
      features: featureVector.namedFeatures,
      modelInfo: _model!.info,
    );
  }

  /// Smooth score using exponential moving average
  double _smoothScore(double current, double previous, {double lambda = 0.9}) {
    return lambda * current + (1.0 - lambda) * previous;
  }

  /// Calculate focus score from HSI data (from synheart-focus-dart)
  double _calculateHSIScore(HSIData data) {
    // Normalize HR (assuming optimal focus HR is 60-80 bpm)
    final hrNormalized = _normalizeHR(data.hr);

    // Higher HRV (RMSSD) generally indicates better autonomic regulation
    // Normalize assuming 20-60ms is typical range
    final hrvNormalized = ((data.hrvRmssd - 20) / 40).clamp(0.0, 1.0);

    // Lower stress is better for focus
    final stressScore = 1.0 - data.stressIndex;

    // Lower motion is better for sustained focus
    final motionScore = 1.0 - data.motionIntensity;

    // Weighted average of HSI components
    return (hrNormalized * 0.25) +
        (hrvNormalized * 0.25) +
        (stressScore * 0.3) +
        (motionScore * 0.2);
  }

  /// Normalize heart rate to focus score
  double _normalizeHR(double hr) {
    // Optimal focus HR range: 60-80 bpm
    const optimalMin = 60.0;
    const optimalMax = 80.0;
    const optimalMid = (optimalMin + optimalMax) / 2;

    if (hr >= optimalMin && hr <= optimalMax) {
      // Within optimal range - score decreases from center
      final distance = (hr - optimalMid).abs();
      return 1.0 - (distance / (optimalMax - optimalMid)) * 0.2;
    } else if (hr < optimalMin) {
      // Too low - might indicate drowsiness
      return (hr / optimalMin).clamp(0.5, 1.0);
    } else {
      // Too high - might indicate stress/excitement
      final excess = hr - optimalMax;
      return math.max(0.3, 1.0 - (excess / 40.0));
    }
  }

  /// Calculate focus score from behavior data (from synheart-focus-dart)
  double _calculateBehaviorScore(BehaviorData data) {
    // Lower task switching indicates sustained focus
    final taskSwitchScore = math.max(0.0, 1.0 - (data.taskSwitchRate / 2.0));

    // Moderate burstiness is good (too high = distraction, too low = inactivity)
    final burstinessScore = 1.0 - (data.interactionBurstiness - 0.3).abs() * 2;

    // Lower idle ratio indicates active engagement
    final engagementScore = 1.0 - data.idleRatio;

    // Weighted average of behavior components
    return (taskSwitchScore * 0.4) +
        (burstinessScore.clamp(0.0, 1.0) * 0.3) +
        (engagementScore * 0.3);
  }

  /// Calculate confidence level based on data quality
  double _calculateConfidence(HSIData hsiData, BehaviorData behaviorData) {
    // Check if HSI values are within reasonable ranges
    final hrValid = hsiData.hr >= 40 && hsiData.hr <= 200;
    final hrvValid = hsiData.hrvRmssd >= 5 && hsiData.hrvRmssd <= 200;

    // Base confidence
    double confidence = 0.7;

    if (hrValid) confidence += 0.1;
    if (hrvValid) confidence += 0.1;

    // Reduce confidence if values are at extremes
    if (hsiData.stressIndex > 0.9 || hsiData.motionIntensity > 0.9) {
      confidence -= 0.1;
    }

    return confidence.clamp(0.0, 1.0);
  }

  /// Get human-readable focus label
  String _getFocusLabel(double score) {
    if (score >= config.highFocusThreshold) {
      return 'High Focus';
    } else if (score >= config.mediumFocusThreshold) {
      return 'Medium Focus';
    } else {
      return 'Low Focus';
    }
  }

  /// Get interpretation of a score
  String interpretScore(double score) {
    if (score >= 80.0) {
      return 'Highly Focused';
    } else if (score >= 60.0) {
      return 'Focused';
    } else if (score >= 40.0) {
      return 'Moderately Focused';
    } else if (score >= 20.0) {
      return 'Distracted';
    } else {
      return 'Very Distracted';
    }
  }

  /// Reset engine state
  void reset() {
    _previousScore = null;
    _lastUpdate = DateTime.now().toUtc();
    _subjectIbiHistory.clear();
    _hrBuffer.clear();
    _lastWindowTime = null;
    _firstDataTime = null;
    _log('info', 'Engine reset');
  }

  /// Log message
  void _log(String level, String message, {Map<String, dynamic>? context}) {
    onLog?.call(level, message, context: context);
  }

  /// Get current state
  Map<String, dynamic> getState() {
    return {
      'config': config.toJson(),
      'previous_score': _previousScore,
      'last_update': _lastUpdate.toIso8601String(),
      'model_loaded': _model != null,
    };
  }

  /// Dispose of resources
  void dispose() {
    _updateController.close();
    _model?.dispose();
  }
}

/// Factory for creating Focus Engines with sensible defaults
class FocusEngineFactory {
  /// Create engine with default configuration
  /// Uses linear composite algorithm matching Python SDK
  static FocusEngine createDefault({
    FocusConfig? config,
    void Function(
      String level,
      String message, {
      Map<String, dynamic>? context,
    })? onLog,
  }) {
    return FocusEngine(config: config, onLog: onLog);
  }
}
