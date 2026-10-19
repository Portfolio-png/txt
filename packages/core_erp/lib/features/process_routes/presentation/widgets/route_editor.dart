import 'package:flutter/material.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/services/feature_flags.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/part_route.dart';
import '../../domain/process_stage.dart';
import 'route_creation_panel.dart';

/// Which editing gesture the route editor offers.
///
/// Doc 10: "Each view produces the same payload: a list of stage ids in order.
/// The view a client sees is a per-client setting, not a code branch." So this
/// changes the gesture and nothing else — not what is saved, not which rules
/// apply, not which endpoint is called.
/// Builds the route authoring panel for a host to embed.
///
/// The seam every other master's editor uses — `UnitsScreen.editorPanel`,
/// `ClientsScreen.editorPanel` and the rest — so the creation bench can host a
/// route card without knowing anything about routes. Hands the saved record to
/// [onSaved] and never pops: the host owns the window.
///
/// [initialPartId] opens it pointed at a part, which is what a loose-end row
/// ("this part has no route") passes. [madeHereItemIds] sorts the parts made in
/// this sitting to the top of the picker.
EmbeddedEditorBuilder routeEditorPanel({
  int? initialPartId,
  Set<int> madeHereItemIds = const <int>{},
}) {
  return (context, {required onSaved, required onCancel}) => RouteCreationPanel(
        onSaved: onSaved,
        onCancel: onCancel,
        initialPartId: initialPartId,
        madeHereItemIds: madeHereItemIds,
      );
}

enum RouteLens {
  /// One dropdown per step, each listing every stage, steps added with a
  /// button. The doc names this as suiting "operators used to older desktop
  /// software", and it is the first client's habit.
  classic,

  /// A palette of stages, tapped to append and dragged to reorder. Faster for
  /// long routes.
  list;

  static RouteLens fromFlags() =>
      FeatureFlags.isEnabled(FeatureKeys.routesListLens)
          ? RouteLens.list
          : RouteLens.classic;
}

/// Edits the ordered stage list for one part.
///
/// Holds a draft and hands it back through [onChanged]; it does not save. The
/// three rules are the backend's — this only stops a user walking into two of
/// them, which is a courtesy and not an enforcement:
///
///   * a non-repeatable stage already in the route is not offered again;
///   * ordering is a list, so `seq` is contiguous by construction.
///
/// It cannot pre-empt the third (an active route is never edited in place),
/// because whether this route is live is the server's to say — so an active
/// route is shown locked, with the version button, rather than silently
/// accepting edits that would be refused.
class RouteEditor extends StatefulWidget {
  const RouteEditor({
    super.key,
    required this.stages,
    required this.steps,
    required this.onChanged,
    this.lens,
    this.locked = false,
    this.lockedVersion,
    this.onDeclareVersion,
    this.enabled = true,
  });

  final List<ProcessStage> stages;
  final List<RouteStep> steps;
  final ValueChanged<List<RouteStep>> onChanged;

  /// Null reads the per-client setting. Passed explicitly only by a test or a
  /// screen that is showing both.
  final RouteLens? lens;

  /// The route is active, so a change needs a declared version.
  final bool locked;
  final int? lockedVersion;
  final Future<void> Function()? onDeclareVersion;

  final bool enabled;

  @override
  State<RouteEditor> createState() => _RouteEditorState();
}

class _RouteEditorState extends State<RouteEditor> {
  late List<RouteStep> _steps = [...widget.steps];

  @override
  void didUpdateWidget(RouteEditor old) {
    super.didUpdateWidget(old);
    // Only adopt the incoming list when it is genuinely a different route —
    // rebuilding on every parent build would discard a half-built draft.
    if (!_sameStages(old.steps, widget.steps) &&
        !_sameStages(_steps, widget.steps)) {
      _steps = [...widget.steps];
    }
  }

  static bool _sameStages(List<RouteStep> a, List<RouteStep> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i].stageId != b[i].stageId) return false;
    }
    return true;
  }

  bool get _editable => widget.enabled && !widget.locked;

  /// Renumbers from 1 on every change, so contiguity is a property of the
  /// structure rather than something anyone has to remember.
  void _emit(List<RouteStep> next) {
    setState(() {
      _steps = [
        for (var i = 0; i < next.length; i += 1)
          RouteStep(
            stageId: next[i].stageId,
            seq: i + 1,
            stageCode: next[i].stageCode,
            stageName: next[i].stageName,
            notes: next[i].notes,
            machineId: next[i].machineId,
            dieId: next[i].dieId,
          ),
      ];
    });
    widget.onChanged(_steps);
  }

  ProcessStage? _stage(int id) {
    for (final stage in widget.stages) {
      if (stage.id == id) return stage;
    }
    return null;
  }

  /// Stages a user may still pick, optionally keeping the one a given slot
  /// already holds so a dropdown can show its own value.
  List<ProcessStage> _available({int? keepStageId}) {
    final used = <int, int>{};
    for (final step in _steps) {
      used[step.stageId] = (used[step.stageId] ?? 0) + 1;
    }
    return [
      for (final stage in widget.stages)
        if (stage.active)
          if (stage.id == keepStageId ||
              stage.repeatable ||
              (used[stage.id] ?? 0) == 0)
            stage,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lens = widget.lens ?? RouteLens.fromFlags();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.locked) _LockedBar(
          version: widget.lockedVersion,
          onDeclareVersion: widget.onDeclareVersion,
        ),
        if (widget.locked) const SizedBox(height: 12),
        switch (lens) {
          RouteLens.classic => _ClassicLens(
              steps: _steps,
              optionsFor: (id) => _available(keepStageId: id),
              stageOf: _stage,
              editable: _editable,
              onEmit: _emit,
              canAdd: _available().isNotEmpty,
            ),
          RouteLens.list => _ListLens(
              steps: _steps,
              palette: _available(),
              stageOf: _stage,
              editable: _editable,
              onEmit: _emit,
            ),
        },
      ],
    );
  }
}

