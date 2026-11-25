import 'package:flutter/material.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../domain/rivet.dart';

/// The rivets in Raw Materials › Rivets, each with its code and how many
/// vendors quote for it. A row opens the rivet form; shown in the Rivets
/// group's window above the general item list.
class RivetsSection extends StatelessWidget {
  const RivetsSection({
    super.key,
    required this.rivets,
    required this.onOpen,
    this.error,
  });

  /// Null while loading.
  final List<RivetDefinition>? rivets;
  final ValueChanged<RivetDefinition> onOpen;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = rivets;
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
            'Rivets',
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
              'No rivets yet. Use Add rivet below.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textPrimary,
              ),
            )
          else
            for (final rivet in list)
              _RivetRow(rivet: rivet, onOpen: () => onOpen(rivet)),
        ],
      ),
    );
  }
}

class _RivetRow extends StatelessWidget {
  const _RivetRow({required this.rivet, required this.onOpen});

  final RivetDefinition rivet;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final vendors = rivet.vendors.length;
    return InkWell(
      key: ValueKey<String>('rivet-row-${rivet.itemId}'),
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
                    rivet.name,
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
                      if (rivet.code.isNotEmpty)
                        _Pill('Code ${rivet.code}', strong: true),
                      _Pill('${rivet.headType.code} · ${rivet.headType.label}'),
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
