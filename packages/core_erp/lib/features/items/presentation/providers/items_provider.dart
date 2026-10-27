import 'dart:async';
import '../../domain/part_code.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/api_item_repository.dart' show ItemApiException;
import '../../data/models/item_api_models.dart';
import '../../data/repositories/item_repository.dart';
import '../../domain/item_asset.dart';
import '../../domain/developed_for.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../../domain/item_master_data.dart';
import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../../production_pipelines/domain/pipeline_stage_node.dart';
import '../../domain/item_usage_record.dart';
import '../../../../core/services/socket_service.dart';

enum ItemDuplicateWarning {
  none,
  sameGroup,
  emptyNodeName,
  invalidTreeStructure,
  duplicateSiblingName,
  duplicatePropertyName,
}

class ItemDuplicateCheck {
  const ItemDuplicateCheck({
    required this.blockingDuplicate,
    required this.warning,
  });

  final bool blockingDuplicate;
  final ItemDuplicateWarning warning;
}

class QuickCreateVariationValueResult {
  const QuickCreateVariationValueResult({
    required this.item,
    required this.createdValueNode,
    required this.selectedValueNodeIds,
  });

  final ItemDefinition item;
  final ItemVariationNodeDefinition createdValueNode;
  final List<int> selectedValueNodeIds;
}

class QuickCreateVariationPropertyResult {
  const QuickCreateVariationPropertyResult({
    required this.item,
    required this.createdPropertyNode,
  });

  final ItemDefinition item;
  final ItemVariationNodeDefinition createdPropertyNode;
}

/// Distinguishes "leave this alone" from "set this to null" on a nullable
/// field, which a plain null cannot do.
const Object _keepField = Object();

class ItemsProvider extends ChangeNotifier {
  ItemsProvider({required ItemRepository repository})
    : _repository = repository;

  final ItemRepository _repository;

  List<ItemDefinition> _items = const [];

  /// Rows this session has written that a read may not have caught up with.
  ///
  /// Item reads come off the local replica, which the changelog brings up to
  /// date a moment AFTER the write returns. So the refresh a save fires reads
  /// the row as it was before the save, and stamps that over the response the
  /// server just handed back. That is what made an edit take two goes to show:
  /// the first click was undone by its own refresh, and the second click's
  /// refresh finally read the first click's row.
  ///
  /// Each entry is dropped as soon as a read comes back at least as new, so
  /// nothing is held past the point the replica can answer for it.
  final Map<int, ItemDefinition> _writtenHere = <int, ItemDefinition>{};

  /// Items this session deleted that a read may not have caught up with.
  final Set<int> _deletedHere = <int>{};

  final Map<int, List<ItemAsset>> _assetsByItemId = <int, List<ItemAsset>>{};
  bool _isLoading = false;
  bool _isSaving = false;

  /// Completed when a save ends, for the writes that wait their turn.
  Completer<void>? _saveIdle;

  void _endSave() {
    _isSaving = false;
    final idle = _saveIdle;
    _saveIdle = null;
    idle?.complete();
  }
  bool _isAssetUploading = false;
  String? _errorMessage;
  String? _errorCode;
  String _searchQuery = '';

  bool _initialized = false;

  ItemDefinition? findById(int? id) {
    if (id == null) return null;
    return _items.where((item) => item.id == id).firstOrNull;
  }

  List<ItemDefinition> get items => _items;
  List<ItemAsset> assetsForItem(int itemId) =>
      _assetsByItemId[itemId] ?? const <ItemAsset>[];
  bool get isLoading => _isLoading;

  /// Whether this provider has been asked to load at all.
  ///
  /// `isInitialized && !isLoading` is the only honest way to read "there are
  /// no items": before that, an empty list means nobody has looked yet, which
  /// is a different fact. Exposed because the creation window decides whether
  /// to run its guided first run on exactly that question, and was reading the
  /// empty list as an answer.
  bool get isInitialized => _initialized;
  bool get isSaving => _isSaving;
  bool get isAssetUploading => _isAssetUploading;
  String? get errorMessage => _errorMessage;

  /// The server's machine-readable reason for the last failed save, where it
  /// sent one (e.g. 'part_code_duplicate'). Null for everything else.
  String? get errorCode => _errorCode;
  String get searchQuery => _searchQuery;

  List<ItemDefinition> get filteredItems {
    final query = _normalize(_searchQuery);
    return _items
        .where((item) {
          if (query.isEmpty) {
            return true;
          }
          final treeText = _treeSearchText(item.variationTree);
          return _normalize(item.name).contains(query) ||
              _normalize(item.alias).contains(query) ||
              _normalize(item.displayName).contains(query) ||
              _normalize(treeText).contains(query);
        })
        .toList(growable: false);
  }

