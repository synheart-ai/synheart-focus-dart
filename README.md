# Synheart Focus Dart/Flutter SDK

Flutter/Dart SDK for Synheart Focus - cognitive concentration inference.

## Installation

```yaml
dependencies:
  synheart_focus: ^0.1.0
```

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:synheart_focus/synheart_focus.dart';

// Initialize
final focusEngine = FocusEngine.initialize(
  config: FocusConfig(),
);

// Subscribe to updates
focusEngine.onUpdate.listen((focusState) {
  print('Focus Score: ${focusState.focusScore}');
  print('Label: ${focusState.focusLabel}');
});

// Provide inputs
final hsiData = HSIData(
  hr: 72,
  hrvRmssd: 45,
  stressIndex: 0.3,
  motionIntensity: 0.1,
);

final behaviorData = BehaviorData(
  taskSwitchRate: 0.2,
  interactionBurstiness: 0.15,
  idleRatio: 0.1,
);

final focusState = await focusEngine.infer(hsiData, behaviorData);
```

## Documentation

- [Full Documentation](https://github.com/synheart-ai/synheart-focus)
- [API Reference](https://github.com/synheart-ai/synheart-focus/tree/main/docs)

## License

Apache 2.0 License


## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.
