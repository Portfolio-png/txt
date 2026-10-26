import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../data/process_route_service.dart';
import '../../domain/part_route.dart';
import '../../domain/process_stage.dart';
import 'route_editor.dart';

/// Authors a part's process route, embedded in a host's window.
///
/// **A route is the one card on the creation bench that cannot stand alone.**
/// Every other kind is a master with its own identity; `process_routes.part_id`
/// is a foreign key, so a route is always a route *of something*. That is why
/// this panel leads with a part picker rather than a stage list, and why Save
/// is drawn disabled until a part is chosen instead of the card pretending it
/// could be saved.
///
/// It writes through `ProcessRouteService`, which the host registers. On a
/// bench that writes as it goes, a part picked from the list has already
/// landed — so "holding" here means the authored stage list survives in panel
/// state until there is a part to attach it to, not that the write is queued.
class RouteCreationPanel extends StatefulWidget {
  const RouteCreationPanel({
    super.key,
    required this.onSaved,
    required this.onCancel,
    this.initialPartId,
    this.madeHereItemIds = const <int>{},
  });

  final ValueChanged<CreatedRecord> onSaved;
  final VoidCallback onCancel;

  /// Opens pointed at a part — what a loose-end row ("this part has no route")
  /// passes so the answer is one click rather than a search.
  final int? initialPartId;

  /// Parts made in this sitting. Sorted to the top of the picker, because the
  /// part somebody is routing is almost always the one they just made.
  final Set<int> madeHereItemIds;

  @override
  State<RouteCreationPanel> createState() => _RouteCreationPanelState();
}

class _RouteCreationPanelState extends State<RouteCreationPanel> {
  ProcessRouteService? _service;
  bool _serviceMissing = false;

  List<ProcessStage> _stages = const [];
  int? _partId;

  /// Held here rather than in [RouteEditor] so it survives the part changing
  /// and the editor being rebuilt under a different key.
  List<RouteStep> _steps = const [];

  /// The chosen part's active route, if it already has one. Non-null means a
  /// change has to be declared as a version rather than saved in place.
  PartRoute? _active;

  /// The route a pending version replaces. Set when New version is pressed,
  /// which clears [_active] to unlock the editor — so this is the only thing
  /// left saying the next save is a version and not a first save.
  PartRoute? _pendingVersionOf;

