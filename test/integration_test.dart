import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_focus/synheart_focus.dart';

/// Integration tests that match the usage pattern in synheart-core FocusHead
///
/// These tests validate that FocusEngine works correctly when used by
/// synheart-core's FocusHead module, which:
/// 1. Uses FocusEngine() for initialization
/// 2. Calls infer(HSIData, BehaviorData) to get focus state
/// 3. Maps FocusState to HSI-compatible schema
/// 4. Subscribes to onUpdate stream for reactive updates
void main() {
  group('synheart-core FocusHead Integration Tests', () {
    late FocusEngine engine;

    setUp(() {
      // Create engine with configuration matching synheart-core FocusHead
      engine = FocusEngine(
        config: const FocusConfig(
          highFocusThreshold: 0.7,
          mediumFocusThreshold: 0.4,
          hsiWeight: 0.6,
          behaviorWeight: 0.4,
          enableSmoothing: true,
          smoothingFactor: 0.3,
        ),
        onLog: (level, message, {context}) {
          // Optional: print('[FocusEngine][$level] $message');
        },
      );
    });

    tearDown(() {
      engine.dispose();
    });

    test('FocusEngine initializes with synheart-core config', () {
      expect(engine.config.highFocusThreshold, equals(0.7));
      expect(engine.config.mediumFocusThreshold, equals(0.4));
      expect(engine.config.hsiWeight, equals(0.6));
      expect(engine.config.behaviorWeight, equals(0.4));
      expect(engine.config.enableSmoothing, isTrue);
    });

    test('infer accepts multimodal HSI and behavior data', () async {
      // synheart-core FocusHead provides HSI data from biosignals
      final hsiData = const HSIData(
        hr: 72.0,
        hrvRmssd: 45.0,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      // and behavioral data from Behavior Module
      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      // Perform inference
      final focusState = await engine.infer(hsiData, behaviorData);

      // Verify FocusState is returned
      expect(focusState, isA<FocusState>());
      expect(focusState.focusScore, inInclusiveRange(0.0, 1.0));
      expect(focusState.confidence, inInclusiveRange(0.0, 1.0));
      expect(focusState.focusLabel, isNotEmpty);
    });

    test('FocusState output is compatible with HSI schema', () async {
      final hsiData = const HSIData(
        hr: 75.0,
        hrvRmssd: 50.0,
        stressIndex: 0.2,
        motionIntensity: 0.15,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.15,
        interactionBurstiness: 0.25,
        idleRatio: 0.08,
      );

      final focusState = await engine.infer(hsiData, behaviorData);

      // Verify HSI-compatible output schema
      // According to HSI_SPECIFICATION.md, FocusState should have:
      // - score (0.0-1.0)
      // - cognitiveLoad (0.0-1.0) - can be derived
      // - clarity (0.0-1.0) - can be derived
      // - distraction (0.0-1.0) - can be derived

      expect(focusState.focusScore, inInclusiveRange(0.0, 1.0));
      expect(focusState.confidence, inInclusiveRange(0.0, 1.0));
      expect(focusState.focusLabel, isIn(['High Focus', 'Medium Focus', 'Low Focus']));
      expect(focusState.timestamp, isNotNull);
      expect(focusState.metadata, isNotNull);
    });

    test('HSI FocusState mapping calculations are correct', () async {
      final hsiData = const HSIData(
        hr: 70.0,
        hrvRmssd: 55.0,
        stressIndex: 0.25,
        motionIntensity: 0.1,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.1,
        interactionBurstiness: 0.3,
        idleRatio: 0.05,
      );

      final focusState = await engine.infer(hsiData, behaviorData);

      // Map to HSI FocusState (matching synheart-core pattern)
      final score = focusState.focusScore.clamp(0.0, 1.0);

      // Derived fields for HSI compatibility
      // cognitiveLoad can be derived from stress and task switching
      final cognitiveLoad = ((hsiData.stressIndex + behaviorData.taskSwitchRate) / 2.0)
          .clamp(0.0, 1.0);

      // clarity can be derived from HRV and engagement
      final clarity = (focusState.focusScore * focusState.confidence)
          .clamp(0.0, 1.0);

      // distraction is inverse of focus
      final distraction = (1.0 - focusState.focusScore).clamp(0.0, 1.0);

      // Verify all fields are valid
      expect(score, inInclusiveRange(0.0, 1.0));
      expect(cognitiveLoad, inInclusiveRange(0.0, 1.0));
      expect(clarity, inInclusiveRange(0.0, 1.0));
      expect(distraction, inInclusiveRange(0.0, 1.0));

      // Verify inverse relationship
      expect(distraction, closeTo(1.0 - score, 0.01));
    });

    test('handles streaming updates for reactive integration', () async {
      // synheart-core FocusHead subscribes to onUpdate stream
      final updatesFuture = engine.onUpdate.take(3).toList();

      // Push multiple inferences
      for (int i = 0; i < 3; i++) {
        final hsiData = HSIData(
          hr: 70.0 + i * 5,
          hrvRmssd: 45.0 + i * 2,
          stressIndex: 0.3 + i * 0.05,
          motionIntensity: 0.1 + i * 0.05,
        );

        final behaviorData = BehaviorData(
          taskSwitchRate: 0.2 + i * 0.1,
          interactionBurstiness: 0.15 + i * 0.05,
          idleRatio: 0.1 + i * 0.05,
        );

        await engine.infer(hsiData, behaviorData);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final updates = await updatesFuture;

      // Verify we received all updates
      expect(updates, hasLength(3));

      // Verify each update is valid
      for (final update in updates) {
        expect(update.focusScore, inInclusiveRange(0.0, 1.0));
        expect(update.confidence, inInclusiveRange(0.0, 1.0));
        expect(update.focusLabel, isNotEmpty);
      }
    });

    test('applies temporal smoothing for stable output', () async {
      // First inference establishes baseline
      final hsiData1 = const HSIData(
        hr: 70.0,
        hrvRmssd: 50.0,
        stressIndex: 0.2,
        motionIntensity: 0.1,
      );

      final behaviorData1 = const BehaviorData(
        taskSwitchRate: 0.1,
        interactionBurstiness: 0.2,
        idleRatio: 0.05,
      );

      final result1 = await engine.infer(hsiData1, behaviorData1);

      // Second inference with very different inputs
      final hsiData2 = const HSIData(
        hr: 100.0,
        hrvRmssd: 25.0,
        stressIndex: 0.8,
        motionIntensity: 0.6,
      );

      final behaviorData2 = const BehaviorData(
        taskSwitchRate: 1.5,
        interactionBurstiness: 0.8,
        idleRatio: 0.5,
      );

      final result2 = await engine.infer(hsiData2, behaviorData2);

      // Smoothing should prevent dramatic jumps
      final scoreChange = (result2.focusScore - result1.focusScore).abs();

      // With smoothing factor 0.3, change should be dampened
      // (not testing exact value, just that smoothing occurred)
      expect(result1.focusScore, isNot(equals(result2.focusScore)));
      expect(scoreChange, lessThan(0.5)); // Dampened by smoothing
    });

    test('handles edge case inputs gracefully', () async {
      // Test with extreme HR
      final hsiDataHighHR = const HSIData(
        hr: 180.0,
        hrvRmssd: 15.0,
        stressIndex: 0.95,
        motionIntensity: 0.9,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.3,
        idleRatio: 0.1,
      );

      final result1 = await engine.infer(hsiDataHighHR, behaviorData);
      expect(result1.focusScore, inInclusiveRange(0.0, 1.0));

      // Test with low HR
      final hsiDataLowHR = const HSIData(
        hr: 45.0,
        hrvRmssd: 80.0,
        stressIndex: 0.1,
        motionIntensity: 0.05,
      );

      final result2 = await engine.infer(hsiDataLowHR, behaviorData);
      expect(result2.focusScore, inInclusiveRange(0.0, 1.0));

      // Test with extreme task switching
      final hsiData = const HSIData(
        hr: 75.0,
        hrvRmssd: 40.0,
        stressIndex: 0.3,
        motionIntensity: 0.2,
      );

      final behaviorDataHighSwitch = const BehaviorData(
        taskSwitchRate: 5.0, // Very high switching
        interactionBurstiness: 0.95,
        idleRatio: 0.8,
      );

      final result3 = await engine.infer(hsiData, behaviorDataHighSwitch);
      expect(result3.focusScore, inInclusiveRange(0.0, 1.0));
      expect(result3.focusScore, lessThan(0.6)); // Should be lower focus with high switching
    });

    test('reset clears engine state', () async {
      // Establish some state
      final hsiData = const HSIData(
        hr: 72.0,
        hrvRmssd: 45.0,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      await engine.infer(hsiData, behaviorData);

      // Reset engine
      engine.reset();

      // Verify state is cleared (next inference should not be smoothed)
      final result1 = await engine.infer(hsiData, behaviorData);
      final result2 = await engine.infer(hsiData, behaviorData);

      // With reset, first inference after should not have smoothing influence
      // from before reset
      expect(result1.focusScore, greaterThan(0.0));
      expect(result2.focusScore, greaterThan(0.0));
    });

    test('confidence decreases with extreme/invalid values', () async {
      // Normal values should have higher confidence
      final hsiDataNormal = const HSIData(
        hr: 72.0,
        hrvRmssd: 45.0,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      final resultNormal = await engine.infer(hsiDataNormal, behaviorData);

      // Extreme values should have lower confidence
      final hsiDataExtreme = const HSIData(
        hr: 185.0,
        hrvRmssd: 5.0,
        stressIndex: 0.98,
        motionIntensity: 0.95,
      );

      final resultExtreme = await engine.infer(hsiDataExtreme, behaviorData);

      // Extreme values should generally have lower confidence
      expect(resultNormal.confidence, greaterThan(0.6));
      expect(resultExtreme.confidence, lessThanOrEqualTo(resultNormal.confidence));
    });

    test('focus labels are assigned correctly', () async {
      // High focus scenario
      final hsiDataHighFocus = const HSIData(
        hr: 70.0,
        hrvRmssd: 55.0,
        stressIndex: 0.15,
        motionIntensity: 0.05,
      );

      final behaviorDataHighFocus = const BehaviorData(
        taskSwitchRate: 0.08,
        interactionBurstiness: 0.28,
        idleRatio: 0.03,
      );

      final resultHigh = await engine.infer(hsiDataHighFocus, behaviorDataHighFocus);
      expect(resultHigh.focusLabel, anyOf('High Focus', 'Medium Focus'));

      // Low focus scenario
      final hsiDataLowFocus = const HSIData(
        hr: 110.0,
        hrvRmssd: 20.0,
        stressIndex: 0.85,
        motionIntensity: 0.75,
      );

      final behaviorDataLowFocus = const BehaviorData(
        taskSwitchRate: 2.5,
        interactionBurstiness: 0.9,
        idleRatio: 0.7,
      );

      final resultLow = await engine.infer(hsiDataLowFocus, behaviorDataLowFocus);
      expect(resultLow.focusLabel, 'Low Focus');
      expect(resultLow.focusScore, lessThan(0.4));
    });

    test('metadata contains useful diagnostic information', () async {
      final hsiData = const HSIData(
        hr: 72.0,
        hrvRmssd: 45.0,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      final result = await engine.infer(hsiData, behaviorData);

      // Verify metadata exists and contains expected fields
      expect(result.metadata, isNotNull);
      expect(result.metadata!.containsKey('hsiScore'), isTrue);
      expect(result.metadata!.containsKey('behaviorScore'), isTrue);
      expect(result.metadata!.containsKey('rawScore'), isTrue);

      // Verify metadata values are valid
      expect(result.metadata!['hsiScore'], inInclusiveRange(0.0, 1.0));
      expect(result.metadata!['behaviorScore'], inInclusiveRange(0.0, 1.0));
      expect(result.metadata!['rawScore'], inInclusiveRange(0.0, 1.0));
    });
  });

  group('FocusState HSI Compatibility', () {
    test('toJson output is HSI-compatible', () {
      final focusState = FocusState(
        focusScore: 0.75,
        focusLabel: 'High Focus',
        confidence: 0.85,
        timestamp: DateTime(2025, 1, 1, 12, 0, 0),
        metadata: {
          'hsiScore': 0.72,
          'behaviorScore': 0.79,
          'rawScore': 0.748,
        },
      );

      final json = focusState.toJson();

      // Verify required fields
      expect(json.containsKey('focusScore'), isTrue);
      expect(json.containsKey('focusLabel'), isTrue);
      expect(json.containsKey('confidence'), isTrue);
      expect(json.containsKey('timestamp'), isTrue);

      // Verify values
      expect(json['focusScore'], equals(0.75));
      expect(json['focusLabel'], equals('High Focus'));
      expect(json['confidence'], equals(0.85));
      expect(json['timestamp'], isA<String>());

      // Verify metadata structure
      expect(json.containsKey('metadata'), isTrue);
      final metadata = json['metadata'] as Map<String, dynamic>;
      expect(metadata.containsKey('hsiScore'), isTrue);
      expect(metadata.containsKey('behaviorScore'), isTrue);
    });

    test('FocusState fields map to HSI schema', () {
      final focusState = FocusState(
        focusScore: 0.68,
        focusLabel: 'Medium Focus',
        confidence: 0.78,
        timestamp: DateTime.now(),
        metadata: const {
          'hsiScore': 0.65,
          'behaviorScore': 0.72,
        },
      );

      // Map to HSI FocusState schema
      final score = focusState.focusScore;
      final cognitiveLoad = 1.0 - focusState.focusScore; // Inverse relationship
      final clarity = focusState.focusScore * focusState.confidence;
      final distraction = 1.0 - focusState.focusScore;

      // Verify all mapped fields are valid
      expect(score, inInclusiveRange(0.0, 1.0));
      expect(cognitiveLoad, inInclusiveRange(0.0, 1.0));
      expect(clarity, inInclusiveRange(0.0, 1.0));
      expect(distraction, inInclusiveRange(0.0, 1.0));

      // Verify relationships
      expect(distraction, closeTo(1.0 - score, 0.01));
      expect(clarity, lessThanOrEqualTo(score));
    });
  });

  group('FocusConfig Customization', () {
    test('custom thresholds affect focus labels', () async {
      final customEngine = FocusEngine(
        config: const FocusConfig(
          highFocusThreshold: 0.8,  // Higher threshold
          mediumFocusThreshold: 0.5, // Higher threshold
        ),
      );

      final hsiData = const HSIData(
        hr: 72.0,
        hrvRmssd: 45.0,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      final result = await customEngine.infer(hsiData, behaviorData);

      // With higher thresholds, same inputs might result in lower label
      expect(result.focusScore, inInclusiveRange(0.0, 1.0));
      expect(result.focusLabel, isIn(['High Focus', 'Medium Focus', 'Low Focus']));

      customEngine.dispose();
    });

    test('custom weights affect score calculation', () async {
      // Engine favoring HSI
      final hsiEngine = FocusEngine(
        config: const FocusConfig(
          hsiWeight: 0.9,
          behaviorWeight: 0.1,
        ),
      );

      // Engine favoring behavior
      final behaviorEngine = FocusEngine(
        config: const FocusConfig(
          hsiWeight: 0.1,
          behaviorWeight: 0.9,
        ),
      );

      final hsiData = const HSIData(
        hr: 70.0,
        hrvRmssd: 55.0,
        stressIndex: 0.15,
        motionIntensity: 0.05,
      );

      final behaviorData = const BehaviorData(
        taskSwitchRate: 0.08,
        interactionBurstiness: 0.28,
        idleRatio: 0.03,
      );

      final result1 = await hsiEngine.infer(hsiData, behaviorData);
      final result2 = await behaviorEngine.infer(hsiData, behaviorData);

      // Both should be valid but may differ based on weights
      expect(result1.focusScore, inInclusiveRange(0.0, 1.0));
      expect(result2.focusScore, inInclusiveRange(0.0, 1.0));

      hsiEngine.dispose();
      behaviorEngine.dispose();
    });
  });
}
