import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/services/generic_asset_service.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/utils/naming_format_helper.dart';
import '../../domain/inventory_set_definition.dart';
import '../providers/inventory_provider.dart';

/// The shelf handoff runs in two visible legs: the composition row drifts left
/// and fades, then the shelf tile flies in from the right. Paced so the carry
/// over reads as one continuous movement rather than a swap.
const Duration _kDepartureDuration = Duration(milliseconds: 460);
const Duration _kArrivalDuration = Duration(milliseconds: 520);
const Duration _kShelfMotionDuration = Duration(milliseconds: 460);

class InventorySetEditorDialog extends StatefulWidget {
  const InventorySetEditorDialog({super.key, this.setDefinition});

  final InventorySetDefinition? setDefinition;

  static Future<void> open(
    BuildContext context, {
    InventorySetDefinition? setDefinition,
  }) {
    return showErpFormDialog<void>(
      context,
      // Headroom for the third column; the dialog only grows into it once
      // completed rows start parking on the shelf.
      maxWidth: 1400,
      maxHeight: 780,
      child: InventorySetEditorDialog(setDefinition: setDefinition),
    );
  }

  @override
  State<InventorySetEditorDialog> createState() =>
      _InventorySetEditorDialogState();
}

class _InventorySetEditorDialogState extends State<InventorySetEditorDialog> {
  /// How many trailing rows stay in the editing column when Add Row pushes the
  /// older ones onto the shelf.
  static const int _maxEditorRows = 2;

  static const double _twoColumnWidth = 1120;
  static const double _threeColumnWidth = 1400;

  final _formKey = GlobalKey<FormState>();
  final GlobalKey _compositionViewportKey = GlobalKey();
  final ScrollController _compositionScrollController = ScrollController();
  late final TextEditingController _nameController;
  late final List<_EditableInventorySetLine> _lines;

  /// Rows that have finished the handoff and now live on the shelf, in shelf
  /// display order: newest first, and the user can drag them around. This is
  /// presentation only — saved line positions still follow composition order.
  final List<_EditableInventorySetLine> _shelfOrder =
      <_EditableInventorySetLine>[];

  /// Rows mid-flight: still occupying their slot in the composition column,
  /// animating out, not yet drawn on the shelf.
  final Set<_EditableInventorySetLine> _departingLines =
      <_EditableInventorySetLine>{};

  /// Rows that finished their exit while a drag or fling was still running;
  /// their slot closes once the scroll settles.
  final Set<_EditableInventorySetLine> _awaitingScrollSettle =
      <_EditableInventorySetLine>{};

  /// Shelved rows the user tapped back open; they stay in the editing column
  /// until the next Add Row.
  final Set<_EditableInventorySetLine> _pinnedLines =
      <_EditableInventorySetLine>{};

  /// The set's photo, held as the read URL the upload returns — the same shape
  /// clients and vendors use, so it needs no set id and works before first save.
  String _photoUrl = '';
  bool _isUploadingPhoto = false;

  ValueNotifier<bool>? _scrollingNotifier;
  double _pendingCompensation = 0;
  double _compensationAnchor = 0;
  bool _isCompensationScheduled = false;

