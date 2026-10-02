import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/entity_link_service.dart';
import '../../domain/entity_link.dart';

/// Opens an editor for a new record of [type] and resolves to it once saved,
/// or null if nothing was saved. The host supplies this; the columns stay out
/// of the business of knowing which master has which editor.
typedef LinkRecordCreator =
    Future<LinkRef?> Function(BuildContext context, String type);

/// Tells the open columns to read their links again.
///
/// A host that can change the graph by other means — the creation window saves
/// a die in its own editor and attaches it to the item showing in a column —
/// calls [refresh] so the column is not left displaying what was true a moment
/// ago. Only what is on screen is re-read; a column nobody has opened has
/// nothing to correct.
class LinkColumnsController extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// The link catalog, or null once the failure has been said out loud.
Future<List<LinkableType>?> _catalogOrNull(
  BuildContext context,
  EntityLinkService service,
) async {
  try {
    return await service.fetchTypes();
  } catch (error) {
    if (context.mounted) {
      showAppToast(context, '$error', kind: AppToastKind.error);
    }
    return null;
  }
}

/// Attach a record to [subject]: pick the master, pick the record (or make a
/// new one through [onCreate]), and link it. Returns what was linked, or null
/// if the gesture was abandoned or refused.
///
/// Public because the column headers are not the only place this belongs. The
/// creation window puts the same gesture on its lineup rows, so a tile can be
/// linked without a column being open at all — and it has to be the SAME
/// gesture, not a second one that drifts: one menu, one picker, one call.
///
/// [at] is where the menu should appear, in global coordinates — usually the
/// bottom-left of whatever was clicked. [types] saves a round trip when the
/// caller already has the catalog; without it this fetches it.
Future<LinkRef?> showLinkAttach(
  BuildContext context, {
  required EntityLinkService service,
  required LinkRef subject,
  required Offset at,
  List<LinkableType>? types,
  LinkRecordCreator? onCreate,
}) async {
  // Read before anything is awaited, so where the menu goes is settled by the
  // layout the click happened in.
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final menuAt = RelativeRect.fromRect(
    Rect.fromLTWH(at.dx, at.dy, 0, 0),
    Offset.zero & overlayBox.size,
  );

  // The guard sits directly after the await, in the same block: anything more
  // tangled and the analyzer cannot tell the context is still good, and
  // neither can a reader.
  var catalog = types;
  if (catalog == null) {
    catalog = await _catalogOrNull(context, service);
    if (!context.mounted) return null;
  }
  if (catalog == null) return null;

  final offerable = catalog
      .where((type) => type.canLink)
      .toList(growable: false);
  if (offerable.isEmpty) {
    showAppToast(
      context,
      'You do not have rights to link anything here.',
      kind: AppToastKind.error,
    );
    return null;
  }

  final chosen = await showMenu<String>(
    context: context,
    position: menuAt,
    items: [
      for (final type in offerable)
        PopupMenuItem<String>(
          key: ValueKey('link_attach_master_${type.type}'),
          value: type.type,
          child: Row(
            children: [
              Icon(_iconFor(type.type), size: 20, color: SoftErpTheme.accent),
              const SizedBox(width: 10),
              Text(type.label, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
    ],
  );
  if (chosen == null || !context.mounted) return null;

  final spec = offerable.where((type) => type.type == chosen).firstOrNull;
  final picked = await showDialog<LinkRef>(
    context: context,
    builder: (_) => _AttachDialog(
      service: service,
      subject: subject,
      type: chosen,
      label: spec?.label ?? chosen,
      plural: spec?.plural ?? chosen,
      onCreate: onCreate,
    ),
  );
  if (picked == null || !context.mounted) return null;

  try {
    await service.link(
      fromType: subject.type,
      fromId: subject.id,
      toType: picked.type,
      toId: picked.id,
    );
  } catch (error) {
    if (context.mounted) {
      showAppToast(context, '$error', kind: AppToastKind.error);
    }
    return null;
  }
  if (context.mounted) {
    showAppToast(
      context,
      '${picked.label} linked to ${subject.label}.',
      kind: AppToastKind.success,
    );
  }
  return picked;
}

/// Miller columns over the link graph.
///
/// The first column lists one master. Picking a record opens a column of
/// everything that record is linked to, grouped by master; picking one of
/// those opens its links in turn, and so on to the right. An item's column
/// shows its dies and machines; a die's column shows the items it makes and
/// the machines it runs on — the same links, read from the other end, because
/// the store keeps one row per link and no privileged direction.
///
/// Every column's header carries a +, which both attaches an existing record
/// and (when the host passes [onCreate]) makes a new one and links it in the
/// same gesture. So "add a die to this item" is one move from the item's own
/// column, and so is "add this die to another item" from the die's.
///
/// What a column can offer comes from the server's catalog, not from a list
/// here: a master added to it appears in every + menu, and a master the user
/// cannot read never appears at all.
class LinkColumns extends StatefulWidget {
  const LinkColumns({
    super.key,
    required this.service,
    this.rootType = 'item',
    this.anchor,
    this.onCreate,
    this.columnWidth = 320,
    this.onSelectionChanged,
    this.controller,
    this.addAtBottom = false,
    this.minColumns = 1,
    this.onAnchorTotal,
  });

  final EntityLinkService service;

  /// Lets the host re-read what is on screen after it changes the graph
  /// itself.
  final LinkColumnsController? controller;

  /// The record the cascade hangs off, when the host already has one in hand.
  ///
  /// Non-null drops the browse column entirely: the first column shown is this
  /// record's links, and the chain grows from there. That is how the creation
  /// window attaches the cascade to the tile selected in its own first
  /// column — the tile IS the root, so a second list of records beside it
  /// would only ask the same question twice. Changing it starts a new chain.
  final LinkRef? anchor;

  /// The master the first column lists, when there is no [anchor]. The header
  /// lets it be switched, which is how the same view answers "this die's
  /// items" instead of "this item's dies".
  final String rootType;

  /// Lets a column make a record as well as attach one.
  final LinkRecordCreator? onCreate;

  final double columnWidth;

  /// The record in the rightmost open column, as it changes. A host can use it
  /// to keep another panel in step.
  final ValueChanged<LinkRef?>? onSelectionChanged;

  /// Puts the + at the foot of each column, full width, instead of as an icon
  /// in its header. Matches a host whose own columns add from the bottom.
  final bool addAtBottom;

  /// How many links the anchor turned out to have, each time they are read.
  ///
  /// A host that only wants to show these columns once there IS something to
  /// show needs the count, and only this widget ever asks for it.
  final ValueChanged<int>? onAnchorTotal;

  /// How many columns stand open even before anything has been picked in them.
  ///
  /// A chain only one deep still shows the next column, empty and saying what
  /// would fill it. Finder does the same, and it is what makes the cascade
  /// legible before you have used it: you can see that picking a die here will
  /// answer what that die runs on, without having to try it.
  final int minColumns;

  @override
  State<LinkColumns> createState() => _LinkColumnsState();
}

class _LinkColumnsState extends State<LinkColumns> {
  final ScrollController _scroll = ScrollController();

  late String _rootType = widget.rootType;

  /// The chain of picked records, left to right. Column 0 lists [_rootType];
  /// column i + 1 shows the links of `_trail[i]`.
  List<LinkRef> _trail = const [];

  List<LinkableType> _types = const [];
  String? _typesError;

  /// One entry per record whose links have been opened, keyed by [LinkRef.key].
  final Map<String, EntityLinks> _links = {};
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};

  List<LinkRef> _roots = const [];
  bool _rootsLoading = true;
  String? _rootsError;
  String _rootQuery = '';
  int _rootQuerySeq = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_reloadOpen);
    _loadTypes();
    if (widget.anchor case final anchor?) {
      _trail = [anchor];
      _loadLinks(anchor);
    } else {
      _loadRoots();
    }
  }

  @override
  void didUpdateWidget(LinkColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_reloadOpen);
      widget.controller?.addListener(_reloadOpen);
    }
    final anchor = widget.anchor;
    if (anchor != oldWidget.anchor) {
      // A different record to hang off: the old chain answered about something
      // else, so it goes rather than being left as a stale tail.
      setState(() => _trail = anchor == null ? const [] : [anchor]);
      if (anchor != null) _loadLinks(anchor, force: true);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_reloadOpen);
    _scroll.dispose();
    super.dispose();
  }

  /// Everything on screen, read again: the first column's listing (a record
  /// may have just been created) and the links of every record in the trail.
  Future<void> _reloadOpen() async {
    if (!mounted) return;
    if (widget.anchor == null) await _loadRoots();
    for (final ref in _trail) {
      await _loadLinks(ref, force: true);
    }
  }

  Future<void> _loadTypes() async {
    try {
      final types = await widget.service.fetchTypes();
      if (!mounted) return;
      setState(() {
        _types = types;
        _typesError = null;
        // The master the first column lists has to be one the server offered;
        // a user without the item master still gets a usable first column.
        if (types.isNotEmpty && !types.any((type) => type.type == _rootType)) {
          _rootType = types.first.type;
          _loadRoots();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _typesError = '$error');
    }
  }

  Future<void> _loadRoots() async {
    final seq = ++_rootQuerySeq;
    setState(() {
      _rootsLoading = true;
      _rootsError = null;
    });
    try {
      final records = await widget.service.browse(_rootType, query: _rootQuery);
      // A slower earlier search must not land on top of a later one.
      if (!mounted || seq != _rootQuerySeq) return;
      setState(() {
        _roots = records;
        _rootsLoading = false;
      });
    } catch (error) {
      if (!mounted || seq != _rootQuerySeq) return;
      setState(() {
        _rootsError = '$error';
        _rootsLoading = false;
      });
    }
  }

  Future<void> _loadLinks(LinkRef ref, {bool force = false}) async {
    if (_loading.contains(ref.key)) return;
    if (!force && _links.containsKey(ref.key)) return;
    setState(() {
      _loading.add(ref.key);
      _errors.remove(ref.key);
    });
    try {
      final links = await widget.service.fetchLinks(ref.type, ref.id);
      if (!mounted) return;
      setState(() {
        _links[ref.key] = links;
        _loading.remove(ref.key);
      });
      if (ref == widget.anchor) widget.onAnchorTotal?.call(links.total);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errors[ref.key] = '$error';
        _loading.remove(ref.key);
      });
    }
  }

  LinkableType? _typeFor(String type) =>
      _types.where((entry) => entry.type == type).firstOrNull;

  /// A pick in column [depth]: everything to its right is a different question
  /// now, so it goes.
  void _select(int depth, LinkRef ref) {
    setState(() {
      _trail = [..._trail.take(depth), ref];
    });
    widget.onSelectionChanged?.call(ref);
    _loadLinks(ref);
    // The column that just opened is off the right edge on a narrow window.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _switchRoot(String type) {
    if (type == _rootType) return;
    setState(() {
      _rootType = type;
      _rootQuery = '';
      _trail = const [];
      _roots = const [];
    });
    widget.onSelectionChanged?.call(null);
    _loadRoots();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showAppToast(
      context,
      message,
      kind: error ? AppToastKind.error : AppToastKind.success,
    );
  }

  // ---------------------------------------------------------------------------
  // Attaching
  // ---------------------------------------------------------------------------

  /// The + at the head or foot of one column.
  Future<void> _addTo(LinkRef subject, Offset at) async {
    final picked = await showLinkAttach(
      context,
      service: widget.service,
      subject: subject,
      at: at,
      types: _types,
      onCreate: widget.onCreate,
    );
    if (picked == null || !mounted) return;
    // Both ends changed: the subject gained a link, and so did the record that
    // was attached — which may well be open in a column further left.
    await _loadLinks(subject, force: true);
    if (_links.containsKey(picked.key)) {
      await _loadLinks(picked, force: true);
    }
  }

  Future<void> _unlink(LinkRef subject, LinkRef other) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlink?'),
        content: Text(
          '${other.label} will no longer be linked to ${subject.label}. '
          'Neither record is deleted.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep', style: TextStyle(fontSize: 15)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unlink', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.service.unlink(
        fromType: subject.type,
        fromId: subject.id,
        toType: other.type,
        toId: other.id,
      );
    } catch (error) {
      _toast('$error', error: true);
      return;
    }
    if (!mounted) return;
    // An unlinked record cannot stay open to the right of the column it was
    // unlinked from.
    final cut = _trail.indexOf(other);
    if (cut >= 0) {
      setState(() => _trail = _trail.sublist(0, cut));
      widget.onSelectionChanged?.call(_trail.lastOrNull);
    }
    await _loadLinks(subject, force: true);
    if (_links.containsKey(other.key)) await _loadLinks(other, force: true);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_typesError != null) {
      return _LinkColumnsMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Links are unavailable',
        detail: _typesError!,
        onRetry: _loadTypes,
      );
    }
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.anchor == null)
              SizedBox(width: widget.columnWidth, child: _buildRootColumn()),
            for (var depth = 0; depth < _trail.length; depth++) ...[
              // No gap before the first column when it is the only root: the
              // host has already placed this whole strip.
              if (depth > 0 || widget.anchor == null)
                const SizedBox(width: 12),
              SizedBox(
                width: widget.columnWidth,
                child: _buildLinksColumn(_trail[depth], depth + 1),
              ),
            ],
            // The columns standing open past the end of the chain.
            for (
              var extra = _trail.length;
              extra < widget.minColumns + (widget.anchor == null ? 1 : 0);
              extra++
            ) ...[
              if (extra > 0 || widget.anchor == null)
                const SizedBox(width: 12),
              SizedBox(
                width: widget.columnWidth,
                child: _WaitingColumn(
                  after: _trail.isEmpty ? null : _trail.last.label,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRootColumn() {
    final spec = _typeFor(_rootType);
    final selected = _trail.firstOrNull;
    return _ColumnShell(
      header: _ColumnHeader(
        title: spec?.plural ?? _rootType,
        count: _roots.length,
        icon: _iconFor(_rootType),
        // The first column's master is a choice, not a given: switching it is
        // what turns "this item's dies" into "this die's items".
        trailing: _types.length > 1
            ? PopupMenuButton<String>(
                key: const ValueKey('link_columns_root_type'),
                tooltip: 'Show a different master',
                onSelected: _switchRoot,
                itemBuilder: (_) => [
                  for (final type in _types)
                    PopupMenuItem<String>(
                      value: type.type,
                      child: Row(
                        children: [
                          Icon(
                            _iconFor(type.type),
                            size: 20,
                            color: type.type == _rootType
                                ? SoftErpTheme.accent
                                : SoftErpTheme.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            type.plural,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                ],
                icon: const Icon(Icons.swap_horiz, size: 22),
                color: Colors.white,
              )
            : null,
      ),
      search: TextField(
        key: const ValueKey('link_columns_root_search'),
        style: const TextStyle(fontSize: 14.5),
        decoration: _searchDecoration('Search ${spec?.plural ?? _rootType}'),
        onChanged: (value) {
          _rootQuery = value.trim();
          _loadRoots();
        },
      ),
      body: _rootsLoading
          ? const _ColumnSpinner()
          : _rootsError != null
          ? _LinkColumnsMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load',
              detail: _rootsError!,
              onRetry: _loadRoots,
            )
          : _roots.isEmpty
          ? _ColumnEmpty(
              text: _rootQuery.isEmpty
                  ? 'Nothing here yet.'
                  : 'Nothing matches "$_rootQuery".',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
              itemCount: _roots.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final ref = _roots[index];
                return _LinkRow(
                  ref: ref,
                  icon: _iconFor(ref.type),
                  selected: ref == selected,
                  onTap: () => _select(0, ref),
                );
              },
            ),
    );
  }

  Widget _buildLinksColumn(LinkRef subject, int depth) {
    final links = _links[subject.key];
    final error = _errors[subject.key];
    final busy = _loading.contains(subject.key);
    final selected = _trail.length > depth ? _trail[depth] : null;

    // One + per column, so a link is made from whichever record is in front of
    // you — the item, or the die you reached through it. Where it sits is the
    // host's call: an icon in the header, or a full-width button at the foot
    // to match a host whose own columns add from the bottom.
    Widget addButton(BuildContext buttonContext, Widget child) => InkWell(
      key: ValueKey('link_columns_add_${subject.key}'),
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
      onTap: () {
        final box = buttonContext.findRenderObject() as RenderBox?;
        final at = box == null
            ? Offset.zero
            : box.localToGlobal(box.size.bottomLeft(Offset.zero));
        _addTo(subject, at);
      },
      child: child,
    );

    return _ColumnShell(
      footer: widget.addAtBottom
          ? Builder(
              builder: (buttonContext) => Tooltip(
                message: 'Link something to ${subject.label}',
                child: addButton(
                  buttonContext,
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        SoftErpTheme.radiusMd,
                      ),
                      border: Border.all(
                        color: SoftErpTheme.borderStrong,
                        width: 1.4,
                      ),
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 26,
                      color: SoftErpTheme.accent,
                    ),
                  ),
                ),
              ),
            )
          : null,
      header: _ColumnHeader(
        title: subject.label,
        subtitle: _typeFor(subject.type)?.label ?? subject.type,
        count: links?.total,
        icon: _iconFor(subject.type),
        trailing: widget.addAtBottom
            ? null
            : Builder(
                builder: (buttonContext) => Tooltip(
                  message: 'Link something to ${subject.label}',
                  child: addButton(
                    buttonContext,
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.add_link,
                        size: 24,
                        color: SoftErpTheme.accent,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      body: busy && links == null
          ? const _ColumnSpinner()
          : error != null
          ? _LinkColumnsMessage(
              icon: Icons.lock_outline,
              title: 'Could not load links',
              detail: error,
              onRetry: () => _loadLinks(subject, force: true),
            )
          : links == null || links.isEmpty
          ? _ColumnEmpty(
              text: 'Nothing linked to ${subject.label} yet.\n'
                  'Use + to attach one.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
              children: [
                for (final group in links.groups) ...[
                  _GroupHeading(
                    label: group.links.length == 1
                        ? group.label
                        : group.plural,
                    count: group.links.length,
                    icon: _iconFor(group.type),
                  ),
                  for (final ref in group.links) ...[
                    _LinkRow(
                      ref: ref,
                      icon: _iconFor(ref.type),
                      selected: ref == selected,
                      onTap: () => _select(depth, ref),
                      onUnlink: () => _unlink(subject, ref),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 6),
                ],
              ],
            ),
    );
  }
}

/// The icon for a master. Keyed by the catalog's `icon` hint, which is a plain
/// word rather than a Flutter codepoint so the server stays free of the app's
/// icon set; an unknown one falls back to a neutral shape rather than nothing.
IconData _iconFor(String type) => switch (type) {
  'item' => Icons.inventory_2_outlined,
  'die' => Icons.build_circle_outlined,
  'machine' => Icons.precision_manufacturing_outlined,
  'group' => Icons.account_tree_outlined,
  'pipeline' => Icons.timeline_outlined,
  'material' => Icons.layers_outlined,
  'unit' => Icons.straighten_outlined,
  'client' => Icons.groups_outlined,
  'vendor' => Icons.storefront_outlined,
  'employee' => Icons.badge_outlined,
  'department' => Icons.apartment_outlined,
  _ => Icons.link_outlined,
};

InputDecoration _searchDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(fontSize: 14.5, color: SoftErpTheme.textSecondary),
  prefixIcon: const Icon(Icons.search, size: 20),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  filled: true,
  fillColor: SoftErpTheme.sectionSurface,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
    borderSide: const BorderSide(color: SoftErpTheme.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
    borderSide: const BorderSide(color: SoftErpTheme.border),
  ),
);

/// A column past the end of the chain: open, empty, and saying what picking
/// something to its left would put in it.
class _WaitingColumn extends StatelessWidget {
  const _WaitingColumn({required this.after});

  /// The record in the column to the left, when there is one.
  final String? after;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.75,
      child: _ColumnShell(
        header: const _ColumnHeader(
          title: 'Nothing picked',
          icon: Icons.more_horiz,
        ),
        body: _ColumnEmpty(
          text: after == null
              ? 'Pick a record on the left.'
              : 'Pick one of $after\'s links, and what IT is linked to shows '
                    'here.',
        ),
      ),
    );
  }
}

class _ColumnShell extends StatelessWidget {
  const _ColumnShell({
    required this.header,
    required this.body,
    this.search,
    this.footer,
  });

  final Widget header;
  final Widget body;
  final Widget? search;

  /// Sits below the list, outside its scroll, so it stays reachable however
  /// long the column gets.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
        border: Border.all(color: SoftErpTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (search != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: search!,
            ),
          const Divider(height: 1, color: SoftErpTheme.border),
          Expanded(child: body),
          if (footer != null) ...[
            const Divider(height: 1, color: SoftErpTheme.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.title,
    required this.icon,
    this.subtitle,
    this.count,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: SoftErpTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            _Badge(label: '$count'),
          ],
          ?trailing,
        ],
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.label,
    required this.count,
    required this.icon,
  });

  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          _Badge(label: '$count'),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.ref,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onUnlink,
  });

  final LinkRef ref;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SoftErpTheme.accentSoft : SoftErpTheme.cardSurfaceAlt,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
      child: InkWell(
        key: ValueKey('link_row_${ref.key}'),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: SoftErpTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.label.isEmpty ? '(unnamed)' : ref.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                    if (ref.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          ref.subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: SoftErpTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (onUnlink != null)
                IconButton(
                  key: ValueKey('link_unlink_${ref.key}'),
                  tooltip: 'Unlink',
                  iconSize: 20,
                  color: SoftErpTheme.textSecondary,
                  icon: const Icon(Icons.link_off),
                  onPressed: onUnlink,
                ),
              const Icon(
                Icons.chevron_right,
                size: 22,
                color: SoftErpTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: SoftErpTheme.accentDeeper,
        ),
      ),
    );
  }
}

