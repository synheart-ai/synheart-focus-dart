# Synheart Focus

**On-device cognitive concentration inference from biosignals and behavioral patterns for Flutter applications**

[![pub package](https://img.shields.io/pub/v/synheart_focus.svg)](https://pub.dev/packages/synheart_focus)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI](https://github.com/synheart-ai/synheart-focus-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/synheart-ai/synheart-focus-flutter/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/synheart-ai/synheart-focus-flutter/branch/main/graph/badge.svg)](https://codecov.io/gh/synheart-ai/synheart-focus-flutter)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0.0+-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.10.0+-blue.svg)](https://flutter.dev)

## 🚀 Features

- **📱 Cross-Platform**: Works on iOS and Android
- **🔄 Real-Time Inference**: Live focus state detection from biosignals and behavior
- **🧠 On-Device Processing**: All computations happen locally for privacy
- **📊 Unified Output**: Consistent focus scores (0-100) with state labels
- **🔒 Privacy-First**: No raw biometric data leaves your device
- **⚡ High Performance**: Optimized for real-time processing on mobile devices

## 📦 Installation

Add `synheart_focus` to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_focus: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## 🎯 Quick Start

### Basic Usage

```dart
import 'package:synheart_focus/synheart_focus.dart';

void main() async {
  // Initialize the focus engine
  final engine = await FocusEngine.initialize(
    config: FocusConfig(),
  );

  // Subscribe to focus updates
  engine.onUpdate.listen((result) {
    print('Focus Score: ${result.focusScore}');
    print('Focus State: ${result.focusState}');
    print('Confidence: ${result.confidence}');
  });

  // Provide biosignal data
  final hsiData = HSIData(
    hr: 72.0,
    hrvRmssd: 45.0,
    stressIndex: 0.3,
    motionIntensity: 0.1,
  );

  // Provide behavioral data
  final behaviorData = BehaviorData(
    taskSwitchRate: 0.2,
    interactionBurstiness: 0.15,
    idleRatio: 0.1,
  );

  // Run inference
  final result = await engine.infer(hsiData, behaviorData);
  print('Focus Score: ${result.focusScore}');
}
```

### Integration with synheart-wear

**synheart_focus** works independently but integrates seamlessly with [synheart-wear](https://github.com/synheart-ai/synheart-wear) for real wearable data.

First, add both to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_wear: ^0.1.0    # For wearable data
  synheart_focus: ^0.1.0   # For focus inference
```

Then integrate in your app:

```dart
import 'package:synheart_wear/synheart_wear.dart';
import 'package:synheart_focus/synheart_focus.dart';

// Initialize both SDKs
final wear = SynheartWear();
final focusEngine = await FocusEngine.initialize(
  config: FocusConfig(),
);

await wear.initialize();

// Stream wearable data to focus engine
wear.streamHR(interval: Duration(seconds: 1)).listen((metrics) {
  final hsiData = HSIData(
    hr: metrics.getMetric(MetricType.hr),
    hrvRmssd: calculateRMSSD(metrics.getMetric(MetricType.rrIntervals)),
    stressIndex: calculateStress(metrics),
    motionIntensity: metrics.getMetric(MetricType.motion),
  );

  // Add behavioral data from your app
  final behaviorData = BehaviorData(
    taskSwitchRate: appMetrics.taskSwitchRate,
    interactionBurstiness: appMetrics.interactionBurstiness,
    idleRatio: appMetrics.idleRatio,
  );

  // Get focus state
  focusEngine.infer(hsiData, behaviorData).then((result) {
    updateUI(result);
  });
});
```

## 📊 Supported Focus States

The library currently supports three focus state categories:

- **🎯 Focused**: High concentration, productive state
- **⏱️ Time Pressure**: Moderate focus with elevated stress
- **😵 Distracted**: Low concentration, fragmented attention

**Focus Scores:**
- **70-100**: Focused (optimal concentration)
- **40-70**: Time Pressure (stressed but engaged)
- **0-40**: Distracted (low concentration)

## 🔧 API Reference

### FocusEngine

The main class for focus inference:

```dart
class FocusEngine {
  // Initialize engine with config
  static Future<FocusEngine> initialize({
    required FocusConfig config,
  });

  // Stream of focus updates
  Stream<FocusResult> get onUpdate;

  // Run inference on current data
  Future<FocusResult> infer(HSIData hsiData, BehaviorData behaviorData);

  // Dispose resources
  Future<void> dispose();
}
```

### FocusConfig

Configuration for the focus engine:

```dart
class FocusConfig {
  final Duration window;                // Rolling window size
  final Duration step;                  // Emission cadence
  final bool enableAdaptiveBaseline;    // Adaptive personalization
  final double smoothingFactor;         // Result smoothing (0.0-1.0)
}
```

### FocusResult

Result of focus inference:

```dart
class FocusResult {
  final DateTime timestamp;                // When inference was performed
  final String focusState;                 // "Focused", "time pressure", or "Distracted"
  final double focusScore;                 // 0-100 focus score
  final double confidence;                 // Confidence score (0.0-1.0)
  final Map<String, double> probabilities; // All state probabilities
  final Map<String, double> features;      // Extracted features
  final Map<String, dynamic> model;        // Model metadata
}
```

### HSIData

Heart Signal Intelligence data:

```dart
class HSIData {
  final double hr;                // Heart rate (BPM)
  final double hrvRmssd;          // HRV RMSSD (ms)
  final double stressIndex;       // Stress index (0.0-1.0)
  final double motionIntensity;   // Motion intensity (0.0-1.0)
}
```

### BehaviorData

Behavioral pattern data:

```dart
class BehaviorData {
  final double taskSwitchRate;        // Task switching frequency
  final double interactionBurstiness; // Interaction pattern metric
  final double idleRatio;             // Idle time ratio
}
```

## 🔒 Privacy & Security

- **On-Device Processing**: All focus inference happens locally
- **No Data Retention**: Raw biometric data is not retained after processing
- **No Network Calls**: No data is sent to external servers
- **Privacy-First Design**: No built-in storage - you control what gets persisted
- **Real Trained Models**: Uses SWELL-trained models with validated accuracy

## 📱 Example App

Check out the complete examples in the [synheart-focus repository](https://github.com/synheart-ai/synheart-focus/tree/main/examples):

```bash
# Clone the main repository for examples
git clone https://github.com/synheart-ai/synheart-focus.git
cd synheart-focus/examples
flutter pub get
flutter run
```

The example demonstrates:
- Real-time focus detection
- Probability visualization
- Multi-modal data integration
- Adaptive baseline tracking

## 🧪 Testing

Run the test suite:

```bash
flutter test
```

Tests cover:
- Feature extraction accuracy
- Model inference performance
- Edge case handling
- Multi-modal fusion

## 📊 Performance

**Target Performance (mid-range phone):**
- **Latency**: < 10ms per inference
- **Model Size**: < 2 MB (ONNX model)
- **CPU Usage**: < 3% during active streaming
- **Memory**: < 5 MB (engine + buffers)
- **Accuracy**: Validated on SWELL dataset

## 🏗️ Architecture

```
Biosignals (HR, HRV) + Behavior Data
         │
         ▼
┌─────────────────────┐
│   FocusEngine       │
│  [Feature Extract]  │
│  [Adaptive Baseline]│
│  [Model Inference]  │
└─────────────────────┘
         │
         ▼
   FocusResult
         │
         ▼
    Your App
```

## 🔗 Integration

### With synheart-wear

Perfect integration with the Synheart Wear SDK for real wearable data:

```dart
// Stream from Apple Watch, Fitbit, etc.
final wearStream = synheartWear.streamHR();
final focusStream = focusEngine.onUpdate;
```

### With synheart-emotion

Combine with emotion detection for comprehensive mental state tracking:

```dart
// Use both emotion and focus together
final emotionResult = emotionEngine.consumeReady();
final focusResult = await focusEngine.infer(hsiData, behaviorData);

// Combined mental state
print('Emotion: ${emotionResult.emotion}, Focus: ${focusResult.focusState}');
```

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

We welcome contributions! See our [Contributing Guidelines](https://github.com/synheart-ai/synheart-focus/blob/main/CONTRIBUTING.md) for details.

## 🔗 Links

- **Main Repository**: [synheart-focus](https://github.com/synheart-ai/synheart-focus) (Source of Truth)
- **Documentation**: [Docs](https://github.com/synheart-ai/synheart-focus/tree/main/docs)
- **Examples**: [Examples](https://github.com/synheart-ai/synheart-focus/tree/main/examples)
- **Models**: [Pre-trained Models](https://github.com/synheart-ai/synheart-focus/tree/main/models)
- **Synheart Wear**: [synheart-wear](https://github.com/synheart-ai/synheart-wear)
- **Synheart Emotion**: [synheart-emotion](https://github.com/synheart-ai/synheart-emotion)
- **Synheart AI**: [synheart.ai](https://synheart.ai)
- **Issues**: [GitHub Issues](https://github.com/synheart-ai/synheart-focus-flutter/issues)

## 👥 Authors

- **Synheart AI Team** - _Initial work_, _Architecture & Design_

---

**Made with ❤️ by the Synheart AI Team**

_Technology with a heartbeat._


## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.