  bool get _isEditMode => widget.setDefinition != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.setDefinition?.name ?? '',
    );
    _lines =
        widget.setDefinition?.lines
            .map(
              (line) => _EditableInventorySetLine(
                itemId: line.itemId,
                variationLeafNodeId: line.variationLeafNodeId,
                selectionKey: '${line.itemId}::${line.variationLeafNodeId}',
                itemLabel: line.itemDisplayName.trim().isEmpty
                    ? line.itemName
                    : line.itemDisplayName,
                variationPathLabel: line.variationPathLabel,
                variationPathNodeIds: line.variationPathNodeIds,
                quantity: line.quantity.toString(),
              ),
            )
            .toList(growable: true) ??
        <_EditableInventorySetLine>[_EditableInventorySetLine()];
    for (final line in _lines) {
      line.quantityController.addListener(_handleQuantityChanged);
    }
    _photoUrl = widget.setDefinition?.photoUrl ?? '';
    // An existing set opens with its older rows already shelved — no flight.
    // Reversed so the shelf starts out newest-first like every later arrival.
    _shelfOrder.addAll(_positionalDepartures().reversed);
    _compositionScrollController.addListener(_handleCompositionScroll);
  }

  @override
  void dispose() {
    _scrollingNotifier?.removeListener(_flushSettledDepartures);
    _compositionScrollController.removeListener(_handleCompositionScroll);
    _compositionScrollController.dispose();
    _nameController.dispose();
    for (final line in _lines) {
      line.quantityController.removeListener(_handleQuantityChanged);
      line.dispose();
    }
    super.dispose();
  }

  /// Uploads a picture for the set and keeps the returned read URL. Mirrors the
  /// client and vendor photo flow, so there is one upload path to reason about.
  Future<void> _pickSetPhoto() async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: <String>['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await file.readAsBytes();
      const baseUrl = String.fromEnvironment(
        'PAPER_API_BASE_URL',
        defaultValue: 'http://localhost:8080',
      );
      final service = GenericAssetService(baseUrl: baseUrl);
      final intent = await service.createUploadIntent(
        GenericAssetUploadIntentInput(
          fileName: file.name,
          contentType:
              file.mimeType ??
              lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
              'image/png',
          sizeBytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        ),
      );
      // A mock intent has nothing to PUT to; the read URL still comes back.
      if (intent.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          intent.uploadUrl,
          headers: intent.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Upload failed with status ${response.statusCode}.');
        }
      }
      final readUrl = intent.readUrl;
      if (readUrl == null) throw Exception('Upload returned no read URL.');
      if (!mounted) return;
      setState(() => _photoUrl = readUrl);
    } catch (error) {
      if (!mounted) return;
      showAppSnack(SnackBar(content: Text('Photo upload failed: $error')));
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  /// Keeps the left-column preview quantities in sync while the user types.
  void _handleQuantityChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  bool _isLineComplete(_EditableInventorySetLine line) {
    if (line.selectionKey == null || line.itemId == null) {
      return false;
    }
    return (int.tryParse(line.quantityController.text.trim()) ?? 0) > 0;
  }

  /// Rows Add Row pushes off: complete, not reopened, and no longer among the
  /// trailing [_maxEditorRows].
  List<_EditableInventorySetLine> _positionalDepartures() {
    final departures = <_EditableInventorySetLine>[];
    for (var index = 0; index < _lines.length - _maxEditorRows; index++) {
      final line = _lines[index];
      if (_pinnedLines.contains(line) || !_isLineComplete(line)) {
        continue;
      }
      departures.add(line);
    }
    return departures;
  }

  /// Scrolling a finished row up past the top of the composition column hands
  /// it to the shelf, the same as Add Row does.
  void _handleCompositionScroll() {
    if (!mounted || !_compositionScrollController.hasClients) {
      return;
    }
    final viewportBox =
        _compositionViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) {
      return;
    }
    final departures = <_EditableInventorySetLine>[];
    for (var index = 0; index < _lines.length - 1; index++) {
      final line = _lines[index];
      if (_shelfOrder.contains(line) ||
          _departingLines.contains(line) ||
          _pinnedLines.contains(line) ||
          !_isLineComplete(line)) {
        continue;
      }
      final rowBox =
          line.rowKey.currentContext?.findRenderObject() as RenderBox?;
      if (rowBox == null || !rowBox.hasSize) {
        continue;
      }
      final top = rowBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      if (top + rowBox.size.height < -8) {
        departures.add(line);
      }
    }
    _beginDeparture(departures);
  }

  /// Scroll and animation callbacks can land mid-frame, where setState would
  /// throw; defer to the next frame when that happens.
  bool _deferToNextFrame(VoidCallback action) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        action();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return true;
  }

  void _beginDeparture(List<_EditableInventorySetLine> lines) {
    final fresh = lines
        .where(
          (line) =>
              !_shelfOrder.contains(line) && !_departingLines.contains(line),
        )
        .toList(growable: false);
    if (fresh.isEmpty || !_isShelfEnabled || !mounted) {
      return;
    }
    if (_deferToNextFrame(() => _beginDeparture(fresh))) {
      return;
    }
    setState(() {
      _departingLines.addAll(fresh);
    });
  }

  /// Second leg of the handoff. The row has faded out by now, so its slot can
  /// close — but not while a drag or fling is running, since the scroll
  /// correction below would cancel the gesture. Holding an invisible slot for a
  /// moment costs nothing.
  void _completeDeparture(_EditableInventorySetLine line) {
    if (!mounted || !_departingLines.contains(line)) {
      return;
    }
    _watchScrollSettle();
    if (_scrollingNotifier?.value ?? false) {
      _awaitingScrollSettle.add(line);
      return;
    }
    if (_deferToNextFrame(() => _completeDeparture(line))) {
      return;
    }

    final vacated = _extentVacatedAboveFold(line);
    if (vacated > 0 && !_isCompensationScheduled) {
      _compensationAnchor = _compositionScrollController.position.pixels;
    }
    setState(() {
      _departingLines.remove(line);
      // Last in, first out: a new arrival always lands on top, whatever order
      // the user has dragged the rest into.
      _shelfOrder.insert(0, line);
    });
    _scheduleScrollCompensation(vacated);
  }

  void _watchScrollSettle() {
    if (!_compositionScrollController.hasClients) {
      return;
    }
    final notifier = _compositionScrollController.position.isScrollingNotifier;
    if (identical(_scrollingNotifier, notifier)) {
      return;
    }
    _scrollingNotifier?.removeListener(_flushSettledDepartures);
    _scrollingNotifier = notifier;
    notifier.addListener(_flushSettledDepartures);
  }

  void _flushSettledDepartures() {
    if ((_scrollingNotifier?.value ?? false) || _awaitingScrollSettle.isEmpty) {
      return;
    }
    final settled = _awaitingScrollSettle.toList(growable: false);
    _awaitingScrollSettle.clear();
    for (final line in settled) {
      _completeDeparture(line);
    }
  }

  /// Height the row is about to give back from above the viewport top — the
  /// part that would otherwise yank the visible rows upward.
  double _extentVacatedAboveFold(_EditableInventorySetLine line) {
    if (!_compositionScrollController.hasClients) {
      return 0;
    }
    final viewportBox =
        _compositionViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final rowBox = line.rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null ||
        rowBox == null ||
        !viewportBox.hasSize ||
        !rowBox.hasSize ||
        rowBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy >= 0) {
      return 0;
    }
    return rowBox.size.height + 12;
  }

  void _scheduleScrollCompensation(double vacated) {
    if (vacated <= 0) {
      return;
    }
    _pendingCompensation += vacated;
    if (_isCompensationScheduled) {
      return;
    }
    _isCompensationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isCompensationScheduled = false;
      final total = _pendingCompensation;
      _pendingCompensation = 0;
      if (!mounted || !_compositionScrollController.hasClients) {
        return;
      }
      final position = _compositionScrollController.position;
      final target = (_compensationAnchor - total).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if ((position.pixels - target).abs() > 0.5) {
        _compositionScrollController.jumpTo(target);
      }
    });
  }

  bool get _isShelfEnabled => MediaQuery.of(context).size.width >= 900;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final items =
        context
            .watch<ItemsProvider>()
            .items
            .where((item) => !item.isArchived)
            .toList(growable: false)
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
    final selectableReferences = _buildSelectableReferences(items);
    final selectableReferenceByKey = {
      for (final reference in selectableReferences) reference.key: reference,
    };
    final previewEntries = _buildPreviewEntries(
      items: items,
      selectableReferenceByKey: selectableReferenceByKey,
    );

    final isNarrow = MediaQuery.of(context).size.width < 900;

    final editorIndices = <int>[];
    for (var index = 0; index < _lines.length; index++) {
      // Departing rows keep their slot in the composition column until their
      // exit animation finishes.
      if (isNarrow || !_shelfOrder.contains(_lines[index])) {
        editorIndices.add(index);
      }
    }
    final hasShelf = !isNarrow && _shelfOrder.isNotEmpty;

    final header = Container(
      height: 76,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(bottom: BorderSide(color: Color(0xFFE7EBF0))),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditMode ? 'Edit Set' : 'Create Set',
                  style: _inventoryInterStyle(
                    color: const Color(0xFF111827),
                    size: 22,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Build a named composition of exact item variations and quantities.',
                  style: _inventoryInterStyle(
                    color: const Color(0xFF6B7280),
                    size: 13,
                    weight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );

    final footer = Container(
      height: 76,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(top: BorderSide(color: Color(0xFFE7EBF0))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: _isEditMode ? 'Save Changes' : 'Create Set',
            isLoading: inventory.isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );

    final detailsCard = _CreateGroupSurfaceCard(
      title: 'Set Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameController,
            style: _inventoryInterStyle(
              color: const Color(0xFF0F172A),
              size: 14,
              weight: FontWeight.w500,
            ),
            decoration: _editorFieldDecoration(
              label: 'Set Name',
              helper:
                  'Use a clear operational name like Starter Pack or Marketing Kit.',
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _SetPhotoField(
            photoUrl: _photoUrl,
            isUploading: _isUploadingPhoto,
            onPick: _pickSetPhoto,
            onClear: () => setState(() => _photoUrl = ''),
          ),
        ],
      ),
    );

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        detailsCard,
        const SizedBox(height: 24),
        _SetSelectionPreviewCard(entries: previewEntries),
      ],
    );

    final shelfCard = _CreateGroupSurfaceCard(
      title: 'Added Items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Newest on top. Drag to rearrange, or tap one to reopen it.',
            style: _inventoryInterStyle(
              color: const Color(0xFF64748B),
              size: 12,
              weight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _handleShelfReorder,
            // The default proxy paints an opaque elevated sheet over the tile;
            // the tile already carries its own surface.
            proxyDecorator: (child, index, animation) =>
                Material(color: Colors.transparent, child: child),
            children: [
              for (var slot = 0; slot < _shelfOrder.length; slot++)
                Padding(
                  key: ObjectKey(_shelfOrder[slot]),
                  padding: EdgeInsets.only(
                    bottom: slot == _shelfOrder.length - 1 ? 0 : 10,
                  ),
                  child: _buildShelvedTile(
                    line: _shelfOrder[slot],
                    dragIndex: slot,
                    selectableReferenceByKey: selectableReferenceByKey,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    final compositionCard = _CreateGroupSurfaceCard(
      title: 'Composition',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Each row must point to an exact item variation instance.',
            style: _inventoryInterStyle(
              color: const Color(0xFF64748B),
              size: 12,
              weight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          // No AnimatedSize here: a departing row has already faded out by the
          // time its slot closes, and an animated collapse would fight the
          // scroll compensation in _completeDeparture.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var slot = 0; slot < editorIndices.length; slot++) ...[
                _DepartingLineRow(
                  key: ObjectKey(_lines[editorIndices[slot]]),
                  rowKey: _lines[editorIndices[slot]].rowKey,
                  isDeparting: _departingLines.contains(
                    _lines[editorIndices[slot]],
                  ),
                  duration: _kDepartureDuration,
                  onDeparted: () =>
                      _completeDeparture(_lines[editorIndices[slot]]),
                  child: _buildLineRow(
                    index: editorIndices[slot],
                    line: _lines[editorIndices[slot]],
                    selectableReferences: selectableReferences,
                    selectableReferenceByKey: selectableReferenceByKey,
                  ),
                ),
                if (slot != editorIndices.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Add Row',
              variant: AppButtonVariant.secondary,
              onPressed: _addLine,
            ),
          ),
        ],
      ),
    );

    final content = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (isNarrow)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leftColumn,
                    const SizedBox(height: 24),
                    compositionCard,
                  ],
                ),
              ),
            )
          else
            // Each column scrolls on its own so the shelf stays in view while
            // the composition list runs long — and so scrolling the rows is
            // what drives the handoff.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Keyed so inserting the shelf column re-parents rather
                    // than shifting the composition scroll view onto a
                    // different element (and its controller with it).
                    Expanded(
                      key: const ValueKey<String>('set-editor-details-column'),
                      flex: 4,
                      child: SingleChildScrollView(child: leftColumn),
                    ),
                    const SizedBox(width: 24),
                    if (hasShelf) ...[
                      Expanded(
                        key: const ValueKey<String>('set-editor-shelf-column'),
                        flex: 4,
                        child: SingleChildScrollView(child: shelfCard),
                      ),
                      const SizedBox(width: 24),
                    ],
                    Expanded(
                      key: const ValueKey<String>(
                        'set-editor-composition-column',
                      ),
                      flex: 6,
                      child: SingleChildScrollView(
                        key: _compositionViewportKey,
                        controller: _compositionScrollController,
                        child: compositionCard,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          footer,
        ],
      ),
    );

    final surface = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: content,
    );

    if (isNarrow) {
      return surface;
    }

    // The dialog widens as the shelf column appears rather than squeezing the
    // composition rows into the existing two-column width.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: AnimatedContainer(
            duration: _kShelfMotionDuration,
            curve: Curves.easeOutCubic,
            width: math.min(
              hasShelf ? _threeColumnWidth : _twoColumnWidth,
              constraints.maxWidth,
            ),
            height: math.min(740.0, constraints.maxHeight),
            child: surface,
          ),
        );
      },
    );
  }


  Widget _buildLineRow({
    required int index,
    required _EditableInventorySetLine line,
    required List<_SelectableSetReference> selectableReferences,
    required Map<String, _SelectableSetReference> selectableReferenceByKey,
  }) {
    final selectedReference = line.selectionKey == null
        ? null
        : selectableReferenceByKey[line.selectionKey!];
    final itemLabel =
        selectedReference?.itemLabel ??
        (line.itemLabel.trim().isEmpty ? null : line.itemLabel);
    final variationLabel =
        selectedReference?.variationPathLabel ??
        (line.variationPathLabel.trim().isEmpty
            ? null
            : line.variationPathLabel);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SearchableSelectField<String?>(
                  tapTargetKey: ValueKey<String>('inventory-set-item-$index'),
                  value: line.selectionKey,
                  decoration: _editorFieldDecoration(
                    label: 'Item',
                    helper:
                        'Search by item name, alias, or variation-path terms.',
                  ),
                  dialogTitle: 'Select Item',
                  searchHintText: 'Search item or variation path',
                  options: selectableReferences
                      .map(
                        (reference) => SearchableSelectOption<String?>(
                          value: reference.key,
                          label: reference.optionLabel,
                          searchText: reference.searchText,
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => _handleReferenceSelection(
                    index,
                    value,
                    selectableReferenceByKey,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: line.quantityController,
                  focusNode: line.quantityFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: _inventoryInterStyle(
                    color: const Color(0xFF0F172A),
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                  decoration: _editorFieldDecoration(
                    label: 'Qty',
                    helper: 'Required',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: IconButton(
                  onPressed: _lines.length == 1
                      ? null
                      : () => _removeLine(index),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD8E0EA)),
            ),
            child: itemLabel == null
                ? Row(
                    children: [
                      const Icon(
                        Icons.link_off_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pick an exact item reference.',
                        style: _inventoryInterStyle(
                          color: const Color(0xFF94A3B8),
                          size: 12,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ReadOnlyReferenceChip(
                        icon: Icons.inventory_2_outlined,
                        label: itemLabel,
                      ),
                      _ReadOnlyReferenceChip(
                        icon: selectedReference?.variationLeafNodeId == 0
                            ? Icons.layers_clear_outlined
                            : Icons.account_tree_outlined,
                        label: variationLabel ?? 'Base item',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelvedTile({
    required _EditableInventorySetLine line,
    required int dragIndex,
    required Map<String, _SelectableSetReference> selectableReferenceByKey,
  }) {
    final reference = selectableReferenceByKey[line.selectionKey];
    final itemLabel = reference?.itemLabel ?? line.itemLabel.trim();
    final variationLabel =
        reference?.variationPathLabel ?? line.variationPathLabel.trim();
    return _ShelvedLineTile(
      dragIndex: dragIndex,
      itemLabel: itemLabel.isEmpty ? 'Item #${line.itemId}' : itemLabel,
      variationLabel: variationLabel.isEmpty ? 'Base item' : variationLabel,
      isBaseItem:
          (reference?.variationLeafNodeId ?? line.variationLeafNodeId) == 0,
      quantity: int.tryParse(line.quantityController.text.trim()) ?? 0,
      onReopen: () => _reopenLine(line),
      onRemove: _lines.length == 1
          ? null
          : () => _removeLine(_lines.indexOf(line)),
    );
  }

  /// Shelf-only reordering; [_lines] keeps its composition order so saved line
  /// positions are unaffected.
  void _handleShelfReorder(int oldIndex, int newIndex) {
    setState(() {
      final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
      _shelfOrder.insert(target, _shelfOrder.removeAt(oldIndex));
    });
  }

  /// Pulls a shelved row back into the editing column, scrolls it into view and
  /// leaves its quantity ready to overwrite.
  void _reopenLine(_EditableInventorySetLine line) {
    setState(() {
      _shelfOrder.remove(line);
      _departingLines.remove(line);
      _awaitingScrollSettle.remove(line);
      _pinnedLines.add(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final rowContext = line.rowKey.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          duration: _kShelfMotionDuration,
          curve: Curves.easeOutCubic,
          alignment: 0.5,
        );
      }
      line.quantityFocusNode.requestFocus();
      line.quantityController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: line.quantityController.text.length,
      );
    });
  }

  void _addLine() {
    setState(() {
      // Starting a new row means the reopened ones are done; let them shelve.
      _pinnedLines.clear();
      final line = _EditableInventorySetLine();
      line.quantityController.addListener(_handleQuantityChanged);
      _lines.add(line);
    });
    _beginDeparture(_positionalDepartures());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_compositionScrollController.hasClients) {
        return;
      }
      _compositionScrollController.animateTo(
        _compositionScrollController.position.maxScrollExtent,
        duration: _kShelfMotionDuration,
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _removeLine(int index) {
    final line = _lines.removeAt(index);
    _pinnedLines.remove(line);
    _shelfOrder.remove(line);
    _departingLines.remove(line);
    _awaitingScrollSettle.remove(line);
    line.quantityController.removeListener(_handleQuantityChanged);
    line.dispose();
    setState(() {});
  }

  Future<void> _handleReferenceSelection(
    int index,
    String? selectionKey,
    Map<String, _SelectableSetReference> selectableReferenceByKey,
  ) async {
    if (selectionKey == null) {
      setState(() {
        final line = _lines[index];
        line.itemId = null;
        line.variationLeafNodeId = null;
        line.itemLabel = '';
        line.variationPathLabel = '';
        line.variationPathNodeIds = const <int>[];
        line.selectionKey = null;
      });
      return;
    }
    final reference = selectableReferenceByKey[selectionKey];
    if (reference == null) {
      return;
    }
    setState(() {
      final line = _lines[index];
      line.selectionKey = reference.key;
      line.itemId = reference.itemId;
      line.variationLeafNodeId = reference.variationLeafNodeId;
      line.itemLabel = reference.itemLabel;
      line.variationPathLabel = reference.variationPathLabel;
      line.variationPathNodeIds = reference.variationPathNodeIds;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final line = _lines[index];
      line.quantityFocusNode.requestFocus();
      line.quantityController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: line.quantityController.text.length,
      );
    });
  }

  /// Collapses the composition rows into one preview entry per distinct
  /// reference, mirroring the duplicate merge that [_save] performs.
  List<_SetSelectionEntry> _buildPreviewEntries({
    required List<ItemDefinition> items,
    required Map<String, _SelectableSetReference> selectableReferenceByKey,
  }) {
    final itemById = {for (final item in items) item.id: item};
    final entries = <String, _SetSelectionEntry>{};
    for (final line in _lines) {
      final selectionKey = line.selectionKey;
      final itemId = line.itemId;
      if (selectionKey == null || itemId == null) {
        continue;
      }
      final reference = selectableReferenceByKey[selectionKey];
      final itemLabel = reference?.itemLabel ?? line.itemLabel.trim();
      final variationLabel =
          reference?.variationPathLabel ?? line.variationPathLabel.trim();
      final quantity = int.tryParse(line.quantityController.text.trim()) ?? 0;
      final existing = entries[selectionKey];
      entries[selectionKey] = _SetSelectionEntry(
        itemId: itemId,
        itemLabel: itemLabel.isEmpty ? 'Item #$itemId' : itemLabel,
        variationLabel: variationLabel.isEmpty ? 'Base item' : variationLabel,
        isBaseItem: (reference?.variationLeafNodeId ?? line.variationLeafNodeId) == 0,
        quantity: (existing?.quantity ?? 0) + (quantity > 0 ? quantity : 0),
        photoUrl: itemById[itemId]?.photoUrl ?? '',
      );
    }
    return entries.values.toList(growable: false);
  }

  List<_SelectableSetReference> _buildSelectableReferences(
    List<ItemDefinition> items,
  ) {
    final references = <_SelectableSetReference>[];
    for (final item in items) {
      final itemLabel = item.displayName.trim().isEmpty
          ? item.name
          : item.displayName;
      final propertyNames = item.topLevelProperties
          .map(
            (property) => property.displayName.trim().isEmpty
                ? property.name
                : property.displayName,
          )
          .where((name) => name.trim().isNotEmpty)
          .join(' ');
      final baseSearchPrefix =
          '$itemLabel ${item.name} ${item.alias} ${item.displayName} $propertyNames';
      if (item.leafVariationNodes.isEmpty) {
        references.add(
          _SelectableSetReference(
            itemId: item.id,
            variationLeafNodeId: 0,
            itemLabel: itemLabel,
            variationPathLabel: 'Base item',
            variationPathNodeIds: const <int>[],
            optionLabel: '$itemLabel • Base item',
            searchText: '$baseSearchPrefix base item no variation',
          ),
        );
        continue;
      }

      final leafPaths = _leafPathNodeIdsByLeafId(item);
      for (final leaf in item.leafVariationNodes) {
        final pathNodeIds = leafPaths[leaf.id] ?? const <int>[];
        // A node's own displayName is blank for most variation values, so build
        // the label from the value path the way every other picker in the app
        // does. Falling back to the node name keeps something readable if the
        // helper comes back empty.
        final builtLabel = NamingFormatHelper.buildVariationSelectionLabel(
          item,
          pathNodeIds,
          const <int, String>{},
          false,
        ).trim();
        final variationPathLabel = builtLabel.isNotEmpty
            ? builtLabel
            : (leaf.displayName.trim().isEmpty
                  ? leaf.name.trim()
                  : leaf.displayName.trim());
        references.add(
          _SelectableSetReference(
            itemId: item.id,
            variationLeafNodeId: leaf.id,
            itemLabel: itemLabel,
            variationPathLabel: variationPathLabel,
            variationPathNodeIds: pathNodeIds,
            // Never leave a dangling bullet, and never repeat the item name
            // when the built label already leads with it.
            optionLabel: variationPathLabel.isEmpty
                ? itemLabel
                : (variationPathLabel.startsWith(itemLabel)
                      ? variationPathLabel
                      : '$itemLabel • $variationPathLabel'),
            searchText: '$baseSearchPrefix $variationPathLabel',
          ),
        );
      }
    }
    references.sort(
      (a, b) =>
          a.optionLabel.toLowerCase().compareTo(b.optionLabel.toLowerCase()),
    );
    return references;
  }

  Map<int, List<int>> _leafPathNodeIdsByLeafId(ItemDefinition item) {
    final byLeafId = <int, List<int>>{};

    void visit(ItemVariationNodeDefinition node, List<int> activeValuePath) {
      if (node.kind == ItemVariationNodeKind.value) {
        final nextPath = [...activeValuePath, node.id];
        if (node.activeChildren.isEmpty) {
          byLeafId[node.id] = nextPath;
          return;
        }
        for (final child in node.activeChildren) {
          visit(child, nextPath);
        }
        return;
      }
      for (final child in node.activeChildren) {
        visit(child, activeValuePath);
      }
    }

    for (final root in item.topLevelProperties) {
      visit(root, const <int>[]);
    }
    return byLeafId;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }

    final parsedLines = <SaveInventorySetLineInput>[];
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      final quantity = int.tryParse(line.quantityController.text.trim());
      if (line.itemId == null ||
          line.variationLeafNodeId == null ||
          quantity == null ||
          quantity <= 0) {
        showAppSnack(
          SnackBar(
            content: Text(
              'Complete row ${index + 1} with an item reference and quantity.',
            ),
          ),
        );
        return;
      }
      parsedLines.add(
        SaveInventorySetLineInput(
          itemId: line.itemId!,
          variationLeafNodeId: line.variationLeafNodeId!,
          quantity: quantity,
          position: index,
          itemName: line.itemLabel,
          itemDisplayName: line.itemLabel,
          variationPathLabel: line.variationPathLabel,
          variationPathNodeIds: line.variationPathNodeIds,
        ),
      );
    }
    if (parsedLines.isEmpty) {
      showAppSnack(
        const SnackBar(content: Text('Add at least one composition row.')),
      );
      return;
    }

    final merged = <String, SaveInventorySetLineInput>{};
    for (final line in parsedLines) {
      final key = '${line.itemId}::${line.variationLeafNodeId}';
      final current = merged[key];
      if (current == null) {
        merged[key] = line;
      } else {
        merged[key] = SaveInventorySetLineInput(
          itemId: line.itemId,
          variationLeafNodeId: line.variationLeafNodeId,
          quantity: current.quantity + line.quantity,
          position: current.position,
          itemName: current.itemName,
          itemDisplayName: current.itemDisplayName,
          variationPathLabel: current.variationPathLabel,
          variationPathNodeIds: current.variationPathNodeIds,
        );
      }
    }

    await context.read<InventoryProvider>().saveSet(
      SaveInventorySetInput(
        id: widget.setDefinition?.id,
        name: name,
        photoUrl: _photoUrl,
        lines: merged.values.toList(growable: false)
          ..sort((a, b) => a.position.compareTo(b.position)),
      ),
    );

    if (!mounted) {
      return;
    }
    final provider = context.read<InventoryProvider>();
    if (provider.errorMessage != null) {
      showAppToast(context, provider.errorMessage!, kind: AppToastKind.error);
      return;
    }
    showAppToast(
      context,
      widget.setDefinition == null ? 'Set created' : 'Set saved',
      kind: AppToastKind.success,
    );
    Navigator.of(context).pop();
  }

  InputDecoration _editorFieldDecoration({
    required String label,
    required String helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6049E3)),
      ),
      helperStyle: _inventoryInterStyle(
        color: const Color(0xFF6B7280),
        size: 12,
        weight: FontWeight.w400,
      ),
    );
  }
}

class _EditableInventorySetLine {
  _EditableInventorySetLine({
    this.itemId,
    this.variationLeafNodeId,
    this.selectionKey,
    this.itemLabel = '',
    this.variationPathLabel = '',
    this.variationPathNodeIds = const <int>[],
    String quantity = '1',
  }) : quantityController = TextEditingController(text: quantity),
       quantityFocusNode = FocusNode(debugLabel: 'set_line_quantity');

  int? itemId;
  int? variationLeafNodeId;
  String? selectionKey;
  String itemLabel;
  String variationPathLabel;
  List<int> variationPathNodeIds;
  final TextEditingController quantityController;
  final FocusNode quantityFocusNode;

  /// Measures the row inside the composition viewport so scrolling it out of
  /// sight can hand it to the shelf without the remaining rows jumping.
  final GlobalKey rowKey = GlobalKey();

  void dispose() {
    quantityController.dispose();
    quantityFocusNode.dispose();
  }
}

class _SelectableSetReference {
  const _SelectableSetReference({
    required this.itemId,
    required this.variationLeafNodeId,
    required this.itemLabel,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    required this.optionLabel,
    required this.searchText,
  });

  final int itemId;
  final int variationLeafNodeId;
  final String itemLabel;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final String optionLabel;
  final String searchText;

  String get key => '$itemId::$variationLeafNodeId';
}

/// First leg of the handoff: holds the composition row in place, then drifts it
/// left toward the shelf and calls [onDeparted] once it is out of sight.
class _DepartingLineRow extends StatefulWidget {
  const _DepartingLineRow({
    super.key,
    required this.rowKey,
    required this.isDeparting,
    required this.duration,
    required this.onDeparted,
    required this.child,
  });

  final Key rowKey;
  final bool isDeparting;
  final Duration duration;
  final VoidCallback onDeparted;
  final Widget child;

  @override
  State<_DepartingLineRow> createState() => _DepartingLineRowState();
}

class _DepartingLineRowState extends State<_DepartingLineRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _exit = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_handleStatus);
    if (widget.isDeparting) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _DepartingLineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDeparting && !oldWidget.isDeparting) {
      _controller.forward();
    } else if (!widget.isDeparting && oldWidget.isDeparting) {
      _controller.reverse();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && widget.isDeparting) {
      widget.onDeparted();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: widget.rowKey,
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0).animate(_exit),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.55, 0),
          ).animate(_exit),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Compact ledger row for a composition line that has moved onto the shelf.