  bool _loadingStages = true;
  bool _loadingRoute = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _partId = widget.initialPartId;
    _resolveService();
    _loadStages();
    // A part handed in at open needs its existing route loaded, exactly as one
    // picked from the field does. `_loadRoute` ran only from `onChanged`, so a
    // panel opened pointed at a part that already had a route did not know —
    // `_active` stayed null, the button said "Save route" rather than "Save as
    // new version", and the save tried to lay a second v1 over the first.
    final initial = widget.initialPartId;
    if (initial != null) _loadRoute(initial);
  }

  /// Adds a stage to the master and to this panel's list, so every step box
  /// offers it from now on. Null (with the reason shown) when it failed.
  Future<ProcessStage?> _createStage(String name) async {
    final service = _service;
    if (service == null) return null;
    try {
      final stage = await service.createStage(name);
      if (!mounted) return stage;
      setState(() {
        _error = null;
        if (!_stages.any((known) => known.id == stage.id)) {
          _stages = [..._stages, stage];
        }
      });
      return stage;
    } on ProcessRouteException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return null;
    }
  }

  void _resolveService() {
    try {
      _service = context.read<ProcessRouteService>();
    } catch (_) {
      // Not registered in this build. The same degradation the part
      // inspector's route section makes for a provider that is not in the
      // tree — a missing service is a build that cannot route, not a crash.
      _serviceMissing = true;
    }
  }

  Future<void> _loadStages() async {
    final service = _service;
    if (service == null) {
      if (mounted) setState(() => _loadingStages = false);
      return;
    }
    try {
      final stages = await service.stages();
      if (!mounted) return;
      setState(() {
        _stages = stages;
        _loadingStages = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingStages = false;
        _error = 'Could not read the stage list. ($error)';
      });
    }
    if (_partId != null) await _loadRoute(_partId!);
  }

  /// Reads the part's active route and adopts its steps.
  ///
  /// Adopting rather than merging on purpose: the stage list on screen should
  /// be what this part actually goes through, so somebody declaring a version
  /// starts from the route they are changing rather than from scratch.
  Future<void> _loadRoute(int partId) async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _loadingRoute = true;
      _error = null;
      // Belonged to whichever part was chosen before. Carrying it over would
      // version the wrong route.
      _pendingVersionOf = null;
    });
    try {
      final active = await service.activeRoute(partId);
      if (!mounted) return;
      setState(() {
        _active = active;
        if (active != null) _steps = active.steps;
        _loadingRoute = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRoute = false;
        _active = null;
        _error = 'Could not read this part’s route. ($error)';
      });
    }
  }

  /// Every part this workspace can see, the ones made here first.
  ///
  /// Read fresh on every build rather than snapshotted, so a part created in
  /// this window moments ago is already here — the same discipline the bench's
  /// own link writes use.
  List<SearchableSelectOption<int>> _partOptions(List<ItemDefinition> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final aHere = widget.madeHereItemIds.contains(a.id) ? 0 : 1;
      final bHere = widget.madeHereItemIds.contains(b.id) ? 0 : 1;
      if (aHere != bHere) return aHere.compareTo(bHere);
      return _titleOf(a).toLowerCase().compareTo(_titleOf(b).toLowerCase());
    });
    return [
      for (final item in sorted)
        SearchableSelectOption<int>(
          value: item.id,
          label: _titleOf(item),
          // A variant is told apart by its code, which is the whole point of
          // SADPB2248 — "Patti Brass 22" and "Patti MS 22" read alike in a
          // list, and their codes do not.
          subtitle: [
            if (item.partCode.trim().isNotEmpty) item.partCode.trim(),
            if (item.baseItemId != null) 'variant',
            if (widget.madeHereItemIds.contains(item.id)) 'made just now',
          ].join(' · '),
          searchText: '${_titleOf(item)} ${item.partCode}',
        ),
    ];
  }

  static String _titleOf(ItemDefinition item) {
    final display = item.displayName.trim();
    if (display.isNotEmpty) return display;
    final name = item.name.trim();
    if (name.isNotEmpty) return name;
    final code = item.partCode.trim();
    return code.isNotEmpty ? code : 'Part ${item.id}';
  }

  bool get _canSave =>
      !_serviceMissing &&
      _partId != null &&
      _steps.isNotEmpty &&
      !_saving &&
      !_loadingRoute;

  String get _saveTooltip {
    if (_serviceMissing) return 'Routing is not available in this build.';
    if (_partId == null) return 'Choose the part this route belongs to first.';
    if (_steps.isEmpty) return 'Add at least one stage.';
    return '';
  }

  Future<void> _save() async {
    final service = _service;
    final partId = _partId;
    if (service == null || partId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // An active route is never edited in place, so a change to one is a
      // declared version. The server enforces this either way; asking for the
      // right thing means the user sees a result rather than a 409.
      //
      // `_pendingVersionOf` is why this is not just `_active == null`: pressing
      // New version CLEARS `_active` to unlock the editor, so by the time the
      // save runs there is no active route in state — but the server still has
      // one, and a plain save would be refused.
      final versioning = _active != null || _pendingVersionOf != null;
      final routes = versioning
          ? await service.declareVersion(partId, _steps)
          : await service.save(partId, _steps);
      if (!mounted) return;
      final saved = routes.where((r) => r.isActive).firstOrNull ??
          (routes.isNotEmpty ? routes.first : null);
      final title = _partTitle(partId);
      widget.onSaved(CreatedRecord(
        id: '${saved?.id ?? partId}',
        title: saved == null ? '$title route' : '$title route v${saved.version}',
        subtitle: '${_steps.length} ${_steps.length == 1 ? 'stage' : 'stages'}',
      ));
      setState(() {
        _saving = false;
        _active = saved;
        _pendingVersionOf = null;
      });
    } on RouteActiveException catch (error) {
      // Somebody else activated a route for this part while this panel was
      // open. Re-read rather than guess, so the version button appears.
      //
      // The re-read comes FIRST and the message second, because `_loadRoute`
      // clears `_error` — setting it before reloading wiped the one sentence
      // explaining why the save did not happen, which is exactly the case
      // where somebody needs it.
      if (!mounted) return;
      setState(() => _saving = false);
      await _loadRoute(partId);
      if (!mounted) return;
      setState(() => _error = error.message);
    } on ProcessRouteException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  String _partTitle(int partId) {
    try {
      final item = context
          .read<ItemsProvider>()
          .items
          .where((i) => i.id == partId)
          .firstOrNull;
      if (item != null) return _titleOf(item);
    } catch (_) {
      // No provider — the generic name below is still true.
    }
    return 'Part $partId';
  }

  @override
  Widget build(BuildContext context) {
    if (_serviceMissing) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Routing is not available in this build.',
          style: TextStyle(fontSize: 15, color: SoftErpTheme.textSecondary),
        ),
      );
    }

    final items = _readItems();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Which part does this route belong to?',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'A route is the stages one part goes through, so it needs the part '
          'first. Variants are listed too — each carries its own route.',
          style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        SearchableSelectField<int>(
          key: const ValueKey<String>('route_part_field'),
          value: _partId,
          options: _partOptions(items),
          decoration: const InputDecoration(
            labelText: 'Part',
            border: OutlineInputBorder(),
          ),
          dialogTitle: 'Pick a part',
          emptyText: 'No parts yet — make one first, then route it.',
          onChanged: (value) {
            if (value == null || value == _partId) return;
            setState(() => _partId = value);
            _loadRoute(value);
          },
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(fontSize: 14, color: Colors.red.shade700),
          ),
          const SizedBox(height: 12),
        ],
        if (_loadingStages)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          RouteEditor(
            // Keyed by part so switching parts builds a fresh editor rather
            // than carrying the previous part's draft into it.
            key: ValueKey<String>('route_editor_${_partId ?? 0}'),
            stages: _stages,
            steps: _steps,
            locked: _active != null,
            lockedVersion: _active?.version,
            onDeclareVersion: _active == null ? null : _unlockForVersion,
            onChanged: (steps) => setState(() => _steps = steps),
            onCreateStage: _service == null ? null : _createStage,
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: widget.onCancel,
            ),
            const SizedBox(width: 12),
            // Drawn disabled rather than hidden: a Save that vanishes until a
            // part is picked reads as a broken card, and the tooltip says what
            // is missing.
            Tooltip(
              message: _saveTooltip,
              child: AppButton(
                label: _active == null ? 'Save route' : 'Save as new version',
                isLoading: _saving,
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the active route for editing as a new version.
  ///
  /// Clearing `_active` is what unlocks the editor; `_pendingVersionOf`
  /// remembers that the save which follows must still be a `declareVersion`,
  /// so v1 is retired rather than rewritten. The steps stay as they are,
  /// because a version usually starts from what it changes.
  Future<void> _unlockForVersion() async {
    final active = _active;
    if (active == null) return;
    setState(() {
      _pendingVersionOf = active;
      _active = null;
    });
  }

  List<ItemDefinition> _readItems() {
    try {
      return context.watch<ItemsProvider>().items;
    } catch (_) {
      return const <ItemDefinition>[];
    }
  }
}
