/// Configuration for FocusEngine
class FocusConfig {
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
    this.highFocusThreshold = 0.7,
    this.mediumFocusThreshold = 0.4,
    this.hsiWeight = 0.6,
    this.behaviorWeight = 0.4,
    this.smoothingFactor = 0.3,
    this.enableDebugLogging = false,
  }) : assert(hsiWeight + behaviorWeight == 1.0,
            'hsiWeight and behaviorWeight must sum to 1.0');

  FocusConfig copyWith({
    double? highFocusThreshold,
    double? mediumFocusThreshold,
    double? hsiWeight,
    double? behaviorWeight,
    double? smoothingFactor,
    bool? enableDebugLogging,
  }) {
    return FocusConfig(
      highFocusThreshold: highFocusThreshold ?? this.highFocusThreshold,
      mediumFocusThreshold: mediumFocusThreshold ?? this.mediumFocusThreshold,
      hsiWeight: hsiWeight ?? this.hsiWeight,
      behaviorWeight: behaviorWeight ?? this.behaviorWeight,
      smoothingFactor: smoothingFactor ?? this.smoothingFactor,
      enableDebugLogging: enableDebugLogging ?? this.enableDebugLogging,
    );
  }

  Map<String, dynamic> toJson() => {
        'highFocusThreshold': highFocusThreshold,
        'mediumFocusThreshold': mediumFocusThreshold,
        'hsiWeight': hsiWeight,
        'behaviorWeight': behaviorWeight,
        'smoothingFactor': smoothingFactor,
        'enableDebugLogging': enableDebugLogging,
      };
}
