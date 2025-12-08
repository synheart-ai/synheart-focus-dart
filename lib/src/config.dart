/// Configuration for Focus Engine
///
/// Merges configuration from both focus-core-dart and synheart-focus-dart
class FocusConfig {
  // From focus-core-dart
  /// Exponential smoothing factor for scores (λ=0.9 default)
  final double smoothingLambda;

  /// Model identifier to use
  final String modelId;

  /// Enable/disable smoothing
  final bool enableSmoothing;

  /// Enable/disable artifact detection
  final bool enableArtifactDetection;

  /// Motion threshold for artifact detection (g)
  final double motionThreshold;

  /// Confidence threshold below which to flag low confidence
  final double lowConfidenceThreshold;

  /// Window size in seconds for feature extraction (matching Python SDK default: 60s)
  final int windowSeconds;

  /// Stride/step size in seconds for sliding window (matching Python SDK default: 5s)
  final int stepSeconds;

  /// Minimum RR intervals required for inference (matching Python SDK default: 30)
  final int minRrCount;

  // From synheart-focus-dart (legacy support)
  /// Threshold for high focus (default: 0.7)
  final double highFocusThreshold;

  /// Threshold for medium focus (default: 0.4)
  final double mediumFocusThreshold;

  /// Weight for HSI data in inference (default: 0.6)
  final double hsiWeight;

  /// Weight for behavior data in inference (default: 0.4)
  final double behaviorWeight;

  /// Smoothing factor for temporal averaging (default: 0.3)
  final double smoothingFactor;

  /// Enable debug logging
  final bool enableDebugLogging;

  const FocusConfig({
    // focus-core-dart defaults
    this.smoothingLambda = 0.9,
    this.modelId = 'focus_cnn_lstm_v1_0',
    this.enableSmoothing = true,
    this.enableArtifactDetection = true,
    this.motionThreshold = 2.0,
    this.lowConfidenceThreshold = 0.3,
    this.windowSeconds = 60,
    this.stepSeconds = 5,
    this.minRrCount = 30,
    // synheart-focus-dart defaults
    this.highFocusThreshold = 0.7,
    this.mediumFocusThreshold = 0.4,
    this.hsiWeight = 0.6,
    this.behaviorWeight = 0.4,
    this.smoothingFactor = 0.3,
    this.enableDebugLogging = false,
  }) : assert(hsiWeight + behaviorWeight == 1.0,
            'hsiWeight and behaviorWeight must sum to 1.0');

  /// Default configuration
  static const FocusConfig defaultConfig = FocusConfig();

  /// Create from JSON
  factory FocusConfig.fromJson(Map<String, dynamic> json) {
    return FocusConfig(
      smoothingLambda: (json['smoothing_lambda'] as num?)?.toDouble() ?? 0.9,
      modelId: json['model_id'] as String? ?? 'focus_model_v1',
      enableSmoothing: json['enable_smoothing'] as bool? ?? true,
      enableArtifactDetection:
          json['enable_artifact_detection'] as bool? ?? true,
      motionThreshold: (json['motion_threshold'] as num?)?.toDouble() ?? 2.0,
      lowConfidenceThreshold:
          (json['low_confidence_threshold'] as num?)?.toDouble() ?? 0.3,
      windowSeconds: (json['window_seconds'] as num?)?.toInt() ?? 60,
      stepSeconds: (json['step_seconds'] as num?)?.toInt() ?? 5,
      minRrCount: (json['min_rr_count'] as num?)?.toInt() ?? 30,
      highFocusThreshold:
          (json['highFocusThreshold'] as num?)?.toDouble() ?? 0.7,
      mediumFocusThreshold:
          (json['mediumFocusThreshold'] as num?)?.toDouble() ?? 0.4,
      hsiWeight: (json['hsiWeight'] as num?)?.toDouble() ?? 0.6,
      behaviorWeight: (json['behaviorWeight'] as num?)?.toDouble() ?? 0.4,
      smoothingFactor: (json['smoothingFactor'] as num?)?.toDouble() ?? 0.3,
      enableDebugLogging: json['enableDebugLogging'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'smoothing_lambda': smoothingLambda,
      'model_id': modelId,
      'enable_smoothing': enableSmoothing,
      'enable_artifact_detection': enableArtifactDetection,
      'motion_threshold': motionThreshold,
      'low_confidence_threshold': lowConfidenceThreshold,
      'window_seconds': windowSeconds,
      'step_seconds': stepSeconds,
      'min_rr_count': minRrCount,
      'highFocusThreshold': highFocusThreshold,
      'mediumFocusThreshold': mediumFocusThreshold,
      'hsiWeight': hsiWeight,
      'behaviorWeight': behaviorWeight,
      'smoothingFactor': smoothingFactor,
      'enableDebugLogging': enableDebugLogging,
    };
  }

  FocusConfig copyWith({
    double? smoothingLambda,
    String? modelId,
    bool? enableSmoothing,
    bool? enableArtifactDetection,
    double? motionThreshold,
    double? lowConfidenceThreshold,
    int? windowSeconds,
    int? stepSeconds,
    int? minRrCount,
    double? highFocusThreshold,
    double? mediumFocusThreshold,
    double? hsiWeight,
    double? behaviorWeight,
    double? smoothingFactor,
    bool? enableDebugLogging,
  }) {
    return FocusConfig(
      smoothingLambda: smoothingLambda ?? this.smoothingLambda,
      modelId: modelId ?? this.modelId,
      enableSmoothing: enableSmoothing ?? this.enableSmoothing,
      enableArtifactDetection:
          enableArtifactDetection ?? this.enableArtifactDetection,
      motionThreshold: motionThreshold ?? this.motionThreshold,
      lowConfidenceThreshold:
          lowConfidenceThreshold ?? this.lowConfidenceThreshold,
      windowSeconds: windowSeconds ?? this.windowSeconds,
      stepSeconds: stepSeconds ?? this.stepSeconds,
      minRrCount: minRrCount ?? this.minRrCount,
      highFocusThreshold: highFocusThreshold ?? this.highFocusThreshold,
      mediumFocusThreshold: mediumFocusThreshold ?? this.mediumFocusThreshold,
      hsiWeight: hsiWeight ?? this.hsiWeight,
      behaviorWeight: behaviorWeight ?? this.behaviorWeight,
      smoothingFactor: smoothingFactor ?? this.smoothingFactor,
      enableDebugLogging: enableDebugLogging ?? this.enableDebugLogging,
    );
  }
}
