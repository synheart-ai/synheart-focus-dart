/// Synheart Focus Dart/Flutter SDK
///
/// On-device cognitive concentration inference from biosignals and behavioral patterns.

library synheart_focus;

// Core engine and configuration
export 'src/engine.dart';
export 'src/config.dart';
export 'src/models.dart';

// Feature extraction and scoring
export 'src/feature_extractor.dart';
export 'src/hrv_feature_extractor_24.dart';
export 'src/scorer.dart';
export 'src/hrv_features.dart';

// Artifact filtering and quality
export 'src/artifact_filter.dart';
export 'src/adaptive_baseline.dart';
export 'src/window_buffer.dart';

// Model loading and inference
export 'src/models/on_device_model.dart';
export 'src/models/model_factory.dart';
export 'src/models/onnx_runtime.dart';
export 'src/models/json_linear_model.dart';
export 'src/models/coreml_ios.dart';
