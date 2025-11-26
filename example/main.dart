import 'package:synheart_focus/synheart_focus.dart';

void main() async {
  // Initialize the FocusEngine with custom configuration
  final focusEngine = FocusEngine.initialize(
    config: const FocusConfig(
      highFocusThreshold: 0.75,
      mediumFocusThreshold: 0.45,
      enableDebugLogging: true,
    ),
  );

  // Subscribe to focus updates
  focusEngine.onUpdate.listen((focusState) {
    print('─────────────────────────────────');
    print('Focus Score: ${focusState.focusScore.toStringAsFixed(2)}');
    print('Focus Label: ${focusState.focusLabel}');
    print('Confidence: ${focusState.confidence.toStringAsFixed(2)}');
    print('Timestamp: ${focusState.timestamp}');
    print('─────────────────────────────────\n');
  });

  // Simulate a focused work session
  print('Simulating a focused work session...\n');

  // Good focus state
  final goodHSI = HSIData(
    hr: 70,
    hrvRmssd: 50,
    stressIndex: 0.2,
    motionIntensity: 0.05,
  );

  final goodBehavior = BehaviorData(
    taskSwitchRate: 0.1,
    interactionBurstiness: 0.3,
    idleRatio: 0.05,
  );

  await focusEngine.infer(goodHSI, goodBehavior);
  await Future.delayed(const Duration(seconds: 1));

  // Moderate focus state
  final moderateHSI = HSIData(
    hr: 85,
    hrvRmssd: 35,
    stressIndex: 0.4,
    motionIntensity: 0.2,
  );

  final moderateBehavior = BehaviorData(
    taskSwitchRate: 0.5,
    interactionBurstiness: 0.5,
    idleRatio: 0.15,
  );

  await focusEngine.infer(moderateHSI, moderateBehavior);
  await Future.delayed(const Duration(seconds: 1));

  // Poor focus state (distracted)
  final poorHSI = HSIData(
    hr: 105,
    hrvRmssd: 20,
    stressIndex: 0.8,
    motionIntensity: 0.6,
  );

  final poorBehavior = BehaviorData(
    taskSwitchRate: 1.5,
    interactionBurstiness: 0.85,
    idleRatio: 0.5,
  );

  await focusEngine.infer(poorHSI, poorBehavior);

  // Clean up
  await Future.delayed(const Duration(seconds: 1));
  focusEngine.dispose();
}
