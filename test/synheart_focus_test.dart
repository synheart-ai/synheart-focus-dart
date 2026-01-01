import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_focus/synheart_focus.dart';

void main() {
  group('FocusEngine', () {
    late FocusEngine engine;

    setUp(() {
      engine = FocusEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('initializes with default config', () {
      expect(engine.config, isNotNull);
      expect(engine.config.highFocusThreshold, 0.7);
      expect(engine.config.mediumFocusThreshold, 0.4);
    });

    test('performs basic inference', () async {
      const hsiData = HSIData(
        hr: 72,
        hrvRmssd: 45,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      const behaviorData = BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      final result = await engine.infer(hsiData, behaviorData);

      expect(result.focusScore, greaterThanOrEqualTo(0.0));
      expect(result.focusScore, lessThanOrEqualTo(1.0));
      expect(result.focusLabel, isNotEmpty);
      expect(result.confidence, greaterThanOrEqualTo(0.0));
      expect(result.confidence, lessThanOrEqualTo(1.0));
    });

    test('emits updates on stream', () async {
      const hsiData = HSIData(
        hr: 72,
        hrvRmssd: 45,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      const behaviorData = BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      final streamFuture = engine.onUpdate.first;
      await engine.infer(hsiData, behaviorData);
      final streamResult = await streamFuture;

      expect(streamResult.focusScore, greaterThanOrEqualTo(0.0));
    });

    test('applies smoothing over multiple inferences', () async {
      const hsiData1 = HSIData(
        hr: 72,
        hrvRmssd: 45,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      const hsiData2 = HSIData(
        hr: 100,
        hrvRmssd: 30,
        stressIndex: 0.7,
        motionIntensity: 0.5,
      );

      const behaviorData = BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      final result1 = await engine.infer(hsiData1, behaviorData);
      final result2 = await engine.infer(hsiData2, behaviorData);

      // Second result should be influenced by first (smoothing)
      // but not equal to raw score of second input
      expect(result1.focusScore, isNot(equals(result2.focusScore)));
      expect(result2.focusScore, greaterThan(0.0));
    });

    test('returns high focus for optimal inputs', () async {
      const hsiData = HSIData(
        hr: 70,
        hrvRmssd: 50,
        stressIndex: 0.1,
        motionIntensity: 0.05,
      );

      const behaviorData = BehaviorData(
        taskSwitchRate: 0.1,
        interactionBurstiness: 0.3,
        idleRatio: 0.05,
      );

      final result = await engine.infer(hsiData, behaviorData);

      expect(result.focusScore, greaterThan(0.6));
      expect(result.focusLabel, anyOf('High Focus', 'Medium Focus'));
    });

    test('returns low focus for poor inputs', () async {
      const hsiData = HSIData(
        hr: 120,
        hrvRmssd: 15,
        stressIndex: 0.9,
        motionIntensity: 0.8,
      );

      const behaviorData = BehaviorData(
        taskSwitchRate: 2.0,
        interactionBurstiness: 0.9,
        idleRatio: 0.8,
      );

      final result = await engine.infer(hsiData, behaviorData);

      expect(result.focusScore, lessThan(0.5));
    });
  });

  group('FocusConfig', () {
    test('creates with default values', () {
      const config = FocusConfig();

      expect(config.highFocusThreshold, 0.7);
      expect(config.mediumFocusThreshold, 0.4);
      expect(config.hsiWeight, 0.6);
      expect(config.behaviorWeight, 0.4);
    });

    test('copyWith updates values correctly', () {
      const config = FocusConfig();
      final updated = config.copyWith(highFocusThreshold: 0.8);

      expect(updated.highFocusThreshold, 0.8);
      expect(updated.mediumFocusThreshold, 0.4);
    });
  });

  group('Data Models', () {
    test('HSIData toJson works correctly', () {
      const data = HSIData(
        hr: 72,
        hrvRmssd: 45,
        stressIndex: 0.3,
        motionIntensity: 0.1,
      );

      final json = data.toJson();

      expect(json['hr'], 72);
      expect(json['hrvRmssd'], 45);
      expect(json['stressIndex'], 0.3);
      expect(json['motionIntensity'], 0.1);
    });

    test('BehaviorData toJson works correctly', () {
      const data = BehaviorData(
        taskSwitchRate: 0.2,
        interactionBurstiness: 0.15,
        idleRatio: 0.1,
      );

      final json = data.toJson();

      expect(json['taskSwitchRate'], 0.2);
      expect(json['interactionBurstiness'], 0.15);
      expect(json['idleRatio'], 0.1);
    });
  });
}
