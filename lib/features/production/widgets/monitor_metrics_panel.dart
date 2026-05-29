import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';

class LiveMetricsPanel extends StatelessWidget {
  const LiveMetricsPanel({super.key, required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final runCounters = context
        .select<ProductionRunProvider, ({int goodYield, int scrap})>(
          (p) => (goodYield: p.goodYield, scrap: p.setupScrap),
        );
    final parentReel = context.select<ProductionProvider, double>(
      (p) => p.parentReelConsumedKg,
    );
    final locked = context.select<ProductionRunProvider, bool>(
      (p) => p.isInputLocked,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LIVE TELEMETRY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Color(0xFF64748B),
                ),
              ),
              if (!locked)
                const Tooltip(
                  message: 'Demo Simulation Mode Active',
                  child: Icon(Icons.science, size: 16, color: Color(0xFF2563EB)),
                ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _MetricDial(
                    label: 'GOOD YIELD',
                    value: runCounters.goodYield.toString(),
                    unit: 'UNT',
                    color: const Color(0xFF10B981),
                    onIncrement: locked
                        ? null
                        : () => context.read<ProductionRunProvider>().incrementYield(),
                    onDecrement: locked
                        ? null
                        : () => context.read<ProductionRunProvider>().decrementYield(),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _MetricDial(
                          label: 'SETUP SCRAP',
                          value: runCounters.scrap.toString(),
                          unit: 'PCS',
                          color: const Color(0xFFEF4444),
                          onIncrement: locked
                              ? null
                              : () => context.read<ProductionRunProvider>().addScrap(),
                          onDecrement: locked
                              ? null
                              : () => context.read<ProductionRunProvider>().removeScrap(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _MetricDial(
                          label: 'PARENT REEL',
                          value: parentReel.toStringAsFixed(1),
                          unit: 'KG',
                          color: const Color(0xFF2563EB),
                          isNegative: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDial extends StatelessWidget {
  const _MetricDial({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.isNegative = false,
    this.onIncrement,
    this.onDecrement,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final bool isNegative;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Stack(
        children: [
          // Background Glow
          Positioned.fill(
            child: Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.08),
                      blurRadius: 40,
                      spreadRadius: 20,
                    )
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (isNegative)
                      Text(
                        '-',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w300,
                          color: color,
                        ),
                      ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onIncrement != null || onDecrement != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: Row(
                children: [
                  if (onDecrement != null)
                    _SimulationButton(icon: Icons.remove, onPressed: onDecrement!),
                  const SizedBox(width: 8),
                  if (onIncrement != null)
                    _SimulationButton(icon: Icons.add, onPressed: onIncrement!),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SimulationButton extends StatelessWidget {
  const _SimulationButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: Color(0xFFE2E8F0))),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 14, color: const Color(0xFF64748B)),
        ),
      ),
    );
  }
}
