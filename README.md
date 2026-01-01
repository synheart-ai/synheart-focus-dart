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
  synheart_focus: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## 🎯 Quick Start

### Basic Usage with HR Data

```dart
import 'package:synheart_focus/synheart_focus.dart';

void main() async {
  // Initialize the focus engine
  final engine = FocusEngine(
    config: const FocusConfig(
      windowSeconds: 60,  // 60-second window
      stepSeconds: 5,     // 5-second step
      minRrCount: 30,
    ),
  );

  // Initialize with ONNX model
  await engine.initialize(
    modelPath: 'assets/models/Gradient_Boosting.onnx',
    backend: 'onnx',
  );

  // Subscribe to focus updates
  engine.onUpdate.listen((result) {
    print('Focus Score: ${result.focusScore}');
    print('Focus State: ${result.focusState}');
    print('Confidence: ${result.confidence}');
    print('Probabilities: ${result.probabilities}');
  });

  // Provide HR data (BPM) - inference happens automatically when window is ready
  await engine.inferFromHrData(
    hrBpm: 72.0,
    timestamp: DateTime.now(),
  );
}
```

### Integration with synheart-wear

**synheart_focus** integrates seamlessly with [synheart-wear](https://pub.dev/packages/synheart_wear) for real-time HR data streaming from wearable devices.

First, add both to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_wear: ^0.2.2    # For wearable data
  synheart_focus: ^0.0.1   # For focus inference
```

Then integrate in your app:

```dart
import 'package:synheart_wear/synheart_wear.dart';
import 'package:synheart_focus/synheart_focus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SynheartWear SDK
  final adapters = <DeviceAdapter>{
    DeviceAdapter.appleHealthKit, // Uses Health Connect on Android
  };
  final synheartWear = SynheartWear(
    config: SynheartWearConfig.withAdapters(adapters),
  );

  // Request permissions
  await synheartWear.requestPermissions(
    permissions: {PermissionType.heartRate},
    reason: 'This app needs access to your heart rate data.',
  );
  await synheartWear.initialize();

  // Initialize Focus Engine
  final focusEngine = FocusEngine(
    config: const FocusConfig(
      windowSeconds: 60,
      stepSeconds: 5,
      minRrCount: 30,
    ),
  );
  await focusEngine.initialize(
    modelPath: 'assets/models/Gradient_Boosting.onnx',
    backend: 'onnx',
  );

  // Stream HR data from wearable and feed to focus engine
  synheartWear.streamHR(interval: const Duration(seconds: 1)).listen((metrics) {
    final hr = metrics.getMetric(MetricType.hr);
    if (hr != null) {
      // Feed HR data to focus engine
      // Inference happens automatically when 60-second window is ready
      focusEngine.inferFromHrData(
        hrBpm: hr.toDouble(),
        timestamp: DateTime.now(),
      ).then((result) {
        if (result != null) {
          print('Focus State: ${result.focusState}');
          print('Focus Score: ${result.focusScore}');
          print('Confidence: ${result.confidence}');
        }
      });
    }
  });
}
```

## 📊 Supported Focus States

The library supports four cognitive state categories (4-class Gradient Boosting model):

- **🎯 Focused**: Optimal cognitive state, high attention and productivity
- **😴 Bored**: Low engagement, reduced attention
- **😰 Anxious**: Heightened arousal, reduced efficiency
- **🔥 Overload**: Cognitive overload, information processing difficulty

**Focus Scores:**
- **70-100**: Focused (optimal concentration)
- **30-50**: Bored (low engagement)
- **20-40**: Anxious (heightened arousal)
- **0-20**: Overload (cognitive overload)

**Note**: The model uses a 60-second sliding window with 5-second steps. First inference occurs after 60 seconds of data collection, then every 5 seconds thereafter.

## 🔧 API Reference

### FocusEngine

The main class for focus inference:

```dart
class FocusEngine {
  // Create engine with config
  FocusEngine({FocusConfig? config, void Function(String, String)? onLog});

  // Initialize with model
  Future<void> initialize({
    String? modelPath,
    String backend = 'onnx',
  });

  // Stream of focus updates
  Stream<FocusState> get onUpdate;

  // Run inference from HR data (BPM) - recommended approach
  Future<FocusResult?> inferFromHrData({
    required double hrBpm,
    required DateTime timestamp,
  });

  // Run inference from RR intervals (legacy)
  Future<FocusResult?> inferFromRrIntervals({
    required List<double> rrIntervalsMs,
    required double hrMean,
    double? motionMagnitude,
  });

