import 'models/on_device_model.dart';
import 'models.dart';

/// Focus Score result matching Python SDK FocusResult format
class FocusResult {
  final DateTime timestamp;
  final String focusState; // "Focused", "time pressure", or "Distracted"
  final double focusScore; // 0-100
  final double confidence; // 0-1 (top-1 probability)
  final Map<String, double> probabilities; // All label probabilities
  final Map<String, double> features; // Extracted features
  final Map<String, dynamic> model; // Model metadata

  FocusResult({
    required this.timestamp,
    required this.focusState,
    required this.focusScore,
    required this.confidence,
    required this.probabilities,
    required this.features,
    required this.model,
  });

  /// Create from inference results (matching Python SDK FocusResult.from_inference)
  factory FocusResult.fromInference({
    required DateTime timestamp,
    required Map<String, double> probabilities,
    required Map<String, double> features,
    required Map<String, dynamic> model,
  }) {
    // Find top-1 focus state (matching Python SDK)
    String topState = 'Focused';
    double maxProb = 0.0;
    probabilities.forEach((state, prob) {
      if (prob > maxProb) {
        maxProb = prob;
        topState = state;
      }
    });
    final confidence = maxProb;

    // Calculate focus score (matching Python SDK FocusResult.from_inference)
    double focusScore;
    if (topState == 'Focused') {
      focusScore = 70.0 + (confidence * 30.0); // 70-100
    } else if (topState == 'time pressure') {
      focusScore = 40.0 + (confidence * 30.0); // 40-70
    } else {
      // Distracted
      focusScore = confidence * 40.0; // 0-40
    }
    focusScore = focusScore.clamp(0.0, 100.0);

    return FocusResult(
      timestamp: timestamp,
      focusState: topState,
      focusScore: focusScore,
      confidence: confidence,
      probabilities: probabilities,
      features: features,
      model: model,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'focus_state': focusState,
      'focus_score': focusScore,
      'confidence': confidence,
      'probabilities': probabilities,
      'features': features,
      'model': model,
    };
  }
}

class FocusScorer {
  /// Create FocusResult from model probabilities
  /// Matching Python SDK FocusResult.from_inference() behavior
  static FocusResult fromProbabilities({
    required Map<String, double> probabilities,
    required Map<String, double> features,
    required ModelInfo modelInfo,
    DateTime? timestamp,
  }) {
    final modelMetadata = {
      'id': modelInfo.id,
      'version': '1.0',
      'type': modelInfo.type,
      'labels':
          modelInfo.classNames ?? ['Focused', 'time pressure', 'Distracted'],
      'feature_names': modelInfo.inputSchema,
      'num_classes': (modelInfo.classNames ?? []).length,
      'num_features': modelInfo.inputSchema.length,
    };

    return FocusResult.fromInference(
      timestamp: timestamp ?? DateTime.now().toUtc(),
      probabilities: probabilities,
      features: features,
      model: modelMetadata,
    );
  }
}