/// Classic: one dropdown per step.
class _ClassicLens extends StatelessWidget {
  const _ClassicLens({
    required this.steps,
    required this.optionsFor,
    required this.stageOf,
    required this.editable,
    required this.onEmit,
    required this.canAdd,
  });

  final List<RouteStep> steps;
  final List<ProcessStage> Function(int? keepStageId) optionsFor;
  final ProcessStage? Function(int id) stageOf;
  final bool editable;
  final ValueChanged<List<RouteStep>> onEmit;
  final bool canAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i += 1)
          Padding(
            key: ValueKey<String>('route_step_$i'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey<String>('route_step_dropdown_$i'),
                    initialValue: steps[i].stageId,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: SoftErpTheme.textPrimary,
                    ),
                    items: [
                      for (final stage in optionsFor(steps[i].stageId))
                        DropdownMenuItem<int>(
                          value: stage.id,
                          child: Text(stage.name, style: const TextStyle(fontSize: 14)),
                        ),
                    ],
                    onChanged: editable
                        ? (value) {
                            if (value == null) return;
                            final next = [...steps];
                            final stage = stageOf(value);
                            next[i] = RouteStep(
                              stageId: value,
                              seq: steps[i].seq,
                              stageCode: stage?.code ?? '',
                              stageName: stage?.name ?? '',
                              notes: steps[i].notes,
                              machineId: steps[i].machineId,
                              dieId: steps[i].dieId,
                            );
                            onEmit(next);
                          }
                        : null,
                  ),
                ),
                // Drawn disabled rather than hidden: a control that vanishes
                // when its precondition fails costs more to explain than one
                // that is visibly unavailable.
                IconButton(
                  key: ValueKey<String>('route_step_remove_$i'),
                  tooltip: editable
                      ? 'Remove this step'
                      : 'This route is active — declare a new version to change it',
                  onPressed: editable
                      ? () => onEmit([...steps]..removeAt(i))
                      : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('route_add_step'),
            onPressed: editable && canAdd
                ? () {
                    final stage = optionsFor(null).first;
                    onEmit([
                      ...steps,
                      RouteStep(
                        stageId: stage.id,
                        stageCode: stage.code,
                        stageName: stage.name,
                      ),
                    ]);
                  }
                : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add step', style: TextStyle(fontSize: 14)),
          ),
        ),
      ],
    );
  }
}

/// List: a palette of stages, tapped to append, dragged to reorder.
class _ListLens extends StatelessWidget {
  const _ListLens({
    required this.steps,
    required this.palette,
    required this.stageOf,
    required this.editable,
    required this.onEmit,
  });

  final List<RouteStep> steps;
  final List<ProcessStage> palette;
  final ProcessStage? Function(int id) stageOf;
  final bool editable;
  final ValueChanged<List<RouteStep>> onEmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (steps.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No steps yet — pick a stage below.',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
          )
        else
          // Deliberately NOT wrapped in a LayoutBuilder. A LayoutBuilder over
          // a reorderable list crashes mid-layout when the drag overlay
          // appears, and it will not reproduce in a widget test — so the guard
          // has to be structural.
          ReorderableListView(
            shrinkWrap: true,
            buildDefaultDragHandles: editable,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (from, to) {
              if (!editable) return;
              final next = [...steps];
              final moved = next.removeAt(from);
              next.insert(to > from ? to - 1 : to, moved);
              onEmit(next);
            },
            children: [
              for (var i = 0; i < steps.length; i += 1)
                ListTile(
                  key: ValueKey<String>('route_tile_${steps[i].stageId}_$i'),
                  dense: true,
                  leading: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                  title: Text(
                    steps[i].labelWith(
                      [for (final stage in palette) stage],
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                  trailing: IconButton(
                    key: ValueKey<String>('route_tile_remove_$i'),
                    tooltip: editable
                        ? 'Remove this step'
                        : 'This route is active — declare a new version to change it',
                    onPressed:
                        editable ? () => onEmit([...steps]..removeAt(i)) : null,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final stage in palette)
              ActionChip(
                key: ValueKey<String>('route_palette_${stage.code}'),
                label: Text(stage.name, style: const TextStyle(fontSize: 14)),
                onPressed: editable
                    ? () => onEmit([
                          ...steps,
                          RouteStep(
                            stageId: stage.id,
                            stageCode: stage.code,
                            stageName: stage.name,
                          ),
                        ])
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// An active route cannot be edited in place; this says so and offers the way
/// forward rather than only refusing.
class _LockedBar extends StatelessWidget {
  const _LockedBar({required this.version, required this.onDeclareVersion});

  final int? version;
  final Future<void> Function()? onDeclareVersion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              version == null
                  ? 'This route is active. Changes need a new version, so jobs already run keep their history.'
                  : 'Version $version is active. Changes need a new version, so jobs already run keep their history.',
              style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
          ),
          if (onDeclareVersion != null)
            TextButton(
              key: const ValueKey<String>('route_declare_version'),
              onPressed: () => onDeclareVersion!(),
              child: const Text('New version', style: TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}
