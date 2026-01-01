import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:synheart_focus/synheart_focus.dart';
import 'package:synheart_wear/synheart_wear.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synheart Focus Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FocusTestPage(),
    );
  }
}

class FocusTestPage extends StatefulWidget {
  const FocusTestPage({super.key});

  @override
  State<FocusTestPage> createState() => _FocusTestPageState();
}

class _FocusTestPageState extends State<FocusTestPage> {
  FocusEngine? _engine;
  bool _isInitialized = false;
  bool _isRunning = false;
  String _status = 'Not initialized';
  
  // Current inference result
  FocusResult? _currentResult;
  
  // Timer for continuous HR data generation
  DateTime? _startTime;
  int _dataPointCount = 0;
  
  // Timer for window tracking
  int _windowElapsedSeconds = 0;
  int _totalElapsedSeconds = 0; // Total elapsed time since start

  @override
  void initState() {
    super.initState();
    _initializeEngine();
    _initializeWearable();
  }
  
  @override
  void dispose() {
    _hrStreamSubscription?.cancel();
    _synheartWear?.dispose();
    super.dispose();
  }
  
  Future<void> _initializeWearable() async {
    try {
      // Initialize SynheartWear SDK
      final adapters = <DeviceAdapter>{
        DeviceAdapter.appleHealthKit, // Uses Health Connect on Android
      };

      _synheartWear = SynheartWear(
        config: SynheartWearConfig.withAdapters(adapters),
      );

      // Request permissions
      final permissionsGranted = await _synheartWear!.requestPermissions(
        permissions: {
          PermissionType.heartRate,
        },
        reason: 'This app needs access to your heart rate data to analyze cognitive focus.',
      );

      if (!permissionsGranted) {
        setState(() {
          _status = 'Permissions denied';
          _deviceInfo = 'Please grant health permissions in Settings';
        });
        print('⚠️ Health permissions not granted');
        return;
      }

      // Initialize the SDK
      await _synheartWear!.initialize();
      
      // Check initial connection
      final initialMetrics = await _synheartWear!.readMetrics();
      if (initialMetrics != null) {
        setState(() {
          _wearableConnected = true;
          _deviceInfo = 'Device: ${initialMetrics.deviceId ?? "Unknown"}';
        });
        print('✓ Wearable device connected: ${initialMetrics.deviceId}');
      }
    } catch (e) {
      print('✗ Error initializing wearable: $e');
      setState(() {
        _deviceInfo = 'Error: $e';
      });
    }
  }

