import 'package:flutter/material.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/services/feature_flags.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/searchable_select.dart';
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
    this.onCreateStage,
    this.onDeleteStage,
  });

  /// Deletes a stage from the factory's master, answering whether it went
  /// (the host asks first and shows any refusal). Null draws no delete
  /// button in the stage dropdowns.
  final Future<bool> Function(ProcessStage stage)? onDeleteStage;

  /// Adds a stage to the factory's master by name and answers it, or null
  /// when it could not (the creator shows its own error). Null means this
  /// host cannot add stages, and the New stage box is drawn disabled saying so.
  final Future<ProcessStage?> Function(String name)? onCreateStage;

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

  Widget _newStageBox() => _NewStageBox(
        enabled: _editable,
        disabledReason: widget.locked
            ? 'This route is active — declare a new version to change it'
            : 'Pick a part first',
        available: _available(),
        allStages: widget.stages,
        onCreate: widget.onCreateStage,
        onDelete: widget.onDeleteStage,
        inRoute: {for (final step in _steps) step.stageId},
        onPick: (stage) {
          // A stage the server handed back for a name it already had may be
          // one this route goes through; adding it twice is only refused later.
          if (!stage.repeatable && _steps.any((s) => s.stageId == stage.id)) {
            return;
          }
          _emit([
            ..._steps,
            RouteStep(stageId: stage.id, stageCode: stage.code, stageName: stage.name),
          ]);
        },
      );

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
              editable: _editable,
              onEmit: _emit,
              canAdd: _available().isNotEmpty,
              newStage: _newStageBox(),
              allStages: widget.stages,
              onCreate: widget.onCreateStage,
              onDelete: widget.onDeleteStage,
            ),
          RouteLens.list => _ListLens(
              steps: _steps,
              palette: _available(),
              stageOf: _stage,
              editable: _editable,
              onEmit: _emit,
              newStage: _newStageBox(),
            ),
        },
      ],
    );
  }
}

/// Classic: one box per step, flowing left to right like the pipeline it is.
///
/// Each box picks its stage from a dropdown listing every stage still
/// available. It used to be one full-width row per step stacked down the page,
/// which spent a screen of height and a scroll on what is one short sequence;
/// as boxes a whole route sits on one line and wraps only when it runs out of
/// width. Deliberately a plain [Wrap], no LayoutBuilder (see the list lens).
class _ClassicLens extends StatelessWidget {
  const _ClassicLens({
    required this.steps,
    required this.optionsFor,
    required this.editable,
    required this.onEmit,
    required this.canAdd,
    required this.newStage,
    required this.allStages,
    required this.onCreate,
    required this.onDelete,
  });

  final List<RouteStep> steps;
  final List<ProcessStage> Function(int? keepStageId) optionsFor;
  final bool editable;
  final ValueChanged<List<RouteStep>> onEmit;
  final bool canAdd;
  final Widget newStage;
  final List<ProcessStage> allStages;
  final Future<ProcessStage?> Function(String name)? onCreate;
  final Future<bool> Function(ProcessStage stage)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i += 1) ...[
          _StepBox(
            key: ValueKey<String>('route_step_$i'),
            index: i,
            step: steps[i],
            options: optionsFor(steps[i].stageId),
            allStages: allStages,
            onCreate: onCreate,
            onDelete: onDelete,
            inRoute: {for (final step in steps) step.stageId},
            editable: editable,
            onPick: (stage) {
              // A stage the server handed back for a name it already had may
              // be one another step goes through.
              if (stage.id == steps[i].stageId) return;
              if (!stage.repeatable && steps.any((s) => s.stageId == stage.id)) {
                return;
              }
              final next = [...steps];
              next[i] = RouteStep(
                stageId: stage.id,
                seq: steps[i].seq,
                stageCode: stage.code,
                stageName: stage.name,
                notes: steps[i].notes,
                machineId: steps[i].machineId,
                dieId: steps[i].dieId,
              );
              onEmit(next);
            },
            onRemove: () => onEmit([...steps]..removeAt(i)),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: SoftErpTheme.textSecondary,
          ),
        ],
        SizedBox(
          height: _StepBox.height,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('route_add_step'),
            style: _boxButtonStyle,
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
        const SizedBox(width: 4),
        newStage,
      ],
    );
  }
}

final ButtonStyle _boxButtonStyle = OutlinedButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 14),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
  ),
);

/// One step: its number, its stage, and a way to take it out.
class _StepBox extends StatelessWidget {
  const _StepBox({
    super.key,
    required this.index,
    required this.step,
    required this.options,
    required this.allStages,
    required this.onCreate,
    required this.onDelete,
    required this.inRoute,
    required this.editable,
    required this.onPick,
    required this.onRemove,
  });

  static const double width = 184;
  static const double height = 52;

