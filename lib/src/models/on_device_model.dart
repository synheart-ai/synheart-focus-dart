class ModelInfo {
  final String id;
  final String type;
  final String checksum;
  final List<String> inputSchema;
  final List<String>? classNames;
  final String? positiveClass;

  const ModelInfo({
    required this.id,
    required this.type,
    required this.checksum,
    required this.inputSchema,
    this.classNames,
    this.positiveClass,
  });
}

abstract class OnDeviceModel {
  ModelInfo get info;

  /// Features must follow `info.inputSchema`. Returns probability in [0,1].
  Future<double> predict(List<double> features);

  Future<void> dispose() async {}
}