  Future<void> _initializeEngine() async {
    try {
      print('═══════════════════════════════════════════════════════');
      print('Initializing Focus Engine with Gradient Boosting model...');
      print('═══════════════════════════════════════════════════════\n');
      
      setState(() {
        _status = 'Initializing...';
      });

      _engine = FocusEngine(
        config: const FocusConfig(
          windowSeconds: 60,  // 60-second window
          stepSeconds: 5,     // 5-second step
          minRrCount: 30,
          enableDebugLogging: true,
        ),
        onLog: (level, message, {context}) {
          print('[$level] $message');
        },
      );

      print('Loading model: assets/models/Gradient_Boosting.onnx...');
      await _engine!.initialize(
        modelPath: 'assets/models/Gradient_Boosting.onnx',
        backend: 'onnx',
      );

      print('✓ Model loaded successfully!');
      print('Window: 60 seconds, Step: 5 seconds\n');
      setState(() {
        _isInitialized = true;
        _status = 'Ready';
      });
    } catch (e, stackTrace) {
      print('✗ Error initializing engine: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  /// Generate Gaussian random number using Box-Muller transform
  double _nextGaussian(Random rng) {
    double u1 = rng.nextDouble();
    double u2 = rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  /// Generate realistic HR data with smooth transitions
  double _generateRealisticHR(DateTime currentTime, DateTime startTime) {
    final elapsed = currentTime.difference(startTime).inSeconds;
    
    // Simulate different cognitive states over time
    double baseHR;
    double variability;
    
    if (elapsed < 120) {
      // First 2 minutes: Focused state
      baseHR = 70.0;
      variability = 4.0;
    } else if (elapsed < 240) {
      // Next 2 minutes: Anxious state
      baseHR = 88.0;
      variability = 7.0;
    } else if (elapsed < 360) {
      // Next 2 minutes: Bored state
      baseHR = 62.0;
      variability = 3.0;
    } else {
      // After 6 minutes: Overload state
      baseHR = 95.0;
      variability = 9.0;
    }
    
    // Add some natural variation with smooth transitions
    final random = Random(elapsed);
    final variation = _nextGaussian(random) * variability;
    
    // Add a subtle sine wave for natural HR variation
    final sineVariation = 2.0 * sin(elapsed * 0.1);
    
    final hr = baseHR + variation + sineVariation;
    
    // Clamp to physiological range
    return hr.clamp(45.0, 120.0);
  }

  Future<void> _startRealTimeSimulation() async {
    if (!_isInitialized || _engine == null || _isRunning) return;
    
    if (_synheartWear == null) {
      print('⚠️ Wearable service not initialized');
      setState(() {
        _status = 'Wearable service not available';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _startTime = DateTime.now();
      _dataPointCount = 0;
      _currentResult = null;
      _windowElapsedSeconds = 0;
      _totalElapsedSeconds = 0;
    });

    print('\n═══════════════════════════════════════════════════════');
    print('Starting Real-Time HR Data Streaming from Wearable');
    print('Window: 60 seconds | Step: 5 seconds');
    print('═══════════════════════════════════════════════════════\n');

    // Timer to update elapsed time every second
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRunning) {
        timer.cancel();
        return;
      }
      if (_startTime != null) {
        final elapsed = DateTime.now().difference(_startTime!).inSeconds;
        setState(() {
          _totalElapsedSeconds = elapsed;
          // Show seconds within current 60-second window (for display)
          _windowElapsedSeconds = elapsed < 60 ? elapsed : elapsed % 60;
        });
      }
    });

    // Stream HR data from wearable device (every 1 second)
    _hrStreamSubscription = _synheartWear!.streamHR(interval: const Duration(seconds: 1))
        .listen(
      (metrics) {
        if (!_isRunning) return;
        
        final hr = metrics.getMetric(MetricType.hr);
        if (hr == null) {
          // No HR data available yet
          return;
        }

        _dataPointCount++;
        final currentTime = DateTime.now();

        // Update device info
        setState(() {
          _wearableConnected = true;
          _deviceInfo = 'Device: ${metrics.deviceId ?? "Unknown"} | HR: ${hr.toStringAsFixed(0)} bpm';
        });

        // Feed HR data to inference engine
        _engine!.inferFromHrData(
          hrBpm: hr.toDouble(),
          timestamp: currentTime,
        ).then((result) {
          if (result != null) {
            // Update UI with new result
            setState(() {
              _currentResult = result;
            });

            // Log to console
            final elapsed = currentTime.difference(_startTime!).inSeconds;
            print('[$elapsed s] ✓ Inference completed!');
            print('  HR: ${hr.toStringAsFixed(0)} BPM');
            print('  State: ${result.focusState}');
            print('  Score: ${result.focusScore.toStringAsFixed(1)}');
            print('  Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%');
            print('  Probabilities: ${result.probabilities}');
          } else {
            // Log data collection status periodically
            final elapsed = currentTime.difference(_startTime!).inSeconds;
            if (elapsed <= 60 && elapsed % 15 == 0) {
              // Log every 15 seconds during first 60 seconds
              print('[$elapsed s] Collecting data... (${elapsed}/60 seconds) | HR: ${hr.toStringAsFixed(0)} BPM');
            } else if (elapsed > 60 && elapsed % 5 == 0) {
              // Log every 5 seconds after 60 seconds if no inference
              print('[$elapsed s] Waiting for inference... | HR: ${hr.toStringAsFixed(0)} BPM');
            }
          }
        }).catchError((e) {
          print('Error processing HR data: $e');
        });
      },
      onError: (error) {
        print('Error streaming HR: $error');
        setState(() {
          _wearableConnected = false;
          _deviceInfo = 'Stream error: $error';
        });
      },
    );
  }

  void _stopSimulation() {
    print('\n⚠ Simulation stopped by user\n');
    _hrStreamSubscription?.cancel();
    setState(() {
      _isRunning = false;
    });
  }

  @override
  void dispose() {
    _stopSimulation();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Synheart Focus - Real-Time'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isInitialized
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isInitialized
                      ? Colors.green.shade300
                      : Colors.orange.shade300,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isInitialized ? Icons.check_circle : Icons.warning,
                    color: _isInitialized ? Colors.green : Colors.orange,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          _status,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _isInitialized ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _deviceInfo,
                          style: TextStyle(
                            fontSize: 12,
                            color: _wearableConnected ? Colors.green.shade700 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isRunning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Window Timer Display
            if (_isRunning)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _totalElapsedSeconds >= 60 
                      ? Colors.green.shade100 
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _totalElapsedSeconds >= 60 
                        ? Colors.green.shade300 
                        : Colors.orange.shade300,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _totalElapsedSeconds >= 60 
                              ? Icons.check_circle 
                              : Icons.timer,
                          color: _totalElapsedSeconds >= 60 
                              ? Colors.green 
                              : Colors.orange,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          children: [
                            Text(
                              _totalElapsedSeconds < 60 
                                  ? 'Collecting Data' 
                                  : 'Window Active',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              _totalElapsedSeconds < 60 
                                  ? '${_totalElapsedSeconds}s / 60s'
                                  : '${_totalElapsedSeconds}s elapsed',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _totalElapsedSeconds >= 60 
                                    ? Colors.green.shade700 
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_totalElapsedSeconds < 60) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _totalElapsedSeconds / 60.0,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Waiting for 60-second window...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Inference: every 5s using last 60s of data',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            if (_isRunning) const SizedBox(height: 24),

            // Control buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isInitialized && !_isRunning
                        ? _startRealTimeSimulation
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start HR Streaming'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRunning ? _stopSimulation : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Current Result Display
            if (_currentResult != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.psychology, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Current Cognitive State',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Dominant label
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
color: Colors.blue.shade200,
blurRadius: 4,
offset: const Offset(0, 2),
),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _currentResult!.focusState,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Focus Score - Prominent Display
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade300, width: 2),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Focus Score',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_currentResult!.focusScore.toStringAsFixed(1)}',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: _currentResult!.focusScore / 100.0,
                                  backgroundColor: Colors.grey.shade300,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _currentResult!.focusScore >= 70 
                                        ? Colors.green 
                                        : _currentResult!.focusScore >= 40 
                                            ? Colors.orange 
                                            : Colors.red,
                                  ),
                                  minHeight: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Confidence: ',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                '${(_currentResult!.confidence * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // All probabilities
                    Text(
                      'All Class Probabilities:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._currentResult!.probabilities.entries.map((entry) {
                      final isDominant = entry.key == _currentResult!.focusState;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDominant ? Colors.blue.shade100 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDominant ? Colors.blue.shade300 : Colors.grey.shade300,
                            width: isDominant ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isDominant ? FontWeight.bold : FontWeight.normal,
                                  color: isDominant ? Colors.blue.shade900 : Colors.grey.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: LinearProgressIndicator(
                                value: entry.value,
                                backgroundColor: Colors.grey.shade300,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isDominant ? Colors.blue : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 50,
                              child: Text(
                                '${(entry.value * 100).toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDominant ? Colors.blue.shade700 : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    
                    const SizedBox(height: 24),
                    
                    // Features Display
                    Text(
                      'HRV Features (24 features):',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _currentResult!.features.entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        entry.key,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        entry.value.toStringAsFixed(4),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No inference results yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start the simulation to see real-time results',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Info box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Results update every 5 seconds as the 60-second window slides. Check console for detailed logs.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