class _ColumnSpinner extends StatelessWidget {
  const _ColumnSpinner();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(strokeWidth: 2.6),
    ),
  );
}

class _ColumnEmpty extends StatelessWidget {
  const _ColumnEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14.5, color: SoftErpTheme.textSecondary),
      ),
    ),
  );
}

class _LinkColumnsMessage extends StatelessWidget {
  const _LinkColumnsMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: SoftErpTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: SoftErpTheme.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Try again', style: TextStyle(fontSize: 15)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Attach one record of a master to [subject]: search what exists, or make a
/// new one. Resolves to the record to link.
class _AttachDialog extends StatefulWidget {
  const _AttachDialog({
    required this.service,
    required this.subject,
    required this.type,
    required this.label,
    required this.plural,
    this.onCreate,
  });

  final EntityLinkService service;
  final LinkRef subject;
  final String type;
  final String label;
  final String plural;
  final LinkRecordCreator? onCreate;

  @override
  State<_AttachDialog> createState() => _AttachDialogState();
}

class _AttachDialogState extends State<_AttachDialog> {
  List<LinkRef> _candidates = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final candidates = await widget.service.fetchCandidates(
        type: widget.subject.type,
        id: widget.subject.id,
        otherType: widget.type,
        query: _query,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final creator = widget.onCreate;
    return Dialog(
      backgroundColor: SoftErpTheme.shellSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Link a ${widget.label.toLowerCase()}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: SoftErpTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'to ${widget.subject.label}',
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: SoftErpTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    iconSize: 24,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                key: const ValueKey('link_attach_search'),
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                decoration: _searchDecoration('Search ${widget.plural}'),
                onChanged: (value) {
                  _query = value.trim();
                  _load();
                },
              ),
            ),
            if (creator != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: OutlinedButton.icon(
                  key: const ValueKey('link_attach_create'),
                  onPressed: () async {
                    // Held before the await: the editor is a route of its own,
                    // and this dialog's own context is gone by the time it
                    // closes.
                    final navigator = Navigator.of(context);
                    final created = await creator(context, widget.type);
                    if (created == null || !mounted) return;
                    // Made and linked in one gesture: the new record goes
                    // straight back as the one to attach.
                    navigator.pop(created);
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(
                    'New ${widget.label.toLowerCase()}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            const Divider(height: 1, color: SoftErpTheme.border),
            Expanded(
              child: _loading
                  ? const _ColumnSpinner()
                  : _error != null
                  ? _LinkColumnsMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load',
                      detail: _error!,
                      onRetry: _load,
                    )
                  : _candidates.isEmpty
                  ? _ColumnEmpty(
                      text: _query.isEmpty
                          ? 'Every ${widget.label.toLowerCase()} there is, is '
                                'already linked here.'
                          : 'Nothing matches "$_query".',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      itemCount: _candidates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final ref = _candidates[index];
                        return _LinkRow(
                          ref: ref,
                          icon: _iconFor(ref.type),
                          selected: false,
                          onTap: () => Navigator.of(context).pop(ref),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
