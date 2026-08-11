import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import '../../machines/presentation/providers/machine_provider.dart';
import '../../dies/presentation/providers/die_provider.dart';

class ChallanInsightsDashboard extends StatefulWidget {
  const ChallanInsightsDashboard({super.key});

  @override
  State<ChallanInsightsDashboard> createState() => _ChallanInsightsDashboardState();
}

class _ChallanInsightsDashboardState extends State<ChallanInsightsDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MachinesProvider>().initialize();
        context.read<DiesProvider>().initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final machinesProvider = context.watch<MachinesProvider>();
    final diesProvider = context.watch<DiesProvider>();

    final machines = machinesProvider.machines;
    final dies = diesProvider.dies;

    // Aggregate statistics
    final totalMachines = machines.length;
    final activeMachines = machines.where((m) => m.customProperties.any((p) => p.key.toLowerCase() == 'status' && p.value.toLowerCase() == 'active')).length;
    final idleMachines = totalMachines - activeMachines;

    final totalDies = dies.length;
    // Mock utilization frequency for dies
    final topDies = dies.take(4).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section: Machines
          Row(
            children: [
              const Icon(Icons.precision_manufacturing_rounded, color: SoftErpTheme.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Machines Load & Utilization',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Total Machines',
                  value: '$totalMachines',
                  subtext: 'Registered assets',
                  icon: Icons.settings_outlined,
                  color: SoftErpTheme.accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'Active Load',
                  value: '$activeMachines',
                  subtext: 'In active production',
                  icon: Icons.bolt_outlined,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'Idle Machines',
                  value: '$idleMachines',
                  subtext: 'Available for scheduling',
                  icon: Icons.pause_circle_outline_rounded,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Machine detail grid list
          SoftSurface(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Machine List',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (machines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No machines found', style: TextStyle(color: SoftErpTheme.textSecondary))),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: machines.length,
                    separatorBuilder: (_, __) => const Divider(height: 20, color: SoftErpTheme.border),
                    itemBuilder: (context, idx) {
                      final m = machines[idx];
                      final isActive = m.customProperties.any((p) => p.key.toLowerCase() == 'status' && p.value.toLowerCase() == 'active');
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: SoftErpTheme.accentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.settings_suggest_rounded, color: SoftErpTheme.accent, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, color: SoftErpTheme.textPrimary)),
                                Text('ID: ${m.assetId} | Model: ${m.makeModel}', style: const TextStyle(fontSize: 11.5, color: SoftErpTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFFE6F4EA) : const Color(0xFFF1F3F4),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              isActive ? 'Running' : 'Idle',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isActive ? const Color(0xFF137333) : SoftErpTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          // Section: Dies
          Row(
            children: [
              const Icon(Icons.build_circle_rounded, color: Color(0xFF8B5CF6), size: 22),
              const SizedBox(width: 8),
              Text(
                'Dies Utilization & Cycles',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Total Dies Registered',
                  value: '$totalDies',
                  subtext: 'Tooling inventory',
                  icon: Icons.storage_rounded,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'Top Tool Code',
                  value: topDies.isNotEmpty ? topDies.first.toolCode : 'N/A',
                  subtext: topDies.isNotEmpty ? topDies.first.name : 'No dies registered',
                  icon: Icons.star_outline_rounded,
                  color: const Color(0xFFEC4899),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Top Dies usage table
          SoftSurface(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Die Usage Frequency & Performance',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (dies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No dies found', style: TextStyle(color: SoftErpTheme.textSecondary))),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: topDies.length,
                    separatorBuilder: (_, __) => const Divider(height: 20, color: SoftErpTheme.border),
                    itemBuilder: (context, idx) {
                      final d = topDies[idx];
                      // Mock some utilization cycles & wear percentage for rich visuals
                      final cycles = 1500 - (idx * 320);
                      final wearPct = (idx * 15 + 12) / 100.0;
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.build_rounded, color: Color(0xFF8B5CF6), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600, color: SoftErpTheme.textPrimary)),
                                Text('Code: ${d.toolCode} | Cycles: $cycles stroke cycles', style: const TextStyle(fontSize: 11.5, color: SoftErpTheme.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Rich progress bar for wear limit
                          SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Wear Limit', style: TextStyle(fontSize: 10, color: SoftErpTheme.textSecondary)),
                                    Text('${(wearPct * 100).toInt()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SoftErpTheme.textPrimary)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: wearPct,
                                    minHeight: 5,
                                    backgroundColor: SoftErpTheme.border,
                                    color: wearPct > 0.4 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtext,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtext;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtext,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ],
      ),
    );
  }
}