  final int index;
  final RouteStep step;
  final List<ProcessStage> options;
  final List<ProcessStage> allStages;
  final Future<ProcessStage?> Function(String name)? onCreate;
  final Future<bool> Function(ProcessStage stage)? onDelete;
  final Set<int> inRoute;
  final bool editable;
  final ValueChanged<ProcessStage> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name =
        step.stageName.isEmpty ? 'Stage #${step.stageId}' : step.stageName;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SoftErpTheme.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            // A Builder so the picker anchors to this box, not to the editor.
            child: Builder(
              builder: (anchor) => InkWell(
                key: ValueKey<String>('route_step_dropdown_$index'),
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
                onTap: editable
                    ? () async {
                        final stage = await _pickStage(
                          anchor,
                          options: options,
                          allStages: allStages,
                          onCreate: onCreate,
                          onDelete: onDelete,
                          inRoute: inRoute,
                          selectedId: step.stageId,
                        );
                        if (stage != null) onPick(stage);
                      }
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: editable
                              ? SoftErpTheme.textPrimary
                              : SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 22,
                      color: editable
                          ? SoftErpTheme.textPrimary
                          : SoftErpTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Drawn disabled rather than hidden: a control that vanishes when
          // its precondition fails costs more to explain than one that is
          // visibly unavailable.
          IconButton(
            key: ValueKey<String>('route_step_remove_$index'),
            tooltip: editable
                ? 'Remove this step'
                : 'This route is active — declare a new version to change it',
            visualDensity: VisualDensity.compact,
            onPressed: editable ? onRemove : null,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

String _norm(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// The house searchable dropdown over [options], anchored to [anchor]: filters
/// as you type and, when [onCreate] is given and nothing in [allStages] has the
/// name typed, offers to add it as a new stage. Answers the stage picked or
/// made, or null when dismissed.
///
/// Both ways onto a route use it — a step box swapping its stage and the box
/// that appends one — so a stage can be found or made from either.
Future<ProcessStage?> _pickStage(
  BuildContext anchor, {
  required List<ProcessStage> options,
  required List<ProcessStage> allStages,
  required Future<ProcessStage?> Function(String name)? onCreate,
  Future<bool> Function(ProcessStage stage)? onDelete,
  Set<int> inRoute = const {},
  int? selectedId,
}) async {
  ProcessStage? created;
  // Deleted while the dropdown is open: its name is free to add again.
  final deleted = <int>{};
  ProcessStage? stageOf(int id) =>
      allStages.where((s) => s.id == id).firstOrNull ??
      options.where((s) => s.id == id).firstOrNull;
  final picked = await showSearchableSelectDialog<int>(
    context: anchor,
    searchHintText: 'Find a stage, or type a new one',
    selectedValue: selectedId,
    emptyText: onCreate == null
        ? 'No stage by that name'
        : 'Already in this route — each stage goes through once',
    options: [
      for (final stage in options)
        SearchableSelectOption<int>(value: stage.id, label: stage.name),
    ],
    // A name the master already has — even one this route has used up — is
    // that stage, never a second one.
    canCreateOption: (query, _) => !allStages.any(
      (stage) =>
          !deleted.contains(stage.id) && _norm(stage.name) == _norm(query),
    ),
    onCreateOption: onCreate == null
        ? null
        : (query) async {
            final stage = await onCreate(query);
            if (stage == null) return null; // the host has said why
            created = stage;
            return SearchableSelectOption<int>(value: stage.id, label: stage.name);
          },
    createOptionLabelBuilder: (query) => 'Add “${query.trim()}” as a new stage',
    // A stage something still stands on stays, and the button says why.
    deleteBlockedReason: (option) {
      if (inRoute.contains(option.value)) {
        return 'In this route — take the step out first';
      }
      final uses = stageOf(option.value)?.uses ?? 0;
      if (uses > 0) {
        return 'In $uses route${uses == 1 ? '' : 's'} — take it out of '
            '${uses == 1 ? 'that route' : 'them'} first';
      }
      return null;
    },
    onDeleteOption: onDelete == null
        ? null
        : (option) async {
            final stage = stageOf(option.value);
            if (stage == null) return false;
            final gone = await onDelete(stage);
            if (gone) deleted.add(stage.id);
            return gone;
          },
  );
  if (picked == null) return null;
  if (created?.id == picked.value) return created;
  return options.where((s) => s.id == picked.value).firstOrNull;
}

/// Finds a stage, or adds one the master does not have yet — by name alone.
///
/// Opens the house searchable dropdown anchored to the box: it lists the
/// stages this route can still take, filters as you type, and when nothing is
/// called what you typed offers to add it as a new stage. One control for both,
/// so nobody has to know whether a stage exists before reaching for it.
class _NewStageBox extends StatelessWidget {
  const _NewStageBox({
    required this.enabled,
    required this.disabledReason,
    required this.available,
    required this.allStages,
    required this.onCreate,
    required this.onDelete,
    required this.inRoute,
    required this.onPick,
  });

  final bool enabled;
  final String disabledReason;

  /// What this route may still take — the options listed.
  final List<ProcessStage> available;

  /// Every stage, so a name already in the master is never offered as new.
  final List<ProcessStage> allStages;

  /// Null means this host cannot add stages; the dropdown then only finds.
  final Future<ProcessStage?> Function(String name)? onCreate;
  final Future<bool> Function(ProcessStage stage)? onDelete;
  final Set<int> inRoute;
  final ValueChanged<ProcessStage> onPick;

  Future<void> _open(BuildContext anchor) async {
    final stage = await _pickStage(
      anchor,
      options: available,
      allStages: allStages,
      onCreate: onCreate,
      onDelete: onDelete,
      inRoute: inRoute,
    );
    if (stage != null) onPick(stage);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled
          ? 'Find a stage, or add one that is not in the list — just its name'
          : disabledReason,
      child: SizedBox(
        height: _StepBox.height,
        // A Builder so the dropdown anchors to this box, not to the editor.
        child: Builder(
          builder: (anchor) => OutlinedButton.icon(
            key: const ValueKey<String>('route_new_stage'),
            style: _boxButtonStyle,
            onPressed: enabled ? () => _open(anchor) : null,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Find or add stage', style: TextStyle(fontSize: 14)),
          ),
        ),
      ),
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
    required this.newStage,
  });

  final Widget newStage;
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
            newStage,
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
