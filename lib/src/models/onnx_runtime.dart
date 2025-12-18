import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'on_device_model.dart';

class ONNXRuntimeModel implements OnDeviceModel {
  late final OrtSession _session;
  late final ModelInfo _info;
  late final List<double> _scalerMean;
  late final List<double> _scalerScale;
  late final List<String> _featureNames;
  bool _isLoaded = false;

  ONNXRuntimeModel._();

  static Future<ONNXRuntimeModel> load(String modelPath) async {
    final model = ONNXRuntimeModel._();
    await model._loadModel(modelPath);
    return model;
  }

  Future<void> _loadModel(String modelPath) async {
    try {
      // Load scaler info from JSON file (Python SDK format)
      // Try scaler_info_top_6_features.json first, then fallback to meta.json
      String? scalerJsonString;
      String? scalerPath;
      try {
        // Try different possible paths
        final possiblePaths = [
          modelPath.replaceAll('.onnx', '_scaler_info.json'),
          modelPath.replaceAll('.onnx', '_scaler.json'),
          modelPath.replaceAll('cnn_lstm_top_6_features.onnx',
              'scaler_info_top_6_features.json'),
          'packages/synheart_focus/assets/models/scaler_info_top_6_features.json',
          'assets/models/scaler_info_top_6_features.json',
        ];

        for (final path in possiblePaths) {
          try {
            scalerJsonString = await rootBundle.loadString(path);
            break;
          } catch (_) {
            continue;
          }
        }

        if (scalerJsonString == null) {
          throw Exception('Scaler info file not found');
        }
      } catch (e) {
        // Fallback: try meta.json format
        try {
          final metaPath = modelPath.replaceAll('.onnx', '.meta.json');
          scalerJsonString = await rootBundle.loadString(metaPath);
        } catch (_) {
          throw Exception('Failed to load scaler info: $e');
        }
      }

      final scalerInfo = json.decode(scalerJsonString) as Map<String, dynamic>;

      // Extract scaler statistics (Python SDK format)
      _scalerMean = List<double>.from(
        (scalerInfo['mean_'] as List).map((e) => (e as num).toDouble()),
      );
      _scalerScale = List<double>.from(
        (scalerInfo['scale_'] as List).map((e) => (e as num).toDouble()),
      );
      _featureNames = List<String>.from(
        scalerInfo['feature_names'] as List? ??
            ['MEDIAN_RR', 'HR', 'MEAN_RR', 'SDRR_RMSSD', 'pNN25', 'higuci'],
      );

      // Initialize ONNX Runtime
      final ort = OnnxRuntime();
      _session = await ort.createSessionFromAsset(modelPath);

      // Create model info matching Python SDK
      _info = ModelInfo(
        id: 'swell_focus_cnn_lstm_onnx_v1_0',
        type: 'onnx',
        checksum: '',
        inputSchema: _featureNames,
        classNames: ['Focused', 'time pressure', 'Distracted'],
        positiveClass: 'Focused',
      );

      _isLoaded = true;
    } catch (e) {
      throw Exception('Failed to load ONNX model: $e');
    }
  }

  @override
  ModelInfo get info {
    if (!_isLoaded) throw Exception('Model not loaded');
    return _info;
  }

  /// Normalize features using scaler statistics (matching Python SDK)
  List<double> _normalizeFeatures(List<double> features) {
    if (features.length != _scalerMean.length) {
      throw Exception(
        'Feature count mismatch: expected ${_scalerMean.length}, got ${features.length}',
      );
    }

    final normalized = <double>[];
    for (int i = 0; i < features.length; i++) {
      final mean = _scalerMean[i];
      final scale = _scalerScale[i];

      // Avoid division by zero
      if (scale > 0) {
        normalized.add((features[i] - mean) / scale);
      } else {
        normalized.add(0.0);
      }
    }
    return normalized;
  }

  /// Predict focus state probabilities (returns all class probabilities)
  /// Matching Python SDK ONNXFocusModel.predict() behavior
  Future<Map<String, double>> predictProbabilities(
      List<double> features) async {
    if (!_isLoaded) throw Exception('Model not loaded');

    try {
      // Normalize features using scaler statistics
      final normalizedFeatures = _normalizeFeatures(features);

      // Prepare input tensor
      if (_session.inputNames.isEmpty) {
        throw Exception('Model has no input names');
      }
      final inputName = _session.inputNames[0];
      final inputShape = [1, normalizedFeatures.length]; // Batch size 1
      final inputTensor =
          await OrtValue.fromList(normalizedFeatures, inputShape);

      // Run inference
      final inputs = <String, OrtValue>{inputName: inputTensor};
      final outputs = await _session.run(inputs);

      if (outputs.isEmpty) {
        throw Exception('ONNX inference returned no outputs');
      }

      // Extract logits from output
      // Note: _extractProbabilities is available as an alternative method
      // if the model outputs probabilities directly instead of logits
      final logits = await _extractLogits(outputs);

      if (logits.isEmpty) {
        throw Exception('ONNX inference produced empty logits');
      }

      // Apply softmax to get probabilities
      final probabilities = _softmax(logits);

      // Return as map matching Python SDK format
      final result = <String, double>{};
      for (int i = 0;
          i < _info.classNames!.length && i < probabilities.length;
          i++) {
        result[_info.classNames![i]] = probabilities[i];
      }

      return result;
    } catch (e) {
      throw Exception('ONNX inference failed: $e');
    }
  }

  @override
  Future<double> predict(List<double> features) async {
    final probabilities = await predictProbabilities(features);

    // Return probability of "Focused" class (positive class)
    return probabilities['Focused'] ??
        probabilities.values.reduce((a, b) => a > b ? a : b);
  }

  /// Extract logits from ONNX output
  Future<List<double>> _extractLogits(Map<String, OrtValue> outputs) async {
    for (final entry in outputs.entries) {
      final data = await entry.value.asList();
      final flattened = _flattenToDoubles(data);
      if (flattened != null && flattened.isNotEmpty) {
        return flattened;
      }
    }
    throw Exception('Could not extract logits tensor from outputs');
  }

  /// Apply softmax to convert logits to probabilities
  List<double> _softmax(List<double> logits) {
    // Find maximum for numerical stability
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);

    // Calculate exponentials
    final expValues =
        logits.map((logit) => math.exp(logit - maxLogit)).toList();

    final sumExp = expValues.fold(0.0, (a, b) => a + b);

    if (sumExp == 0.0) {
      // Fallback: uniform distribution
      return List.filled(logits.length, 1.0 / logits.length);
    }

    return expValues.map((exp) => exp / sumExp).toList();
  }

  /// Get model metadata (for debugging and inspection)
  Map<String, dynamic> get metadata {
    if (!_isLoaded) throw Exception('Model not loaded');
    return Map<String, dynamic>.from(_metadata);
  }

  @override
  Future<void> dispose() async {
    if (_isLoaded) {
      // ONNX sessions are automatically disposed when they go out of scope
      _isLoaded = false;
    }
  }

  List<double>? _flattenToDoubles(dynamic data) {
    if (data is List) {
      if (data.isEmpty) {
        return <double>[];
      }
      if (data.first is List) {
        return _flattenToDoubles(data.first);
      }
      if (data.first is num) {
        return data.map((e) => (e as num).toDouble()).toList();
      }
    }
    return null;
  }
}
