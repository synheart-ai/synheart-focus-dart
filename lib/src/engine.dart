import 'dart:async';
import 'dart:math' as math;
import 'config.dart';
import 'models.dart';

/// Core engine for cognitive concentration inference
class FocusEngine {
  final FocusConfig config;
  final StreamController<FocusState> _updateController;
  double? _previousFocusScore;

  FocusEngine._({required this.config})
      : _updateController = StreamController<FocusState>.broadcast();

  /// Initialize the FocusEngine with optional configuration
  factory FocusEngine.initialize({FocusConfig? config}) {
    return FocusEngine._(config: config ?? const FocusConfig());
  }

  /// Stream of focus state updates
  Stream<FocusState> get onUpdate => _updateController.stream;

  /// Perform inference on input data
  Future<FocusState> infer(HSIData hsiData, BehaviorData behaviorData) async {
    // Calculate HSI-based focus score
    final hsiScore = _calculateHSIScore(hsiData);

    // Calculate behavior-based focus score
    final behaviorScore = _calculateBehaviorScore(behaviorData);

    // Weighted combination
    final rawScore =
        (hsiScore * config.hsiWeight) + (behaviorScore * config.behaviorWeight);

    // Apply temporal smoothing if we have previous data
    final smoothedScore = _previousFocusScore != null
        ? (rawScore * (1 - config.smoothingFactor)) +
            (_previousFocusScore! * config.smoothingFactor)
        : rawScore;

    _previousFocusScore = smoothedScore;

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
      // ignore: avoid_print
      print('[FocusEngine] $focusState');
    }

    // Emit update
    _updateController.add(focusState);

    return focusState;
  }

  /// Calculate focus score from HSI data
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

  /// Calculate focus score from behavior data
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

  /// Reset the engine state
  void reset() {
    _previousFocusScore = null;
  }

  /// Dispose of resources
  void dispose() {
    _updateController.close();
  }
}
