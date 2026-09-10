import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/soft_erp_theme.dart';
import '../../../../../core/app_flow_hooks.dart';
import '../../../../../core/widgets/app_toast.dart';
import '../../../../../core/widgets/searchable_select.dart';
import '../../../../items/domain/item_definition.dart';
import '../../../../items/presentation/providers/items_provider.dart';
import '../../../../items/data/services/item_link_options_service.dart';

// --- PIPELINES ---

class ComponentPipelinesCard extends StatefulWidget {
  const ComponentPipelinesCard({
    super.key,
    required this.item,
    required this.onSave,
  });
  final ItemDefinition item;
  final VoidCallback onSave;

  @override
  State<ComponentPipelinesCard> createState() => _ComponentPipelinesCardState();
}

class _ComponentPipelinesCardState extends State<ComponentPipelinesCard> {
  List<Map<String, String>> _pipelines = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final pipelines = await context
        .read<ItemsProvider>()
        .fetchPipelineTemplates();
    if (mounted) setState(() => _pipelines = pipelines);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePipeline(String pipelineId) async {
    final provider = context.read<ItemsProvider>();
    await _run(() async {
      final saved = await provider.setItemPipeline(widget.item.id, pipelineId);
      if (!mounted) return;
      if (saved == null) {
        final reason = provider.errorMessage ?? 'Could not set the pipeline.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(reason)));
      }
    });
  }

  Future<void> _createPipeline() async {
    final create = AppFlowHooks.createPipelineFor(context);
    if (create == null) return;
    final id = await create();
    if (id == null || !mounted) return;
    await _run(() async {
      await context.read<ItemsProvider>().setItemPipeline(widget.item.id, id);
      await _loadOptions();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          value: widget.item.defaultPipelineId,
          decoration: InputDecoration(
            labelText: 'Pipeline',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('No pipeline'),
            ),
            for (final p in _pipelines)
              DropdownMenuItem<String>(value: p['id'], child: Text(p['name']!)),
          ],
          onChanged: (val) {
            if (val != null) {
              _choosePipeline(val);
            } else {
              _run(
                () => context.read<ItemsProvider>().setItemPipeline(
                  widget.item.id,
                  null,
                ),
              );
            }
          },
        ),
        if (AppFlowHooks.createPipelineFor(context) != null) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _createPipeline,
            icon: const Icon(Icons.add),
            label: const Text('Create New Pipeline'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: widget.onSave,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

// --- MACHINES AND DIES ---

/// Which of an item's two link lists a card is showing.
///
/// Attaching a machine and attaching a die are the same flow — read what is
/// on the item, take one off, pick another, make a new one — so both run on
/// one body. Only the wording, the icon and the list they read differ.
enum _LinkKind { machine, die }

class ComponentMachinesCard extends StatelessWidget {
  const ComponentMachinesCard({
    super.key,
    required this.item,
    required this.onSave,
  });

  final ItemDefinition item;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) =>
      _ComponentLinksCard(kind: _LinkKind.machine, item: item, onSave: onSave);
}

class ComponentDiesCard extends StatelessWidget {
  const ComponentDiesCard({
    super.key,
    required this.item,
    required this.onSave,
  });

  final ItemDefinition item;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) =>
      _ComponentLinksCard(kind: _LinkKind.die, item: item, onSave: onSave);
}

/// One attached machine or die, flattened so the two lists render as one.
class _AttachedLink {
  const _AttachedLink({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.photoUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? photoUrl;
}

class _ComponentLinksCard extends StatefulWidget {
  const _ComponentLinksCard({
    required this.kind,
    required this.item,
    required this.onSave,
  });

  final _LinkKind kind;
  final ItemDefinition item;
  final VoidCallback onSave;

  @override
  State<_ComponentLinksCard> createState() => _ComponentLinksCardState();
}

class _ComponentLinksCardState extends State<_ComponentLinksCard> {
  List<ItemLinkOption> _options = const [];
  bool _busy = false;

  bool get _isMachine => widget.kind == _LinkKind.machine;

  /// 'machine' or 'die', for the wording.
  String get _noun => _isMachine ? 'machine' : 'die';

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final service = context.read<ItemLinkOptionsService>();
      final loaded = _isMachine
          ? await service.fetchMachines()
          : await service.fetchDies();
      if (mounted) setState(() => _options = loaded);
    } catch (_) {
      // Nothing to add is a workable state: what is already attached still
      // reads, and the picker says it has nothing to offer.
    }
  }

  List<_AttachedLink> get _attached => _isMachine
      ? [
          for (final machine in widget.item.machines)
            _AttachedLink(
              id: machine.id,
              title: machine.name,
              subtitle: machine.assetId,
              photoUrl: machine.photoUrl,
            ),
        ]
      : [
          for (final die in widget.item.dies)
            _AttachedLink(
              id: die.id,
              title: die.toolCode.trim().isEmpty
                  ? 'Die ${die.id}'
                  : die.toolCode,
              photoUrl: die.photoUrl,
            ),
        ];

