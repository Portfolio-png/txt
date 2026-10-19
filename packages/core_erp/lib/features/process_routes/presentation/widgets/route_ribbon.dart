import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/part_route.dart';
import '../../domain/process_stage.dart';

/// A route, read-only: the stages in order, with the version it belongs to.
///
/// What an inspector shows. It never offers to edit — walking the graph and
/// changing it are different intentions, and the inspectors already have one
/// explicit Edit button for the second.
///
/// A route the caller could not read renders NOTHING, not "no route". The same
/// rule the ecosystem ribbon follows: a refusal and an absence must not look
/// alike, and only an empty answer says there is no route.
class RouteRibbon extends StatelessWidget {
  const RouteRibbon({
    super.key,
    required this.route,
    this.stages = const [],
    this.heading = 'Goes through',
  });

  /// Null renders nothing at all.
  final PartRoute? route;

  /// The stage master, used only to name a step whose stage name did not come
  /// down with it.
  final List<ProcessStage> stages;

  final String heading;

  @override
  Widget build(BuildContext context) {
    final current = route;
    if (current == null || current.steps.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              heading,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            _VersionPill(route: current),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < current.steps.length; i += 1) ...[
              if (i > 0)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: SoftErpTheme.textSecondary,
                ),
              _StagePill(
                seq: current.steps[i].seq,
                label: current.steps[i].labelWith(stages),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.route});

  final PartRoute route;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (route.status) {
      RouteStatus.active => ('v${route.version}', SoftErpTheme.textSecondary),
      RouteStatus.draft => ('v${route.version} draft', Colors.orange.shade700),
      RouteStatus.retired => ('v${route.version} retired', SoftErpTheme.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colour),
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill({required this.seq, required this.label});

  final int seq;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 11, 7),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$seq',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