  /// Takes the server's answer to a write as the row of record.
  ///
  /// Applied straight away so the screen moves with the click, and held in
  /// [_writtenHere] so the read that follows cannot put the old row back.
  void _recordWrite(ItemDefinition item) {
    _writtenHere[item.id] = item;
    final index = _items.indexWhere((existing) => existing.id == item.id);
    final next = List<ItemDefinition>.of(_items);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.add(item);
    }
    _items = next;
    _sortItems();
  }

  /// Lays what this session wrote over a list read, and forgets the ones the
  /// read has caught up with.
  ///
  /// A row missing from [incoming] is kept too: a just-created item reaches
  /// the replica no faster than an edit does, and dropping it would make the
  /// new item vanish until the next read.
  List<ItemDefinition> _withLocalWrites(List<ItemDefinition> incoming) {
    if (_deletedHere.isNotEmpty) {
      // A delete reaches the replica no faster than an edit does, so a read
      // straight after one still lists the row. Hidden until a read agrees.
      final listed = {for (final item in incoming) item.id};
      _deletedHere.removeWhere((id) => !listed.contains(id));
      if (_deletedHere.isNotEmpty) {
        incoming = [
          for (final item in incoming)
            if (!_deletedHere.contains(item.id)) item,
        ];
      }
    }
    if (_writtenHere.isEmpty) return incoming;
    final merged = <ItemDefinition>[];
    final seen = <int>{};
    for (final item in incoming) {
      seen.add(item.id);
      final written = _writtenHere[item.id];
      if (written == null) {
        merged.add(item);
        continue;
      }
      if (!item.updatedAt.isBefore(written.updatedAt)) {
        _writtenHere.remove(item.id);
        merged.add(item);
      } else {
        merged.add(written);
      }
    }
    for (final entry in _writtenHere.entries) {
      if (!seen.contains(entry.key)) merged.add(entry.value);
    }
    return merged;
  }

  void _sortItems() {
    _items.sort((a, b) {
      final groupCompare = a.groupId.compareTo(b.groupId);
      if (groupCompare != 0) {
        return groupCompare;
      }
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) {
        return nameCompare;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }

  /// The row an item_added / item_updated event carries.
  ///
  /// The server builds that payload with the same helper the list endpoint
  /// uses, so it is complete — machines, dies, variation tree and all. Reading
  /// the row back instead, as this used to, went to the local replica, which
  /// the changelog has not reached yet at the moment the event fires: the
  /// event announcing a change was answering with the state before it.
  ///
  /// Only the Socket.IO channel (the mobile app) carries that row. The desktop
  /// listens on SSE, where every change arrives as `{'id': N}` — and parsing
  /// that as a row "succeeded" with a blank name, no group, no dies and an
  /// updatedAt of now, so it replaced the real part in every open window. An
  /// id alone is now read as "this part changed; fetch it" ([_refetchAnnounced]).
  ItemDefinition? _itemFromEvent(dynamic data) {
    if (data is! Map || data['id'] == null) return null;
    if (!data.containsKey('name')) return null;
    try {
      return ItemDto.fromJson(Map<String, dynamic>.from(data)).toDomain();
    } catch (_) {
      return null;
    }
  }

  /// Takes an announced row, unless the one already held is newer.
  void _acceptAnnounced(ItemDefinition item) {
    final held = _items.where((existing) => existing.id == item.id).firstOrNull;
    if (held != null && held.updatedAt.isAfter(item.updatedAt)) return;
    _writtenHere.remove(item.id);
    final index = _items.indexWhere((existing) => existing.id == item.id);
    final next = List<ItemDefinition>.of(_items);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.add(item);
    }
    _items = next;
    _sortItems();
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    SocketService.instance.on('item_added', _onItemAnnounced);
    SocketService.instance.on('item_updated', _onItemAnnounced);
    SocketService.instance.on('item_deleted', _onItemDeleted);
    // Events missed while the stream was down are replayed after this fires,
    // and each replayed id goes through the fresh fetch; the refresh covers
    // anything older than the replay window.
    SocketService.instance.on('realtime:reconnected', _onReconnected);

    await refresh();
  }

  void _onItemAnnounced(dynamic data) {
    final announced = _itemFromEvent(data);
    if (announced != null) {
      // Dedupe: the creator already has this row, so a rail echo must
      // replace-if-present rather than blindly append.
      _acceptAnnounced(announced);
      return;
    }
    final id = _eventId(data);
    if (id != null) {
      _refetchAnnounced(id);
    } else {
      refresh();
    }
  }

  void _onItemDeleted(dynamic data) {
    final id = _eventId(data);
    if (id == null) {
      refresh();
      return;
    }
    _forgetItem(id);
  }

  void _onReconnected(dynamic _) => refresh();

  static int? _eventId(dynamic data) {
    if (data is! Map) return null;
    final raw = data['id'];
    return raw is int ? raw : int.tryParse('$raw');
  }

  void _forgetItem(int id) {
    _writtenHere.remove(id);
    if (!_items.any((i) => i.id == id)) return;
    _items = _items.where((i) => i.id != id).toList();
    notifyListeners();
  }

  /// Ids announced and waiting to be fetched, collected for a moment so the
  /// burst one save makes (the row, its variation nodes, its die links, each
  /// a changelog row) costs one request, not five.
  final Set<int> _pendingFetches = <int>{};
  Timer? _fetchTimer;
  bool _disposed = false;

  void _refetchAnnounced(int id) {
    if (_deletedHere.contains(id)) return;
    _pendingFetches.add(id);
    _fetchTimer ??= Timer(const Duration(milliseconds: 100), _flushFetches);
  }

  Future<void> _flushFetches() async {
    _fetchTimer = null;
    final ids = _pendingFetches.toList();
    _pendingFetches.clear();
    for (final id in ids) {
      if (_disposed) return;
      ItemDefinition? fresh;
      try {
        // From the server, not the replica: the replica applies this same
        // event on its own, later, and reading it now answers with the state
        // before the change.
        fresh = await _repository.getItemFresh(id);
      } catch (_) {
        continue; // Unreachable for now; the next event or refresh catches up.
      }
      if (_disposed) return;
      if (fresh == null) {
        _forgetItem(id);
      } else {
        _acceptAnnounced(fresh);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _fetchTimer?.cancel();
    SocketService.instance.off('item_added', _onItemAnnounced);
    SocketService.instance.off('item_updated', _onItemAnnounced);
    SocketService.instance.off('item_deleted', _onItemDeleted);
    SocketService.instance.off('realtime:reconnected', _onReconnected);
    super.dispose();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.init();
      final items = _withLocalWrites(await _repository.getItems());
      items.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final groupCompare = a.groupId.compareTo(b.groupId);
        if (groupCompare != 0) {
          return groupCompare;
        }
        final nameCompare = a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        );
        if (nameCompare != 0) {
          return nameCompare;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      _items = items;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, String>>> fetchPipelineTemplates() async {
    try {
      return await _repository.getPipelineTemplates();
    } catch (e) {
      return [];
    }
  }

  /// Process nodes keyed by pipeline template id, in reading order. Empty on
  /// failure — stage-by-stage Master Data falls back to generic stage names
  /// rather than blocking.
  Future<Map<String, List<PipelineStageNode>>> fetchPipelineStageNodes() async {
    try {
      return await _repository.getPipelineStageNodes();
    } catch (e) {
      return const <String, List<PipelineStageNode>>{};
    }
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  /// An item another screen has asked the items list to reveal.
  ///
  /// The groups tree lists items but does not own them — clicking one hands
  /// over to the items screen, which is where an item and its variants
  /// actually live. Handing over means arriving with the item on screen rather
  /// than on a collapsed list the user has to go and find it in, so the id is
  /// left here for the list to pick up and act on once.
  int? _pendingRevealItemId;
  int? get pendingRevealItemId => _pendingRevealItemId;

  void revealItem(int itemId) {
    _pendingRevealItemId = itemId;
    notifyListeners();
  }

  /// Takes the request, leaving nothing behind: revealing is a one-off, and a
  /// request that stayed set would re-open the row every time the list rebuilt.
  int? consumeReveal() {
    final id = _pendingRevealItemId;
    _pendingRevealItemId = null;
    return id;
  }

  ItemDuplicateCheck checkDuplicate({
    required String name,
    required int? groupId,
    required int? unitId,
    required List<ItemVariationNodeInput> variationTree,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    if (groupId != null &&
        unitId != null &&
        _items.any(
          (item) =>
              item.id != excludeId &&
              item.groupId == groupId &&
              item.unitId == unitId &&
              _normalize(item.name) == normalizedName,
        )) {
      return const ItemDuplicateCheck(
        blockingDuplicate: true,
        warning: ItemDuplicateWarning.sameGroup,
      );
    }

    // Property names only need to be unique among siblings (checked in
    // _validateNode). Branches that can never be active together — e.g.
    // sheet/coil/strip each carrying their own "size" — may reuse a name.

    for (final node in variationTree) {
      final result = _validateNode(
        node,
        expectedKind: ItemVariationNodeKind.property,
        siblings: variationTree,
      );
      if (result != ItemDuplicateWarning.none) {
        return ItemDuplicateCheck(blockingDuplicate: true, warning: result);
      }
    }

    return const ItemDuplicateCheck(
      blockingDuplicate: false,
      warning: ItemDuplicateWarning.none,
    );
  }

  bool _areVariationTreesIdentical(
    List<ItemVariationNodeDefinition> existing,
    List<ItemVariationNodeInput> input,
  ) {
    if (existing.length != input.length) return false;

    final existingSorted = existing.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final inputSorted = input.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (var i = 0; i < existingSorted.length; i++) {
      final eNode = existingSorted[i];
      final iNode = inputSorted[i];

      if (_normalize(eNode.name) != _normalize(iNode.name)) return false;
      if (eNode.kind != iNode.kind) return false;

      if (!_areVariationTreesIdentical(eNode.children, iNode.children)) {
        return false;
      }
    }

    return true;
  }

  ItemDuplicateWarning _validateNode(
    ItemVariationNodeInput node, {
    required ItemVariationNodeKind expectedKind,
    required List<ItemVariationNodeInput> siblings,
  }) {
    final normalizedName = _normalize(node.name);
    if (normalizedName.isEmpty) {
      return ItemDuplicateWarning.emptyNodeName;
    }
    if (node.kind != expectedKind) {
      return ItemDuplicateWarning.invalidTreeStructure;
    }
    if (siblings
            .where((entry) => _normalize(entry.name) == normalizedName)
            .length >
        1) {
      return ItemDuplicateWarning.duplicateSiblingName;
    }
    ItemVariationNodeKind nextKind;
    if (node.kind == ItemVariationNodeKind.property) {
      final hasPropertyChildren = node.children.any(
        (c) => c.kind == ItemVariationNodeKind.property,
      );
      nextKind = hasPropertyChildren
          ? ItemVariationNodeKind.property
          : ItemVariationNodeKind.value;
    } else {
      nextKind = ItemVariationNodeKind.property;
    }
    for (final child in node.children) {
      final result = _validateNode(
        child,
        expectedKind: nextKind,
        siblings: node.children,
      );
      if (result != ItemDuplicateWarning.none) {
        return result;
      }
    }
    return ItemDuplicateWarning.none;
  }

  Future<ItemDefinition?> createItem(CreateItemInput input) async {
    return _save(() => _repository.createItem(input));
  }

  Future<ItemDefinition?> updateItem(UpdateItemInput input) async {
    return _save(() => _repository.updateItem(input));
  }

  // --- Master Data, keyed by (variant, pipeline) ---------------------------
  //
  // A pipeline makes many variants, so it holds one record per variant rather
  // than a single baseline. These are read straight through rather than cached
  // on the provider: which record applies depends on the pipeline in front of
  // the user, and a stale answer would quote the wrong variant's numbers.

  /// Which of the four resolution steps answers for this pair. With [adopt] the
  /// answer is written onto the pair, so the next lookup is an exact match.
  Future<MasterDataResolution?> resolveMasterData({
    required int itemId,
    String? pipelineId,
    bool adopt = false,
  }) async {
    try {
      return await _repository.resolveMasterData(
        itemId: itemId,
        pipelineId: pipelineId,
        adopt: adopt,
      );
    } catch (error) {
      _errorMessage = _messageFor(error);
      notifyListeners();
      return null;
    }
  }

  Future<List<ItemMasterDataRecord>> itemMasterData(int itemId) async {
    try {
      return await _repository.getItemMasterData(itemId);
    } catch (error) {
      _errorMessage = _messageFor(error);
      notifyListeners();
      return const <ItemMasterDataRecord>[];
    }
  }

  Future<ItemMasterDataRecord?> saveMasterData({
    required int itemId,
    required String pipelineId,
    required PenPaperBaseline baseline,
  }) async {
    try {
      final record = await _repository.saveMasterData(
        itemId: itemId,
        pipelineId: pipelineId,
        baseline: baseline,
      );
      _errorMessage = null;
      notifyListeners();
      return record;
    } catch (error) {
      _errorMessage = _messageFor(error);
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteMasterData({
    required int itemId,
    required String pipelineId,
  }) async {
    try {
      await _repository.deleteMasterData(
        itemId: itemId,
        pipelineId: pipelineId,
      );
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error);
      notifyListeners();
      return false;
    }
  }

  /// Every variant's Master Data on one pipeline — the insight view.
  Future<PipelineMasterDataRoster?> pipelineMasterData(
    String pipelineId,
  ) async {
    try {
      return await _repository.getPipelineMasterData(pipelineId);
    } catch (error) {
      _errorMessage = _messageFor(error);
      notifyListeners();
      return null;
    }
  }

  String _messageFor(Object error) =>
      error is ItemApiException ? error.message : error.toString();

  /// Which sets hold this part, one row per line.
  ///
  /// Not routed through [_save] — it writes nothing, and a lookup that failed
  /// must not blank the error of a save that failed.
  Future<List<ItemSetMembership>?> itemSets(int itemId) async {
    try {
      return await _repository.itemSets(itemId);
    } catch (_) {
      // Null is "could not ask", which a caller must tell apart from "in no
      // sets" — the part code's re-derivation depends on knowing which.
      return null;
    }
  }

  /// What the next part in this scope should be called.
  ///
  /// Deliberately not routed through [_save]: it writes nothing, and a
  /// suggestion that failed must not blank the error of a save that failed.
  Future<PartIdentitySuggestion?> nextPartIdentity({
    required int groupId,
    int? setId,
    bool setPending = false,
    String setName = '',
    String name = '',
  }) async {
    try {
      return await _repository.nextPartIdentity(
        groupId: groupId,
        setId: setId,
        setPending: setPending,
        setName: setName,
        name: name,
      );
    } catch (_) {
      // A form that cannot pre-fill is still a usable form.
      return null;
    }
  }

  Future<ItemDefinition?> updateShortCode(int id, String shortCode) async {
    return _save(() => _repository.updateShortCode(id, shortCode));
  }

  Future<ItemDefinition?> addUnitConversion({
    required int itemId,
    required int unitId,
    required double unitsPerPrimary,
  }) async {
    final current = _items.where((item) => item.id == itemId).firstOrNull;
    if (current == null) {
      _errorMessage = 'Item not found. Please select the item again.';
      notifyListeners();
      return null;
    }
    if (unitId == current.unitId ||
        current.unitConversions.any(
          (conversion) => conversion.unitId == unitId,
        )) {
      _errorMessage = 'This unit is already available for this item.';
      notifyListeners();
      return null;
    }
    if (unitsPerPrimary <= 0) {
      _errorMessage = 'Enter a conversion value greater than zero.';
      notifyListeners();
      return null;
    }

    return updateItem(
      _preservingInput(
        current,
        unitConversions: <ItemUnitConversionInput>[
          ...current.unitConversions.map(
            (conversion) => ItemUnitConversionInput(
              unitId: conversion.unitId,
              factorToPrimary: conversion.factorToPrimary,
            ),
          ),
          ItemUnitConversionInput(
            unitId: unitId,
            factorToPrimary: 1 / unitsPerPrimary,
          ),
        ],
        variationTree: current.variationTree
            .map(_toInput)
            .toList(growable: false),
      ),
    );
  }

  Future<QuickCreateVariationValueResult?> appendVariationValue({
    required int itemId,
    required int propertyNodeId,
    required String valueName,
  }) async {
    final current = _items.where((item) => item.id == itemId).firstOrNull;
    final trimmedValueName = valueName.trim();
    if (current == null) {
      _errorMessage = 'Item not found.';
      notifyListeners();
      return null;
    }
    if (trimmedValueName.isEmpty) {
      _errorMessage = 'Variation value name is required.';
      notifyListeners();
      return null;
    }
    final propertyPathSegments = _nodePathSegmentsById(
      current.variationTree,
      propertyNodeId,
    );
    if (propertyPathSegments.isEmpty) {
      _errorMessage = 'Variation property not found.';
      notifyListeners();
      return null;
    }

    final mutation = _appendVariationValueToTree(
      current.variationTree.map(_toInput).toList(growable: false),
      propertyNodeId: propertyNodeId,
      valueName: trimmedValueName,
      valuePath: const <String>[],
    );
    if (!mutation.inserted) {
      _errorMessage = 'Variation property not found.';
      notifyListeners();
      return null;
    }

    return _saveQuickCreateVariationValue(
      () => _repository.updateItem(
        _preservingInput(current, variationTree: mutation.nodes),
      ),
      propertyNodeId: propertyNodeId,
      valueName: trimmedValueName,
      propertyPathSegments: propertyPathSegments,
    );
  }

  /// Every field of [current], with only the variation tree replaced.
  ///
  /// `UpdateItemRequest.toJson` emits every field unconditionally, so a sparse
  /// input is not a partial update — it is an update that blanks whatever it
  /// leaves out. These quick-create writes used to omit the photo, CAD file,
  /// attachments, machines and dies, and so silently stripped them from the
  /// item every time someone added a variation value.
  UpdateItemInput _preservingInput(
    ItemDefinition current, {
    required List<ItemVariationNodeInput> variationTree,
    List<ItemUnitConversionInput>? unitConversions,
    Object? defaultPipelineId = _keepField,
    List<String>? machineIds,
    List<String>? dieIds,
    DevelopedFor? developedFor,
    PenPaperBaseline? penPaperBaseline,
  }) {
    return UpdateItemInput(
      id: current.id,
      name: current.name,
      alias: current.alias,
      displayName: current.displayName,
      groupId: current.groupId,
      unitId: current.unitId,
      unitConversions: unitConversions ?? _preservedConversions(current),
      namingFormat: current.namingFormat,
      defaultPipelineId: defaultPipelineId == _keepField
          ? current.defaultPipelineId
          : defaultPipelineId as String?,
      availableForPurchase: current.availableForPurchase,
      baseItemId: current.baseItemId,
      photoUrl: current.photoUrl,
      cadFileKey: current.cadFileKey,
      cadFileName: current.cadFileName,
      attachments: current.attachments
          .map(
            (attachment) => ItemAttachmentInput(
              label: attachment.label,
              objectKey: attachment.objectKey,
              fileName: attachment.fileName,
            ),
          )
          .toList(growable: false),
      machineIds:
          machineIds ??
          current.machines.map((machine) => machine.id).toList(growable: false),
      dieIds:
          dieIds ?? current.dies.map((die) => die.id).toList(growable: false),
      developedForClientId: current.developedForClientId,
      // Carried for the same reason as partNo/partCode below: this input is
      // rebuilt wholesale by every preserving save, and a block that fell out
      // here would take who the part was made for with it.
      //
      // A plain `??` rather than the `_keepField` sentinel defaultPipelineId
      // needs: clearing this one is `DevelopedFor.empty`, a value that is
      // present, so null here can only ever mean "leave it alone".
      developedFor: developedFor ?? current.developedFor,
      penPaperBaseline: penPaperBaseline ?? current.penPaperBaseline,
      blankWidthMm: current.blankWidthMm,
      blankHeightMm: current.blankHeightMm,
      // Carried, not defaulted. The request omits these when they are null, so
      // this is belt and braces — but it is the layer that would notice if
      // that omission ever regressed, and a wiped part code is a code already
      // printed on a drawing that no longer matches the catalogue.
      partNo: current.partNo,
      partCode: current.partCode,
      variationTree: variationTree,
    );
  }

  List<ItemUnitConversionInput> _preservedConversions(ItemDefinition item) =>
      item.unitConversions
          .map(
            (c) => ItemUnitConversionInput(
              unitId: c.unitId,
              factorToPrimary: c.factorToPrimary,
            ),
          )
          .toList(growable: false);

  /// Adds a top-level property and, where the type allows one, its first
  /// value — in a single save.
  ///
  /// Doing it as two calls meant two whole-tree rewrites, with the new
  /// property's node id read back between them. Anything that shifted in
  /// between (ids reassigned on save, another edit landing) left the second
  /// call looking for a node that had moved, which surfaced as "Created
  /// variation value was not found after saving". One write, one lookup.
  ///
  /// [valueName] is ignored for Numeric and Gauge properties: those are typed
  /// per use and hold no stored value nodes.
  Future<QuickCreateVariationPropertyResult?> appendTopLevelPropertyWithValue({
    required int itemId,
    required String propertyName,
    required String inputType,
    required String valueName,
  }) async {
    final current = _items.where((item) => item.id == itemId).firstOrNull;
    final trimmedPropertyName = propertyName.trim();
    final trimmedValueName = valueName.trim();
    if (current == null) {
      _errorMessage = 'Item not found.';
      notifyListeners();
      return null;
    }
    if (trimmedPropertyName.isEmpty) {
      _errorMessage = 'Variation property name is required.';
      notifyListeners();
      return null;
    }
    if (current.topLevelProperties.any(
      (property) =>
          _normalize(property.name) == _normalize(trimmedPropertyName),
    )) {
      _errorMessage = 'A top-level property with this name already exists.';
      notifyListeners();
      return null;
    }

    final storesValues = !isDataEntryInputType(inputType);
    if (_isSaving) return null;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.updateItem(
        _preservingInput(
          current,
          variationTree: <ItemVariationNodeInput>[
            ...current.variationTree.map(_toInput),
            ItemVariationNodeInput(
              kind: ItemVariationNodeKind.property,
              name: trimmedPropertyName,
              inputType: inputType,
              children: storesValues && trimmedValueName.isNotEmpty
                  ? <ItemVariationNodeInput>[
                      ItemVariationNodeInput(
                        kind: ItemVariationNodeKind.value,
                        name: trimmedValueName,
                      ),
                    ]
                  : const <ItemVariationNodeInput>[],
            ),
          ],
        ),
      );
      _recordWrite(updated);
      await refresh();
      // Same rule as the value path: the response to this write outranks the
      // list read that follows it, which can lag behind.
      ItemDefinition? sourceItem;
      ItemVariationNodeDefinition? createdProperty;
      for (final candidate in <ItemDefinition>[
        updated,
        ..._items.where((item) => item.id == updated.id),
      ]) {
        final found = candidate.topLevelProperties
            .where(
              (property) =>
                  _normalize(property.name) == _normalize(trimmedPropertyName),
            )
            .firstOrNull;
        if (found != null) {
          sourceItem = candidate;
          createdProperty = found;
          break;
        }
      }
      if (sourceItem == null || createdProperty == null) {
        throw StateError('Created variation property was not found.');
      }
      return QuickCreateVariationPropertyResult(
        item: sourceItem,
        createdPropertyNode: createdProperty,
      );
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _endSave();
      notifyListeners();
    }
  }

  /// Numeric and Gauge properties are answered per use rather than chosen from
  /// stored values, so they carry no value nodes to append to.
  static bool isDataEntryInputType(String inputType) =>
      inputType == 'Numeric' || inputType == 'Gauge';

  Future<QuickCreateVariationPropertyResult?> appendTopLevelProperty({
    required int itemId,
    required String propertyName,
    // A quick-created property used to be Text whatever the caller meant, so a
    // property declared as a number or a material came out untyped.
    String inputType = 'Text',
  }) async {
    final current = _items.where((item) => item.id == itemId).firstOrNull;
    final trimmedPropertyName = propertyName.trim();
    if (current == null) {
      _errorMessage = 'Item not found.';
      notifyListeners();
      return null;
    }
    if (trimmedPropertyName.isEmpty) {
      _errorMessage = 'Variation property name is required.';
      notifyListeners();
      return null;
    }
    final duplicateExists = current.topLevelProperties.any(
      (property) =>
          _normalize(property.name) == _normalize(trimmedPropertyName),
    );
    if (duplicateExists) {
      _errorMessage = 'A top-level property with this name already exists.';
      notifyListeners();
      return null;
    }

    if (_isSaving) return null;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.updateItem(
        _preservingInput(
          current,
          variationTree: <ItemVariationNodeInput>[
            ...current.variationTree.map(_toInput),
            ItemVariationNodeInput(
              kind: ItemVariationNodeKind.property,
              name: trimmedPropertyName,
              inputType: inputType,
            ),
          ],
        ),
      );
      _recordWrite(updated);
      await refresh();
      // Same rule as the value path: the response to this write outranks the
      // list read that follows it, which can lag behind.
      ItemDefinition? sourceItem;
      ItemVariationNodeDefinition? createdProperty;
      for (final candidate in <ItemDefinition>[
        updated,
        ..._items.where((item) => item.id == updated.id),
      ]) {
        final found = candidate.topLevelProperties
            .where(
              (property) =>
                  _normalize(property.name) == _normalize(trimmedPropertyName),
            )
            .firstOrNull;
        if (found != null) {
          sourceItem = candidate;
          createdProperty = found;
          break;
        }
      }
      if (sourceItem == null || createdProperty == null) {
        throw StateError('Created variation property was not found.');
      }
      return QuickCreateVariationPropertyResult(
        item: sourceItem,
        createdPropertyNode: createdProperty,
      );
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _endSave();
      notifyListeners();
    }
  }

  Future<bool> deleteItem(int id) async {
    if (_isSaving) return false;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteItem(id);
      _writtenHere.remove(id);
      _deletedHere.add(id);
      _items = _items.where((i) => i.id != id).toList();
      await refresh();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    } finally {
      _endSave();
      notifyListeners();
    }
  }

  /// Archives a part and takes its archived row as the one of record. False
  /// with [errorMessage] set — the server's reason — when it is refused,
  /// which it is while orders or challans still use the part.
  Future<bool> archiveItem(int id) async {
    while (_isSaving) {
      await (_saveIdle ??= Completer<void>()).future;
    }
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.archiveItem(id);
      final fresh = await _repository.getItemFresh(id);
      if (fresh != null) _recordWrite(fresh);
      return true;
    } catch (error) {
      _errorMessage =
          error is ItemApiException ? error.message : error.toString();
      return false;
    } finally {
      _endSave();
      notifyListeners();
    }
  }

  /// Points an item at a pipeline (or clears it) without disturbing anything
  /// else it carries.
  Future<ItemDefinition?> setItemPipeline(int itemId, String? pipelineId) {
    return _updateOneField(
      itemId,
      (current) => _preservingInput(
        current,
        defaultPipelineId: pipelineId,
        variationTree: current.variationTree
            .map(_toInput)
            .toList(growable: false),
      ),
    );
  }

  /// Records who a part was developed for, leaving everything else as it is.
  ///
  /// [DevelopedFor.empty] is how it is cleared — the block is one fact and
  /// arrives whole, which is why this takes no nullable "unset".
  Future<ItemDefinition?> setItemDevelopedFor(
    int itemId,
    DevelopedFor developedFor,
  ) {
    return _updateOneField(
      itemId,
      (current) => _preservingInput(
        current,
        developedFor: developedFor,
        variationTree: current.variationTree
            .map(_toInput)
            .toList(growable: false),
      ),
    );
  }

  /// Replaces the machines and/or dies an item is linked to. Attaching one here
  /// is what assigns it to that item's work.
  Future<ItemDefinition?> setItemLinks(
    int itemId, {
    List<String>? machineIds,
    List<String>? dieIds,
  }) {
    return _updateOneField(
      itemId,
      (current) => _preservingInput(
        current,
        machineIds: machineIds,
        dieIds: dieIds,
        variationTree: current.variationTree
            .map(_toInput)
            .toList(growable: false),
      ),
    );
  }

  /// Records the raw sheet a part is cut from — its size, gauge, the strips
  /// laid on it and the cut plan — leaving everything else as it is. The item
  /// sheet's right-hand panel writes this; the old Master Data dialog wrote the
  /// same field through a full-item save.
  Future<ItemDefinition?> setItemPenPaperBaseline(
    int itemId,
    PenPaperBaseline baseline,
  ) {
    return _updateOneField(
      itemId,
      (current) => _preservingInput(
        current,
        penPaperBaseline: baseline,
        variationTree: current.variationTree
            .map(_toInput)
            .toList(growable: false),
      ),
    );
  }

  /// Saves how the part's item sheet is nested. The server re-links the
  /// part's client, dies and machines to match, so this is a data write, not
  /// a layout preference.
  Future<ItemDefinition?> saveSectionTree(int itemId, Map<String, String> tree) {
    return _save(() => _repository.saveSectionTree(itemId, tree));
  }

  Future<ItemDefinition?> _updateOneField(
    int itemId,
    UpdateItemInput Function(ItemDefinition current) build,
  ) async {
    // Waits its turn rather than answering null. These are "set this one
    // field" writes that follow another save — the sheet links dies and saves
    // its nesting right after a row commits — and refusing them made the NEXT
    // row's commit fail with "another one was still finishing". Waiting is
    // safe here because each is idempotent, and `current` is read only after
    // the wait so the full replace carries what that earlier save wrote.
    while (_isSaving) {
      await (_saveIdle ??= Completer<void>()).future;
    }
    final current = _items.where((item) => item.id == itemId).firstOrNull;
    if (current == null) {
      _errorMessage = 'Item not found.';
      notifyListeners();
      return null;
    }
    return updateItem(build(current));
  }

  Future<ItemDefinition?> reassignItemGroup(int id, int groupId) async {
    return _save(() => _repository.reassignItemGroup(id, groupId));
  }

  /// Signs a fresh download link for the item's CAD file. Returns null (and
  /// sets [errorMessage]) when the item has no CAD file or signing failed.
  Future<Uri?> createCadFileReadUrl(int itemId) async {
    try {
      return await _repository.createCadFileReadUrl(itemId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  /// Signs a fresh download link for one of the item's extra named files.
  Future<Uri?> createAttachmentReadUrl(int itemId, int attachmentId) async {
    try {
      return await _repository.createAttachmentReadUrl(itemId, attachmentId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<List<ItemAsset>> loadItemAssets(int itemId) async {
    try {
      final assets = await _repository.getItemAssets(itemId);
      _assetsByItemId[itemId] = assets;
      notifyListeners();
      return assets;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return _assetsByItemId[itemId] ?? const <ItemAsset>[];
    }
  }

  Future<ItemAssetUploadIntent?> createAssetUploadIntent(
    ItemAssetUploadIntentInput input,
  ) async {
    _isAssetUploading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _repository.createAssetUploadIntent(input);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isAssetUploading = false;
      notifyListeners();
    }
  }

  Future<ItemAsset?> completeAssetUpload(
    CompleteItemAssetUploadInput input,
  ) async {
    _isAssetUploading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final asset = await _repository.completeAssetUpload(input);
      await loadItemAssets(asset.entityId);
      return asset;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isAssetUploading = false;
      notifyListeners();
    }
  }

  Future<ItemAsset?> setPrimaryAsset(int assetId) async {
    _isAssetUploading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final asset = await _repository.setPrimaryAsset(assetId);
      await loadItemAssets(asset.entityId);
      return asset;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isAssetUploading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteAsset(ItemAsset asset) async {
    _isAssetUploading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteAsset(asset.id);
      await loadItemAssets(asset.entityId);
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    } finally {
      _isAssetUploading = false;
      notifyListeners();
    }
  }

  Future<ItemDefinition?> _save(
    Future<ItemDefinition> Function() action,
  ) async {
    if (_isSaving) return null;
    _isSaving = true;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();
    try {
      final updated = await action();
      // The response is the same fully populated shape the list endpoint
      // returns, so it stands as the row of record until a read overtakes it.
      _recordWrite(updated);
      await refresh();
      return updated;
    } catch (error) {
      _errorMessage = error.toString();
      // Kept beside the sentence so a caller can tell one refusal from
      // another — a taken part code is worth recovering from, where a name
      // clash is for the person to resolve.
      _errorCode = error is ItemApiException ? error.code : null;
      notifyListeners();
      return null;
    } finally {
      _endSave();
      notifyListeners();
    }
  }

  Future<QuickCreateVariationValueResult?> _saveQuickCreateVariationValue(
    Future<ItemDefinition> Function() action, {
    required int propertyNodeId,
    required String valueName,
    required List<String> propertyPathSegments,
  }) async {
    if (_isSaving) return null;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await action();
      _recordWrite(updated);
      await refresh();

      // The response to this very write is the best evidence of what was
      // written; the refreshed list is a second read that can lag it. Looking
      // in the list first meant a save that succeeded could still be reported
      // as "Created variation value was not found after saving".
      ItemDefinition? sourceItem;
      ItemVariationNodeDefinition? createdValueNode;
      for (final candidate in <ItemDefinition>[
        updated,
        ..._items.where((item) => item.id == updated.id),
      ]) {
        final propertyNode =
            _findNodeById(candidate.variationTree, propertyNodeId) ??
            _findNodeByPathSegments(
              candidate.variationTree,
              propertyPathSegments,
            );
        final found = propertyNode?.activeChildren
            .where((node) => node.kind == ItemVariationNodeKind.value)
            .where((node) => _normalize(node.name) == _normalize(valueName))
            .firstOrNull;
        if (found != null) {
          sourceItem = candidate;
          createdValueNode = found;
          break;
        }
      }
      if (sourceItem == null || createdValueNode == null) {
        throw StateError('Created variation value was not found after saving.');
      }
      return QuickCreateVariationValueResult(
        item: sourceItem,
        createdValueNode: createdValueNode,
        selectedValueNodeIds: _valueNodePathIdsForNode(
          sourceItem.variationTree,
          createdValueNode.id,
        ),
      );
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _endSave();
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  Future<List<ItemUsageRecord>> fetchItemUsage(int itemId) async {
    try {
      return await _repository.getItemUsage(itemId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return const [];
    }
  }

  static String normalizeValue(String value) => _normalize(value);

  /// A stored variation node back into an input, WHOLE.
  ///
  /// This used to copy seven fields and drop five: `inputType`, `nameJoin`,
  /// both numeric bounds and `materialTypeId`. Every write that preserves a
  /// tree goes through here — including [setItemLinks] — so attaching a die to
  /// a part silently reset each of its Gauge and Material properties to Text,
  /// and lost the bounds on a Numeric one. The part looked unchanged until
  /// somebody opened its variations.
  ItemVariationNodeInput _toInput(ItemVariationNodeDefinition node) {
    return ItemVariationNodeInput(
      id: node.id,
      parentNodeId: node.parentNodeId,
      kind: node.kind,
      name: node.name,
      code: node.code,
      displayName: node.displayName,
      inputType: node.inputType,
      nameJoin: node.nameJoin,
      numericMin: node.numericMin,
      numericMax: node.numericMax,
      materialTypeId: node.materialTypeId,
      children: node.children.map(_toInput).toList(growable: false),
    );
  }

  _VariationTreeMutation _appendVariationValueToTree(
    List<ItemVariationNodeInput> nodes, {
    required int propertyNodeId,
    required String valueName,
    required List<String> valuePath,
  }) {
    var inserted = false;
    final nextNodes = <ItemVariationNodeInput>[];

    for (final node in nodes) {
      final nextValuePath = node.kind == ItemVariationNodeKind.value
          ? <String>[...valuePath, node.name.trim()]
          : valuePath;
      if (node.id == propertyNodeId) {
        if (node.kind != ItemVariationNodeKind.property) {
          throw StateError(
            'Variation values can only be added under properties.',
          );
        }
        final duplicateExists = node.children
            .where((child) => child.kind == ItemVariationNodeKind.value)
            .any((child) => _normalize(child.name) == _normalize(valueName));
        if (duplicateExists) {
          throw StateError('A value with this name already exists.');
        }
        final referenceValue = node.children
            .where((child) => child.kind == ItemVariationNodeKind.value)
            .where((child) => child.children.isNotEmpty)
            .firstOrNull;
        final nextPath = <String>[...valuePath, valueName];
        final clonedChildren = referenceValue == null
            ? const <ItemVariationNodeInput>[]
            : _cloneBranchForQuickCreate(
                referenceValue.children,
                valuePath: nextPath,
              );
        nextNodes.add(
          ItemVariationNodeInput(
            id: node.id,
            parentNodeId: node.parentNodeId,
            kind: node.kind,
            name: node.name,
            // Carried through, or appending a value would retype the property
            // to Text and drop its range and material link.
            code: node.code,
            inputType: node.inputType,
            nameJoin: node.nameJoin,
            numericMin: node.numericMin,
            numericMax: node.numericMax,
            materialTypeId: node.materialTypeId,
            displayName: '',
            children: <ItemVariationNodeInput>[
              ...node.children,
              ItemVariationNodeInput(
                kind: ItemVariationNodeKind.value,
                name: valueName,
                displayName: _generateLeafDisplayName(nextPath),
                children: clonedChildren,
              ),
            ],
          ),
        );
        inserted = true;
        continue;
      }

      final mutation = _appendVariationValueToTree(
        node.children,
        propertyNodeId: propertyNodeId,
        valueName: valueName,
        valuePath: nextValuePath,
      );
      if (mutation.inserted) {
        inserted = true;
      }
      nextNodes.add(
        ItemVariationNodeInput(
          id: node.id,
          parentNodeId: node.parentNodeId,
          kind: node.kind,
          name: node.name,
          code: node.code,
          inputType: node.inputType,
          nameJoin: node.nameJoin,
          numericMin: node.numericMin,
          numericMax: node.numericMax,
          materialTypeId: node.materialTypeId,
          displayName: node.displayName,
          children: mutation.nodes,
        ),
      );
    }

    return _VariationTreeMutation(nodes: nextNodes, inserted: inserted);
  }

  List<ItemVariationNodeInput> _cloneBranchForQuickCreate(
    List<ItemVariationNodeInput> nodes, {
    required List<String> valuePath,
  }) {
    final result = <ItemVariationNodeInput>[];
    for (final node in nodes) {
      if (node.kind == ItemVariationNodeKind.property) {
        // Clone this property node and recurse into its children (which are values)
        result.add(
          ItemVariationNodeInput(
            kind: node.kind,
            name: node.name,
            children: _cloneBranchForQuickCreate(
              node.children,
              valuePath: valuePath,
            ),
          ),
        );
      } else if (node.kind == ItemVariationNodeKind.value) {
        // Don't clone value nodes themselves, but recurse into their children
        // to find sub-properties that should be inherited.
        result.addAll(
          _cloneBranchForQuickCreate(node.children, valuePath: valuePath),
        );
      }
    }
    return result;
  }

  ItemVariationNodeDefinition? _findNodeById(
    List<ItemVariationNodeDefinition> nodes,
    int nodeId,
  ) {
    for (final node in nodes) {
      if (node.id == nodeId) {
        return node;
      }
      final child = _findNodeById(node.children, nodeId);
      if (child != null) {
        return child;
      }
    }
    return null;
  }

  List<String> _nodePathSegmentsById(
    List<ItemVariationNodeDefinition> nodes,
    int nodeId,
  ) {
    final path = <ItemVariationNodeDefinition>[];

    bool visit(
      ItemVariationNodeDefinition node,
      List<ItemVariationNodeDefinition> current,
    ) {
      final next = <ItemVariationNodeDefinition>[...current, node];
      if (node.id == nodeId) {
        path
          ..clear()
          ..addAll(next);
        return true;
      }
      for (final child in node.children) {
        if (visit(child, next)) {
          return true;
        }
      }
      return false;
    }

    for (final node in nodes) {
      if (visit(node, const <ItemVariationNodeDefinition>[])) {
        break;
      }
    }

    return path
        .map((node) => node.name.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  ItemVariationNodeDefinition? _findNodeByPathSegments(
    List<ItemVariationNodeDefinition> nodes,
    List<String> pathSegments,
  ) {
    if (pathSegments.isEmpty) {
      return null;
    }

    ItemVariationNodeDefinition? current;
    Iterable<ItemVariationNodeDefinition> scope = nodes.where(
      (node) => !node.isArchived,
    );

    for (final segment in pathSegments) {
      current = scope
          .where((node) => _normalize(node.name) == _normalize(segment))
          .firstOrNull;
      if (current == null) {
        return null;
      }
      scope = current.activeChildren;
    }

    return current;
  }

  List<int> _valueNodePathIdsForNode(
    List<ItemVariationNodeDefinition> nodes,
    int nodeId,
  ) {
    final path = <ItemVariationNodeDefinition>[];

    bool visit(
      ItemVariationNodeDefinition node,
      List<ItemVariationNodeDefinition> current,
    ) {
      final next = <ItemVariationNodeDefinition>[...current, node];
      if (node.id == nodeId) {
        path
          ..clear()
          ..addAll(next);
        return true;
      }
      for (final child in node.children) {
        if (visit(child, next)) {
          return true;
        }
      }
      return false;
    }

    for (final node in nodes) {
      if (visit(node, const <ItemVariationNodeDefinition>[])) {
        break;
      }
    }

    return path
        .where((node) => node.kind == ItemVariationNodeKind.value)
        .map((node) => node.id)
        .toList(growable: false);
  }

  String _generateLeafDisplayName(List<String> valuePath) {
    return valuePath
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .join(' | ');
  }

  static String _treeSearchText(List<ItemVariationNodeDefinition> nodes) {
    final parts = <String>[];

    void visit(ItemVariationNodeDefinition node) {
      parts.add(node.name);
      parts.add(node.displayName);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return parts.join(' ');
  }

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

class _VariationTreeMutation {
  const _VariationTreeMutation({required this.nodes, required this.inserted});

  final List<ItemVariationNodeInput> nodes;
  final bool inserted;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
