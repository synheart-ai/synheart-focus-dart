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
      // Load metadata from JSON file
      // Try Gradient_Boosting_metadata.json first, then fallback to other formats
      String? metadataJsonString;
      try {
        final possiblePaths = [
          modelPath.replaceAll('.onnx', '_metadata.json'),
          modelPath.replaceAll(
            'Gradient_Boosting.onnx',
            'Gradient_Boosting_metadata.json',
          ),
          modelPath.replaceAll(
            'cnn_lstm_top_6_features.onnx',
            'scaler_info_top_6_features.json',
          ),
          'packages/synheart_focus/assets/models/Gradient_Boosting_metadata.json',
          'assets/models/Gradient_Boosting_metadata.json',
          'packages/synheart_focus/assets/models/scaler_info_top_6_features.json',
          'assets/models/scaler_info_top_6_features.json',
        ];

        for (final path in possiblePaths) {
          try {
            metadataJsonString = await rootBundle.loadString(path);
            break;
          } catch (_) {
            continue;
          }
        }

        if (metadataJsonString == null) {
          throw Exception('Metadata file not found');
        }
      } catch (e) {
        throw Exception('Failed to load metadata: $e');
      }

      final metadata = json.decode(metadataJsonString) as Map<String, dynamic>;

      // Check if this is the new format (Gradient Boosting) or old format
      final isNewFormat = metadata.containsKey('model_id') &&
          metadata.containsKey('classes') &&
          metadata.containsKey('features');

      if (isNewFormat) {
        // New format: Gradient Boosting model
        _featureNames = List<String>.from(metadata['features'] as List);
        final classNames = List<String>.from(metadata['classes'] as List);

        // New model uses z-score normalization (subject-specific), not scaler
        // So we don't load scaler mean/scale
        _scalerMean = [];
        _scalerScale = [];

        // Initialize ONNX Runtime
        final ort = OnnxRuntime();
        _session = await ort.createSessionFromAsset(modelPath);

        // Create model info
        _info = ModelInfo(
          id: metadata['model_id'] as String? ?? 'gradient_boosting_4class',
          type: 'onnx',
          checksum: '',
          inputSchema: _featureNames,
          classNames: classNames,
          positiveClass: 'Focused',
        );

        // Model metadata is parsed from JSON above; ONNXRuntimeModel currently
        // exposes metadata via `info` (ModelInfo) and inference outputs.
      } else {
        // Old format: CNN-LSTM with scaler
        _scalerMean = List<double>.from(
          (metadata['mean_'] as List).map((e) => (e as num).toDouble()),
        );
        _scalerScale = List<double>.from(
          (metadata['scale_'] as List).map((e) => (e as num).toDouble()),
        );
        _featureNames = List<String>.from(
          metadata['feature_names'] as List? ??
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

        // Model metadata is parsed from JSON above; ONNXRuntimeModel currently
        // exposes metadata via `info` (ModelInfo) and inference outputs.
      }

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
  /// For new model, features should already be z-score normalized (subject-specific)
  List<double> _normalizeFeatures(List<double> features) {
    // If no scaler (new model), features should already be normalized
    if (_scalerMean.isEmpty || _scalerScale.isEmpty) {
      return features;
    }

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
    List<double> features,
  ) async {
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
      final inputTensor = await OrtValue.fromList(
        normalizedFeatures,
        inputShape,
      );

      // Run inference
      final inputs = <String, OrtValue>{inputName: inputTensor};
      final outputs = await _session.run(inputs);

      if (outputs.isEmpty) {
        throw Exception('ONNX inference returned no outputs');
      }

      // Handle different output formats
      // New model may output both label and probabilities
      // Old model outputs logits that need softmax

      // Try to extract probabilities directly first
      List<double> probabilities;
      try {
        // Check if output is already probabilities (new model format)
        final probData = await _extractProbabilities(outputs);
        if (probData.isNotEmpty &&
            probData.length == _info.classNames!.length) {
          probabilities = probData;
        } else {
          // Extract logits and apply softmax
          final logits = await _extractLogits(outputs);
          if (logits.isEmpty) {
            throw Exception('ONNX inference produced empty logits');
          }
          probabilities = _softmax(logits);
        }
      } catch (e) {
        // Fallback: extract logits
        final logits = await _extractLogits(outputs);
        if (logits.isEmpty) {
          throw Exception('ONNX inference produced empty logits');
        }
        probabilities = _softmax(logits);
      }

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

  @override
  Future<void> dispose() async {
    if (_isLoaded) {
      // ONNX sessions are automatically disposed when they go out of scope
      _isLoaded = false;
    }
  }

  Future<List<double>> _extractProbabilities(
    Map<String, OrtValue> outputs,
  ) async {
    for (final entry in outputs.entries) {
      final data = await entry.value.asList();
      final flattened = _flattenToDoubles(data);
      if (flattened != null && flattened.isNotEmpty) {
        return flattened;
      }
    }
    throw Exception('Could not extract probability tensor from outputs');
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
