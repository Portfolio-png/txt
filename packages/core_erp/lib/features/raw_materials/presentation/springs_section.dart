import 'package:flutter/material.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../domain/spring.dart';

/// The springs in Raw Materials › Springs, each with its code, coil count
/// and how many vendors quote for it. A row opens the spring form; shown in
/// the Springs group's window above the general item list.
class SpringsSection extends StatelessWidget {
  const SpringsSection({
    super.key,
    required this.springs,
    required this.onOpen,
    this.error,
  });

  /// Null while loading.
  final List<SpringDefinition>? springs;
  final ValueChanged<SpringDefinition> onOpen;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = springs;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Springs',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Each with its size, code and the vendors who sell it. Open one to change it.',
            style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Text(
              error!,
              style: const TextStyle(
                fontSize: 14,
                color: SoftErpTheme.dangerText,
              ),
            )
          else if (list == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            const Text(
              'No springs yet. Use Add spring below.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textPrimary,
              ),
            )
          else
            for (final spring in list)
              _SpringRow(spring: spring, onOpen: () => onOpen(spring)),
        ],
      ),
    );
  }
}

class _SpringRow extends StatelessWidget {
  const _SpringRow({required this.spring, required this.onOpen});

  final SpringDefinition spring;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final vendors = spring.vendors.length;
    return InkWell(
      key: ValueKey<String>('spring-row-${spring.itemId}'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    spring.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      if (spring.code.isNotEmpty)
                        _Pill('Code ${spring.code}', strong: true),
                      _Pill(spring.kind.label),
                      if (spring.coilCount != null)
                        _Pill('${spring.coilCount} coils'),
                      if (spring.springType.isNotEmpty)
                        _Pill(spring.springType),
                      if (spring.wireGauge.isNotEmpty) _Pill(spring.wireGauge),
                      _Pill(
                        vendors == 0
                            ? 'No vendor'
                            : vendors == 1
                            ? '1 vendor'
                            : '$vendors vendors',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: SoftErpTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? SoftErpTheme.accentSoft : SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: strong ? SoftErpTheme.accentDark : SoftErpTheme.textSecondary,
        ),
      ),
    );
  }
}
