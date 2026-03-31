class RunOverrides {
  const RunOverrides({
    this.actualDurationHoursByNode = const {},
    this.batchQuantityByNode = const {},
    this.machineOverrideByNode = const {},
  });

  final Map<String, double> actualDurationHoursByNode;
  final Map<String, int> batchQuantityByNode;
  final Map<String, String> machineOverrideByNode;

  factory RunOverrides.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    return RunOverrides(
      actualDurationHoursByNode: Map<String, double>.fromEntries(
        (source['actualDurationHoursByNode'] as Map<String, dynamic>? ??
                const {})
            .entries
            .map(
              (entry) => MapEntry(entry.key, (entry.value as num).toDouble()),
            ),
      ),
      batchQuantityByNode: Map<String, int>.fromEntries(
        (source['batchQuantityByNode'] as Map<String, dynamic>? ?? const {})
            .entries
            .map((entry) => MapEntry(entry.key, entry.value as int)),
      ),
      machineOverrideByNode: Map<String, String>.from(
        source['machineOverrideByNode'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  RunOverrides copyWith({
    Map<String, double>? actualDurationHoursByNode,
    Map<String, int>? batchQuantityByNode,
    Map<String, String>? machineOverrideByNode,
  }) {
    return RunOverrides(
      actualDurationHoursByNode:
          actualDurationHoursByNode ?? this.actualDurationHoursByNode,
      batchQuantityByNode: batchQuantityByNode ?? this.batchQuantityByNode,
      machineOverrideByNode:
          machineOverrideByNode ?? this.machineOverrideByNode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'actualDurationHoursByNode': actualDurationHoursByNode,
      'batchQuantityByNode': batchQuantityByNode,
      'machineOverrideByNode': machineOverrideByNode,
    };
  }
}
