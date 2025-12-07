import 'package:flutter/material.dart';
import 'package:synheart_focus/synheart_focus.dart';

void main() {
  // Start the Flutter app immediately
  runApp(const MyApp());

  // Run console simulation in the background
  _runConsoleSimulation();
}

Future<void> _runConsoleSimulation() async {
  // Initialize the FocusEngine with custom configuration
  final focusEngine = FocusEngine(
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synheart Focus Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FocusDemoPage(),
    );
  }
}

class FocusDemoPage extends StatefulWidget {
  const FocusDemoPage({super.key});

  @override
  State<FocusDemoPage> createState() => _FocusDemoPageState();
}

class _FocusDemoPageState extends State<FocusDemoPage> {
  FocusEngine? _focusEngine;
  FocusState? _currentFocusState;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeEngine();
  }

  void _initializeEngine() {
    _focusEngine = FocusEngine(
      config: const FocusConfig(
        highFocusThreshold: 0.75,
        mediumFocusThreshold: 0.45,
        enableDebugLogging: true,
      ),
    );

    _focusEngine!.onUpdate.listen((focusState) {
      if (mounted) {
        setState(() {
          _currentFocusState = focusState;
        });
      }
    });

    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _simulateFocusState({
    required HSIData hsiData,
    required BehaviorData behaviorData,
  }) async {
    await _focusEngine?.infer(hsiData, behaviorData);
  }

  Color _getFocusColor() {
    if (_currentFocusState == null) return Colors.grey;
    final score = _currentFocusState!.focusScore;
    if (score >= 0.75) return Colors.green;
    if (score >= 0.45) return Colors.orange;
    return Colors.red;
  }

  Color _getFocusColorLight() {
    final color = _getFocusColor();
    return color.withOpacity(0.1);
  }

  @override
  void dispose() {
    _focusEngine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synheart Focus Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isInitialized
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Focus Score Card
                  Card(
                    elevation: 4,
                    child: Container(
                      padding: const EdgeInsets.all(32.0),
                      decoration: BoxDecoration(
                        color: _getFocusColorLight(),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Focus Score',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: _currentFocusState?.focusScore ?? 0.0,
                                  strokeWidth: 20,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _getFocusColor(),
                                  ),
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _currentFocusState?.focusScore
                                              .toStringAsFixed(2) ??
                                          '0.00',
                                      style: TextStyle(
                                        fontSize: 48,
                                        fontWeight: FontWeight.bold,
                                        color: _getFocusColor(),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _currentFocusState?.focusLabel ?? 'N/A',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: _getFocusColor(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Details Card
                  if (_currentFocusState != null)
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Details',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow(
                              'Confidence',
                              '${(_currentFocusState!.confidence * 100).toStringAsFixed(1)}%',
                              Icons.verified,
                            ),
                            const SizedBox(height: 12),
                            _buildDetailRow(
                              'Timestamp',
                              _formatTimestamp(_currentFocusState!.timestamp),
                              Icons.access_time,
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_currentFocusState == null)
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'Tap a button below to simulate focus states',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Simulation Buttons
                  const Text(
                    'Simulate Focus States',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  _buildSimulationButton(
                    label: 'High Focus',
                    description: 'Calm, focused state',
                    color: Colors.green,
                    onPressed: () => _simulateFocusState(
                      hsiData: const HSIData(
                        hr: 70,
                        hrvRmssd: 50,
                        stressIndex: 0.2,
                        motionIntensity: 0.05,
                      ),
                      behaviorData: const BehaviorData(
                        taskSwitchRate: 0.1,
                        interactionBurstiness: 0.3,
                        idleRatio: 0.05,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildSimulationButton(
                    label: 'Moderate Focus',
                    description: 'Somewhat distracted',
                    color: Colors.orange,
                    onPressed: () => _simulateFocusState(
                      hsiData: const HSIData(
                        hr: 85,
                        hrvRmssd: 35,
                        stressIndex: 0.4,
                        motionIntensity: 0.2,
                      ),
                      behaviorData: const BehaviorData(
                        taskSwitchRate: 0.5,
                        interactionBurstiness: 0.5,
                        idleRatio: 0.15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildSimulationButton(
                    label: 'Low Focus',
                    description: 'Highly distracted',
                    color: Colors.red,
                    onPressed: () => _simulateFocusState(
                      hsiData: const HSIData(
                        hr: 105,
                        hrvRmssd: 20,
                        stressIndex: 0.8,
                        motionIntensity: 0.6,
                      ),
                      behaviorData: const BehaviorData(
                        taskSwitchRate: 1.5,
                        interactionBurstiness: 0.85,
                        idleRatio: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildSimulationButton({
    required String label,
    required String description,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.play_arrow),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }
}
