import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/machine_telemetry.dart';

class TelemetryProvider extends ChangeNotifier {
  TelemetryProvider() {
    _startSimulation();
  }

  final Map<String, MachineTelemetry> _telemetries = {};
  Timer? _simulationTimer;
  final Random _random = Random();

  Map<String, MachineTelemetry> get telemetries => _telemetries;

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }

  void _startSimulation() {
    // Update telemetry every 3 seconds to feel "live"
    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _simulateTick();
    });
  }

  void _simulateTick() {
    // If we have machines to simulate, randomly fluctuate their OEE slightly
    bool changed = false;
    
    // We expect external code to register machines by calling registerMachine(machineId)
    // or we can just randomly jitter existing telemetries.
    final updated = <String, MachineTelemetry>{};
    for (final entry in _telemetries.entries) {
      final current = entry.value;
      
      // 5% chance to change state
      TelemetryState nextState = current.state;
      if (_random.nextDouble() < 0.05) {
        if (current.state == TelemetryState.running) {
          nextState = _random.nextBool() ? TelemetryState.idle : TelemetryState.faulted;
        } else if (current.state == TelemetryState.faulted) {
          nextState = TelemetryState.setup;
        } else {
          nextState = TelemetryState.running;
        }
      }

      double avail = current.availability;
      double perf = current.performance;
      double qual = current.quality;

      if (nextState == TelemetryState.running) {
        perf = (perf + (_random.nextDouble() * 2 - 0.5)).clamp(70.0, 100.0);
        qual = (qual + (_random.nextDouble() * 0.5 - 0.1)).clamp(90.0, 100.0);
        avail = (avail + 0.1).clamp(0.0, 100.0);
      } else if (nextState == TelemetryState.faulted || nextState == TelemetryState.idle) {
        avail = (avail - 1.0).clamp(0.0, 100.0);
        perf = (perf - 2.0).clamp(0.0, 100.0);
      }

      final oee = (avail / 100.0) * (perf / 100.0) * (qual / 100.0) * 100.0;

      updated[entry.key] = current.copyWith(
        state: nextState,
        availability: avail,
        performance: perf,
        quality: qual,
        oee: oee,
        lastUpdated: DateTime.now(),
      );
      changed = true;
    }

    if (changed) {
      _telemetries.addAll(updated);
      notifyListeners();
    }
  }

  void registerMachine(String machineId, {String? activeJob}) {
    if (_telemetries.containsKey(machineId)) return;
    
    // Initial random values
    final avail = 80.0 + _random.nextDouble() * 15;
    final perf = 75.0 + _random.nextDouble() * 20;
    final qual = 95.0 + _random.nextDouble() * 4.9;
    final oee = (avail / 100.0) * (perf / 100.0) * (qual / 100.0) * 100.0;

    _telemetries[machineId] = MachineTelemetry(
      machineId: machineId,
      state: _random.nextDouble() > 0.2 ? TelemetryState.running : TelemetryState.idle,
      availability: avail,
      performance: perf,
      quality: qual,
      oee: oee,
      activeJob: activeJob,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
  }
}