  /// Writes the new list, and says so when it does not land.
  ///
  /// The save is refused outright while another one is in flight, which the
  /// old silent call left looking like a click that did nothing — the reason
  /// picking a second machine seemed to be what made the first appear.
  Future<void> _setLinks(List<String> ids) async {
    if (_busy) return;
    setState(() => _busy = true);
    final provider = context.read<ItemsProvider>();
    try {
      final saved = await provider.setItemLinks(
        widget.item.id,
        machineIds: _isMachine ? ids : null,
        dieIds: _isMachine ? null : ids,
      );
      if (!mounted || saved != null) return;
      showAppToast(
        context,
        provider.errorMessage ?? 'Could not save the ${_noun}s. Try again.',
        kind: AppToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(String id) {
    final ids = _attached.map((link) => link.id).toList();
    if (ids.contains(id)) return Future<void>.value();
    return _setLinks(<String>[...ids, id]);
  }

  Future<void> _detach(String id) {
    final ids = _attached.map((link) => link.id).toList();
    if (!ids.remove(id)) return Future<void>.value();
    return _setLinks(ids);
  }

  String _labelFor(ItemLinkOption option) => option.subtitle.trim().isEmpty
      ? option.label
      : '${option.label} · ${option.subtitle}';

  Future<bool> Function()? get _createHandler => _isMachine
      ? AppFlowHooks.createMachineFor(context)
      : AppFlowHooks.createDieFor(context);

  /// Opens the host's machine or die editor and hands back what it made, so a
  /// freshly created one attaches on the spot instead of sending the user off
  /// to find it again.
  Future<SearchableSelectOption<String>?> _createAndPick() async {
    final create = _createHandler;
    if (create == null) return null;
    final knownIds = _options.map((option) => option.id).toSet();
    final made = await create();
    if (!made || !mounted) return null;
    await _loadOptions();
    if (!mounted) return null;
    final fresh = _options
        .where((option) => !knownIds.contains(option.id))
        .toList(growable: false);
    if (fresh.length != 1) return null;
    return SearchableSelectOption<String>(
      value: fresh.single.id,
      label: _labelFor(fresh.single),
    );
  }

  Future<void> _openPicker(BuildContext anchorContext) async {
    final attachedIds = _attached.map((link) => link.id).toSet();
    final canCreate = _createHandler != null;
    final picked = await showSearchableSelectDialog<String>(
      context: anchorContext,
      title: _isMachine ? 'Add Machine' : 'Add Die',
      searchHintText: _isMachine ? 'Search machines...' : 'Search dies...',
      emptyText: _isMachine
          ? 'No machines left to add.'
          : 'No dies left to add.',
      options: [
        for (final option in _options)
          if (!attachedIds.contains(option.id))
            SearchableSelectOption<String>(
              value: option.id,
              label: _labelFor(option),
              searchText: '${option.label} ${option.subtitle}',
            ),
      ],
      canCreateOption: canCreate ? (query, options) => true : null,
      createOptionLabelBuilder: (query) =>
          _isMachine ? 'New machine' : 'New die',
      onCreateOption: canCreate ? (query) => _createAndPick() : null,
    );
    if (picked == null || !mounted) return;
    await _attach(picked.value);
  }

  /// The editor on its own, for when nothing has been typed to create from.
  Future<void> _createOnly() async {
    final create = _createHandler;
    if (create == null) return;
    final made = await create();
    if (!made || !mounted) return;
    await _loadOptions();
  }

  @override
  Widget build(BuildContext context) {
    final attached = _attached;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (attached.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No ${_noun}s attached yet.',
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          )
        else
          for (final link in attached) ...[
            _AttachedLinkRow(
              link: link,
              icon: _isMachine
                  ? Icons.precision_manufacturing_outlined
                  : Icons.dashboard_customize_outlined,
              onRemove: _busy ? null : () => _detach(link.id),
            ),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 6),
        Builder(
          builder: (anchorContext) => _AddLinkButton(
            label: _isMachine ? 'Add machine' : 'Add die',
            busy: _busy,
            onTap: _busy ? null : () => _openPicker(anchorContext),
          ),
        ),
        if (_createHandler != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _createOnly,
              icon: const Icon(Icons.add, size: 16),
              label: Text(_isMachine ? 'Create New Machine' : 'Create New Die'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: widget.onSave,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

/// An attached machine or die: what it is, what it is called, and the way off.
class _AttachedLinkRow extends StatelessWidget {
  const _AttachedLinkRow({
    required this.link,
    required this.icon,
    required this.onRemove,
  });

  final _AttachedLink link;
  final IconData icon;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final photoUrl = link.photoUrl;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              image: photoUrl != null && photoUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(photoUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? null
                : Icon(icon, size: 15, color: SoftErpTheme.textSecondary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  link.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (link.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    link.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: SoftErpTheme.textSecondary,
            onPressed: onRemove,
            tooltip: 'Detach',
            splashRadius: 18,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}

/// The way in to the picker.
///
/// A button rather than a select field: a field that is filled in and then
/// immediately empties itself reads as a failed edit, and the one this
/// replaced kept showing the last pick until it was rebuilt from scratch.
class _AddLinkButton extends StatelessWidget {
  const _AddLinkButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: SoftErpTheme.accent.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            if (busy)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.add, size: 16, color: SoftErpTheme.accentDeeper),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                busy ? 'Saving…' : label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.accentDeeper,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: SoftErpTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
