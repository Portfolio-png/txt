enum TelemetryState {
  running,
  idle,
  setup,
  faulted,
  offline
}

class MachineTelemetry {
  const MachineTelemetry({
    required this.machineId,
    required this.state,
    required this.oee,
    required this.availability,
    required this.performance,
    required this.quality,
    this.activeJob,
    required this.lastUpdated,
  });

  final String machineId;
  final TelemetryState state;
  final double oee;
  final double availability;
  final double performance;
  final double quality;
  final String? activeJob;
  final DateTime lastUpdated;

  MachineTelemetry copyWith({
    String? machineId,
    TelemetryState? state,
    double? oee,
    double? availability,
    double? performance,
    double? quality,
    String? activeJob,
    DateTime? lastUpdated,
  }) {
    return MachineTelemetry(
      machineId: machineId ?? this.machineId,
      state: state ?? this.state,
      oee: oee ?? this.oee,
      availability: availability ?? this.availability,
      performance: performance ?? this.performance,
      quality: quality ?? this.quality,
      activeJob: activeJob ?? this.activeJob,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