/// Slides in from the composition column the first time it is built.
class _ShelvedLineTile extends StatefulWidget {
  // Identity lives on the keyed wrapper the reorderable list requires, so a
  // fresh tile (and its fly-in) is built only for a genuinely new arrival.
  const _ShelvedLineTile({
    required this.dragIndex,
    required this.itemLabel,
    required this.variationLabel,
    required this.isBaseItem,
    required this.quantity,
    required this.onReopen,
    this.onRemove,
  });

  final int dragIndex;
  final String itemLabel;
  final String variationLabel;
  final bool isBaseItem;
  final int quantity;
  final VoidCallback onReopen;
  final VoidCallback? onRemove;

  @override
  State<_ShelvedLineTile> createState() => _ShelvedLineTileState();
}

class _ShelvedLineTileState extends State<_ShelvedLineTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kArrivalDuration,
  );
  late final Animation<double> _entrance = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entrance,
      child: SlideTransition(
        position: Tween<Offset>(
          // Starts clear of the shelf column so the tile visibly travels in
          // from the composition side rather than fading in place.
          begin: const Offset(1.15, 0),
          end: Offset.zero,
        ).animate(_entrance),
        child: Material(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onReopen,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The name gets the full tile width and wraps — this column
                  // exists to read item names in full, so nothing is clipped.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReorderableDragStartListener(
                        index: widget.dragIndex,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Tooltip(
                            message: 'Drag to rearrange',
                            child: Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: const Color(0xFFD8E0EA),
                                ),
                              ),
                              child: const Icon(
                                Icons.drag_handle_rounded,
                                size: 15,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            widget.itemLabel,
                            softWrap: true,
                            style: _inventoryInterStyle(
                              color: const Color(0xFF0F172A),
                              size: 13,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove row',
                        onPressed: widget.onRemove,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        iconSize: 15,
                        constraints: const BoxConstraints.tightFor(
                          width: 26,
                          height: 26,
                        ),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 32, right: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            widget.isBaseItem
                                ? Icons.layers_clear_outlined
                                : Icons.account_tree_outlined,
                            size: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.variationLabel,
                            softWrap: true,
                            style: _inventoryInterStyle(
                              color: const Color(0xFF64748B),
                              size: 11,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFD8E0EA)),
                          ),
                          child: Text(
                            '×${widget.quantity}',
                            style: _inventoryInterStyle(
                              color: const Color(0xFF334155),
                              size: 12,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The set's picture: a preview that doubles as the pick target, so the whole
/// tile is clickable rather than hiding the action behind a small button.
class _SetPhotoField extends StatelessWidget {
  const _SetPhotoField({
    required this.photoUrl,
    required this.isUploading,
    required this.onPick,
    required this.onClear,
  });

  final String photoUrl;
  final bool isUploading;
  final Future<void> Function() onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set Photo',
          style: _inventoryInterStyle(
            color: const Color(0xFF334155),
            size: 13,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Material(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: isUploading ? null : () => onPick(),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD8E0EA)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: isUploading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : hasPhoto
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 20,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 22,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPhoto
                        ? 'Shown on the set card in Inventory and Items.'
                        : 'Add a photo so this set is recognisable at a glance '
                              'in card view.',
                    style: _inventoryInterStyle(
                      color: const Color(0xFF64748B),
                      size: 11.5,
                      weight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      AppButton(
                        label: hasPhoto ? 'Replace' : 'Upload',
                        icon: Icons.upload_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: isUploading ? null : () => onPick(),
                      ),
                      if (hasPhoto && !isUploading)
                        AppButton(
                          label: 'Remove',
                          variant: AppButtonVariant.secondary,
                          onPressed: onClear,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SetSelectionEntry {
  const _SetSelectionEntry({
    required this.itemId,
    required this.itemLabel,
    required this.variationLabel,
    required this.isBaseItem,
    required this.quantity,
    required this.photoUrl,
  });

  final int itemId;
  final String itemLabel;
  final String variationLabel;
  final bool isBaseItem;
  final int quantity;
  final String photoUrl;
}

/// Left-column visual confirmation of what the composition currently holds:
/// a thumbnail collage that expands into an itemised list when tapped.
class _SetSelectionPreviewCard extends StatefulWidget {
  const _SetSelectionPreviewCard({required this.entries});

  final List<_SetSelectionEntry> entries;

  @override
  State<_SetSelectionPreviewCard> createState() =>
      _SetSelectionPreviewCardState();
}

class _SetSelectionPreviewCardState extends State<_SetSelectionPreviewCard> {
  static const int _maxCollageTiles = 6;

  final Set<int> _requestedAssetItemIds = <int>{};
  bool _isListExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAssetsLoaded());
  }

  @override
  void didUpdateWidget(covariant _SetSelectionPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAssetsLoaded());
  }

  /// Item media lives in [ItemsProvider] keyed by item id and is only fetched
  /// on demand, so pull it once per distinct item that lands in the preview.
  void _ensureAssetsLoaded() {
    if (!mounted) {
      return;
    }
    final provider = context.read<ItemsProvider>();
    for (final entry in widget.entries) {
      if (!_requestedAssetItemIds.add(entry.itemId)) {
        continue;
      }
      if (provider.assetsForItem(entry.itemId).isEmpty) {
        provider.loadItemAssets(entry.itemId);
      }
    }
  }

  String _imageUrlFor(ItemsProvider provider, _SetSelectionEntry entry) {
    var resolved = entry.photoUrl.trim();
    for (final asset in provider.assetsForItem(entry.itemId)) {
      final readUrl = asset.readUrl?.toString() ?? '';
      if (readUrl.isEmpty) {
        continue;
      }
      resolved = readUrl;
      if (asset.isPrimary) {
        break;
      }
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final entries = widget.entries;
    final totalUnits = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.quantity,
    );

    return _CreateGroupSurfaceCard(
      title: 'Selection Preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entries.isEmpty
                ? 'Pick items in the composition to preview them here.'
                : 'Tap the collage to list everything that is selected.',
            style: _inventoryInterStyle(
              color: const Color(0xFF64748B),
              size: 12,
              weight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            _buildEmptyState()
          else ...[
            _buildCollage(itemsProvider, entries),
            const SizedBox(height: 14),
            _buildSummaryToggle(entries.length, totalUnits),
            if (_isListExpanded) ...[
              const SizedBox(height: 14),
              for (var index = 0; index < entries.length; index++) ...[
                _buildListRow(itemsProvider, entries[index]),
                if (index != entries.length - 1) const SizedBox(height: 10),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 26,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(height: 10),
          Text(
            'No selections yet',
            textAlign: TextAlign.center,
            style: _inventoryInterStyle(
              color: const Color(0xFF94A3B8),
              size: 12,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollage(
    ItemsProvider itemsProvider,
    List<_SetSelectionEntry> entries,
  ) {
    final overflowCount = entries.length > _maxCollageTiles
        ? entries.length - (_maxCollageTiles - 1)
        : 0;
    final visibleEntries = overflowCount > 0
        ? entries.take(_maxCollageTiles - 1).toList(growable: false)
        : entries;

    return Semantics(
      button: true,
      label: _isListExpanded
          ? 'Hide the list of selected items'
          : 'Show the list of selected items',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _isListExpanded = !_isListExpanded),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 8.0;
              const columns = 3;
              final tileSize =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final entry in visibleEntries)
                    SizedBox(
                      width: tileSize,
                      height: tileSize,
                      child: _SetSelectionTile(
                        imageUrl: _imageUrlFor(itemsProvider, entry),
                        label: entry.itemLabel,
                        quantity: entry.quantity,
                      ),
                    ),
                  if (overflowCount > 0)
                    SizedBox(
                      width: tileSize,
                      height: tileSize,
                      child: _SetSelectionOverflowTile(count: overflowCount),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryToggle(int selectionCount, int totalUnits) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _isListExpanded = !_isListExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$selectionCount selection${selectionCount == 1 ? '' : 's'}'
                ' • $totalUnits unit${totalUnits == 1 ? '' : 's'}',
                style: _inventoryInterStyle(
                  color: const Color(0xFF475569),
                  size: 12,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              _isListExpanded ? 'Hide list' : 'Show list',
              style: _inventoryInterStyle(
                color: const Color(0xFF6049E3),
                size: 12,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              _isListExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: const Color(0xFF6049E3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListRow(
    ItemsProvider itemsProvider,
    _SetSelectionEntry entry,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: _SetSelectionTile(
              imageUrl: _imageUrlFor(itemsProvider, entry),
              label: entry.itemLabel,
              quantity: 0,
              borderRadius: 10,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.itemLabel,
                  softWrap: true,
                  style: _inventoryInterStyle(
                    color: const Color(0xFF0F172A),
                    size: 13,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        entry.isBaseItem
                            ? Icons.layers_clear_outlined
                            : Icons.account_tree_outlined,
                        size: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.variationLabel,
                        softWrap: true,
                        style: _inventoryInterStyle(
                          color: const Color(0xFF64748B),
                          size: 11,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFD8E0EA)),
            ),
            child: Text(
              '×${entry.quantity}',
              style: _inventoryInterStyle(
                color: const Color(0xFF334155),
                size: 12,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetSelectionTile extends StatelessWidget {
  const _SetSelectionTile({
    required this.imageUrl,
    required this.label,
    required this.quantity,
    this.borderRadius = 12,
  });

  final String imageUrl;
  final String label;
  final int quantity;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _SetSelectionTilePlaceholder(label: label);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isEmpty)
            placeholder
          else
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
          if (quantity > 1)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE60F172A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '×$quantity',
                  style: _inventoryInterStyle(
                    color: Colors.white,
                    size: 10,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SetSelectionTilePlaceholder extends StatelessWidget {
  const _SetSelectionTilePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDFBF6), Color(0xFFF1F5F9)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _selectionToken(label),
              style: _inventoryInterStyle(
                color: const Color(0xFF6049E3),
                size: 18,
                weight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetSelectionOverflowTile extends StatelessWidget {
  const _SetSelectionOverflowTile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8DCF7)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            '+$count',
            style: _inventoryInterStyle(
              color: const Color(0xFF6049E3),
              size: 18,
              weight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

String _selectionToken(String label) {
  final parts = label
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .take(2)
      .map((part) => part.substring(0, 1).toUpperCase())
      .toList(growable: false);
  return parts.isEmpty ? 'IT' : parts.join();
}

class _ReadOnlyReferenceChip extends StatelessWidget {
  const _ReadOnlyReferenceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: _inventoryInterStyle(
              color: const Color(0xFF475569),
              size: 12,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateGroupSurfaceCard extends StatelessWidget {
  const _CreateGroupSurfaceCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _inventoryInterStyle(
              color: const Color(0xFF1E293B),
              size: 16,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

TextStyle _inventoryInterStyle({
  required Color color,
  required double size,
  required FontWeight weight,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    color: color,
    fontSize: size,
    fontWeight: weight,
    height: 1.3,
  );
}