  // Legacy: Run inference with HSI and behavior data
  Future<FocusState> infer(HSIData hsiData, BehaviorData behaviorData);

  // Reset engine state
  void reset();

  // Dispose resources
  Future<void> dispose();
}
```

### FocusConfig

Configuration for the focus engine:

```dart
class FocusConfig {
  final int windowSeconds;              // Window size in seconds (default: 60)
  final int stepSeconds;                // Step size in seconds (default: 5)
  final int minRrCount;                 // Minimum RR intervals required (default: 30)
  final bool enableSmoothing;           // Enable score smoothing (default: true)
  final double smoothingLambda;         // Smoothing factor (default: 0.9)
  final bool enableDebugLogging;        // Enable debug logs (default: false)
}
```

### FocusResult

Result of focus inference:

```dart
class FocusResult {
  final DateTime timestamp;                // When inference was performed
  final String focusState;                 // "Focused", "Bored", "Anxious", or "Overload"
  final double focusScore;                 // 0-100 focus score
  final double confidence;                 // Confidence score (0.0-1.0) - top probability
  final Map<String, double> probabilities; // All 4 class probabilities
  final Map<String, double> features;     // All 24 HRV features with values
  final Map<String, dynamic> model;        // Model metadata
}
```

**Features Extracted (24 total):**
- **Time Domain (9)**: mean_rr, std_rr, min_rr, max_rr, range_rr, rmssd, sdnn, nn50, pnn50
- **Frequency Domain (11)**: VLF, LF, HF, UHF powers, total_power, lf_hf_ratio, normalized powers
- **Statistical (4)**: skewness, kurtosis, median_rr, iqr

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
- Integration with synheart-core FocusHead (25 tests)
- HSI schema compatibility validation
- Multimodal data fusion (biosignals + behavior)
- Temporal smoothing and stable output

## 📊 Performance

**Target Performance (mid-range phone):**
- **Latency**: < 10ms per inference
- **Model Size**: < 2 MB (ONNX model)
- **CPU Usage**: < 3% during active streaming
- **Memory**: < 5 MB (engine + buffers)
- **Accuracy**: Validated on SWELL dataset

## 🏗️ Architecture

```
HR Data (BPM) from Wearable Device
         │
         ▼
┌─────────────────────┐
│  Windowing Buffer   │
│  (60-second window) │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│   HR → IBI Convert  │
│   (60000 / HR)      │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ Z-Score Normalize   │
│ (Subject-specific)  │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ 24 HRV Features      │
│ (Time, Freq, Stats) │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  ONNX Model         │
│  (Gradient Boosting) │
└─────────────────────┘
         │
         ▼
   FocusResult
   (4-class output)
         │
         ▼
    Your App
```

**Processing Pipeline:**
1. Stream HR data (1 Hz) from wearable device
2. Buffer in 60-second sliding window
3. Convert HR (BPM) → IBI (ms)
4. Apply subject-specific z-score normalization
5. Extract 24 HRV features (time, frequency, statistical domains)
6. Run ONNX model inference (Gradient Boosting)
7. Calculate focus score from 4-class probabilities
8. Return result with all features and probabilities

## 🔗 Integration

### With synheart-core (HSI)

**synheart_focus** is designed to integrate seamlessly with [synheart-core](https://github.com/synheart-ai/synheart-core) as part of the Human State Interface (HSI) system:

```dart
import 'package:synheart_core/synheart_core.dart';

// Initialize synheart-core (includes focus capability)
await Synheart.initialize(
  userId: 'user_123',
  config: SynheartConfig(
    enableWear: true,
    enableBehavior: true,
  ),
);

// Enable focus interpretation layer (powered by synheart-focus)
await Synheart.enableFocus();

// Get focus updates through HSI
Synheart.onFocusUpdate.listen((focus) {
  print('Focus Score: ${focus.focusScore}');
  print('Focus Label: ${focus.focusLabel}');
  print('Confidence: ${focus.confidence}');
  print('Cognitive Load: ${focus.cognitiveLoad}');
  print('Clarity: ${focus.clarity}');
});
```

**HSI Schema Compatibility:**
- FocusState from synheart-focus maps to HSI FocusState
- Output validated against HSI_SPECIFICATION.md
- Comprehensive integration tests ensure compatibility
- Supports multimodal fusion with HSI (biosignals) + Behavior data

See the [synheart-core documentation](https://github.com/synheart-ai/synheart-core) for more details on HSI integration.

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