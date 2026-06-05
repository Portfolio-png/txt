import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../providers/machine_provider.dart';
import '../providers/telemetry_provider.dart';
import '../../domain/machine_telemetry.dart';

class MachineTelemetryScreen extends StatefulWidget {
  const MachineTelemetryScreen({super.key});

  @override
  State<MachineTelemetryScreen> createState() => _MachineTelemetryScreenState();
}

class _MachineTelemetryScreenState extends State<MachineTelemetryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTelemetry();
    });
  }

  void _initializeTelemetry() {
    final machines = context.read<MachinesProvider>().machines;
    final telemetryProvider = context.read<TelemetryProvider>();
    for (final m in machines) {
      telemetryProvider.registerMachine(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final machines = context.watch<MachinesProvider>().machines;
    final telemetries = context.watch<TelemetryProvider>().telemetries;

    int runningCount = 0;
    int downCount = 0;
    double totalOee = 0;
    int trackedCount = 0;

    for (final t in telemetries.values) {
      if (t.state == TelemetryState.running) {
        runningCount++;
      } else if (t.state == TelemetryState.faulted || t.state == TelemetryState.offline) {
        downCount++;
      }
      totalOee += t.oee;
      trackedCount++;
    }

    final avgOee = trackedCount > 0 ? totalOee / trackedCount : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Machine Telemetry',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Live view of factory OEE and machine states.',
                    style: TextStyle(color: SoftErpTheme.textSecondary, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _TelemetryKpiCard(
                          title: 'Factory OEE',
                          value: '${avgOee.toStringAsFixed(1)}%',
                          icon: Icons.speed,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _TelemetryKpiCard(
                          title: 'Machines Running',
                          value: '$runningCount / ${machines.length}',
                          icon: Icons.precision_manufacturing,
                          color: const Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _TelemetryKpiCard(
                          title: 'Machines Down',
                          value: downCount.toString(),
                          icon: Icons.warning_amber_rounded,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 450,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.25,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final machine = machines[index];
                  final telemetry = telemetries[machine.id];

                  if (telemetry == null) {
                    return const Card(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  return _MachineCard(
                    machineName: machine.name,
                    makeModel: machine.makeModel,
                    telemetry: telemetry,
                  );
                },
                childCount: machines.length,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

class _TelemetryKpiCard extends StatelessWidget {
  const _TelemetryKpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({
    required this.machineName,
    required this.makeModel,
    required this.telemetry,
  });

  final String machineName;
  final String makeModel;
  final MachineTelemetry telemetry;

  Color _getStateColor(TelemetryState state) {
    switch (state) {
      case TelemetryState.running:
        return const Color(0xFF22C55E);
      case TelemetryState.idle:
      case TelemetryState.setup:
        return const Color(0xFFEAB308);
      case TelemetryState.faulted:
      case TelemetryState.offline:
        return const Color(0xFFEF4444);
    }
  }

  String _getStateLabel(TelemetryState state) {
    switch (state) {
      case TelemetryState.running:
        return 'Running';
      case TelemetryState.idle:
        return 'Idle';
      case TelemetryState.setup:
        return 'Setup';
      case TelemetryState.faulted:
        return 'Faulted';
      case TelemetryState.offline:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateColor = _getStateColor(telemetry.state);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      machineName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: SoftErpTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      makeModel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: SoftErpTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: stateColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getStateLabel(telemetry.state),
                      style: TextStyle(
                        color: stateColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${telemetry.oee.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6.0, left: 4.0),
                child: Text(
                  'OEE',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          _ProgressBar(label: 'Availability', value: telemetry.availability),
          const SizedBox(height: 8),
          _ProgressBar(label: 'Performance', value: telemetry.performance),
          const SizedBox(height: 8),
          _ProgressBar(label: 'Quality', value: telemetry.quality),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: SoftErpTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 12,
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(3),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(seconds: 1),
                  curve: Curves.easeOutCubic,
                  width: constraints.maxWidth * (value / 100).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
