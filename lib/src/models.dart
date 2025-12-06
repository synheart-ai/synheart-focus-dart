// Re-export ModelInfo from models directory
export 'models/on_device_model.dart' show ModelInfo;

/// Human-Signal Interface (HSI) data from biosignals
class HSIData {
  /// Heart rate in beats per minute
  final double hr;

  /// Heart rate variability (RMSSD) in milliseconds
  final double hrvRmssd;

  /// Stress index (0.0 to 1.0)
  final double stressIndex;

  /// Motion intensity (0.0 to 1.0)
  final double motionIntensity;

  const HSIData({
    required this.hr,
    required this.hrvRmssd,
    required this.stressIndex,
    required this.motionIntensity,
  });

  Map<String, dynamic> toJson() => {
        'hr': hr,
        'hrvRmssd': hrvRmssd,
        'stressIndex': stressIndex,
        'motionIntensity': motionIntensity,
      };

  @override
  String toString() => 'HSIData(hr: $hr, hrvRmssd: $hrvRmssd, '
      'stressIndex: $stressIndex, motionIntensity: $motionIntensity)';
}

/// Behavioral pattern data from user interactions
class BehaviorData {
  /// Task switching rate (switches per minute)
  final double taskSwitchRate;

  /// Interaction burstiness (0.0 to 1.0)
  final double interactionBurstiness;

  /// Idle time ratio (0.0 to 1.0)
  final double idleRatio;

  const BehaviorData({
    required this.taskSwitchRate,
    required this.interactionBurstiness,
    required this.idleRatio,
  });

  Map<String, dynamic> toJson() => {
        'taskSwitchRate': taskSwitchRate,
        'interactionBurstiness': interactionBurstiness,
        'idleRatio': idleRatio,
      };

  @override
  String toString() => 'BehaviorData(taskSwitchRate: $taskSwitchRate, '
      'interactionBurstiness: $interactionBurstiness, idleRatio: $idleRatio)';
}

/// Focus state inference result
class FocusState {
  /// Focus score (0.0 to 1.0)
  final double focusScore;

  /// Human-readable focus label
  final String focusLabel;

  /// Confidence level (0.0 to 1.0)
  final double confidence;

  /// Timestamp of inference
  final DateTime timestamp;

  /// Additional metadata
  final Map<String, dynamic>? metadata;

  const FocusState({
    required this.focusScore,
    required this.focusLabel,
    required this.confidence,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'focusScore': focusScore,
        'focusLabel': focusLabel,
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        if (metadata != null) 'metadata': metadata,
      };

  @override
  String toString() => 'FocusState(focusScore: $focusScore, '
      'focusLabel: $focusLabel, confidence: $confidence)';
}
