import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_info_panel.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/page_container.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../groups/presentation/screens/groups_screen.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/screens/items_screen.dart';
import 'package:paper/widgets/variation_path_selector_dialog.dart';
import '../../../pm/presentation/barcode/material_barcode_toolkit.dart';
import '../../../pm/presentation/screens/pm_screen.dart';
import '../../../units/domain/unit_definition.dart';
import '../../../units/domain/unit_inputs.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../../units/presentation/screens/units_screen.dart';
import '../../domain/create_parent_material_input.dart';
import '../../domain/group_property_draft.dart' as governance;
import '../../domain/inventory_control_tower.dart';
import '../../domain/material_control_tower_detail.dart';
import '../../domain/material_group_configuration.dart' as groupcfg;
import '../../domain/material_inputs.dart';
import '../../domain/material_record.dart';
import '../providers/inventory_provider.dart';

enum _InventoryViewMode { groups, items }



enum _InventoryListingMode { all, recentFirst }

enum _InventorySortColumn { name, id, stock, activity, createdBy, status }

const _inventoryHoverColor = SoftErpTheme.accentSurface;

enum _InventoryStockAction { receive, transfer, adjust }

enum _InventoryQuickCreateAction { group, item }

final ValueNotifier<int> _inventoryActionsOverlayDismissSignal =
    ValueNotifier<int>(0);

const _inventoryPinnedStateFileName = 'inventory_pins.json';

class _SelectAllFilteredIntent extends Intent {
  const _SelectAllFilteredIntent();
}

class _ClearSelectionIntent extends Intent {
  const _ClearSelectionIntent();
}

class _DeleteSelectionIntent extends Intent {
  const _DeleteSelectionIntent();
}

class _BulkFailureItem {
  const _BulkFailureItem({required this.record, required this.message});

  final MaterialRecord record;
  final String message;
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  static bool get _isDesktopPlatform =>
      kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<T?> _showInventoryModal<T>(
    BuildContext context,
    Widget body,
  ) async {
    final isNarrow =
        MediaQuery.of(context).size.width < 800 || !_isDesktopPlatform;
    if (isNarrow) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: body,
        ),
      );
    }

    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 72, vertical: 48),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: body,
      ),
    );
  }

  static Future<void> openCreateGroupForm(BuildContext context) async {
    await _showInventoryModal<void>(context, const _AddMaterialForm());
  }

  static Future<bool?> openAddStockForm(BuildContext context) {
    return _showInventoryModal<bool>(context, const _AddStockForm());
  }

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final Set<String> _selectedBarcodes = <String>{};
  final Set<String> _expandedParents = <String>{};
  bool _hasInitializedExpandedParents = false;
  _InventoryViewMode _viewMode = _InventoryViewMode.groups;
  _InventoryListingMode _listingMode = _InventoryListingMode.recentFirst;
  String? _supplierFilter;
  String? _typeFilter;
  String? _kindFilter;
  _InventorySortColumn? _sortColumn;
  bool _sortAscending = true;
  bool _isBulkRunning = false;
  String? _bulkProgressLabel;
  final Set<String> _pinnedBarcodes = <String>{};

  @override
  void initState() {
    super.initState();
    // KPIs removed: loadInventoryHealth() call removed
    _loadPinnedState();
  }

  @override
  Widget build(BuildContext context) {
    final isRequestDelete = context.select<AuthProvider, bool>(
      (auth) =>
          !auth.can('inventory.delete') && auth.can('inventory.request_delete'),
    );
    return Consumer3<InventoryProvider, GroupsProvider, ItemsProvider>(
      builder: (context, inventory, groups, items, _) {
        if (inventory.isLoading && inventory.materials.isEmpty) {
          return const _InventoryLoadingSkeleton();
        }

        final records = inventory.materials;
        final groupNameById = <int, String>{
          for (final group in groups.groups) group.id: group.name,
        };
        final groupsById = <int, GroupDefinition>{
          for (final group in groups.groups) group.id: group,
        };
        final itemById = <int, ItemDefinition>{
          for (final item in items.items) item.id: item,
        };
        if (!_hasInitializedExpandedParents && groupsById.isNotEmpty) {
          _expandedParents.addAll(
            _defaultExpandedGroupBarcodes(
              records,
              groupsById: groupsById,
              itemById: itemById,
            ),
          );
          _hasInitializedExpandedParents = true;
        }
        final suppliers = _distinctValues(
          records.map((record) => record.supplier),
        );
        final types = _distinctValues(records.map((record) => record.type));
        final filteredRecords = _applyFilters(
          records,
          inventory.searchQuery,
          groupNameById: groupNameById,
          itemById: itemById,
        );
        final rows = _buildRows(
          filteredRecords,
          groupNameById: groupNameById,
          groupsById: groupsById,
          itemById: itemById,
          expandedParents: _expandedParents,
          searchQuery: inventory.searchQuery,
        );
        // KPIs removed: summary computation removed
        final selectableRows = rows
            .where((row) => row.record.id != null)
            .toList(growable: false);
        final selectableBarcodes = <String>{
          for (final row in selectableRows) row.record.barcode,
        };
        final selectedRecords = selectableRows
            .map((row) => row.record)
            .where((record) => _selectedBarcodes.contains(record.barcode))
            .toList(growable: false);

        _selectedBarcodes.removeWhere(
          (barcode) => !selectableBarcodes.contains(barcode),
        );
        final validExpandedBarcodes = <String>{
          for (final record in records) record.barcode,
          for (final group in groupsById.values)
            _masterGroupInventoryBarcode(group.id),
        };
        _expandedParents.removeWhere(
          (barcode) => !validExpandedBarcodes.contains(barcode),
        );

        final workspaceContent = PageContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (inventory.isLoading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 3,
                    color: Color(0xFF6E56FF),
                    backgroundColor: Color(0xFFEAE5FF),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (inventory.errorMessage != null) ...[
                _ErrorBanner(message: inventory.errorMessage!),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InventoryWorkspaceHeader(
                        viewMode: _viewMode,
                        onViewModeChanged: (value) {
                          setState(() {
                            _viewMode = value;
                          });
                        },
                        onPrimaryCreateTap: _handlePrimaryCreateTap,
                        onQuickCreateSelected: _handleQuickCreate,
                        onAddStock: () async {
                          final created =
                              await InventoryScreen.openAddStockForm(context);
                          if (!mounted || created != true) {
                            return;
                          }
                          setState(() {
                            _kindFilter = null;
                          });
                        },
                        onReceiveStock: () => _openMovementComposer(
                          movementType: InventoryMovementType.receive,
                        ),
                        onTransferStock: () => _openMovementComposer(
                          movementType: InventoryMovementType.transfer,
                        ),
                        onAdjustStock: () => _openMovementComposer(
                          movementType: InventoryMovementType.adjust,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InventoryControlsRow(
                        supplierFilter: _supplierFilter,
                        typeFilter: _typeFilter,
                        kindFilter: _kindFilter,
                        suppliers: suppliers,
                        types: types,
                        selectedCount: _selectedBarcodes.length,
                        filteredCount: selectableRows.length,
                        listingMode: _listingMode,
                        onSupplierSelected: (value) {
                          setState(() {
                            _supplierFilter = value;
                          });
                        },
                        onTypeSelected: (value) {
                          setState(() {
                            _typeFilter = value;
                          });
                        },
                        onKindSelected: (value) {
                          setState(() {
                            _kindFilter = value;
                          });
                        },
                        onClearSelection: () {
                          setState(_selectedBarcodes.clear);
                        },
                        onSelectAllFiltered: () {
                          setState(() {
                            _selectedBarcodes.addAll(
                              selectableRows.map((row) => row.record.barcode),
                            );
                          });
                        },
                        onClearFilters: () {
                          setState(() {
                            _supplierFilter = null;
                            _typeFilter = null;
                            _kindFilter = null;
                            _sortColumn = null;
                            _sortAscending = true;
                          });
                        },
                        onListingModeChanged: (value) {
                          setState(() {
                            _listingMode = value;
                          });
                        },
                      ),
                      if (selectedRecords.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _InventoryBulkActionBar(
                          selectedCount: selectedRecords.length,
                          isBusy: _isBulkRunning,
                          isRequestDelete: isRequestDelete,
                          progressLabel: _bulkProgressLabel,
                          onClearSelection: () {
                            setState(_selectedBarcodes.clear);
                          },
                          onOpenSingleDetails: selectedRecords.length == 1
                              ? () => _openDetails(selectedRecords.first)
                              : null,
                          onResetTrace: () => _bulkResetTrace(selectedRecords),
                          onUnlink: () => _bulkUnlink(selectedRecords),
                          onDelete: () => _bulkDelete(selectedRecords),
                        ),
                      ],
                      const SizedBox(height: 4),
                      const Divider(height: 1, color: SoftErpTheme.border),
                      const SizedBox(height: 14),
                      Expanded(
                        child: _InventoryTable(
                          rows: rows,
                          viewMode: _viewMode,
                          sortColumn: _sortColumn,
                          sortAscending: _sortAscending,
                          groupsProvider: groups,
                          itemsProvider: items,
                          selectedBarcodes: _selectedBarcodes,
                          pinnedBarcodes: _pinnedBarcodes,
                          expandedParents: _expandedParents,
                          isRequestDelete: isRequestDelete,
                          onToggleSelection: (barcode) {
                            setState(() {
                              if (_selectedBarcodes.contains(barcode)) {
                                _selectedBarcodes.remove(barcode);
                              } else {
                                _selectedBarcodes.add(barcode);
                              }
                            });
                          },
                          onToggleExpanded: (barcode) {
                            setState(() {
                              if (_expandedParents.contains(barcode)) {
                                _expandedParents.remove(barcode);
                              } else {
                                _expandedParents.add(barcode);
                              }
                            });
                          },
                          onTogglePinned: (barcode) {
                            setState(() {
                              if (_pinnedBarcodes.contains(barcode)) {
                                _pinnedBarcodes.remove(barcode);
                              } else {
                                _pinnedBarcodes.add(barcode);
                              }
                            });
                            _persistPinnedState();
                          },
                          onHeaderSortRequested: (column, ascending) {
                            setState(() {
                              if (column == null) {
                                _sortColumn = null;
                                _sortAscending = true;
                              } else {
                                _sortColumn = column;
                                _sortAscending = ascending;
                              }
                            });
                          },
                          onOpenDetails: (record) => _openDetails(record),
                          onReceive: (record) => _openMovementComposer(
                            movementType: InventoryMovementType.receive,
                            initialBarcode: record.barcode,
                          ),
                          onAddSubGroup: (record) => _openAddSubGroup(record),
                          onEdit: (record) => _openEditMaterial(record),
                          onDelete: (record) => _confirmDelete(record),
                          onLinkGroup: (record) => _openGroupLinker(record),
                          onLinkItem: (record) => _openItemLinker(record),
                          onUnlink: (record) => _unlinkInheritance(record),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        final isApplePlatform = !kIsWeb && Platform.isMacOS;
        final isDesktopWeb = kIsWeb;
        final shortcuts = <ShortcutActivator, Intent>{
          SingleActivator(
            LogicalKeyboardKey.keyA,
            control: !isApplePlatform && !isDesktopWeb,
            meta: isApplePlatform || isDesktopWeb,
          ): const _SelectAllFilteredIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyA,
            control: !isApplePlatform && !isDesktopWeb,
            meta: isApplePlatform || isDesktopWeb,
            shift: true,
          ): const _ClearSelectionIntent(),
          const SingleActivator(LogicalKeyboardKey.escape):
              const _ClearSelectionIntent(),
          const SingleActivator(LogicalKeyboardKey.delete):
              const _DeleteSelectionIntent(),
        };

        final workspaceShell = workspaceContent;

        return Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: {
              _SelectAllFilteredIntent:
                  CallbackAction<_SelectAllFilteredIntent>(
                    onInvoke: (intent) {
                      if (selectableRows.isEmpty || _isBulkRunning) {
                        return null;
                      }
                      setState(() {
                        _selectedBarcodes.addAll(
                          selectableRows.map((row) => row.record.barcode),
                        );
                      });
                      return null;
                    },
                  ),
              _ClearSelectionIntent: CallbackAction<_ClearSelectionIntent>(
                onInvoke: (intent) {
                  if (_selectedBarcodes.isEmpty || _isBulkRunning) {
                    return null;
                  }
                  setState(_selectedBarcodes.clear);
                  return null;
                },
              ),
              _DeleteSelectionIntent: CallbackAction<_DeleteSelectionIntent>(
                onInvoke: (intent) {
                  if (selectedRecords.isEmpty || _isBulkRunning) {
                    return null;
                  }
                  _bulkDelete(selectedRecords);
                  return null;
                },
              ),
            },
            child: Focus(autofocus: true, child: workspaceShell),
          ),
        );
      },
    );
  }

  Future<void> _openCreateGroupEditor({MaterialRecord? initialRecord}) async {
    if (!mounted) {
      return;
    }
    if (initialRecord == null) {
      await InventoryScreen.openCreateGroupForm(context);
      return;
    }

    final linkedGroupId = initialRecord.linkedGroupId;
    if (linkedGroupId != null) {
      final linkedGroup = context.read<GroupsProvider>().findById(
        linkedGroupId,
      );
      if (linkedGroup != null) {
        await GroupsScreen.openEditor(context, group: linkedGroup);
        return;
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _EditMaterialSheet(record: initialRecord),
        ),
      ),
    );
  }

  Future<void> _handleQuickCreate(_InventoryQuickCreateAction action) async {
    switch (action) {
      case _InventoryQuickCreateAction.group:
        await _openCreateGroupEditor();
      case _InventoryQuickCreateAction.item:
        await ItemsScreen.openEditor(context);
    }
  }

  Future<void> _handlePrimaryCreateTap() async {
    switch (_viewMode) {
      case _InventoryViewMode.groups:
        await _openCreateGroupEditor();
      case _InventoryViewMode.items:
        await ItemsScreen.openEditor(context);
    }
  }

  List<String> _distinctValues(Iterable<String> values) {
    final distinct =
        values
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return distinct;
  }

  Future<void> _loadPinnedState() async {
    try {
      final file = await _inventoryPinnedStateFile();
      if (!await file.exists()) {
        return;
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      final pinned = <String>{};
      if (decoded is Map<String, dynamic>) {
        final barcodes = decoded['barcodes'];
        if (barcodes is List) {
          for (final value in barcodes) {
            final normalized = value?.toString().trim() ?? '';
            if (normalized.isNotEmpty) {
              pinned.add(normalized);
            }
          }
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _pinnedBarcodes
          ..clear()
          ..addAll(pinned);
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _persistPinnedState() async {
    try {
      final file = await _inventoryPinnedStateFile();
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'barcodes': _pinnedBarcodes.toList(growable: false),
        }),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to persist pinned inventory rows.'),
        ),
      );
    }
  }

  Future<File> _inventoryPinnedStateFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_inventoryPinnedStateFileName');
  }

  Set<String> _defaultExpandedGroupBarcodes(
    List<MaterialRecord> records, {
    required Map<int, GroupDefinition> groupsById,
    required Map<int, ItemDefinition> itemById,
  }) {
    final groupRecordsByGroupId = <int, MaterialRecord>{
      for (final record in records.where(
        (record) => record.linkedGroupId != null,
      ))
        record.linkedGroupId!: record,
    };
    final groupsWithChildren = <int>{};
    for (final group in groupsById.values) {
      final parentId = group.parentGroupId;
      if (parentId != null && groupsById.containsKey(parentId)) {
        groupsWithChildren.add(parentId);
      }
    }
    for (final record in records.where(
      (record) => record.linkedItemId != null,
    )) {
      final item = itemById[record.linkedItemId];
      if (item != null && groupRecordsByGroupId.containsKey(item.groupId)) {
        groupsWithChildren.add(item.groupId);
      }
    }
    return groupsWithChildren
        .map(
          (groupId) =>
              groupRecordsByGroupId[groupId]?.barcode ??
              _masterGroupInventoryBarcode(groupId),
        )
        .whereType<String>()
        .toSet();
  }

  List<MaterialRecord> _applyFilters(
    List<MaterialRecord> records,
    String query, {
    required Map<int, String> groupNameById,
    required Map<int, ItemDefinition> itemById,
  }) {
    final normalizedQuery = _normalize(query);
    final scoped = records
        .where((record) {
          if (_supplierFilter != null && record.supplier != _supplierFilter) {
            return false;
          }
          if (_typeFilter != null && record.type != _typeFilter) {
            return false;
          }
          if (_kindFilter != null && record.kind != _kindFilter) {
            return false;
          }
          // KPIs removed: summaryFilter (awaiting scan / linked) removed
          if (normalizedQuery.isEmpty) {
            return true;
          }

          final linkedItem = record.linkedItemId == null
              ? null
              : itemById[record.linkedItemId];
          final linkedItemLabel = linkedItem == null
              ? ''
              : linkedItem.displayName.trim().isEmpty
              ? linkedItem.name
              : linkedItem.displayName;
          final linkedGroupLabel = record.linkedGroupId == null
              ? ''
              : groupNameById[record.linkedGroupId] ?? '';
          final haystack = <String>[
            record.name,
            record.barcode,
            record.type,
            record.grade,
            record.thickness,
            record.supplier,
            record.location,
            record.unit,
            record.notes,
            record.parentBarcode ?? '',
            record.displayStock,
            record.createdBy,
            record.workflowStatus,
            linkedGroupLabel,
            linkedItemLabel,
            linkedItem?.alias ?? '',
          ].map(_normalize).join(' ');
          return haystack.contains(normalizedQuery);
        })
        .toList(growable: false);

    return scoped;
  }



  List<_InventoryRowEntry> _buildRows(
    List<MaterialRecord> scopedRecords, {
    required Map<int, String> groupNameById,
    required Map<int, GroupDefinition> groupsById,
    required Map<int, ItemDefinition> itemById,
    required Set<String> expandedParents,
    required String searchQuery,
  }) {
    if (_viewMode == _InventoryViewMode.items) {
      return scopedRecords
          .where((record) => record.linkedItemId != null)
          .map((record) {
            final linkedItem = record.linkedItemId == null
                ? null
                : itemById[record.linkedItemId];
            final linkedGroupName = linkedItem == null
                ? null
                : groupNameById[linkedItem.groupId];
            return _InventoryRowEntry(
              record: record,
              displayName: linkedItem == null
                  ? record.name
                  : linkedItem.displayName.trim().isEmpty
                  ? linkedItem.name
                  : linkedItem.displayName,
              displayId: record.linkedItemId?.toString() ?? record.barcode,
              displayMetadata: _itemMetadataText(record, linkedGroupName),
            );
          })
          .toList(growable: false)
        ..sort(_compareRowEntries);
    }

    final itemRecordsByGroupId = <int, List<MaterialRecord>>{};
    // Collect items that already have inventory records.
    final coveredItemIds = <int>{};
    for (final record in scopedRecords.where(
      (record) => record.linkedItemId != null,
    )) {
      final linkedItem = itemById[record.linkedItemId];
      if (linkedItem == null) {
        continue;
      }
      coveredItemIds.add(linkedItem.id);
      itemRecordsByGroupId
          .putIfAbsent(linkedItem.groupId, () => <MaterialRecord>[])
          .add(record);
    }

    final groupRecordsByGroupId = <int, MaterialRecord>{
      for (final record in scopedRecords.where(
        (record) => record.linkedGroupId != null,
      ))
        record.linkedGroupId!: record,
    };
    if (_shouldIncludeMasterOnlyGroups()) {
      final normalizedQuery = _normalize(searchQuery);
      for (final group in groupsById.values.where(
        (group) => !group.isArchived,
      )) {
        if (groupRecordsByGroupId.containsKey(group.id)) {
          continue;
        }
        final parentName = groupNameById[group.parentGroupId] ?? '';
        final matchesQuery =
            normalizedQuery.isEmpty ||
            _normalize(group.name).contains(normalizedQuery) ||
            _normalize(parentName).contains(normalizedQuery);
        if (!matchesQuery) {
          continue;
        }
        groupRecordsByGroupId[group.id] = _masterGroupRecord(
          group,
          parentName: parentName,
        );
      }
    }
    // Also inject master-only items (no stock record yet) so their group shows
    // them as children and the group's expand chevron is visible.
    if (_shouldIncludeMasterOnlyGroups()) {
      final normalizedQuery = _normalize(searchQuery);
      for (final item in itemById.values.where((i) => !i.isArchived)) {
        if (coveredItemIds.contains(item.id)) {
          continue;
        }
        if (!groupRecordsByGroupId.containsKey(item.groupId)) {
          continue;
        }
        final itemLabel = item.displayName.trim().isEmpty ? item.name : item.displayName;
        final groupName = groupNameById[item.groupId] ?? '';
        if (normalizedQuery.isNotEmpty &&
            !_normalize(itemLabel).contains(normalizedQuery) &&
            !_normalize(item.name).contains(normalizedQuery) &&
            !_normalize(groupName).contains(normalizedQuery)) {
          continue;
        }
        itemRecordsByGroupId
            .putIfAbsent(item.groupId, () => <MaterialRecord>[])
            .add(_masterItemRecord(item));
      }
    }
    final childGroupIdsByParentId = <int, List<int>>{};
    for (final group in groupsById.values) {
      final parentId = group.parentGroupId;
      if (parentId == null) {
        continue;
      }
      if (!groupRecordsByGroupId.containsKey(group.id) ||
          !groupRecordsByGroupId.containsKey(parentId)) {
        continue;
      }
      childGroupIdsByParentId
          .putIfAbsent(parentId, () => <int>[])
          .add(group.id);
    }
    for (final childIds in childGroupIdsByParentId.values) {
      childIds.sort(
        (a, b) => _compareRowLike(
          aRecord: groupRecordsByGroupId[a]!,
          aName: groupNameById[a] ?? groupRecordsByGroupId[a]!.name,
          aId: a.toString(),
          bRecord: groupRecordsByGroupId[b]!,
          bName: groupNameById[b] ?? groupRecordsByGroupId[b]!.name,
          bId: b.toString(),
        ),
      );
    }

    void appendGroupRows(
      int groupId,
      int depth,
      List<_InventoryRowEntry> rows,
    ) {
      final groupRecord = groupRecordsByGroupId[groupId];
      if (groupRecord == null) {
        return;
      }
      final linkedGroupName = groupNameById[groupId];
      final childGroupIds = childGroupIdsByParentId[groupId] ?? const <int>[];
      final childRecords =
          (itemRecordsByGroupId[groupId] ?? const <MaterialRecord>[]).toList(
            growable: false,
          );
      final hasChildren = childGroupIds.isNotEmpty || childRecords.isNotEmpty;
      final isExpanded = expandedParents.contains(groupRecord.barcode);
      rows.add(
        _InventoryRowEntry(
          record: groupRecord,
          displayName: linkedGroupName ?? groupRecord.name,
          displayId: groupId.toString(),
          displayMetadata: _groupMetadataText(
            groupRecord,
            groupCount: childGroupIds.length,
            itemCount: childRecords.length,
          ),
          depth: depth,
          canExpand: hasChildren,
          isExpanded: isExpanded,
          opensDetails: false,
        ),
      );
      if (!isExpanded) {
        return;
      }
      for (final childGroupId in childGroupIds) {
        appendGroupRows(childGroupId, depth + 1, rows);
      }
      if (_viewMode == _InventoryViewMode.groups) {
        return;
      }
      childRecords.sort(
        (a, b) => _compareRowLike(
          aRecord: a,
          aName: (() {
            final linkedItem = itemById[a.linkedItemId];
            if (linkedItem == null) {
              return a.name;
            }
            return linkedItem.displayName.trim().isEmpty
                ? linkedItem.name
                : linkedItem.displayName;
          })(),
          aId: a.linkedItemId?.toString() ?? a.barcode,
          bRecord: b,
          bName: (() {
            final linkedItem = itemById[b.linkedItemId];
            if (linkedItem == null) {
              return b.name;
            }
            return linkedItem.displayName.trim().isEmpty
                ? linkedItem.name
                : linkedItem.displayName;
          })(),
          bId: b.linkedItemId?.toString() ?? b.barcode,
        ),
      );
      for (final childRecord in childRecords) {
        final linkedItem = itemById[childRecord.linkedItemId];
        final childName = linkedItem == null
            ? childRecord.name
            : linkedItem.displayName.trim().isEmpty
            ? linkedItem.name
            : linkedItem.displayName;
        rows.add(
          _InventoryRowEntry(
            record: childRecord,
            displayName: childName,
            displayId:
                childRecord.linkedItemId?.toString() ?? childRecord.barcode,
            displayMetadata: _itemMetadataText(childRecord, linkedGroupName),
            depth: depth + 1,
          ),
        );
      }
    }

    final rootGroupIds =
        groupRecordsByGroupId.keys
            .where((groupId) {
              final parentId = groupsById[groupId]?.parentGroupId;
              return parentId == null ||
                  !groupRecordsByGroupId.containsKey(parentId);
            })
            .toList(growable: false)
          ..sort(
            (a, b) => _compareRowLike(
              aRecord: groupRecordsByGroupId[a]!,
              aName: groupNameById[a] ?? groupRecordsByGroupId[a]!.name,
              aId: a.toString(),
              bRecord: groupRecordsByGroupId[b]!,
              bName: groupNameById[b] ?? groupRecordsByGroupId[b]!.name,
              bId: b.toString(),
            ),
          );

    final rows = <_InventoryRowEntry>[];
    for (final groupId in rootGroupIds) {
      appendGroupRows(groupId, 0, rows);
    }
    final standaloneParentRecords =
        scopedRecords
            .where(
              (record) =>
                  record.linkedGroupId == null &&
                  record.linkedItemId == null &&
                  record.parentBarcode == null,
            )
            .toList(growable: false)
          ..sort(
            (a, b) => _compareRowLike(
              aRecord: a,
              aName: a.name,
              aId: a.barcode,
              bRecord: b,
              bName: b.name,
              bId: b.barcode,
            ),
          );
    for (final record in standaloneParentRecords) {
      rows.add(
        _InventoryRowEntry(
          record: record,
          displayName: record.name,
          displayId: record.barcode,
          displayMetadata: _itemMetadataText(record, null),
          canExpand: record.linkedChildBarcodes.isNotEmpty,
          isExpanded: expandedParents.contains(record.barcode),
        ),
      );
    }
    return rows;
  }

  bool _shouldIncludeMasterOnlyGroups() {
    // BUG-12: Master-only groups are structural tree nodes from the Masters
    // module that have no inventory record yet. They must always appear in
    // the groups view so the folder hierarchy is never broken by active
    // supplier or type filters (those filters apply to inventory records, not
    // group placeholders). Only suppress them in items view or when the kind
    // filter explicitly excludes parent groups.
    return _viewMode == _InventoryViewMode.groups &&
        (_kindFilter == null || _kindFilter == 'parent');
  }

  MaterialRecord _masterGroupRecord(
    GroupDefinition group, {
    required String parentName,
  }) {
    return MaterialRecord(
      id: null,
      barcode: _masterGroupInventoryBarcode(group.id),
      name: group.name,
      type: 'Group',
      grade: '',
      thickness: '',
      supplier: parentName,
      location: 'Configurator Groups',
      unitId: group.unitId,
      unit: '',
      notes: 'Master group without a linked inventory stock record.',
      groupMode: 'item_group_authoring',
      inheritanceEnabled: true,
      createdAt: group.createdAt,
      updatedAt: group.updatedAt,
      kind: 'parent',
      parentBarcode: group.parentGroupId == null
          ? null
          : _masterGroupInventoryBarcode(group.parentGroupId!),
      numberOfChildren: 0,
      linkedChildBarcodes: const <String>[],
      scanCount: 0,
      linkedGroupId: group.id,
      displayStock: '0',
      createdBy: 'Configurator',
      workflowStatus: 'notStarted',
    );
  }

  String _masterGroupInventoryBarcode(int groupId) {
    return 'GROUP-MASTER-$groupId';
  }

  MaterialRecord _masterItemRecord(ItemDefinition item) {
    return MaterialRecord(
      id: null,
      barcode: 'ITEM-MASTER-${item.id}',
      name: item.displayName.trim().isEmpty ? item.name : item.displayName,
      type: 'Item',
      grade: '',
      thickness: '',
      supplier: '',
      location: 'Master Items',
      notes: 'Master item without inventory stock record.',
      kind: 'child',
      parentBarcode: null,
      numberOfChildren: 0,
      linkedChildBarcodes: const <String>[],
      scanCount: 0,
      linkedItemId: item.id,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
  }

  String _groupMetadataText(
    MaterialRecord record, {
    required int groupCount,
    required int itemCount,
  }) {
    final parts = <String>[
      if (groupCount > 0) '$groupCount ${groupCount == 1 ? 'group' : 'groups'}',
      '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
      if (record.supplier.trim().isNotEmpty) record.supplier.trim(),
      if (record.location.trim().isNotEmpty) record.location.trim(),
      record.hasBeenScanned
          ? 'Scanned ${record.scanCount}x'
          : 'Awaiting first scan',
    ];
    return parts.join('  •  ');
  }

  String _itemMetadataText(MaterialRecord record, String? linkedGroupName) {
    final parts = <String>[
      if (linkedGroupName != null && linkedGroupName.trim().isNotEmpty)
        linkedGroupName.trim(),
      if (record.supplier.trim().isNotEmpty) record.supplier.trim(),
      if (record.location.trim().isNotEmpty) record.location.trim(),
      record.hasBeenScanned
          ? 'Scanned ${record.scanCount}x'
          : 'Awaiting first scan',
    ];
    return parts.join('  •  ');
  }

  int _compareRowEntries(_InventoryRowEntry a, _InventoryRowEntry b) {
    return _compareRowLike(
      aRecord: a.record,
      aName: a.displayName ?? a.record.name,
      aId: a.displayId ?? a.record.barcode,
      bRecord: b.record,
      bName: b.displayName ?? b.record.name,
      bId: b.displayId ?? b.record.barcode,
    );
  }

  int _compareRowLike({
    required MaterialRecord aRecord,
    required String aName,
    required String aId,
    required MaterialRecord bRecord,
    required String bName,
    required String bId,
  }) {
    final aPinned = _pinnedBarcodes.contains(aRecord.barcode);
    final bPinned = _pinnedBarcodes.contains(bRecord.barcode);
    if (aPinned != bPinned) {
      return aPinned ? -1 : 1;
    }

    final column = _sortColumn;
    if (column != null) {
      final comparison = switch (column) {
        _InventorySortColumn.name => _compareText(aName, bName),
        _InventorySortColumn.id => _compareText(aId, bId),
        _InventorySortColumn.stock => aRecord.onHand.compareTo(bRecord.onHand),
        _InventorySortColumn.activity =>
          (aRecord.lastScannedAt ?? aRecord.updatedAt).compareTo(
            bRecord.lastScannedAt ?? bRecord.updatedAt,
          ),
        _InventorySortColumn.createdBy => _compareText(
          aRecord.createdBy.ifEmpty('Demo Admin'),
          bRecord.createdBy.ifEmpty('Demo Admin'),
        ),
        _InventorySortColumn.status => _resolveInventoryState(
          aRecord,
        ).index.compareTo(_resolveInventoryState(bRecord).index),
      };
      if (comparison != 0) {
        return _sortAscending ? comparison : -comparison;
      }
    } else if (_listingMode == _InventoryListingMode.recentFirst) {
      final timeCompare = bRecord.createdAt.compareTo(aRecord.createdAt);
      if (timeCompare != 0) {
        return timeCompare;
      }
    }

    return _compareText(aName, bName);
  }

  int _compareText(String a, String b) {
    return a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
  }

  _InventoryRecordState _resolveInventoryState(MaterialRecord record) {
    if (!record.hasBeenScanned) {
      return _InventoryRecordState.awaitingScan;
    }
    switch (record.workflowStatus) {
      case 'completed':
        return _InventoryRecordState.completed;
      case 'inProgress':
        return _InventoryRecordState.inProgress;
      default:
        return _InventoryRecordState.notStarted;
    }
  }

  Future<void> _openDetails(MaterialRecord record) async {
    _dismissInventoryActionOverlays();
    final provider = context.read<InventoryProvider>();
    await provider.selectMaterial(record.barcode);
    if (!mounted) {
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Inventory details',
      barrierColor: const Color(0x66100D1F),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
              child: SizedBox(
                height: double.infinity,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 520,
                    minWidth: 420,
                  ),
                  child: _InventoryDetailSheet(record: record),
                ),
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _openAddSubGroup(MaterialRecord record) async {
    if (!record.isParent) {
      return;
    }
    _dismissInventoryActionOverlays();
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: _AddChildMaterialSheet(parent: record),
        ),
      ),
    );
  }

  Future<void> _openEditMaterial(MaterialRecord record) async {
    _dismissInventoryActionOverlays();
    if (record.isParent &&
        (record.groupMode == 'item_group_authoring' ||
            record.type.trim().toLowerCase() == 'item group')) {
      await _openCreateGroupEditor(initialRecord: record);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _EditMaterialSheet(record: record),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(MaterialRecord record) async {
    _dismissInventoryActionOverlays();
    final auth = context.read<AuthProvider>();
    if (!auth.can('inventory.delete') && auth.can('inventory.request_delete')) {
      await _requestDelete(record);
      return;
    }
    if (!auth.can('inventory.delete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to delete records.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record.isParent ? 'Delete group?' : 'Delete item?'),
        content: Text(
          record.isParent
              ? 'This will remove ${record.name} and all of its linked child items.'
              : 'This will remove ${record.name} from inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<InventoryProvider>().deleteMaterial(record.barcode);
  }

  Future<void> _requestDelete(MaterialRecord record) async {
    _dismissInventoryActionOverlays();
    final controller = TextEditingController();
    final requested = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          record.isParent ? 'Request group deletion' : 'Request item deletion',
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Tell an admin why this should be deleted.',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Request delete'),
          ),
        ],
      ),
    );
    if (requested != true || !mounted) {
      controller.dispose();
      return;
    }
    final ok = await context.read<AuthProvider>().requestDelete(
      entityType: 'material',
      entityId: record.barcode,
      entityLabel: record.name,
      reason: controller.text,
    );
    controller.dispose();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Delete request sent to admins.'
              : context.read<AuthProvider>().errorMessage ??
                    'Failed to request deletion.',
        ),
      ),
    );
  }

  Future<void> _openGroupLinker(MaterialRecord record) async {
    _dismissInventoryActionOverlays();
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _LinkGroupSheet(record: record),
        ),
      ),
    );
  }

  Future<void> _openItemLinker(MaterialRecord record) async {
    _dismissInventoryActionOverlays();
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _LinkItemSheet(record: record),
        ),
      ),
    );
  }

  Future<void> _unlinkInheritance(MaterialRecord record) async {
    await context.read<InventoryProvider>().unlinkMaterial(record.barcode);
  }

  Future<void> _openMovementComposer({
    required InventoryMovementType movementType,
    String? initialBarcode,
  }) async {
    _dismissInventoryActionOverlays();
    final inventory = context.read<InventoryProvider>();
    final materials = inventory.materials;
    if (materials.isEmpty) {
      return;
    }

    final resolvedInitialBarcode =
        initialBarcode ??
        inventory.selectedMaterial?.barcode ??
        materials.first.barcode;
    final draft = await showDialog<_MovementComposerDraft>(
      context: context,
      builder: (dialogContext) => _InventoryMovementComposerDialog(
        movementType: movementType,
        materials: materials,
        initialBarcode: resolvedInitialBarcode,
      ),
    );

    if (draft == null || !mounted) {
      return;
    }

    final detail = await inventory.postInventoryMovement(
      CreateInventoryMovementInput(
        materialBarcode: draft.materialBarcode,
        movementType: movementType,
        qty: draft.qty,
        fromLocationId: draft.fromLocationId,
        toLocationId: draft.toLocationId,
        reasonCode: draft.reasonCode,
        referenceType: draft.referenceType,
        referenceId: draft.referenceId,
        actor: 'Inventory UI',
        lotCode: draft.lotCode,
      ),
    );

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (detail == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(inventory.errorMessage ?? 'Failed to post movement.'),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${_movementTypeLabel(movementType)} posted for ${draft.materialBarcode}.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _dismissInventoryActionOverlays() {
    _inventoryActionsOverlayDismissSignal.value++;
  }

  Future<void> _bulkResetTrace(List<MaterialRecord> records) async {
    if (_isBulkRunning || records.isEmpty) {
      return;
    }
    final provider = context.read<InventoryProvider>();
    var success = 0;
    var failed = 0;
    final failures = <_BulkFailureItem>[];
    await _runBulkOperation(
      label: 'Resetting trace...',
      run: () async {
        for (var index = 0; index < records.length; index += 1) {
          final record = records[index];
          _setBulkProgress('Resetting trace ${index + 1}/${records.length}');
          provider.clearError();
          await provider.resetScanTrace(record.barcode);
          if (provider.errorMessage == null) {
            success += 1;
          } else {
            failed += 1;
            failures.add(
              _BulkFailureItem(
                record: record,
                message: provider.errorMessage ?? 'Unknown failure',
              ),
            );
          }
        }
      },
    );
    _showBulkResult(
      actionLabel: 'Reset trace',
      successCount: success,
      failedCount: failed,
    );
    if (failures.isNotEmpty) {
      await _showBulkFailuresDialog(
        actionLabel: 'Reset Trace',
        failures: failures,
        onRetryFailed: () => _bulkResetTrace(
          failures.map((item) => item.record).toList(growable: false),
        ),
      );
    }
  }

  Future<void> _bulkUnlink(List<MaterialRecord> records) async {
    if (_isBulkRunning || records.isEmpty) {
      return;
    }
    final provider = context.read<InventoryProvider>();
    var success = 0;
    var failed = 0;
    var skipped = 0;
    final failures = <_BulkFailureItem>[];
    await _runBulkOperation(
      label: 'Removing inheritance links...',
      run: () async {
        for (var index = 0; index < records.length; index += 1) {
          final record = records[index];
          _setBulkProgress('Unlinking ${index + 1}/${records.length}');
          if (!record.hasInheritanceLink) {
            skipped += 1;
            continue;
          }
          provider.clearError();
          await provider.unlinkMaterial(record.barcode);
          if (provider.errorMessage == null) {
            success += 1;
          } else {
            failed += 1;
            failures.add(
              _BulkFailureItem(
                record: record,
                message: provider.errorMessage ?? 'Unknown failure',
              ),
            );
          }
        }
      },
    );
    _showBulkResult(
      actionLabel: 'Unlink',
      successCount: success,
      failedCount: failed,
      skippedCount: skipped,
    );
    if (failures.isNotEmpty) {
      await _showBulkFailuresDialog(
        actionLabel: 'Unlink',
        failures: failures,
        onRetryFailed: () => _bulkUnlink(
          failures.map((item) => item.record).toList(growable: false),
        ),
      );
    }
  }

  Future<void> _bulkDelete(List<MaterialRecord> records) async {
    if (_isBulkRunning || records.isEmpty) {
      return;
    }
    final auth = context.read<AuthProvider>();
    if (!auth.can('inventory.delete') && auth.can('inventory.request_delete')) {
      await _bulkRequestDelete(records);
      return;
    }
    if (!auth.can('inventory.delete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to delete records.'),
        ),
      );
      return;
    }
    final count = records.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count selected record${count == 1 ? '' : 's'}?'),
        content: const Text(
          'This action cannot be undone. Parent records will also remove their child records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final provider = context.read<InventoryProvider>();
    var success = 0;
    var failed = 0;
    final deletedBarcodes = <String>{};
    final failures = <_BulkFailureItem>[];
    await _runBulkOperation(
      label: 'Deleting records...',
      run: () async {
        for (var index = 0; index < records.length; index += 1) {
          final record = records[index];
          _setBulkProgress('Deleting ${index + 1}/${records.length}');
          provider.clearError();
          await provider.deleteMaterial(record.barcode);
          if (provider.errorMessage == null) {
            success += 1;
            deletedBarcodes.add(record.barcode);
          } else {
            failed += 1;
            failures.add(
              _BulkFailureItem(
                record: record,
                message: provider.errorMessage ?? 'Unknown failure',
              ),
            );
          }
        }
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedBarcodes.removeWhere(deletedBarcodes.contains);
    });
    _showBulkResult(
      actionLabel: 'Delete',
      successCount: success,
      failedCount: failed,
    );
    if (failures.isNotEmpty) {
      await _showBulkFailuresDialog(
        actionLabel: 'Delete',
        failures: failures,
        onRetryFailed: () => _bulkDelete(
          failures.map((item) => item.record).toList(growable: false),
        ),
      );
    }
  }

  Future<void> _bulkRequestDelete(List<MaterialRecord> records) async {
    final controller = TextEditingController();
    final requested = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request deletion for ${records.length} records?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'This reason will be attached to every selected record.',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Request delete'),
          ),
        ],
      ),
    );
    if (requested != true || !mounted) {
      controller.dispose();
      return;
    }
    final auth = context.read<AuthProvider>();
    var success = 0;
    for (final record in records) {
      final ok = await auth.requestDelete(
        entityType: 'material',
        entityId: record.barcode,
        entityLabel: record.name,
        reason: controller.text,
      );
      if (ok) {
        success += 1;
      }
    }
    controller.dispose();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sent $success delete request${success == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  Future<void> _runBulkOperation({
    required String label,
    required Future<void> Function() run,
  }) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBulkRunning = true;
      _bulkProgressLabel = label;
    });
    try {
      await run();
    } finally {
      if (mounted) {
        setState(() {
          _isBulkRunning = false;
          _bulkProgressLabel = null;
        });
      }
    }
  }

  void _setBulkProgress(String value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _bulkProgressLabel = value;
    });
  }

  void _showBulkResult({
    required String actionLabel,
    required int successCount,
    required int failedCount,
    int skippedCount = 0,
  }) {
    if (!mounted) {
      return;
    }
    if (successCount == 0 && failedCount == 0 && skippedCount == 0) {
      return;
    }

    final parts = <String>[];
    if (successCount > 0) {
      parts.add('$successCount succeeded');
    }
    if (failedCount > 0) {
      parts.add('$failedCount failed');
    }
    if (skippedCount > 0) {
      parts.add('$skippedCount skipped');
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$actionLabel: ${parts.join(', ')}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: failedCount > 0
            ? const Color(0xFFB33A3A)
            : const Color(0xFF2E7D32),
      ),
    );
  }

  Future<void> _showBulkFailuresDialog({
    required String actionLabel,
    required List<_BulkFailureItem> failures,
    required VoidCallback onRetryFailed,
  }) async {
    if (!mounted || failures.isEmpty) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '$actionLabel failed for ${failures.length} record${failures.length == 1 ? '' : 's'}',
        ),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: failures.length,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final failure = failures[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failure.record.barcode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failure.record.name,
                      style: const TextStyle(
                        color: Color(0xFF525D6F),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failure.message,
                      style: const TextStyle(
                        color: Color(0xFFB33A3A),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onRetryFailed();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry Failed'),
          ),
        ],
      ),
    );
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  String _movementTypeLabel(InventoryMovementType type) {
    switch (type) {
      case InventoryMovementType.receive:
        return 'Receive';
      case InventoryMovementType.issue:
        return 'Issue';
      case InventoryMovementType.transfer:
        return 'Transfer';
      case InventoryMovementType.adjust:
        return 'Adjust';
      case InventoryMovementType.reserve:
        return 'Reserve';
      case InventoryMovementType.release:
        return 'Release';
      case InventoryMovementType.consume:
        return 'Consume';
      case InventoryMovementType.split:
        return 'Split';
      case InventoryMovementType.merge:
        return 'Merge';
    }
  }
}

class _MovementComposerDraft {
  const _MovementComposerDraft({
    required this.materialBarcode,
    required this.qty,
    this.fromLocationId,
    this.toLocationId,
    this.reasonCode,
    this.referenceType,
    this.referenceId,
    this.lotCode,
  });

  final String materialBarcode;
  final double qty;
  final String? fromLocationId;
  final String? toLocationId;
  final String? reasonCode;
  final String? referenceType;
  final String? referenceId;
  final String? lotCode;
}

class _InventoryMovementComposerDialog extends StatefulWidget {
  const _InventoryMovementComposerDialog({
    required this.movementType,
    required this.materials,
    required this.initialBarcode,
  });

  final InventoryMovementType movementType;
  final List<MaterialRecord> materials;
  final String initialBarcode;

  @override
  State<_InventoryMovementComposerDialog> createState() =>
      _InventoryMovementComposerDialogState();
}

class _InventoryMovementComposerDialogState
    extends State<_InventoryMovementComposerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qtyController;
  late final TextEditingController _fromLocationController;
  late final TextEditingController _toLocationController;
  late final TextEditingController _reasonController;
  late final TextEditingController _referenceTypeController;
  late final TextEditingController _referenceIdController;
  late final TextEditingController _lotCodeController;
  late String _selectedBarcode;

  @override
  void initState() {
    super.initState();
    _selectedBarcode = widget.initialBarcode;
    _qtyController = TextEditingController(text: '1');
    _fromLocationController = TextEditingController();
    _toLocationController = TextEditingController();
    _reasonController = TextEditingController();
    _referenceTypeController = TextEditingController();
    _referenceIdController = TextEditingController();
    _lotCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _fromLocationController.dispose();
    _toLocationController.dispose();
    _reasonController.dispose();
    _referenceTypeController.dispose();
    _referenceIdController.dispose();
    _lotCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_movementTypeLabel(widget.movementType)} Stock',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedBarcode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Material',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.materials
                      .map(
                        (material) => DropdownMenuItem<String>(
                          value: material.barcode,
                          child: Text('${material.name} (${material.barcode})'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedBarcode = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (widget.movementType == InventoryMovementType.transfer) ...[
                  TextFormField(
                    controller: _fromLocationController,
                    decoration: const InputDecoration(
                      labelText: 'From Location',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _toLocationController,
                    decoration: const InputDecoration(
                      labelText: 'To Location',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  TextFormField(
                    controller: _toLocationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _lotCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Lot Code (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason Code (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _referenceTypeController,
                        decoration: const InputDecoration(
                          labelText: 'Reference Type',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _referenceIdController,
                        decoration: const InputDecoration(
                          labelText: 'Reference ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    AppButton(
                      label: _movementTypeLabel(widget.movementType),
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final qty = double.parse(_qtyController.text.trim());
    Navigator.of(context).pop(
      _MovementComposerDraft(
        materialBarcode: _selectedBarcode,
        qty: qty,
        fromLocationId: _normalized(_fromLocationController.text),
        toLocationId: _normalized(_toLocationController.text),
        reasonCode: _normalized(_reasonController.text),
        referenceType: _normalized(_referenceTypeController.text),
        referenceId: _normalized(_referenceIdController.text),
        lotCode: _normalized(_lotCodeController.text),
      ),
    );
  }

  String? _normalized(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _movementTypeLabel(InventoryMovementType type) {
    switch (type) {
      case InventoryMovementType.receive:
        return 'Receive';
      case InventoryMovementType.issue:
        return 'Issue';
      case InventoryMovementType.transfer:
        return 'Transfer';
      case InventoryMovementType.adjust:
        return 'Adjust';
      case InventoryMovementType.reserve:
        return 'Reserve';
      case InventoryMovementType.release:
        return 'Release';
      case InventoryMovementType.consume:
        return 'Consume';
      case InventoryMovementType.split:
        return 'Split';
      case InventoryMovementType.merge:
        return 'Merge';
    }
  }
}

class _InventoryWorkspaceHeader extends StatelessWidget {
  static const List<PMFigmaSegmentOption> _segments = <PMFigmaSegmentOption>[
    PMFigmaSegmentOption(key: 'group', label: 'Groups'),
    PMFigmaSegmentOption(key: 'item', label: 'Items'),
  ];

  const _InventoryWorkspaceHeader({
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onPrimaryCreateTap,
    required this.onQuickCreateSelected,
    required this.onAddStock,
    required this.onReceiveStock,
    required this.onTransferStock,
    required this.onAdjustStock,
  });

  final _InventoryViewMode viewMode;
  final ValueChanged<_InventoryViewMode> onViewModeChanged;
  final VoidCallback onPrimaryCreateTap;
  final ValueChanged<_InventoryQuickCreateAction> onQuickCreateSelected;
  final VoidCallback onAddStock;
  final VoidCallback onReceiveStock;
  final VoidCallback onTransferStock;
  final VoidCallback onAdjustStock;

  @override
  Widget build(BuildContext context) {
    final segmented = PMFigmaSegmentedControl(
      value: viewMode == _InventoryViewMode.groups ? 'group' : 'item',
      segments: _segments,
      semanticLabel: 'Inventory group and item segmented control',
      onChanged: (value) {
        onViewModeChanged(
          value == 'group'
              ? _InventoryViewMode.groups
              : _InventoryViewMode.items,
        );
      },
    );

    final secondaryActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _InventoryQuickCreateMenuButton(
          label: 'Create',
          onPrimaryTap: onPrimaryCreateTap,
          onSelected: onQuickCreateSelected,
        ),
        const SizedBox(width: 10),
        _InventoryStockActionsButton(
          onReceiveStock: onReceiveStock,
          onTransferStock: onTransferStock,
          onAdjustStock: onAdjustStock,
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        secondaryActions,
        const SizedBox(width: 20),
        _InventoryToolbarButton(
          label: '+ Add Stock',
          onTap: onAddStock,
          isPrimary: true,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              segmented,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ],
          );
        }

        if (constraints.maxWidth < 1320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: segmented),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            segmented,
            const SizedBox(width: 14),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InventoryToolbarButton extends StatelessWidget {
  const _InventoryToolbarButton({
    required this.label,
    required this.onTap,
    required this.isPrimary,
  });

  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final minWidth = switch (label) {
      '+ Add Stock' => 140.0,
      _ => 120.0,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: _inventoryHoverColor,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 44,
          constraints: BoxConstraints(minWidth: minWidth),
          padding: EdgeInsets.symmetric(horizontal: isPrimary ? 24 : 16),
          decoration: BoxDecoration(
            gradient: isPrimary ? SoftErpTheme.accentGradient : null,
            color: isPrimary ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary ? SoftErpTheme.accentDark : SoftErpTheme.border,
            ),
            boxShadow: isPrimary
                ? SoftErpTheme.raisedShadow
                : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : SoftErpTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryStockActionsButton extends StatelessWidget {
  const _InventoryStockActionsButton({
    required this.onReceiveStock,
    required this.onTransferStock,
    required this.onAdjustStock,
  });

  final VoidCallback onReceiveStock;
  final VoidCallback onTransferStock;
  final VoidCallback onAdjustStock;

  Future<void> _showActionsMenu(BuildContext context) async {
    final buttonRenderBox = context.findRenderObject() as RenderBox?;
    final overlayRenderBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (buttonRenderBox == null || overlayRenderBox == null) {
      return;
    }

    final topLeft = buttonRenderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayRenderBox,
    );
    final bottomRight = buttonRenderBox.localToGlobal(
      buttonRenderBox.size.bottomRight(Offset.zero),
      ancestor: overlayRenderBox,
    );

    final selected = await showMenu<_InventoryStockAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlayRenderBox.size,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: SoftErpTheme.border),
      ),
      color: SoftErpTheme.cardSurface,
      items: const [
        PopupMenuItem<_InventoryStockAction>(
          value: _InventoryStockAction.receive,
          height: 42,
          child: Text('Receive'),
        ),
        PopupMenuItem<_InventoryStockAction>(
          value: _InventoryStockAction.transfer,
          height: 42,
          child: Text('Transfer'),
        ),
        PopupMenuItem<_InventoryStockAction>(
          value: _InventoryStockAction.adjust,
          height: 42,
          child: Text('Adjust'),
        ),
      ],
    );

    if (selected == null) {
      return;
    }
    switch (selected) {
      case _InventoryStockAction.receive:
        onReceiveStock();
      case _InventoryStockAction.transfer:
        onTransferStock();
      case _InventoryStockAction.adjust:
        onAdjustStock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showActionsMenu(context),
        borderRadius: BorderRadius.circular(14),
        hoverColor: _inventoryHoverColor,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 44,
          constraints: const BoxConstraints(minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SoftErpTheme.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Warehouse ▾',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryQuickCreateMenuButton extends StatelessWidget {
  const _InventoryQuickCreateMenuButton({
    required this.label,
    required this.onPrimaryTap,
    required this.onSelected,
  });

  final String label;
  final VoidCallback onPrimaryTap;
  final ValueChanged<_InventoryQuickCreateAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPrimaryTap,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              hoverColor: _inventoryHoverColor,
              child: Container(
                constraints: const BoxConstraints(minWidth: 100),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, color: SoftErpTheme.border),
          PopupMenuButton<_InventoryQuickCreateAction>(
            tooltip: 'Create options',
            onSelected: onSelected,
            color: SoftErpTheme.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: SoftErpTheme.border),
            ),
            itemBuilder: (context) => const [
              PopupMenuItem<_InventoryQuickCreateAction>(
                value: _InventoryQuickCreateAction.group,
                height: 42,
                child: Text('Create Group'),
              ),
              PopupMenuItem<_InventoryQuickCreateAction>(
                value: _InventoryQuickCreateAction.item,
                height: 42,
                child: Text('Create Item'),
              ),
            ],
            child: Container(
              width: 42,
              alignment: Alignment.center,
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryControlsRow extends StatelessWidget {
  const _InventoryControlsRow({
    required this.supplierFilter,
    required this.typeFilter,
    required this.kindFilter,
    required this.suppliers,
    required this.types,
    required this.selectedCount,
    required this.filteredCount,
    required this.listingMode,
    required this.onSupplierSelected,
    required this.onTypeSelected,
    required this.onKindSelected,
    required this.onClearSelection,
    required this.onSelectAllFiltered,
    required this.onClearFilters,
    required this.onListingModeChanged,
  });

  final String? supplierFilter;
  final String? typeFilter;
  final String? kindFilter;
  final List<String> suppliers;
  final List<String> types;
  final int selectedCount;
  final int filteredCount;
  final _InventoryListingMode listingMode;
  final ValueChanged<String?> onSupplierSelected;
  final ValueChanged<String?> onTypeSelected;
  final ValueChanged<String?> onKindSelected;
  final VoidCallback onClearSelection;
  final VoidCallback onSelectAllFiltered;
  final VoidCallback onClearFilters;
  final ValueChanged<_InventoryListingMode> onListingModeChanged;

  @override
  Widget build(BuildContext context) {
    final filters = Wrap(
      spacing: 0,
      runSpacing: 8,
      children: [
        _InventoryFilterChipButton<String?>(
          label: 'Party',
          valueLabel: supplierFilter ?? 'All',
          isFirst: true,
          values: [
            const _MenuValue<String?>(value: null, label: 'All'),
            ...suppliers.map(
              (value) => _MenuValue<String?>(value: value, label: value),
            ),
          ],
          onSelected: onSupplierSelected,
        ),
        _InventoryFilterChipButton<String?>(
          label: 'Item',
          valueLabel: typeFilter ?? 'Anytime',
          values: [
            const _MenuValue<String?>(value: null, label: 'Any'),
            ...types.map(
              (value) => _MenuValue<String?>(value: value, label: value),
            ),
          ],
          onSelected: onTypeSelected,
        ),
        _InventoryFilterChipButton<String?>(
          label: 'Status',
          valueLabel: switch (kindFilter) {
            'parent' => 'Groups',
            'child' => 'Items',
            _ => 'All',
          },
          isLast: true,
          values: const [
            _MenuValue<String?>(value: null, label: 'All'),
            _MenuValue<String?>(value: 'parent', label: 'Groups'),
            _MenuValue<String?>(value: 'child', label: 'Items'),
          ],
          onSelected: onKindSelected,
        ),
      ],
    );

    final trailingActions = <Widget>[
      if (selectedCount > 0) ...[
        Text(
          '$selectedCount Selected',
          style: const TextStyle(
            color: Color(0xFF5E6572),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        InkWell(
          onTap: onClearSelection,
          hoverColor: _inventoryHoverColor,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7FB),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFF6A6A6A),
            ),
          ),
        ),
      ],
      _ActionChip(
        label: 'All',
        icon: Icons.inventory_2_outlined,
        isActive: listingMode == _InventoryListingMode.all,
        onTap: () => onListingModeChanged(_InventoryListingMode.all),
      ),
      _ActionChip(
        label: 'Recently Added',
        icon: Icons.schedule_rounded,
        isActive: listingMode == _InventoryListingMode.recentFirst,
        onTap: () => onListingModeChanged(_InventoryListingMode.recentFirst),
      ),
      if (filteredCount > 0 && selectedCount < filteredCount)
        _ActionChip(
          label: 'Select All ($filteredCount)',
          icon: Icons.select_all_rounded,
          onTap: onSelectAllFiltered,
        ),
      _ActionChip(
        label: 'Clear Filters',
        icon: Icons.filter_alt_off_outlined,
        onTap: onClearFilters,
      ),
    ];
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var index = 0; index < trailingActions.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          trailingActions[index],
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: filters),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: filters),
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InventoryFilterChipButton<T> extends StatelessWidget {
  const _InventoryFilterChipButton({
    required this.label,
    required this.valueLabel,
    required this.values,
    required this.onSelected,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String valueLabel;
  final List<_MenuValue<T>> values;
  final ValueChanged<T> onSelected;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.horizontal(
      left: Radius.circular(isFirst ? 8 : 0),
      right: Radius.circular(isLast ? 8 : 0),
    );
    return InkWell(
      borderRadius: borderRadius,
      onTap: () async {
        final selected = await showSearchableSelectDialog<T>(
          context: context,
          title: label,
          searchHintText: 'Search $label',
          options: values
              .map(
                (entry) => SearchableSelectOption<T>(
                  value: entry.value,
                  label: entry.label,
                ),
              )
              .toList(growable: false),
        );
        if (selected != null) {
          onSelected(selected.value);
        }
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xF7FFFFFF),
          border: Border.all(color: const Color(0xFFE4E7F3)),
          borderRadius: borderRadius,
          boxShadow: SoftErpTheme.insetShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFirst) ...[
              const Icon(
                Icons.tune_rounded,
                size: 14,
                color: SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              '$label: ',
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Flexible(
              child: Text(
                valueLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: SoftErpTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: _inventoryHoverColor,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFEEF0FF) : const Color(0xFFF7F7FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFC9D0FB)
                  : const Color(0xFFE4E7F2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive
                    ? SoftErpTheme.accentDark
                    : const Color(0xFF60677A),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? SoftErpTheme.accentDark
                      : const Color(0xFF484848),
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryBulkActionBar extends StatelessWidget {
  const _InventoryBulkActionBar({
    required this.selectedCount,
    required this.isBusy,
    required this.isRequestDelete,
    required this.onClearSelection,
    required this.onResetTrace,
    required this.onUnlink,
    required this.onDelete,
    this.progressLabel,
    this.onOpenSingleDetails,
  });

  final int selectedCount;
  final bool isBusy;
  final bool isRequestDelete;
  final VoidCallback onClearSelection;
  final String? progressLabel;
  final VoidCallback? onOpenSingleDetails;
  final VoidCallback onResetTrace;
  final VoidCallback onUnlink;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: SoftErpTheme.accentSurface,
      radius: SoftErpTheme.radiusMd,
      strongBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: SoftErpTheme.cardSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: SoftErpTheme.border),
                ),
                child: Text(
                  '$selectedCount Selected',
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onOpenSingleDetails != null)
                _InventoryBulkActionButton(
                  label: 'Open',
                  icon: Icons.open_in_new_rounded,
                  isDisabled: isBusy,
                  onTap: onOpenSingleDetails!,
                ),
              _InventoryBulkActionButton(
                label: 'Reset Trace',
                icon: Icons.restore_rounded,
                isDisabled: isBusy,
                onTap: onResetTrace,
              ),
              _InventoryBulkActionButton(
                label: 'Unlink',
                icon: Icons.link_off_rounded,
                isDisabled: isBusy,
                onTap: onUnlink,
              ),
              _InventoryBulkActionButton(
                label: isRequestDelete ? 'Request Delete' : 'Delete',
                icon: Icons.delete_outline_rounded,
                isDestructive: true,
                isDisabled: isBusy,
                onTap: onDelete,
              ),
              _InventoryBulkActionButton(
                label: 'Clear',
                icon: Icons.close_rounded,
                isDisabled: isBusy,
                onTap: onClearSelection,
              ),
            ],
          ),
          if (isBusy) ...[
            const SizedBox(height: 10),
            Text(
              progressLabel ?? 'Processing bulk action...',
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            const LinearProgressIndicator(
              minHeight: 4,
              color: Color(0xFF6B53EE),
              backgroundColor: SoftErpTheme.accentSoft,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
          ],
        ],
      ),
    );
  }
}

class _InventoryBulkActionButton extends StatelessWidget {
  const _InventoryBulkActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
    this.isDisabled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final foreground = isDestructive
        ? SoftErpTheme.dangerText
        : SoftErpTheme.textPrimary;
    final effectiveForeground = isDisabled
        ? const Color(0xFFA3AAB7)
        : foreground;
    return InkWell(
      onTap: isDisabled ? null : onTap,
      hoverColor: _inventoryHoverColor,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: isDisabled ? 0.7 : 1,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDestructive
                  ? const Color(0xFFF0B4B4)
                  : SoftErpTheme.border,
            ),
            boxShadow: SoftErpTheme.insetShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: effectiveForeground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: effectiveForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _InventoryTable extends StatefulWidget {
  const _InventoryTable({
    required this.rows,
    required this.viewMode,
    required this.sortColumn,
    required this.sortAscending,
    required this.groupsProvider,
    required this.itemsProvider,
    required this.selectedBarcodes,
    required this.pinnedBarcodes,
    required this.expandedParents,
    required this.isRequestDelete,
    required this.onToggleSelection,
    required this.onToggleExpanded,
    required this.onTogglePinned,
    required this.onHeaderSortRequested,
    required this.onOpenDetails,
    required this.onReceive,
    required this.onAddSubGroup,
    required this.onEdit,
    required this.onDelete,
    required this.onLinkGroup,
    required this.onLinkItem,
    required this.onUnlink,
  });

  final List<_InventoryRowEntry> rows;
  final _InventoryViewMode viewMode;
  final _InventorySortColumn? sortColumn;
  final bool sortAscending;
  final GroupsProvider groupsProvider;
  final ItemsProvider itemsProvider;
  final Set<String> selectedBarcodes;
  final Set<String> pinnedBarcodes;
  final Set<String> expandedParents;
  final bool isRequestDelete;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<String> onTogglePinned;
  final void Function(_InventorySortColumn?, bool) onHeaderSortRequested;
  final ValueChanged<MaterialRecord> onOpenDetails;
  final ValueChanged<MaterialRecord> onReceive;
  final ValueChanged<MaterialRecord> onAddSubGroup;
  final ValueChanged<MaterialRecord> onEdit;
  final ValueChanged<MaterialRecord> onDelete;
  final ValueChanged<MaterialRecord> onLinkGroup;
  final ValueChanged<MaterialRecord> onLinkItem;
  final ValueChanged<MaterialRecord> onUnlink;

  @override
  State<_InventoryTable> createState() => _InventoryTableState();
}

class _InventoryTableState extends State<_InventoryTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _verticalController.addListener(_onVerticalScroll);
  }

  @override
  void dispose() {
    _verticalController.removeListener(_onVerticalScroll);
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _onVerticalScroll() {
    _setScrolledState(_verticalController.offset > 2);
  }

  void _setScrolledState(bool value) {
    if (_isScrolled == value || !mounted) {
      return;
    }
    setState(() => _isScrolled = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return const AppEmptyState(
        title: 'No materials found',
        message:
            'Try a different search or filter, or create a new inventory group to populate this workspace.',
        icon: Icons.inventory_2_outlined,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _InventoryTableMetrics.fromViewportWidth(
          constraints.maxWidth,
        );
        final minViewportWidth = constraints.maxWidth;
        final totalTableWidth = math.max(
          metrics.dataWidth + metrics.actionsWidth,
          minViewportWidth,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minViewportWidth),
                child: SizedBox(
                  width: totalTableWidth,
                  child: _InventoryTableHeader(
                    viewMode: widget.viewMode,
                    metrics: metrics,
                    sortColumn: widget.sortColumn,
                    sortAscending: widget.sortAscending,
                    onSortRequested: widget.onHeaderSortRequested,
                    includeActions: true,
                    showShadow: _isScrolled,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: minViewportWidth),
                  child: SizedBox(
                    width: totalTableWidth,
                    child: ListView.separated(
                      controller: _verticalController,
                      itemCount: widget.rows.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: metrics.rowGap),
                      itemBuilder: (context, index) {
                        final entry = widget.rows[index];
                        final record = entry.record;
                        final isSelectable = record.id != null;
                        final rowTap = !entry.opensDetails
                            ? (entry.canExpand
                                  ? () =>
                                        widget.onToggleExpanded(record.barcode)
                                  : () {})
                            : () => widget.onOpenDetails(record);
                        return _InventoryMainDataRow(
                          record: record,
                          entry: entry,
                          viewMode: widget.viewMode,
                          metrics: metrics,
                          isSelected:
                              isSelectable &&
                              widget.selectedBarcodes.contains(record.barcode),
                          isPinned: widget.pinnedBarcodes.contains(
                            record.barcode,
                          ),
                          isStriped: index.isOdd,
                          isRequestDelete: widget.isRequestDelete,
                          onTap: rowTap,
                          onLongPress: isSelectable
                              ? () => widget.onToggleSelection(record.barcode)
                              : null,
                          onSecondaryTapDown: (details) =>
                              _showRowContextMenu(context, details, record),
                          onExpandToggle: entry.canExpand
                              ? () => widget.onToggleExpanded(record.barcode)
                              : null,
                          onReceive: () => widget.onReceive(record),
                          showOpenAction: entry.opensDetails,
                          onAddSubGroup: () => widget.onAddSubGroup(record),
                          onEdit: () => widget.onEdit(record),
                          onDelete: () => widget.onDelete(record),
                          onLinkGroup: () => widget.onLinkGroup(record),
                          onLinkItem: () => widget.onLinkItem(record),
                          onUnlink: () => widget.onUnlink(record),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRowContextMenu(
    BuildContext context,
    TapDownDetails details,
    MaterialRecord record,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) {
      return;
    }
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          0,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      color: SoftErpTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SoftErpTheme.border),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'pin',
          height: 40,
          child: Text(
            widget.pinnedBarcodes.contains(record.barcode) ? 'Unpin' : 'Pin',
          ),
        ),
      ],
    );
    if (selected == 'pin') {
      widget.onTogglePinned(record.barcode);
    }
  }
}

class _InventoryTableHeader extends StatelessWidget {
  const _InventoryTableHeader({
    required this.viewMode,
    required this.metrics,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSortRequested,
    this.includeActions = true,
    this.showShadow = false,
  });

  final _InventoryViewMode viewMode;
  final _InventoryTableMetrics metrics;
  final _InventorySortColumn? sortColumn;
  final bool sortAscending;
  final void Function(_InventorySortColumn?, bool) onSortRequested;
  final bool includeActions;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      height: metrics.headerHeight,
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      color: const Color(0xFFEEF0F9),
      radius: 22,
      elevated: showShadow,
      strongBorder: false,
      child: Row(
        children: [
          _HeaderCell(
            viewMode == _InventoryViewMode.groups ? 'Group Name' : 'Item Name',
            width: viewMode == _InventoryViewMode.groups
                ? metrics.nameWidth + metrics.barcodeWidth
                : metrics.nameWidth,
            metrics: metrics,
            onSortRequested: onSortRequested,
            sortColumn: _InventorySortColumn.name,
            activeSortColumn: sortColumn,
            sortAscending: sortAscending,
          ),
          if (viewMode != _InventoryViewMode.groups)
            _HeaderCell(
              'Item ID',
              width: metrics.barcodeWidth,
              metrics: metrics,
              onSortRequested: onSortRequested,
              sortColumn: _InventorySortColumn.id,
              activeSortColumn: sortColumn,
              sortAscending: sortAscending,
            ),
          _HeaderCell(
            'Stock',
            width: metrics.stockWidth,
            metrics: metrics,
            onSortRequested: onSortRequested,
            sortColumn: _InventorySortColumn.stock,
            activeSortColumn: sortColumn,
            sortAscending: sortAscending,
          ),
          _HeaderCell(
            'Last Activity',
            width: metrics.dateWidth,
            metrics: metrics,
            onSortRequested: onSortRequested,
            sortColumn: _InventorySortColumn.activity,
            activeSortColumn: sortColumn,
            sortAscending: sortAscending,
          ),
          _HeaderCell(
            'Created By',
            width: metrics.createdByWidth,
            metrics: metrics,
            onSortRequested: onSortRequested,
            sortColumn: _InventorySortColumn.createdBy,
            activeSortColumn: sortColumn,
            sortAscending: sortAscending,
          ),
          _HeaderCell(
            'Status',
            width: metrics.statusWidth,
            metrics: metrics,
            onSortRequested: onSortRequested,
            sortColumn: _InventorySortColumn.status,
            activeSortColumn: sortColumn,
            sortAscending: sortAscending,
          ),
          if (includeActions)
            _HeaderCell(
              'Actions',
              width: metrics.actionsWidth,
              metrics: metrics,
            ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatefulWidget {
  const _HeaderCell(
    this.label, {
    required this.width,
    required this.metrics,
    this.sortColumn,
    this.activeSortColumn,
    this.sortAscending = true,
    this.onSortRequested,
  });

  final String label;
  final double width;
  final _InventoryTableMetrics metrics;
  final _InventorySortColumn? sortColumn;
  final _InventorySortColumn? activeSortColumn;
  final bool sortAscending;
  final void Function(_InventorySortColumn?, bool)? onSortRequested;

  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final onSortRequested = widget.onSortRequested;
    final sortColumn = widget.sortColumn;
    if (sortColumn == null || onSortRequested == null) {
      return SizedBox(
        width: widget.width,
        child: Text(
          widget.label,
          style: _inventoryManropeStyle(
            color: const Color(0xFF454545),
            size: widget.metrics.headerFontSize,
            weight: FontWeight.w500,
          ),
        ),
      );
    }

    final isActive = widget.activeSortColumn == sortColumn;
    final nextAscending = isActive ? !widget.sortAscending : true;
    final directionLabel = isActive
        ? (widget.sortAscending ? 'ascending' : 'descending')
        : 'not sorted';
    final nextDirectionLabel = nextAscending ? 'ascending' : 'descending';
    final showArrow = isActive || _isHovered;
    final arrowIcon = isActive
        ? (widget.sortAscending
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded)
        : Icons.swap_vert_rounded;

    return SizedBox(
      width: widget.width,
      child: Tooltip(
        waitDuration: const Duration(milliseconds: 350),
        message:
            '${widget.label}: $directionLabel. Click to sort $nextDirectionLabel.',
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: () => onSortRequested(sortColumn, nextAscending),
            borderRadius: BorderRadius.circular(999),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: _inventoryManropeStyle(
                        color: isActive
                            ? const Color(0xFF5145E5)
                            : const Color(0xFF454545),
                        size: widget.metrics.headerFontSize,
                        weight: isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: showArrow ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Icon(
                        arrowIcon,
                        size: 14,
                        color: isActive
                            ? const Color(0xFF5145E5)
                            : const Color(0xFF6B7280),
                      ),
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

class _InventoryMainDataRow extends StatefulWidget {
  const _InventoryMainDataRow({
    required this.record,
    required this.entry,
    required this.viewMode,
    required this.metrics,
    required this.isSelected,
    required this.isPinned,
    required this.isStriped,
    required this.isRequestDelete,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTapDown,
    required this.onReceive,
    required this.showOpenAction,
    required this.onAddSubGroup,
    required this.onEdit,
    required this.onDelete,
    required this.onLinkGroup,
    required this.onLinkItem,
    required this.onUnlink,
    this.onExpandToggle,
  });

  final MaterialRecord record;
  final _InventoryRowEntry entry;
  final _InventoryViewMode viewMode;
  final _InventoryTableMetrics metrics;
  final bool isSelected;
  final bool isPinned;
  final bool isStriped;
  final bool isRequestDelete;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<TapDownDetails> onSecondaryTapDown;
  final VoidCallback onReceive;
  final bool showOpenAction;
  final VoidCallback onAddSubGroup;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLinkGroup;
  final VoidCallback onLinkItem;
  final VoidCallback onUnlink;
  final VoidCallback? onExpandToggle;

  @override
  State<_InventoryMainDataRow> createState() => _InventoryMainDataRowState();
}

class _InventoryMainDataRowState extends State<_InventoryMainDataRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isStriped
        ? const Color(0xFFF9FBFF).withValues(alpha: 0.8)
        : SoftErpTheme.cardSurface.withValues(alpha: 0.8);
    const hoverColor = Color(0xFFFFFFFF);
    final selectedColor = widget.entry.depth == 0 && widget.entry.isExpanded
        ? const Color(0xFFF2EFFF)
        : const Color(0xFFF1F5FF);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onLongPress,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SoftRowCard(
            isSelected:
                widget.isSelected ||
                (widget.entry.depth == 0 && widget.entry.isExpanded),
            onTap: widget.onTap,
            baseColor: baseColor,
            hoverColor: hoverColor,
            selectedColor: selectedColor,
            child: SizedBox(
              height: widget.metrics.rowHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.metrics.horizontalPadding,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: widget.viewMode == _InventoryViewMode.groups
                          ? widget.metrics.nameWidth +
                                widget.metrics.barcodeWidth
                          : widget.metrics.nameWidth,
                      child: _InventoryNameCell(
                        record: widget.record,
                        entry: widget.entry,
                        metrics: widget.metrics,
                        isPinned: widget.isPinned,
                        onExpandToggle: widget.onExpandToggle,
                      ),
                    ),
                    if (widget.viewMode != _InventoryViewMode.groups)
                      _DataCell(
                        _displayPrimaryId(widget.entry),
                        width: widget.metrics.barcodeWidth,
                        metrics: widget.metrics,
                      ),
                    _DataCell(
                      _displayStock(widget.record),
                      width: widget.metrics.stockWidth,
                      metrics: widget.metrics,
                    ),
                    _DataCell(
                      _activityDate(widget.record),
                      width: widget.metrics.dateWidth,
                      metrics: widget.metrics,
                    ),
                    _DataCell(
                      widget.record.createdBy.ifEmpty('Demo Admin'),
                      width: widget.metrics.createdByWidth,
                      metrics: widget.metrics,
                    ),
                    SizedBox(
                      width: widget.metrics.statusWidth,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _InventoryStatusBadge(
                          record: widget.record,
                          metrics: widget.metrics,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: widget.metrics.actionsWidth,
                      child: _InventoryActionsCell(
                        record: widget.record,
                        metrics: widget.metrics,
                        hovered: _hovered,
                        isSelected: widget.isSelected,
                        isStriped: widget.isStriped,
                        isRequestDelete: widget.isRequestDelete,
                        onTap: widget.onTap,
                        onReceive: widget.onReceive,
                        showOpenAction: widget.showOpenAction,
                        onAddSubGroup: widget.onAddSubGroup,
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                        onLinkGroup: widget.onLinkGroup,
                        onLinkItem: widget.onLinkItem,
                        onUnlink: widget.onUnlink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day-$month-${value.year}';
  }

  String _activityDate(MaterialRecord value) {
    return _formatDate(value.lastScannedAt ?? value.updatedAt);
  }

  String _displayPrimaryId(_InventoryRowEntry entry) {
    return entry.displayId ?? entry.record.barcode;
  }

  String _displayStock(MaterialRecord value) {
    if (value.displayStock.trim().isNotEmpty) {
      return value.displayStock;
    }
    return '1000 Pieces';
  }
}

class _InventoryActionsCell extends StatelessWidget {
  const _InventoryActionsCell({
    required this.record,
    required this.metrics,
    required this.hovered,
    required this.isSelected,
    required this.isStriped,
    required this.isRequestDelete,
    required this.onTap,
    required this.onReceive,
    required this.showOpenAction,
    required this.onAddSubGroup,
    required this.onEdit,
    required this.onDelete,
    required this.onLinkGroup,
    required this.onLinkItem,
    required this.onUnlink,
  });

  final MaterialRecord record;
  final _InventoryTableMetrics metrics;
  final bool hovered;
  final bool isSelected;
  final bool isStriped;
  final bool isRequestDelete;
  final VoidCallback onTap;
  final VoidCallback onReceive;
  final bool showOpenAction;
  final VoidCallback onAddSubGroup;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLinkGroup;
  final VoidCallback onLinkItem;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: _InventoryInlineRowActions(
        hovered: hovered,
        onOpen: showOpenAction ? onTap : null,
        onReceive: onReceive,
        menuAnchor: _InventoryActionsOverlayAnchor(
          triggerSize: metrics.actionButtonSize,
          canAddSubGroup:
              record.id != null &&
              (record.numberOfChildren > 0 ||
                  (record.parentBarcode ?? '').isEmpty),
          canDelete: record.id != null,
          isRequestDelete: isRequestDelete,
          onAddSubGroup: onAddSubGroup,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

class _InventoryQuickHintButton extends StatelessWidget {
  const _InventoryQuickHintButton({
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 26),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: emphasized
                ? const Color(0xFFEDF0FF)
                : const Color(0xFFF6F7FC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: emphasized ? const Color(0xFFC6CCF6) : SoftErpTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: emphasized
                  ? SoftErpTheme.accentDark
                  : SoftErpTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryInlineRowActions extends StatelessWidget {
  const _InventoryInlineRowActions({
    required this.hovered,
    required this.onOpen,
    required this.onReceive,
    required this.menuAnchor,
  });

  final bool hovered;
  final VoidCallback? onOpen;
  final VoidCallback onReceive;
  final Widget menuAnchor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showQuick = hovered && constraints.maxWidth >= 124;
        final showBothQuick = showQuick && constraints.maxWidth >= 176;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showQuick && onOpen != null)
              IgnorePointer(
                ignoring: !hovered,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: hovered ? 1 : 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _InventoryQuickHintButton(
                        label: 'Open',
                        emphasized: true,
                        onTap: onOpen!,
                      ),
                      if (showBothQuick) ...[
                        const SizedBox(width: 6),
                        _InventoryQuickHintButton(
                          label: 'Receive',
                          onTap: onReceive,
                        ),
                      ],
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            menuAnchor,
          ],
        );
      },
    );
  }
}

class _InventoryNameCell extends StatelessWidget {
  const _InventoryNameCell({
    required this.record,
    required this.entry,
    required this.metrics,
    required this.isPinned,
    this.onExpandToggle,
  });

  final MaterialRecord record;
  final _InventoryRowEntry entry;
  final _InventoryTableMetrics metrics;
  final bool isPinned;
  final VoidCallback? onExpandToggle;

  @override
  Widget build(BuildContext context) {
    final title = entry.displayName ?? record.name;
    final metadata = entry.displayMetadata ?? _metadataText(record);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: entry.depth * metrics.treeIndent),
        if (entry.canExpand)
          InkWell(
            onTap: onExpandToggle,
            hoverColor: _inventoryHoverColor,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              turns: entry.isExpanded ? 0.25 : 0,
              child: Icon(
                Icons.keyboard_arrow_right_rounded,
                size: metrics.chevronSize,
                color: const Color(0xFF5A6271),
              ),
            ),
          )
        else
          SizedBox(width: metrics.chevronSize),
        SizedBox(width: metrics.nameGap),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: title,
                waitDuration: const Duration(milliseconds: 500),
                child: Row(
                  children: [
                    if (isPinned) ...[
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: SoftErpTheme.accentDark,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _inventoryManropeStyle(
                          color: const Color(0xFF2F2F2F),
                          size: metrics.bodyFontSize,
                          weight: entry.depth == 0
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Tooltip(
                message: metadata,
                waitDuration: const Duration(milliseconds: 500),
                child: Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _inventorySegoeStyle(
                    color: const Color(0xFF7B8392),
                    size: math.max(11, metrics.bodyFontSize - 3),
                    weight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _metadataText(MaterialRecord material) {
    final parts = <String>[];
    if (material.unit.trim().isNotEmpty) {
      parts.add(material.unit.trim());
    }
    if (material.supplier.trim().isNotEmpty) {
      parts.add(material.supplier.trim());
    }
    if (material.location.trim().isNotEmpty) {
      parts.add(material.location.trim());
    }
    if (material.hasInheritanceLink) {
      parts.add(material.linkedItemId != null ? 'Linked item' : 'Linked group');
    }
    parts.add(
      material.hasBeenScanned
          ? 'Scanned ${material.scanCount}x'
          : 'Awaiting first scan',
    );
    return parts.join('  •  ');
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(this.text, {required this.width, required this.metrics});

  final String text;
  final double width;
  final _InventoryTableMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 450),
        child: Text(
          text,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _inventoryManropeStyle(
            color: const Color(0xFF3C3C3C),
            size: metrics.bodyFontSize,
            weight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _InventoryStatusBadge extends StatelessWidget {
  const _InventoryStatusBadge({required this.record, required this.metrics});

  final MaterialRecord record;
  final _InventoryTableMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = switch (_resolveState()) {
      _InventoryRecordState.awaitingScan => (
        bg: SoftErpTheme.warningBg,
        border: const Color(0xFFE9C99A),
        text: SoftErpTheme.warningText,
        label: 'Awaiting Scan',
      ),
      _InventoryRecordState.notStarted => (
        bg: SoftErpTheme.warningBg,
        border: const Color(0xFFE9C99A),
        text: SoftErpTheme.warningText,
        label: 'Not Started',
      ),
      _InventoryRecordState.inProgress => (
        bg: SoftErpTheme.infoBg,
        border: const Color(0xFFA8C3FF),
        text: SoftErpTheme.infoText,
        label: 'In Progress',
      ),
      _InventoryRecordState.completed => (
        bg: SoftErpTheme.successBg,
        border: const Color(0xFFA3EBCB),
        text: SoftErpTheme.successText,
        label: 'Completed',
      ),
    };

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.border),
      ),
      child: Text(
        scheme.label,
        style: TextStyle(
          color: scheme.text,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
      ),
    );
  }

  _InventoryRecordState _resolveState() {
    if (!record.hasBeenScanned) {
      return _InventoryRecordState.awaitingScan;
    }
    switch (record.workflowStatus) {
      case 'completed':
        return _InventoryRecordState.completed;
      case 'inProgress':
        return _InventoryRecordState.inProgress;
      default:
        return _InventoryRecordState.notStarted;
    }
  }
}

class _InventoryDetailSheet extends StatelessWidget {
  const _InventoryDetailSheet({required this.record});

  final MaterialRecord record;

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupsProvider>();
    final items = context.watch<ItemsProvider>();
    final inventory = context.watch<InventoryProvider>();
    final linkedGroup = groups.findById(record.linkedGroupId);
    final linkedItem = items.items
        .where((item) => item.id == record.linkedItemId)
        .firstOrNull;
    final linkedItemTitle = linkedItem == null
        ? null
        : linkedItem.displayName.trim().isEmpty
        ? linkedItem.name
        : linkedItem.displayName;
    final title = linkedItemTitle ?? linkedGroup?.name ?? record.name;
    final cachedDetail = inventory.detailFor(record.barcode);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(color: Color(0xFFFBFBFB)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF3F3F3F),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<MaterialControlTowerDetail?>(
              future: cachedDetail != null
                  ? null
                  : context
                        .read<InventoryProvider>()
                        .loadMaterialControlTowerDetail(record.barcode),
              initialData: cachedDetail,
              builder: (context, snapshot) {
                final detail = snapshot.data;
                final material = detail?.material ?? record;
                final stockPositions =
                    detail?.stockPositions ?? const <StockPosition>[];
                final movements =
                    detail?.movements ?? const <InventoryMovement>[];
                final reservations =
                    detail?.reservations ?? const <InventoryReservation>[];
                final alerts = detail?.alerts ?? const <InventoryAlert>[];
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: AppInfoPanel(
                    title: material.barcode,
                    subtitle:
                        '${_materialClassLabel(material.materialClass)} • ${_inventoryStateLabel(material.inventoryState)}',
                    headerTrailing: BarcodeTraceBadge(
                      scanCount: material.scanCount,
                    ),
                    rows: [
                      if (linkedGroup != null)
                        AppInfoRow(
                          label: 'Inherited group',
                          value: linkedGroup.name,
                        ),
                      if (linkedItem != null)
                        AppInfoRow(
                          label: 'Inherited item',
                          value: linkedItem.displayName,
                        ),
                      AppInfoRow(
                        label: 'Material class',
                        value: _materialClassLabel(material.materialClass),
                      ),
                      AppInfoRow(
                        label: 'Inventory state',
                        value: _inventoryStateLabel(material.inventoryState),
                      ),
                      AppInfoRow(
                        label: 'Procurement',
                        value: _procurementStateLabel(
                          material.procurementState,
                        ),
                      ),
                      AppInfoRow(
                        label: 'Traceability',
                        value: _traceabilityModeLabel(
                          material.traceabilityMode,
                        ),
                      ),
                      AppInfoRow(
                        label: 'Location',
                        value: material.location.ifEmpty('Unassigned'),
                      ),
                      AppInfoRow(
                        label: 'Last activity',
                        value: _formatDateTime(
                          material.lastScannedAt ?? material.updatedAt,
                        ),
                      ),
                      AppInfoRow(
                        label: 'Last scanned',
                        value: material.lastScannedAt == null
                            ? 'Awaiting first scan'
                            : _formatDateTime(material.lastScannedAt!),
                      ),
                      AppInfoRow(
                        label: 'Stock summary',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Badge(
                              label:
                                  'On hand ${_formatQuantity(material.onHand)}',
                              color: const Color(0xFFE7F8EE),
                              borderColor: const Color(0xFF9CD3AF),
                              textColor: const Color(0xFF106B36),
                            ),
                            _Badge(
                              label:
                                  'Reserved ${_formatQuantity(material.reserved)}',
                              color: const Color(0xFFFFF3E6),
                              borderColor: const Color(0xFFE9C69A),
                              textColor: const Color(0xFF8A4D00),
                            ),
                            _Badge(
                              label:
                                  'ATP ${_formatQuantity(material.availableToPromise)}',
                              color: const Color(0xFFEAF2FF),
                              borderColor: const Color(0xFFB2CAFA),
                              textColor: const Color(0xFF1F4DBA),
                            ),
                            _Badge(
                              label:
                                  'Incoming ${_formatQuantity(material.incoming)}',
                              color: const Color(0xFFF4EEFF),
                              borderColor: const Color(0xFFD4C2FF),
                              textColor: const Color(0xFF5D35B4),
                            ),
                          ],
                        ),
                      ),
                      AppInfoRow(
                        label: 'Stock by location',
                        child: _StockPositionList(
                          positions: stockPositions,
                          fallbackUnit: material.unit,
                        ),
                      ),
                      AppInfoRow(
                        label: 'Reservations',
                        child: _ReservationList(reservations: reservations),
                      ),
                      AppInfoRow(
                        label: 'Alerts',
                        child: _InventoryAlertList(alerts: alerts),
                      ),
                      AppInfoRow(
                        label: 'Linked demand',
                        value:
                            'Orders ${detail?.linkedOrderDemand.toStringAsFixed(0) ?? material.linkedOrderCount} • Pipeline ${detail?.linkedPipelineDemand.toStringAsFixed(0) ?? material.linkedPipelineCount}',
                      ),
                      ...buildMaterialBarcodeInfoRows(
                        material,
                        includeBarcodeImage: InventoryScreen._isDesktopPlatform,
                      ),
                      if (material.isParent)
                        AppInfoRow(
                          label: 'Child barcodes',
                          child: material.linkedChildBarcodes.isEmpty
                              ? const Text(
                                  'No child barcodes linked.',
                                  style: TextStyle(
                                    color: Color(0xFF717B8C),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: material.linkedChildBarcodes
                                      .map((barcode) => _Badge(label: barcode))
                                      .toList(growable: false),
                                ),
                        ),
                      AppInfoRow(
                        label: 'Movement timeline',
                        child: _InventoryMovementTimeline(
                          movements: movements,
                          fallbackUnit: material.unit,
                        ),
                      ),
                    ],
                    footer: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (InventoryScreen._isDesktopPlatform)
                          ShowBarcodeButton(material: material),
                        if (kDebugMode)
                          AppButton(
                            label: 'Reset Trace',
                            icon: Icons.restore,
                            variant: AppButtonVariant.secondary,
                            onPressed: () {
                              context.read<InventoryProvider>().resetScanTrace(
                                material.barcode,
                              );
                              Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day-$month-${value.year} $hour:$minute';
  }

  String _materialClassLabel(MaterialClass value) {
    switch (value) {
      case MaterialClass.rawMaterial:
        return 'Raw Material';
      case MaterialClass.wip:
        return 'WIP';
      case MaterialClass.finishedGood:
        return 'Finished Good';
      case MaterialClass.packaging:
        return 'Packaging';
      case MaterialClass.consumable:
        return 'Consumable';
    }
  }

  String _inventoryStateLabel(InventoryState value) {
    switch (value) {
      case InventoryState.available:
        return 'Available';
      case InventoryState.reserved:
        return 'Reserved';
      case InventoryState.inProduction:
        return 'In Production';
      case InventoryState.qualityHold:
        return 'Quality Hold';
      case InventoryState.damaged:
        return 'Damaged';
      case InventoryState.archived:
        return 'Archived';
    }
  }

  String _procurementStateLabel(ProcurementState value) {
    switch (value) {
      case ProcurementState.notOrdered:
        return 'Not Ordered';
      case ProcurementState.ordered:
        return 'Ordered';
      case ProcurementState.receivedPartial:
        return 'Received Partial';
      case ProcurementState.receivedComplete:
        return 'Received Complete';
    }
  }

  String _traceabilityModeLabel(TraceabilityMode value) {
    switch (value) {
      case TraceabilityMode.lotTracked:
        return 'Lot Tracked';
      case TraceabilityMode.serialTracked:
        return 'Serial Tracked';
      case TraceabilityMode.bulk:
        return 'Bulk';
    }
  }

  String _formatQuantity(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0001) {
      return rounded.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}

class _StockPositionList extends StatelessWidget {
  const _StockPositionList({
    required this.positions,
    required this.fallbackUnit,
  });

  final List<StockPosition> positions;
  final String fallbackUnit;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return const Text(
        'No stock positions available.',
        style: TextStyle(
          color: Color(0xFF717B8C),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    return Column(
      children: positions
          .map((position) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD9E1F3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${position.locationName} • Lot ${position.lotCode}',
                      style: const TextStyle(
                        color: Color(0xFF2F2F2F),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'On hand ${_formatQty(position.onHandQty)}',
                    style: const TextStyle(
                      color: Color(0xFF23448A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Res ${_formatQty(position.reservedQty)}',
                    style: const TextStyle(
                      color: Color(0xFF8A4D00),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    fallbackUnit.ifEmpty('Units'),
                    style: const TextStyle(
                      color: Color(0xFF6F7480),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _ReservationList extends StatelessWidget {
  const _ReservationList({required this.reservations});

  final List<InventoryReservation> reservations;

  @override
  Widget build(BuildContext context) {
    if (reservations.isEmpty) {
      return const Text(
        'No active reservations.',
        style: TextStyle(
          color: Color(0xFF717B8C),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      );
    }
    return Column(
      children: reservations
          .map(
            (reservation) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${reservation.referenceType.toUpperCase()} • ${reservation.referenceId}',
                      style: const TextStyle(
                        color: Color(0xFF2F2F2F),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _formatQty(reservation.reservedQty),
                    style: const TextStyle(
                      color: Color(0xFF8A4D00),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                    label: reservation.status,
                    color: const Color(0xFFF5F2FF),
                    borderColor: const Color(0xFFDED5FF),
                    textColor: const Color(0xFF5F4BCB),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _InventoryAlertList extends StatelessWidget {
  const _InventoryAlertList({required this.alerts});

  final List<InventoryAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final openAlerts = alerts
        .where((alert) => alert.isOpen)
        .toList(growable: false);
    if (openAlerts.isEmpty) {
      return const Text(
        'No open alerts.',
        style: TextStyle(
          color: Color(0xFF717B8C),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      );
    }
    return Column(
      children: openAlerts
          .map(
            (alert) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _alertBackground(alert.severity),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _alertBorder(alert.severity)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Badge(
                    label: _alertLabel(alert.severity),
                    color: Colors.white,
                    borderColor: _alertBorder(alert.severity),
                    textColor: _alertText(alert.severity),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.message,
                      style: const TextStyle(
                        color: Color(0xFF333A48),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _InventoryMovementTimeline extends StatelessWidget {
  const _InventoryMovementTimeline({
    required this.movements,
    required this.fallbackUnit,
  });

  final List<InventoryMovement> movements;
  final String fallbackUnit;

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return const Text(
        'No movements posted yet.',
        style: TextStyle(
          color: Color(0xFF717B8C),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    final sorted = movements.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      children: sorted
          .take(8)
          .map((movement) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: _movementColor(movement.movementType),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _movementTitle(movement.movementType),
                          style: const TextStyle(
                            color: Color(0xFF2F2F2F),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatQty(movement.qty)} ${fallbackUnit.ifEmpty('Units')} • ${movement.reasonCode?.ifEmpty('No reason') ?? 'No reason'}',
                          style: const TextStyle(
                            color: Color(0xFF717B8C),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatTimelineDate(movement.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF8C93A1),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

String _movementTitle(InventoryMovementType type) {
  switch (type) {
    case InventoryMovementType.receive:
      return 'Received stock';
    case InventoryMovementType.issue:
      return 'Issued stock';
    case InventoryMovementType.transfer:
      return 'Transferred stock';
    case InventoryMovementType.adjust:
      return 'Adjusted stock';
    case InventoryMovementType.reserve:
      return 'Reserved stock';
    case InventoryMovementType.release:
      return 'Released reservation';
    case InventoryMovementType.consume:
      return 'Consumed stock';
    case InventoryMovementType.split:
      return 'Split lot';
    case InventoryMovementType.merge:
      return 'Merged lots';
  }
}

Color _movementColor(InventoryMovementType type) {
  switch (type) {
    case InventoryMovementType.receive:
      return const Color(0xFF117B3A);
    case InventoryMovementType.issue:
    case InventoryMovementType.consume:
      return const Color(0xFFB42318);
    case InventoryMovementType.transfer:
      return const Color(0xFF1E4FB9);
    case InventoryMovementType.adjust:
      return const Color(0xFF7B3FC1);
    case InventoryMovementType.reserve:
    case InventoryMovementType.release:
      return const Color(0xFFB86B00);
    case InventoryMovementType.split:
    case InventoryMovementType.merge:
      return const Color(0xFF4B5565);
  }
}

String _formatTimelineDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day-$month $hour:$minute';
}

String _formatQty(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.0001) {
    return rounded.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

String _alertLabel(InventoryAlertSeverity severity) {
  switch (severity) {
    case InventoryAlertSeverity.info:
      return 'Info';
    case InventoryAlertSeverity.warning:
      return 'Warning';
    case InventoryAlertSeverity.critical:
      return 'Critical';
  }
}

Color _alertBackground(InventoryAlertSeverity severity) {
  switch (severity) {
    case InventoryAlertSeverity.info:
      return const Color(0xFFEFF5FF);
    case InventoryAlertSeverity.warning:
      return const Color(0xFFFFF6EA);
    case InventoryAlertSeverity.critical:
      return const Color(0xFFFFF1F1);
  }
}

Color _alertBorder(InventoryAlertSeverity severity) {
  switch (severity) {
    case InventoryAlertSeverity.info:
      return const Color(0xFFB8CBF5);
    case InventoryAlertSeverity.warning:
      return const Color(0xFFE9C78D);
    case InventoryAlertSeverity.critical:
      return const Color(0xFFF2B6B6);
  }
}

Color _alertText(InventoryAlertSeverity severity) {
  switch (severity) {
    case InventoryAlertSeverity.info:
      return const Color(0xFF1D4FB7);
    case InventoryAlertSeverity.warning:
      return const Color(0xFF8A4D00);
    case InventoryAlertSeverity.critical:
      return const Color(0xFFB42318);
  }
}



class _InventoryRowEntry {
  const _InventoryRowEntry({
    required this.record,
    this.displayName,
    this.displayId,
    this.displayMetadata,
    this.depth = 0,
    this.canExpand = false,
    this.isExpanded = false,
    this.opensDetails = true,
  });

  final MaterialRecord record;
  final String? displayName;
  final String? displayId;
  final String? displayMetadata;
  final int depth;
  final bool canExpand;
  final bool isExpanded;
  final bool opensDetails;
}

class _InventoryTableMetrics {
  const _InventoryTableMetrics({
    required this.horizontalPadding,
    required this.nameWidth,
    required this.barcodeWidth,
    required this.stockWidth,
    required this.dateWidth,
    required this.createdByWidth,
    required this.statusWidth,
    required this.actionsWidth,
    required this.headerHeight,
    required this.rowHeight,
    required this.headerFontSize,
    required this.bodyFontSize,
    required this.statusFontSize,
    required this.treeIndent,
    required this.chevronSize,
    required this.nameGap,
    required this.rowRadius,
    required this.statusRadius,
    required this.statusHorizontalPadding,
    required this.statusVerticalPadding,
    required this.actionButtonSize,
    required this.rowGap,
  });

  factory _InventoryTableMetrics.fromViewportWidth(double width) {
    if (width < 1120) {
      return const _InventoryTableMetrics(
        horizontalPadding: 18,
        nameWidth: 228,
        barcodeWidth: 132,
        stockWidth: 144,
        dateWidth: 148,
        createdByWidth: 138,
        statusWidth: 136,
        actionsWidth: 152,
        headerHeight: 46,
        rowHeight: 82,
        headerFontSize: 12,
        bodyFontSize: 14,
        statusFontSize: 11,
        treeIndent: 20,
        chevronSize: 20,
        nameGap: 8,
        rowRadius: 18,
        statusRadius: 4,
        statusHorizontalPadding: 8,
        statusVerticalPadding: 4,
        actionButtonSize: 24,
        rowGap: 4,
      );
    }
    if (width < 1500) {
      return const _InventoryTableMetrics(
        horizontalPadding: 24,
        nameWidth: 274,
        barcodeWidth: 158,
        stockWidth: 162,
        dateWidth: 170,
        createdByWidth: 166,
        statusWidth: 172,
        actionsWidth: 168,
        headerHeight: 48,
        rowHeight: 86,
        headerFontSize: 14,
        bodyFontSize: 15,
        statusFontSize: 12,
        treeIndent: 22,
        chevronSize: 22,
        nameGap: 9,
        rowRadius: 20,
        statusRadius: 4,
        statusHorizontalPadding: 10,
        statusVerticalPadding: 5,
        actionButtonSize: 24,
        rowGap: 5,
      );
    }
    return const _InventoryTableMetrics(
      horizontalPadding: 32,
      nameWidth: 298,
      barcodeWidth: 174,
      stockWidth: 176,
      dateWidth: 184,
      createdByWidth: 182,
      statusWidth: 194,
      actionsWidth: 184,
      headerHeight: 50,
      rowHeight: 86,
      headerFontSize: 14,
      bodyFontSize: 16,
      statusFontSize: 12,
      treeIndent: 24,
      chevronSize: 24,
      nameGap: 10,
      rowRadius: 22,
      statusRadius: 4,
      statusHorizontalPadding: 10,
      statusVerticalPadding: 5,
      actionButtonSize: 24,
      rowGap: 4,
    );
  }

  final double horizontalPadding;
  final double nameWidth;
  final double barcodeWidth;
  final double stockWidth;
  final double dateWidth;
  final double createdByWidth;
  final double statusWidth;
  final double actionsWidth;
  final double headerHeight;
  final double rowHeight;
  final double headerFontSize;
  final double bodyFontSize;
  final double statusFontSize;
  final double treeIndent;
  final double chevronSize;
  final double nameGap;
  final double rowRadius;
  final double statusRadius;
  final double statusHorizontalPadding;
  final double statusVerticalPadding;
  final double actionButtonSize;
  final double rowGap;

  double get dataWidth =>
      nameWidth +
      barcodeWidth +
      stockWidth +
      dateWidth +
      createdByWidth +
      statusWidth +
      4 +
      (horizontalPadding * 2);
}

enum _InventoryRecordState { awaitingScan, notStarted, inProgress, completed }

class _ActionMenuLabel extends StatelessWidget {
  const _ActionMenuLabel({
    required this.icon,
    required this.label,
    this.isHighlighted = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isHighlighted;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final iconColor = isDestructive
        ? const Color(0xFFFF5C5C)
        : isHighlighted
        ? const Color(0xFF7357FF)
        : const Color(0xFF6D7483);
    final textColor = isDestructive
        ? const Color(0xFF2F2F2F)
        : const Color(0xFF3C3C3C);

    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Text(
          label,
          style:
              _inventoryInterStyle(
                color: textColor,
                size: 14,
                weight: FontWeight.w400,
              ).copyWith(
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
                decorationThickness: 0,
              ),
        ),
      ],
    );
  }
}

class _InventoryActionMenuButton extends StatelessWidget {
  const _InventoryActionMenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isHighlighted = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isHighlighted;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return _InventoryActionMenuHoverTile(
      icon: icon,
      label: label,
      onPressed: onPressed,
      isHighlighted: isHighlighted,
      isDestructive: isDestructive,
    );
  }
}

class _InventoryActionMenuHoverTile extends StatefulWidget {
  const _InventoryActionMenuHoverTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isHighlighted = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isHighlighted;
  final bool isDestructive;

  @override
  State<_InventoryActionMenuHoverTile> createState() =>
      _InventoryActionMenuHoverTileState();
}

class _InventoryActionMenuHoverTileState
    extends State<_InventoryActionMenuHoverTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: true,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreFocusable: false,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerUp: (_) => widget.onPressed(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: 234,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _isHovered ? _inventoryHoverColor : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _ActionMenuLabel(
                icon: widget.icon,
                label: widget.label,
                isHighlighted: widget.isHighlighted || _isHovered,
                isDestructive: widget.isDestructive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryActionsOverlayAnchor extends StatefulWidget {
  const _InventoryActionsOverlayAnchor({
    required this.triggerSize,
    required this.canAddSubGroup,
    required this.canDelete,
    required this.isRequestDelete,
    required this.onAddSubGroup,
    required this.onEdit,
    required this.onDelete,
  });

  final double triggerSize;
  final bool canAddSubGroup;
  final bool canDelete;
  final bool isRequestDelete;
  final VoidCallback onAddSubGroup;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_InventoryActionsOverlayAnchor> createState() =>
      _InventoryActionsOverlayAnchorState();
}

class _InventoryActionsOverlayAnchorState
    extends State<_InventoryActionsOverlayAnchor> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _inventoryActionsOverlayDismissSignal.addListener(_handleDismissSignal);
  }

  @override
  void dispose() {
    _inventoryActionsOverlayDismissSignal.removeListener(_handleDismissSignal);
    _removeOverlay();
    super.dispose();
  }

  void _handleDismissSignal() {
    if (_isOpen) {
      _removeOverlay();
    }
  }

  void _toggleMenu() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.topRight,
            offset: const Offset(-12, -8),
            child: Theme(
              data: Theme.of(context).copyWith(
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
              ),
              child: ExcludeFocus(
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 250,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.canAddSubGroup)
                              _InventoryActionMenuButton(
                                icon: Icons.add_rounded,
                                label: 'Add Sub-Group',
                                isHighlighted: true,
                                onPressed: () {
                                  _removeOverlay();
                                  widget.onAddSubGroup();
                                },
                              ),
                            _InventoryActionMenuButton(
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                              onPressed: () {
                                _removeOverlay();
                                widget.onEdit();
                              },
                            ),
                            if (widget.canDelete)
                              _InventoryActionMenuButton(
                                icon: Icons.delete_outline_rounded,
                                label: widget.isRequestDelete
                                    ? 'Request Delete'
                                    : 'Delete',
                                isDestructive: true,
                                onPressed: () {
                                  _removeOverlay();
                                  widget.onDelete();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted && _isOpen) {
      setState(() => _isOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: _InventoryActionTriggerButton(
        size: widget.triggerSize,
        isOpen: _isOpen,
        onTap: _toggleMenu,
      ),
    );
  }
}

class _InventoryActionTriggerButton extends StatefulWidget {
  const _InventoryActionTriggerButton({
    required this.size,
    required this.isOpen,
    required this.onTap,
  });

  final double size;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  State<_InventoryActionTriggerButton> createState() =>
      _InventoryActionTriggerButtonState();
}

class _InventoryActionTriggerButtonState
    extends State<_InventoryActionTriggerButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isOpen || _isHovered;
    return MouseRegion(
      opaque: true,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreFocusable: false,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerUp: (_) => widget.onTap(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: isActive ? _inventoryHoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.more_vert,
              size: 18,
              color: Color(0xFF58458F),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _inventoryManropeStyle({
  required Color color,
  required double size,
  required FontWeight weight,
}) {
  return TextStyle(
    fontFamily: 'Manrope',
    fontFamilyFallback: const ['Segoe UI', 'Arial'],
    color: color,
    fontSize: size,
    fontWeight: weight,
  );
}

TextStyle _inventoryInterStyle({
  required Color color,
  required double size,
  required FontWeight weight,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Segoe UI', 'Arial'],
    color: color,
    fontSize: size,
    fontWeight: weight,
  );
}

TextStyle _inventorySegoeStyle({
  required Color color,
  required double size,
  required FontWeight weight,
}) {
  return TextStyle(
    fontFamily: 'Segoe UI',
    fontFamilyFallback: const ['Arial'],
    color: color,
    fontSize: size,
    fontWeight: weight,
  );
}

class _MenuValue<T> {
  const _MenuValue({required this.value, required this.label});

  final T value;
  final String label;
}

class _AddChildMaterialSheet extends StatefulWidget {
  const _AddChildMaterialSheet({required this.parent});

  final MaterialRecord parent;

  @override
  State<_AddChildMaterialSheet> createState() => _AddChildMaterialSheetState();
}

class _AddChildMaterialSheetState extends State<_AddChildMaterialSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${widget.parent.name} - Sub Group',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle(
              title: 'Add Sub-Group',
              subtitle:
                  'Create a child inventory node under this group using the parent properties as a base.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Sub-group name'),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: 'Create',
                  isLoading: provider.isSaving,
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) {
                      return;
                    }
                    await context.read<InventoryProvider>().addChildMaterial(
                      CreateChildMaterialInput(
                        parentBarcode: widget.parent.barcode,
                        name: _nameController.text.trim(),
                        notes: _notesController.text.trim(),
                      ),
                    );
                    if (!context.mounted ||
                        context.read<InventoryProvider>().errorMessage !=
                            null) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditMaterialSheet extends StatefulWidget {
  const _EditMaterialSheet({required this.record});

  final MaterialRecord record;

  @override
  State<_EditMaterialSheet> createState() => _EditMaterialSheetState();
}

class _EditMaterialSheetState extends State<_EditMaterialSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;
  late final TextEditingController _gradeController;
  late final TextEditingController _thicknessController;
  late final TextEditingController _supplierController;
  late final TextEditingController _locationController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.record.name);
    _typeController = TextEditingController(text: widget.record.type);
    _gradeController = TextEditingController(text: widget.record.grade);
    _thicknessController = TextEditingController(text: widget.record.thickness);
    _supplierController = TextEditingController(text: widget.record.supplier);
    _locationController = TextEditingController(text: widget.record.location);
    _notesController = TextEditingController(text: widget.record.notes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _gradeController.dispose();
    _thicknessController.dispose();
    _supplierController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle(
              title: 'Edit Inventory Record',
              subtitle:
                  'Update the label and inventory metadata without breaking barcode traceability.',
            ),
            const SizedBox(height: 16),
            _SimpleField(controller: _nameController, label: 'Name'),
            const SizedBox(height: 12),
            _SimpleField(controller: _typeController, label: 'Type'),
            const SizedBox(height: 12),
            _SimpleField(controller: _gradeController, label: 'Grade'),
            const SizedBox(height: 12),
            _SimpleField(controller: _thicknessController, label: 'Thickness'),
            const SizedBox(height: 12),
            _SimpleField(controller: _supplierController, label: 'Supplier'),
            const SizedBox(height: 12),
            _SimpleField(controller: _locationController, label: 'Location'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: 'Save',
                  isLoading: provider.isSaving,
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) {
                      return;
                    }
                    await context.read<InventoryProvider>().updateMaterial(
                      UpdateMaterialInput(
                        barcode: widget.record.barcode,
                        name: _nameController.text.trim(),
                        type: _typeController.text.trim(),
                        grade: _gradeController.text.trim(),
                        thickness: _thicknessController.text.trim(),
                        supplier: _supplierController.text.trim(),
                        location: _locationController.text.trim(),
                        unitId: widget.record.unitId,
                        unit: widget.record.unit,
                        notes: _notesController.text.trim(),
                      ),
                    );
                    if (!context.mounted ||
                        context.read<InventoryProvider>().errorMessage !=
                            null) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleField extends StatelessWidget {
  const _SimpleField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: (value) => (value?.trim().isEmpty ?? true) ? 'Required' : null,
    );
  }
}

// ignore: unused_element
class _CreateGroupToggleSection extends StatelessWidget {
  const _CreateGroupToggleSection({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  onChanged: (checked) => onChanged(checked ?? false),
                  activeColor: const Color(0xFF6049E3),
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: Color(0xFFB8B8B8)),
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: _inventoryManropeStyle(
                    color: const Color(0xFF3F3F3F),
                    size: 14,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: child,
          ),
          crossFadeState: value
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}

class _CreateGroupField extends StatelessWidget {
  const _CreateGroupField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: _inventorySegoeStyle(
            color: const Color(0xFF717171),
            size: 14,
            weight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _CreateGroupDropdown extends StatelessWidget {
  const _CreateGroupDropdown({
    required this.value,
    required this.placeholder,
    required this.options,
    required this.onSelected,
  });

  final String? value;
  final String placeholder;
  final List<String> options;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final selected = await showSearchableSelectDialog<String>(
          context: context,
          title: placeholder,
          searchHintText: 'Search option',
          selectedValue: value,
          options: options
              .map(
                (option) => SearchableSelectOption<String>(
                  value: option,
                  label: option,
                ),
              )
              .toList(growable: false),
        );
        onSelected(selected?.value);
      },
      child: Row(
        children: [
          Expanded(
            child: Text(
              value ?? placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _inventorySegoeStyle(
                color: value == null
                    ? const Color(0xFF9D9D9D)
                    : const Color(0xFF3F3F3F),
                size: 14,
                weight: FontWeight.w400,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF727272),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _PropertyChip extends StatelessWidget {
  const _PropertyChip({
    required this.label,
    required this.onRemove,
    this.removable = true,
  });

  final String label;
  final VoidCallback onRemove;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FF),
        border: Border.all(color: const Color(0xFFCFC7FF)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: _inventoryInterStyle(
              color: const Color(0xFF2A00E4),
              size: 12,
              weight: FontWeight.w500,
            ),
          ),
          if (removable) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: const Icon(
                Icons.close_rounded,
                size: 12,
                color: Color(0xFF5A4BBA),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeedPropertyToggleChip extends StatelessWidget {
  const _SeedPropertyToggleChip({
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: enabled ? const Color(0xFF93C5FD) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enabled
                  ? Icons.check_circle_rounded
                  : Icons.remove_circle_outline_rounded,
              size: 15,
              color: enabled
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: _inventoryInterStyle(
                color: enabled
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFF64748B),
                size: 12,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkGroupSheet extends StatelessWidget {
  const _LinkGroupSheet({required this.record});

  final MaterialRecord record;

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupsProvider>().activeGroups;
    final provider = context.watch<InventoryProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Link Group Inheritance',
            subtitle:
                'Attach this inventory group to a configurator group so inherited properties can be referenced and later unlinked.',
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: groups.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFFE8E8F0)),
              itemBuilder: (context, index) {
                final group = groups[index];
                final isSelected = group.id == record.linkedGroupId;
                return ListTile(
                  title: Text(group.name),
                  subtitle: Text(
                    group.parentGroupId == null
                        ? 'Top level group'
                        : 'Nested group',
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF6049E3))
                      : null,
                  onTap: () async {
                    await context.read<InventoryProvider>().linkMaterialToGroup(
                      record.barcode,
                      group.id,
                    );
                    if (!context.mounted || provider.errorMessage != null) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkItemSheet extends StatelessWidget {
  const _LinkItemSheet({required this.record});

  final MaterialRecord record;

  @override
  Widget build(BuildContext context) {
    final items = context
        .watch<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Link Item Inheritance',
            subtitle:
                'Attach this inventory item to a configurator item so inherited item properties and variation structure stay visible.',
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFFE8E8F0)),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = item.id == record.linkedItemId;
                return ListTile(
                  title: Text(item.displayName),
                  subtitle: Text(
                    item.topLevelProperties.isEmpty
                        ? 'No inherited properties'
                        : item.topLevelProperties
                              .map((node) => node.name)
                              .join(', '),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF6049E3))
                      : null,
                  onTap: () async {

                    final requiresVariation =
                        item.topLevelProperties.isNotEmpty &&
                        item.leafVariationNodes.isNotEmpty;

                    if (requiresVariation) {
                      final result = await showDialog<VariationPathSelectionResult>(
                        context: context,
                        builder: (dialogContext) => Dialog(
                          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
                            child: VariationPathSelectorDialog(
                              item: item,
                              initialRootPropertyId: null,
                              initialValueNodeIds: const [],
                              onCreateValue: ({
                                required item,
                                required propertyNodeId,
                                required propertyLabel,
                                required valueName,
                              }) async {
                                final itemsProvider = context.read<ItemsProvider>();
                                final result = await itemsProvider.appendVariationValue(
                                  itemId: item.id,
                                  propertyNodeId: propertyNodeId,
                                  valueName: valueName,
                                );
                                if (!context.mounted) return null;
                                if (result == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        itemsProvider.errorMessage ?? 'Unable to create variation.',
                                      ),
                                    ),
                                  );
                                }
                                return result;
                              },
                            ),
                          ),
                        ),
                      );
                      if (result == null || result.leaf == null) {
                        return; // User cancelled or selected an incomplete path
                      }

                    }

                    if (!context.mounted) return;

                    await context.read<InventoryProvider>().linkMaterialToItem(
                      record.barcode,
                      item.id,
                    );
                    if (!context.mounted) return;
                    final provider = context.read<InventoryProvider>();
                    if (provider.errorMessage != null) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMaterialForm extends StatefulWidget {
  const _AddMaterialForm();

  @override
  State<_AddMaterialForm> createState() => _AddMaterialFormState();
}

class _AddMaterialFormState extends State<_AddMaterialForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _propertyController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  int? _selectedUnitId;
  int? _selectedParentGroupId;
  int? _selectedSeedItemId;
  final List<String> _addedProperties = <String>[];
  final Set<String> _disabledSeedPropertyKeys = <String>{};

  @override
  void dispose() {
    _nameController.dispose();
    _propertyController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final groups = context.watch<GroupsProvider>().activeGroups;
    final units = context.watch<UnitsProvider>().activeUnits;
    final items = context
        .watch<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);
    final selectedUnit = units
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    final selectedParentGroup = groups
        .where((group) => group.id == _selectedParentGroupId)
        .firstOrNull;
    final selectedSeedItem = items
        .where((item) => item.id == _selectedSeedItemId)
        .firstOrNull;
    final seedProperties = _seedPropertyNames(selectedSeedItem);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 1140,
        height: 700,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
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
                            'Create Group',
                            style: _inventoryInterStyle(
                              color: const Color(0xFF111827),
                              size: 22,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Define the group, assign its unit, and optionally seed it with items or properties.',
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
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 940;
                    final detailsCard = _CreateGroupSurfaceCard(
                      title: 'Group Details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CreateGroupField(
                            label: 'Group Name',
                            child: TextFormField(
                              controller: _nameController,
                              focusNode: _nameFocus,
                              decoration: const InputDecoration(
                                hintText: 'Enter group name',
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                              style: _inventorySegoeStyle(
                                color: const Color(0xFF3F3F3F),
                                size: 14,
                                weight: FontWeight.w400,
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SearchableSelectField<int?>(
                            tapTargetKey: const ValueKey<String>(
                              'inventory-create-group-parent',
                            ),
                            value:
                                groups.any(
                                  (group) => group.id == _selectedParentGroupId,
                                )
                                ? _selectedParentGroupId
                                : null,
                            decoration: _selectDecoration(
                              label: 'Parent Group',
                              helper:
                                  'Primary means this group is a top-level inventory group.',
                            ),
                            dialogTitle: 'Parent Group',
                            searchHintText: 'Search group',
                            options: [
                              const SearchableSelectOption<int?>(
                                value: null,
                                label: 'Primary',
                              ),
                              ...groups.map(
                                (group) => SearchableSelectOption<int?>(
                                  value: group.id,
                                  label: group.name,
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedParentGroupId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          SearchableSelectField<int>(
                            tapTargetKey: const ValueKey<String>(
                              'inventory-create-group-unit',
                            ),
                            value:
                                units.any((unit) => unit.id == _selectedUnitId)
                                ? _selectedUnitId
                                : selectedUnit?.id,
                            decoration: _selectDecoration(
                              label: 'Group Unit',
                              helper:
                                  'Required. If the unit is missing, create it here and continue.',
                            ),
                            dialogTitle: 'Group Unit',
                            searchHintText: 'Search unit',
                            onCreateOption: (query) async {
                              final created = await UnitsScreen.openEditor(
                                context,
                                initialName: query,
                              );
                              if (!context.mounted || created == null) {
                                return null;
                              }
                              return SearchableSelectOption<int>(
                                value: created.id,
                                label: created.displayLabel,
                              );
                            },
                            createOptionLabelBuilder: (query) =>
                                'Create unit "$query"',
                            options: units
                                .map(
                                  (unit) => SearchableSelectOption<int>(
                                    value: unit.id,
                                    label: unit.displayLabel,
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              setState(() {
                                _selectedUnitId = value;
                              });
                            },
                            validator: (value) =>
                                value == null ? 'Required' : null,
                          ),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _PropertyChip(
                                  label: _nameController.text.trim().isEmpty
                                      ? 'Name pending'
                                      : _nameController.text.trim(),
                                  onRemove: () {},
                                  removable: false,
                                ),
                                _PropertyChip(
                                  label: selectedParentGroup == null
                                      ? 'Primary parent'
                                      : 'Under: ${selectedParentGroup.name}',
                                  onRemove: () {},
                                  removable: false,
                                ),
                                _PropertyChip(
                                  label: selectedUnit == null
                                      ? 'Unit pending'
                                      : 'Unit: ${selectedUnit.displayLabel}',
                                  onRemove: () {},
                                  removable: false,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );

                    final compositionCard = _CreateGroupSurfaceCard(
                      title: 'Structure & Properties',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SearchableSelectField<int?>(
                            tapTargetKey: const ValueKey<String>(
                              'inventory-create-group-seed-item',
                            ),
                            value:
                                items.any(
                                  (item) => item.id == _selectedSeedItemId,
                                )
                                ? _selectedSeedItemId
                                : null,
                            decoration: _selectDecoration(
                              label: 'Seed Item',
                              helper:
                                  'Optional. Reuse top-level properties from an existing item.',
                            ),
                            dialogTitle: 'Seed Item',
                            searchHintText: 'Search item',
                            options: [
                              const SearchableSelectOption<int?>(
                                value: null,
                                label: 'No seed item',
                              ),
                              ...items.map(
                                (item) => SearchableSelectOption<int?>(
                                  value: item.id,
                                  label: item.displayName.trim().isEmpty
                                      ? item.name
                                      : item.displayName,
                                  searchText:
                                      '${item.name} ${item.alias} ${item.displayName}',
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedSeedItemId = value;
                                _disabledSeedPropertyKeys.clear();
                              });
                            },
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Properties',
                            style: _inventoryInterStyle(
                              color: const Color(0xFF334155),
                              size: 14,
                              weight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: _CreateGroupField(
                                  label: 'Add Property',
                                  child: TextFormField(
                                    controller: _propertyController,
                                    decoration: const InputDecoration(
                                      hintText: 'e.g. Material, Size, Color',
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                    ),
                                    style: _inventorySegoeStyle(
                                      color: const Color(0xFF3F3F3F),
                                      size: 14,
                                      weight: FontWeight.w400,
                                    ),
                                    onFieldSubmitted: (_) => _addPropertyChip(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 40,
                                child: OutlinedButton(
                                  onPressed: _addPropertyChip,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Color(0xFFDDDDDD),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(48),
                                    ),
                                  ),
                                  child: Text(
                                    '+ Add',
                                    style: _inventoryInterStyle(
                                      color: const Color(0xFF484848),
                                      size: 14,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(minHeight: 140),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child:
                                seedProperties.isEmpty &&
                                    _addedProperties.isEmpty
                                ? Text(
                                    selectedSeedItem == null
                                        ? 'No properties added yet. Pick a seed item or add properties manually.'
                                        : 'No properties added yet. This seed item has no top-level properties.',
                                    style: _inventoryInterStyle(
                                      color: const Color(0xFF94A3B8),
                                      size: 13,
                                      weight: FontWeight.w400,
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ...seedProperties.map(
                                        (property) => _SeedPropertyToggleChip(
                                          label: property,
                                          enabled: !_disabledSeedPropertyKeys
                                              .contains(_propertyKey(property)),
                                          onChanged: (enabled) {
                                            setState(() {
                                              final key = _propertyKey(
                                                property,
                                              );
                                              if (enabled) {
                                                _disabledSeedPropertyKeys
                                                    .remove(key);
                                              } else {
                                                _disabledSeedPropertyKeys.add(
                                                  key,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      ..._addedProperties.map(
                                        (property) => _PropertyChip(
                                          label: property,
                                          onRemove: () {
                                            setState(() {
                                              _addedProperties.remove(property);
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    );

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                detailsCard,
                                const SizedBox(height: 18),
                                compositionCard,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: detailsCard),
                                const SizedBox(width: 18),
                                Expanded(child: compositionCard),
                              ],
                            ),
                    );
                  },
                ),
              ),
              Container(
                height: 61,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E2E2))),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDDDDDD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: _inventoryInterStyle(
                          color: const Color(0xFF484848),
                          size: 14,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: provider.isSaving
                          ? null
                          : () => _submit(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6049E3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: provider.isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Save',
                              style: _inventoryInterStyle(
                                color: Colors.white,
                                size: 14,
                                weight: FontWeight.w500,
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
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a group unit before saving.')),
      );
      return;
    }

    final selectedParentGroup = context
        .read<GroupsProvider>()
        .activeGroups
        .where((group) => group.id == _selectedParentGroupId)
        .firstOrNull;
    final items = context
        .read<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);
    final selectedSeedItem = items
        .where((item) => item.id == _selectedSeedItemId)
        .firstOrNull;
    final enabledSeedProperties = _enabledSeedProperties(
      _seedPropertyNames(selectedSeedItem),
    );
    final notes = <String>[
      if (selectedParentGroup != null)
        'Parent Group: ${selectedParentGroup.name}',
      if (selectedParentGroup == null) 'Parent Group: Primary',
      if (selectedSeedItem != null)
        'Seed Item: ${selectedSeedItem.displayName.trim().isEmpty ? selectedSeedItem.name : selectedSeedItem.displayName}',
      if (enabledSeedProperties.isNotEmpty)
        'Seeded Properties: ${enabledSeedProperties.join(', ')}',
      if (_addedProperties.isNotEmpty)
        'Manual Properties: ${_addedProperties.join(', ')}',
    ].join('\n');
    final childrenCount = selectedSeedItem == null ? 0 : 1;
    final provider = context.read<InventoryProvider>();
    final selectedUnit = context
        .read<UnitsProvider>()
        .units
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    await provider.addParentMaterial(
      CreateParentMaterialInput(
        name: _nameController.text.trim(),
        type: 'Group',
        grade: '',
        thickness: '',
        supplier: '',
        unitId: _selectedUnitId,
        unit: selectedUnit?.displayLabel ?? 'Pieces',
        groupMode: selectedParentGroup == null
            ? 'standalone_group'
            : 'nested_group',
        notes: notes,
        numberOfChildren: childrenCount,
      ),
    );

    if (!context.mounted || provider.errorMessage != null) {
      return;
    }

    Navigator.of(context).maybePop();
  }

  void _addPropertyChip() {
    final value = _propertyController.text.trim();
    if (value.isEmpty) {
      return;
    }
    final existingKeys = {
      ..._addedProperties.map(_propertyKey),
      ..._enabledSeedProperties(
        _seedPropertyNames(
          context
              .read<ItemsProvider>()
              .items
              .where((item) => item.id == _selectedSeedItemId)
              .firstOrNull,
        ),
      ).map(_propertyKey),
    };
    if (existingKeys.contains(_propertyKey(value))) {
      _propertyController.clear();
      return;
    }
    setState(() {
      _addedProperties.add(value);
      _propertyController.clear();
    });
  }

  List<String> _seedPropertyNames(ItemDefinition? item) {
    if (item == null) {
      return const <String>[];
    }
    final seen = <String>{};
    final properties = <String>[];
    for (final property in item.topLevelProperties) {
      final name = property.displayName.trim().isEmpty
          ? property.name.trim()
          : property.displayName.trim();
      final key = _propertyKey(name);
      if (name.isNotEmpty && seen.add(key)) {
        properties.add(name);
      }
    }
    return properties
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> _enabledSeedProperties(List<String> seedProperties) {
    return seedProperties
        .where(
          (property) =>
              !_disabledSeedPropertyKeys.contains(_propertyKey(property)),
        )
        .toList(growable: false);
  }

  String _propertyKey(String value) => value.trim().toLowerCase();

  InputDecoration _selectDecoration({
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

class _CreateGroupSurfaceCard extends StatelessWidget {
  const _CreateGroupSurfaceCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _inventoryInterStyle(
              color: const Color(0xFF111827),
              size: 18,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InventoryCreateGroupEditor extends StatefulWidget {
  const _InventoryCreateGroupEditor({
    required this.onClose,
    required this.initialRecord,
  });

  final VoidCallback onClose;
  final MaterialRecord? initialRecord;

  @override
  State<_InventoryCreateGroupEditor> createState() =>
      _InventoryCreateGroupEditorState();
}

class _InventoryCreateGroupEditorState
    extends State<_InventoryCreateGroupEditor> {
  static const List<String> _propertyInputTypes = <String>[
    'Text',
    'Number',
    'Dropdown',
    'Date',
    'Boolean',
  ];

  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController(text: 'Main Warehouse');
  final _propertyNameController = TextEditingController();
  final _itemSearchController = TextEditingController();
  final _itemListScrollController = ScrollController();

  String? _selectedUnitGroup;
  bool _enableVariants = false;
  bool _showSelectedItemsOnly = false;
  bool _inheritPropertiesFromItems = true;
  bool _commonOnlyMode = true;
  bool _showPartialMatches = true;
  String _propertyInputType = 'Text';
  bool _propertyMandatory = false;
  final Set<int> _selectedItemIds = <int>{};
  final Set<String> _unlinkedInheritedPropertyKeys = <String>{};
  final List<_GroupPropertyDraft> _properties = <_GroupPropertyDraft>[];
  final Map<int, _UnitGovernanceDraft> _unitGovernanceByUnitId =
      <int, _UnitGovernanceDraft>{};
  bool _isHydratingExisting = false;
  bool _didHydrateExisting = false;

  bool get _isEditMode => widget.initialRecord != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    if (initial != null) {
      _groupNameController.text = initial.name;
      _locationController.text = initial.location.trim().isEmpty
          ? 'Main Warehouse'
          : initial.location;
      _descriptionController.text = _extractDescription(initial.notes);
      _inheritPropertiesFromItems = initial.inheritanceEnabled;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didHydrateExisting || !_isEditMode) {
      return;
    }
    _didHydrateExisting = true;
    Future<void>.microtask(_hydrateExistingGovernance);
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _propertyNameController.dispose();
    _itemSearchController.dispose();
    _itemListScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final items = context.watch<ItemsProvider>().items.toList(growable: false);
    final unitGroups =
        context
            .watch<UnitsProvider>()
            .activeUnits
            .map((unit) => unit.unitGroupName?.trim() ?? '')
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final units = context.watch<UnitsProvider>().activeUnits;
    final inheritedProperties = _derivedPropertiesFromItems(items);
    final selectedCount = _selectedItemIds.length;
    final activeInheritedProperties = _inheritPropertiesFromItems
        ? inheritedProperties
              .where(
                (property) =>
                    !_unlinkedInheritedPropertyKeys.contains(
                      _propertyKey(property.name),
                    ) &&
                    (!_commonOnlyMode ||
                        property.coverageCount == selectedCount) &&
                    (_showPartialMatches ||
                        property.coverageCount == selectedCount),
              )
              .toList(growable: false)
        : const <_GroupPropertyDraft>[];
    final relinkableInheritedProperties = inheritedProperties
        .where(
          (property) => _unlinkedInheritedPropertyKeys.contains(
            _propertyKey(property.name),
          ),
        )
        .toList(growable: false);
    final query = _itemSearchController.text.trim().toLowerCase();
    final matchingItems = items
        .where((item) {
          if (query.isEmpty) {
            return true;
          }
          return item.displayName.toLowerCase().contains(query) ||
              item.name.toLowerCase().contains(query) ||
              item.alias.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final filteredItems = matchingItems
        .where(
          (item) =>
              !_showSelectedItemsOnly || _selectedItemIds.contains(item.id),
        )
        .toList(growable: false);
    final combinedProperties = _combinedProperties(
      inheritedProperties: activeInheritedProperties,
    );
    final selectedUnitCards = _derivedUnitCards(items, units);
    _syncUnitGovernanceDrafts(selectedUnitCards);
    final effectiveUnitGovernance = _effectiveUnitGovernance(selectedUnitCards);
    final unitGroupMismatch = _hasUnitGroupMismatch(
      selectedUnitCards,
      units,
      effectiveUnitGovernance,
    );
    final overriddenCount = combinedProperties
        .where((property) => property.state == _EditorPropertyState.overridden)
        .length;
    final conflictedCount = combinedProperties
        .where((property) => property.hasTypeConflict)
        .length;
    final partialCoverageCount = activeInheritedProperties
        .where((property) => property.coverageCount < selectedCount)
        .length;
    final allCoverageCount = activeInheritedProperties
        .where((property) => property.coverageCount == selectedCount)
        .length;
    final hasBlockingReview =
        conflictedCount > 0 ||
        unitGroupMismatch ||
        (_inheritPropertiesFromItems && _selectedItemIds.isEmpty);
    final blockingReviewReasons = <String>[
      if (conflictedCount > 0)
        '$conflictedCount conflicted ${conflictedCount == 1 ? 'property' : 'properties'}',
      if (unitGroupMismatch) 'Unit strategy mismatch',
      if (_inheritPropertiesFromItems && _selectedItemIds.isEmpty)
        'Select at least one source item',
    ];

    final basicInformationCard = _CreateGroupEditorCard(
      title: 'Basic Information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EditorFieldLabel('Group Name', required: true),
          const SizedBox(height: 6),
          _EditorTextField(
            controller: _groupNameController,
            hintText: 'Enter group name',
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Group name is required'
                : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _EditorFieldLabel('Group ID'),
          const SizedBox(height: 6),
          _EditorReadOnlyField(value: _generatedGroupId),
          const SizedBox(height: 6),
          Text(
            'Auto-generated based on group name',
            style: _inventoryInterStyle(
              color: const Color(0xFF94A3B8),
              size: 12,
              weight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          _EditorFieldLabel('Description'),
          const SizedBox(height: 6),
          _EditorTextField(
            controller: _descriptionController,
            hintText: 'Enter group description',
            maxLines: 5,
          ),
          const SizedBox(height: 16),
          _EditorFieldLabel('Location'),
          const SizedBox(height: 6),
          _EditorTextField(
            controller: _locationController,
            hintText: 'e.g., Main Warehouse / Zone A / Bin 12',
          ),
          const SizedBox(height: 16),
          _EditorFieldLabel('Unit Group'),
          const SizedBox(height: 6),
          _EditorDropdownField(
            value: _selectedUnitGroup,
            hintText: 'Select unit group',
            options: unitGroups,
            onSelected: (value) {
              setState(() {
                _selectedUnitGroup = value;
              });
            },
          ),
          const SizedBox(height: 18),
          _EditorCheckboxTile(
            value: _enableVariants,
            title: 'Enable Variants',
            subtitle: 'Allow multiple variants for this group',
            onChanged: (value) {
              setState(() {
                _enableVariants = value;
              });
            },
          ),
        ],
      ),
    );

    final sourceWorkbenchCard = _CreateGroupEditorCard(
      title: 'Source Items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isEditMode ? 'Linked Items' : 'Add Existing Items',
                  style: _inventoryInterStyle(
                    color: const Color(0xFF334155),
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${_selectedItemIds.length} selected',
                style: _inventoryInterStyle(
                  color: const Color(0xFF2D8CFF),
                  size: 12,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pick items to seed this group schema and inheritance rules.',
            style: _inventoryInterStyle(
              color: const Color(0xFF94A3B8),
              size: 12,
              weight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compactSearchControls = constraints.maxWidth < 430;
              final toggleChip = ChoiceChip(
                label: Text(_showSelectedItemsOnly ? 'Selected' : 'All Items'),
                selected: _showSelectedItemsOnly,
                onSelected: (selected) {
                  setState(() {
                    _showSelectedItemsOnly = selected;
                  });
                },
                selectedColor: const Color(0xFFE0EEFF),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFD8E5F3)),
                ),
                labelStyle: _inventoryInterStyle(
                  color: _showSelectedItemsOnly
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF64748B),
                  size: 12,
                  weight: FontWeight.w500,
                ),
              );
              final searchField = _EditorTextField(
                controller: _itemSearchController,
                hintText: 'Search items...',
                prefixIcon: Icons.search_rounded,
                onChanged: (_) => setState(() {}),
              );
              if (compactSearchControls) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: toggleChip),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 8),
                  toggleChip,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TextButton.icon(
                onPressed: filteredItems.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _selectedItemIds.addAll(
                            filteredItems
                                .where((item) => !item.isArchived)
                                .map((item) => item.id),
                          );
                          final availablePropertyKeys =
                              _derivedPropertiesFromItems(items)
                                  .map(
                                    (property) => _propertyKey(property.name),
                                  )
                                  .toSet();
                          _unlinkedInheritedPropertyKeys.removeWhere(
                            (key) => !availablePropertyKeys.contains(key),
                          );
                        });
                      },
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text('Select visible'),
              ),
              TextButton.icon(
                onPressed: matchingItems.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _selectedItemIds.addAll(
                            matchingItems
                                .where((item) => !item.isArchived)
                                .map((item) => item.id),
                          );
                          final availablePropertyKeys =
                              _derivedPropertiesFromItems(items)
                                  .map(
                                    (property) => _propertyKey(property.name),
                                  )
                                  .toSet();
                          _unlinkedInheritedPropertyKeys.removeWhere(
                            (key) => !availablePropertyKeys.contains(key),
                          );
                        });
                      },
                icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                label: const Text('Select all matching'),
              ),
              TextButton.icon(
                onPressed: _selectedItemIds.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _selectedItemIds.clear();
                          _unlinkedInheritedPropertyKeys.clear();
                        });
                      },
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Clear selection'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Scrollbar(
              controller: _itemListScrollController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _itemListScrollController,
                padding: EdgeInsets.zero,
                itemCount: filteredItems.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  final isSelected = _selectedItemIds.contains(item.id);
                  final compatibility = _itemCompatibilityLabel(
                    item: item,
                    selectedItems: items
                        .where((entry) => _selectedItemIds.contains(entry.id))
                        .toList(growable: false),
                    units: units,
                  );
                  return _EditorSelectableItemTile(
                    item: item,
                    selected: isSelected,
                    compatibilityLabel: compatibility.$1,
                    compatibilityTone: compatibility.$2,
                    propertyContributionCount: item.topLevelProperties.length,
                    isDisabled: item.isArchived,
                    onChanged: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedItemIds.add(item.id);
                        } else {
                          _selectedItemIds.remove(item.id);
                        }
                        final availablePropertyKeys =
                            _derivedPropertiesFromItems(items)
                                .map((property) => _propertyKey(property.name))
                                .toSet();
                        _unlinkedInheritedPropertyKeys.removeWhere(
                          (key) => !availablePropertyKeys.contains(key),
                        );
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );

    final propertiesCard = _CreateGroupEditorCard(
      title: 'Properties',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F8FE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD7E5F5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditorFieldLabel('Property Name', required: true),
                const SizedBox(height: 6),
                _EditorTextField(
                  controller: _propertyNameController,
                  hintText: 'e.g., Material, Size, Color',
                ),
                const SizedBox(height: 12),
                _EditorFieldLabel('Input Type', required: true),
                const SizedBox(height: 6),
                _EditorDropdownField(
                  value: _propertyInputType,
                  hintText: 'Select input type',
                  options: _propertyInputTypes,
                  onSelected: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _propertyInputType = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _propertyInputTypes
                      .map(
                        (type) => ActionChip(
                          label: Text(type),
                          onPressed: () {
                            setState(() {
                              _propertyInputType = type;
                            });
                          },
                          backgroundColor: _propertyInputType == type
                              ? const Color(0xFFE0EEFF)
                              : Colors.white,
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 10),
                _EditorCheckboxTile(
                  value: _propertyMandatory,
                  title: 'Mandatory Field',
                  dense: true,
                  onChanged: (value) {
                    setState(() {
                      _propertyMandatory = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _addProperty,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2D8CFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      'Add Property',
                      style: _inventoryInterStyle(
                        color: Colors.white,
                        size: 13,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _EditorCheckboxTile(
            value: _inheritPropertiesFromItems,
            title: 'Inherit properties from selected items',
            subtitle:
                'Link item properties into this group. You can unlink individual inherited properties below.',
            onChanged: (value) {
              setState(() {
                _inheritPropertiesFromItems = value;
              });
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Selected Units (${selectedUnitCards.length})',
            style: _inventoryInterStyle(
              color: const Color(0xFF475569),
              size: 13,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (selectedUnitCards.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'No units linked from selected items yet.',
                style: _inventoryInterStyle(
                  color: const Color(0xFF94A3B8),
                  size: 13,
                  weight: FontWeight.w400,
                ),
              ),
            )
          else
            Column(
              children: selectedUnitCards
                  .map(
                    (unitCard) => _EditorUnitCard(
                      unitCard: unitCard,
                      state:
                          _unitGovernanceByUnitId[unitCard.unitId]?.state ??
                          groupcfg.GroupUnitState.active,
                      isPrimary:
                          _unitGovernanceByUnitId[unitCard.unitId]?.isPrimary ??
                          false,
                      onToggleDetach: () {
                        setState(() {
                          final current =
                              _unitGovernanceByUnitId[unitCard.unitId] ??
                              _UnitGovernanceDraft(unitId: unitCard.unitId);
                          _unitGovernanceByUnitId[unitCard.unitId] = current
                              .copyWith(
                                state:
                                    current.state ==
                                        groupcfg.GroupUnitState.detached
                                    ? groupcfg.GroupUnitState.active
                                    : groupcfg.GroupUnitState.detached,
                                isPrimary:
                                    current.state ==
                                        groupcfg.GroupUnitState.detached
                                    ? current.isPrimary
                                    : false,
                              );
                        });
                      },
                      onSetPrimary: () {
                        setState(() {
                          final next = <int, _UnitGovernanceDraft>{};
                          for (final row in _unitGovernanceByUnitId.values) {
                            next[row.unitId] = row.copyWith(isPrimary: false);
                          }
                          final current =
                              next[unitCard.unitId] ??
                              _UnitGovernanceDraft(unitId: unitCard.unitId);
                          next[unitCard.unitId] = current.copyWith(
                            state: groupcfg.GroupUnitState.active,
                            isPrimary: true,
                          );
                          _unitGovernanceByUnitId
                            ..clear()
                            ..addAll(next);
                        });
                      },
                      onRemove: () {
                        setState(() {
                          _selectedItemIds.removeWhere(
                            (itemId) => items.any(
                              (item) =>
                                  item.id == itemId &&
                                  item.unitId == unitCard.unitId,
                            ),
                          );
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          if (unitGroupMismatch) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Text(
                'Unit group mismatch detected across active unit cards. Set one primary unit or detach incompatible units before saving.',
                style: _inventoryInterStyle(
                  color: const Color(0xFFB45309),
                  size: 11,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (_inheritPropertiesFromItems) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Inherited Properties (${activeInheritedProperties.length})',
                    style: _inventoryInterStyle(
                      color: const Color(0xFF475569),
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_unlinkedInheritedPropertyKeys.isNotEmpty)
                  Text(
                    '${_unlinkedInheritedPropertyKeys.length} unlinked',
                    style: _inventoryInterStyle(
                      color: const Color(0xFF64748B),
                      size: 11,
                      weight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All inherited'),
                  selected: !_commonOnlyMode,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _commonOnlyMode = false;
                      }
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Only common to all'),
                  selected: _commonOnlyMode,
                  onSelected: (selected) {
                    setState(() {
                      _commonOnlyMode = selected;
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Show partial matches'),
                  selected: _showPartialMatches,
                  onSelected: (selected) {
                    setState(() {
                      _showPartialMatches = selected;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: activeInheritedProperties.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _unlinkedInheritedPropertyKeys.addAll(
                          activeInheritedProperties.map(
                            (property) => _propertyKey(property.name),
                          ),
                        );
                      });
                    },
              icon: const Icon(Icons.link_off_rounded, size: 16),
              label: const Text('Remove all inherited'),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: conflictedCount > 0
                  ? Container(
                      key: const ValueKey('conflict-center-visible'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        'Conflict Center: $conflictedCount property types need resolution before this group is safe to create.',
                        style: _inventoryInterStyle(
                          color: const Color(0xFF9A3412),
                          size: 11,
                          weight: FontWeight.w600,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('conflict-center-hidden'),
                    ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: activeInheritedProperties.isEmpty
                  ? Container(
                      key: ValueKey(
                        _selectedItemIds.isEmpty
                            ? 'inherited-empty-no-items'
                            : 'inherited-empty-no-properties',
                      ),
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        _selectedItemIds.isEmpty
                            ? 'Select items to inherit their properties.'
                            : 'No inheritable properties found on selected items.',
                        style: _inventoryInterStyle(
                          color: const Color(0xFF94A3B8),
                          size: 12,
                          weight: FontWeight.w400,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('inherited-empty-hidden'),
                    ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Added Properties (${combinedProperties.length})',
            style: _inventoryInterStyle(
              color: const Color(0xFF475569),
              size: 13,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (combinedProperties.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'No properties added yet.',
                style: _inventoryInterStyle(
                  color: const Color(0xFF94A3B8),
                  size: 13,
                  weight: FontWeight.w400,
                ),
              ),
            )
          else
            Column(
              children: combinedProperties
                  .map(
                    (property) => _EditorPropertyListTile(
                      property: property,
                      inputTypeOptions: _propertyInputTypes,
                      onRemove: !property.isInherited
                          ? () {
                              setState(() {
                                _properties.removeWhere(
                                  (manualProperty) =>
                                      _propertyKey(manualProperty.name) ==
                                      _propertyKey(property.name),
                                );
                              });
                            }
                          : null,
                      onUnlink: property.isInherited
                          ? () {
                              setState(() {
                                _unlinkedInheritedPropertyKeys.add(
                                  _propertyKey(property.name),
                                );
                              });
                            }
                          : null,
                      onConvertToManual: property.isInherited
                          ? () {
                              setState(() {
                                _unlinkedInheritedPropertyKeys.remove(
                                  _propertyKey(property.name),
                                );
                                _properties.removeWhere(
                                  (manualProperty) =>
                                      _propertyKey(manualProperty.name) ==
                                      _propertyKey(property.name),
                                );
                                _properties.add(
                                  property.copyWith(
                                    isInherited: false,
                                    state: _EditorPropertyState.overridden,
                                    sourceType: governance
                                        .GroupPropertySourceType
                                        .manual,
                                    sourceLabel: property.sourceLabel == null
                                        ? 'Override'
                                        : 'Override of ${property.sourceLabel}',
                                  ),
                                );
                              });
                            }
                          : null,
                      onToggleLockOverride:
                          property.state == _EditorPropertyState.overridden &&
                              !property.isInherited
                          ? () {
                              setState(() {
                                final key = _propertyKey(property.name);
                                final index = _properties.indexWhere(
                                  (manualProperty) =>
                                      _propertyKey(manualProperty.name) == key,
                                );
                                if (index == -1) {
                                  return;
                                }
                                _properties[index] = _properties[index]
                                    .copyWith(
                                      overrideLocked:
                                          !_properties[index].overrideLocked,
                                    );
                              });
                            }
                          : null,
                      onResolveInputType: property.hasTypeConflict
                          ? (value) {
                              setState(() {
                                final key = _propertyKey(property.name);
                                final inherited = activeInheritedProperties
                                    .where(
                                      (item) => _propertyKey(item.name) == key,
                                    )
                                    .firstOrNull;
                                final resolved = property.copyWith(
                                  inputType: value,
                                  hasTypeConflict: false,
                                  isInherited: true,
                                  sourceType: governance
                                      .GroupPropertySourceType
                                      .inheritedItem,
                                  sourceItemIds:
                                      inherited?.sourceItemIds ??
                                      property.sourceItemIds,
                                  sourceItemNames:
                                      inherited?.sourceItemNames ??
                                      property.sourceItemNames,
                                  sourceLabel:
                                      inherited?.sourceLabel ??
                                      property.sourceLabel,
                                  selectedItemCountAtResolution:
                                      _selectedItemIds.length,
                                  resolutionSource: 'resolved_by_user',
                                );
                                _upsertPropertyDraft(resolved);
                              });
                            }
                          : null,
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(label: 'Selected items: ${_selectedItemIds.length}'),
                _Badge(label: 'Selected units: ${selectedUnitCards.length}'),
                _Badge(
                  label:
                      'Active inherited: ${activeInheritedProperties.length}',
                ),
                _Badge(label: 'Overridden: $overriddenCount'),
                _Badge(
                  label: 'Unlinked: ${_unlinkedInheritedPropertyKeys.length}',
                ),
                _Badge(label: 'Conflicted: $conflictedCount'),
                _Badge(label: 'All-source: $allCoverageCount'),
                _Badge(label: 'Partial-source: $partialCoverageCount'),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child:
                  (_inheritPropertiesFromItems &&
                      relinkableInheritedProperties.isNotEmpty)
                  ? Column(
                      key: const ValueKey('relink-section-visible'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          'Unlinked Inherited Properties',
                          style: _inventoryInterStyle(
                            color: const Color(0xFF64748B),
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: relinkableInheritedProperties
                              .map(
                                (property) => ActionChip(
                                  avatar: const Icon(
                                    Icons.link_rounded,
                                    size: 14,
                                    color: Color(0xFF2563EB),
                                  ),
                                  label: Text('Relink ${property.name}'),
                                  onPressed: () {
                                    setState(() {
                                      _unlinkedInheritedPropertyKeys.remove(
                                        _propertyKey(property.name),
                                      );
                                    });
                                  },
                                  backgroundColor: const Color(0xFFEFF6FF),
                                  side: const BorderSide(
                                    color: Color(0xFFBFDBFE),
                                  ),
                                  labelStyle: _inventoryInterStyle(
                                    color: const Color(0xFF1D4ED8),
                                    size: 12,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('relink-section-hidden'),
                    ),
            ),
          ),
        ],
      ),
    );

    final liveOutcomeCard = _CreateGroupEditorCard(
      title: 'Live Outcome',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasBlockingReview
                  ? const Color(0xFFFFF7ED)
                  : const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasBlockingReview
                    ? const Color(0xFFFED7AA)
                    : const Color(0xFFBBF7D0),
              ),
            ),
            child: Text(
              hasBlockingReview ? 'Review required' : 'Safe to create',
              style: _inventoryInterStyle(
                color: hasBlockingReview
                    ? const Color(0xFFB45309)
                    : const Color(0xFF047857),
                size: 13,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'What changed',
            style: _inventoryInterStyle(
              color: const Color(0xFF334155),
              size: 12,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _Badge(label: '+${activeInheritedProperties.length} inherited ready'),
          const SizedBox(height: 6),
          _Badge(label: '$overriddenCount overrides preserved'),
          const SizedBox(height: 6),
          _Badge(
            label:
                '${_unlinkedInheritedPropertyKeys.length} unlinked awaiting relink',
          ),
          const SizedBox(height: 14),
          Text(
            'Coverage breakdown',
            style: _inventoryInterStyle(
              color: const Color(0xFF334155),
              size: 12,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _Badge(label: 'All-item properties: $allCoverageCount'),
          const SizedBox(height: 6),
          _Badge(label: 'Partial properties: $partialCoverageCount'),
          const SizedBox(height: 6),
          _Badge(label: 'Conflicted properties: $conflictedCount'),
          const SizedBox(height: 14),
          Text(
            'Unit strategy',
            style: _inventoryInterStyle(
              color: const Color(0xFF334155),
              size: 12,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (effectiveUnitGovernance.isEmpty)
            Text(
              'No units selected yet.',
              style: _inventoryInterStyle(
                color: const Color(0xFF94A3B8),
                size: 12,
                weight: FontWeight.w500,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: effectiveUnitGovernance
                  .map((unitRow) {
                    final card = selectedUnitCards
                        .where((entry) => entry.unitId == unitRow.unitId)
                        .firstOrNull;
                    if (card == null) {
                      return const SizedBox.shrink();
                    }
                    final stateText =
                        unitRow.state == groupcfg.GroupUnitState.detached
                        ? 'Detached'
                        : (unitRow.isPrimary ? 'Primary' : 'Active');
                    return _Badge(label: '${card.label} • $stateText');
                  })
                  .toList(growable: false),
            ),
        ],
      ),
    );

    final isCompactEditor = MediaQuery.of(context).size.width < 980;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF4F7FB)),
      child: Column(
        children: [
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5EAF1))),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeader = constraints.maxWidth < 1100;
                final titleCluster = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(999),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 22,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _isEditMode ? 'Edit Item Group' : 'Create Item Group',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _inventoryInterStyle(
                          color: const Color(0xFF1F2937),
                          size: 18,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _Badge(label: _generatedGroupId),
                  ],
                );
                final actionsCluster = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: widget.onClose,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD8E0EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: _inventoryInterStyle(
                          color: const Color(0xFF475569),
                          size: 13,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: inventory.isSaving || hasBlockingReview
                          ? null
                          : () => _submit(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2D8CFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      icon: inventory.isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.inventory_2_outlined, size: 16),
                      label: Text(
                        _isEditMode ? 'Save Changes' : 'Create Group',
                        style: _inventoryInterStyle(
                          color: Colors.white,
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
                if (compactHeader) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(child: titleCluster),
                          const SizedBox(width: 12),
                          Flexible(child: actionsCluster),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [titleCluster, const Spacer(), actionsCluster],
                );
              },
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (inventory.errorMessage != null) ...[
                      _ErrorBanner(message: inventory.errorMessage!),
                      const SizedBox(height: 16),
                    ],
                    if (_isHydratingExisting) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 14),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasBlockingReview
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasBlockingReview
                              ? const Color(0xFFFED7AA)
                              : const Color(0xFFBBF7D0),
                        ),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Badge(
                            label: hasBlockingReview
                                ? 'Needs review'
                                : 'Resolved',
                            tone: hasBlockingReview
                                ? _BadgeTone.warning
                                : _BadgeTone.success,
                          ),
                          _Badge(
                            label: 'Selected items ${_selectedItemIds.length}',
                            tone: _BadgeTone.info,
                          ),
                          _Badge(
                            label:
                                'Unit mismatch ${unitGroupMismatch ? 'Yes' : 'No'}',
                            tone: unitGroupMismatch
                                ? _BadgeTone.warning
                                : _BadgeTone.success,
                          ),
                          _Badge(
                            label: 'Conflicts $conflictedCount',
                            tone: conflictedCount > 0
                                ? _BadgeTone.warning
                                : _BadgeTone.success,
                          ),
                          _Badge(
                            label:
                                'Inherited ${activeInheritedProperties.length}',
                            tone: _BadgeTone.info,
                          ),
                          _Badge(
                            label: 'Overridden $overriddenCount',
                            tone: _BadgeTone.neutral,
                          ),
                        ],
                      ),
                    ),
                    if (hasBlockingReview &&
                        blockingReviewReasons.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Before create: ${blockingReviewReasons.join(' • ')}',
                        style: _inventoryInterStyle(
                          color: const Color(0xFFB45309),
                          size: 12,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (isCompactEditor) ...[
                      sourceWorkbenchCard,
                      const SizedBox(height: 18),
                      basicInformationCard,
                      const SizedBox(height: 18),
                      propertiesCard,
                      const SizedBox(height: 18),
                      liveOutcomeCard,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 9, child: sourceWorkbenchCard),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 10,
                            child: Column(
                              children: [
                                basicInformationCard,
                                const SizedBox(height: 18),
                                propertiesCard,
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(flex: 6, child: liveOutcomeCard),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _generatedGroupId {
    final normalized = _groupNameController.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (normalized.isEmpty) {
      return 'GRP-001';
    }
    final capped = normalized.length > 10
        ? normalized.substring(0, 10)
        : normalized;
    return 'GRP-$capped';
  }

  Future<void> _hydrateExistingGovernance() async {
    final initial = widget.initialRecord;
    if (initial == null || !mounted) {
      return;
    }

    setState(() {
      _isHydratingExisting = true;
    });

    final provider = context.read<InventoryProvider>();
    final configuration = await provider.loadGroupConfiguration(
      initial.barcode,
    );

    if (!mounted) {
      return;
    }

    if (configuration != null) {
      final itemsById = {
        for (final item in context.read<ItemsProvider>().items) item.id: item,
      };
      final loadedProperties = <_GroupPropertyDraft>[];
      final unlinkedKeys = <String>{};
      final unitGovernanceByUnitId = <int, _UnitGovernanceDraft>{};

      for (final draft in configuration.propertyDrafts) {
        final state = switch (draft.state) {
          governance.GroupPropertyState.active => _EditorPropertyState.active,
          governance.GroupPropertyState.unlinked =>
            _EditorPropertyState.unlinked,
          governance.GroupPropertyState.overridden =>
            _EditorPropertyState.overridden,
        };
        final sourceItemIds =
            draft.sources
                .map((source) => source.itemId)
                .where((id) => id > 0)
                .toSet()
                .toList(growable: false)
              ..sort();
        final sourceItemNames = sourceItemIds
            .map((id) => itemsById[id]?.displayName)
            .whereType<String>()
            .toList(growable: false);
        if (state == _EditorPropertyState.unlinked) {
          unlinkedKeys.add(_propertyKey(draft.name));
          continue;
        }
        if (draft.sourceType ==
                governance.GroupPropertySourceType.inheritedItem &&
            state == _EditorPropertyState.active &&
            draft.resolutionSource != 'resolved_by_user') {
          continue;
        }
        loadedProperties.add(
          _GroupPropertyDraft(
            name: draft.name,
            inputType: draft.inputType,
            mandatory: draft.mandatory,
            state: state,
            isInherited:
                draft.sourceType ==
                governance.GroupPropertySourceType.inheritedItem,
            sourceType: draft.sourceType,
            sourceLabel: sourceItemNames.isEmpty
                ? null
                : sourceItemNames.join(', '),
            sourceItemIds: sourceItemIds,
            sourceItemNames: sourceItemNames,
            overrideLocked: draft.overrideLocked,
            hasTypeConflict: draft.hasTypeConflict,
            coverageCount: draft.coverageCount,
            selectedItemCountAtResolution: draft.selectedItemCountAtResolution,
            resolutionSource: draft.resolutionSource,
          ),
        );
      }
      for (final row in configuration.unitGovernance) {
        if (row.unitId <= 0) {
          continue;
        }
        unitGovernanceByUnitId[row.unitId] = _UnitGovernanceDraft(
          unitId: row.unitId,
          state: row.state,
          isPrimary: row.isPrimary,
        );
      }

      setState(() {
        _inheritPropertiesFromItems = configuration.inheritanceEnabled;
        _commonOnlyMode = configuration.uiPreferences.commonOnlyMode;
        _showPartialMatches = configuration.uiPreferences.showPartialMatches;
        _selectedItemIds
          ..clear()
          ..addAll(configuration.selectedItemIds);
        _unlinkedInheritedPropertyKeys
          ..clear()
          ..addAll(unlinkedKeys);
        _properties
          ..clear()
          ..addAll(loadedProperties);
        _unitGovernanceByUnitId
          ..clear()
          ..addAll(unitGovernanceByUnitId);
      });
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isHydratingExisting = false;
    });
  }

  String _extractDescription(String notes) {
    final lines = notes.split('\n');
    for (final line in lines) {
      if (line.toLowerCase().startsWith('description:')) {
        return line.split(':').skip(1).join(':').trim();
      }
    }
    return '';
  }

  void _addProperty() {
    final name = _propertyNameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    final items = context.read<ItemsProvider>().items;
    final inheritedByKey = {
      for (final property in _derivedPropertiesFromItems(items))
        _propertyKey(property.name): property,
    };
    final key = _propertyKey(name);
    final inherited = inheritedByKey[key];
    setState(() {
      _upsertPropertyDraft(
        _GroupPropertyDraft(
          name: name,
          inputType: _propertyInputType,
          mandatory: _propertyMandatory,
          state: inherited == null
              ? _EditorPropertyState.active
              : _EditorPropertyState.overridden,
          sourceType: governance.GroupPropertySourceType.manual,
          sourceLabel: inherited == null
              ? 'Manual'
              : 'Override of ${inherited.sourceLabel ?? 'inherited property'}',
          sourceItemIds: inherited?.sourceItemIds ?? const <int>[],
          sourceItemNames: inherited?.sourceItemNames ?? const <String>[],
          hasTypeConflict: false,
          coverageCount: inherited?.coverageCount ?? 0,
          selectedItemCountAtResolution:
              inherited?.selectedItemCountAtResolution ?? 0,
          resolutionSource: inherited == null ? null : 'manual_override',
        ),
      );
      _unlinkedInheritedPropertyKeys.remove(key);
      _propertyNameController.clear();
      _propertyInputType = 'Text';
      _propertyMandatory = false;
    });
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final provider = context.read<InventoryProvider>();
    final selectedItems = context
        .read<ItemsProvider>()
        .items
        .where((item) => _selectedItemIds.contains(item.id))
        .map((item) => item.displayName)
        .toList(growable: false);
    final selectedUnits = _derivedUnitCards(
      context.read<ItemsProvider>().items,
      context.read<UnitsProvider>().activeUnits,
    );
    _syncUnitGovernanceDrafts(selectedUnits);
    final unitGovernanceRows = _effectiveUnitGovernance(selectedUnits);
    final allPropertyDrafts = _finalPropertyDrafts(
      context.read<ItemsProvider>().items,
    );
    final combinedProperties = allPropertyDrafts
        .where((property) => property.state != _EditorPropertyState.unlinked)
        .toList(growable: false);

    final notes = <String>[
      'Group ID: $_generatedGroupId',
      if (_descriptionController.text.trim().isNotEmpty)
        'Description: ${_descriptionController.text.trim()}',
      if (_locationController.text.trim().isNotEmpty)
        'Location: ${_locationController.text.trim()}',
      if (_selectedUnitGroup != null) 'Unit Group: $_selectedUnitGroup',
      'Variants Enabled: ${_enableVariants ? 'Yes' : 'No'}',
      'Property Inheritance: ${_inheritPropertiesFromItems ? 'Enabled' : 'Disabled'}',
      if (selectedItems.isNotEmpty)
        'Existing Items: ${selectedItems.join(', ')}',
      if (selectedUnits.isNotEmpty)
        'Units: ${selectedUnits.map((unit) => unit.label).join(', ')}',
      if (_unlinkedInheritedPropertyKeys.isNotEmpty)
        'Unlinked Properties: ${_unlinkedInheritedPropertyKeys.join(', ')}',
      if (combinedProperties.isNotEmpty)
        'Properties: ${combinedProperties.map((property) => property.summary).join(' | ')}',
    ].join('\n');

    final propertyDrafts = allPropertyDrafts
        .map(_toDomainPropertyDraft)
        .toList(growable: false);
    final selectedItemIds = _selectedItemIds.toList(growable: false);
    final initial = widget.initialRecord;
    if (initial == null) {
      await provider.addParentMaterial(
        CreateParentMaterialInput(
          name: _groupNameController.text.trim(),
          type: 'Item Group',
          grade: '',
          thickness: '',
          supplier: '',
          location: _locationController.text.trim(),
          unitId: null,
          unit: 'Pieces',
          groupMode: 'item_group_authoring',
          inheritanceEnabled: _inheritPropertiesFromItems,
          selectedItemIds: selectedItemIds,
          propertyDrafts: propertyDrafts,
          unitGovernance: unitGovernanceRows,
          uiPreferences: groupcfg.GroupUiPreferences(
            commonOnlyMode: _commonOnlyMode,
            showPartialMatches: _showPartialMatches,
          ),
          notes: notes,
          numberOfChildren: _selectedItemIds.length,
        ),
      );
    } else {
      await provider.updateMaterial(
        UpdateMaterialInput(
          barcode: initial.barcode,
          name: _groupNameController.text.trim(),
          type: initial.type.trim().isEmpty ? 'Item Group' : initial.type,
          grade: initial.grade,
          thickness: initial.thickness,
          supplier: initial.supplier,
          location: _locationController.text.trim(),
          unitId: initial.unitId,
          unit: initial.unit.trim().isEmpty ? 'Pieces' : initial.unit,
          notes: notes,
        ),
      );
      if (provider.errorMessage == null) {
        await provider.updateGroupConfiguration(
          initial.barcode,
          inheritanceEnabled: _inheritPropertiesFromItems,
          selectedItemIds: selectedItemIds,
          propertyDrafts: propertyDrafts,
          unitGovernance: unitGovernanceRows,
          uiPreferences: groupcfg.GroupUiPreferences(
            commonOnlyMode: _commonOnlyMode,
            showPartialMatches: _showPartialMatches,
          ),
        );
      }
    }

    if (!context.mounted || provider.errorMessage != null) {
      return;
    }

    widget.onClose();
  }

  List<_GroupPropertyDraft> _combinedProperties({
    required List<_GroupPropertyDraft> inheritedProperties,
  }) {
    final combined = <String, _GroupPropertyDraft>{};
    final inheritedByKey = <String, _GroupPropertyDraft>{
      for (final property in inheritedProperties)
        _propertyKey(property.name): property,
    };

    for (final property in _properties) {
      final key = _propertyKey(property.name);
      final inherited = inheritedByKey[key];
      if (inherited != null &&
          property.state == _EditorPropertyState.active &&
          property.sourceType == governance.GroupPropertySourceType.manual) {
        combined[key] = property.copyWith(
          state: _EditorPropertyState.overridden,
          sourceItemIds: inherited.sourceItemIds,
          sourceItemNames: inherited.sourceItemNames,
          sourceLabel: inherited.sourceLabel == null
              ? 'Override'
              : 'Override of ${inherited.sourceLabel}',
          coverageCount: inherited.coverageCount,
          selectedItemCountAtResolution:
              inherited.selectedItemCountAtResolution,
          resolutionSource: 'manual_override',
        );
        continue;
      }
      if (inherited != null &&
          property.sourceType ==
              governance.GroupPropertySourceType.inheritedItem) {
        combined[key] = property.copyWith(
          sourceItemIds: inherited.sourceItemIds,
          sourceItemNames: inherited.sourceItemNames,
          sourceLabel: inherited.sourceLabel,
          coverageCount: inherited.coverageCount,
          selectedItemCountAtResolution:
              inherited.selectedItemCountAtResolution,
        );
        continue;
      }
      combined[key] = property;
    }

    for (final property in inheritedProperties) {
      combined.putIfAbsent(_propertyKey(property.name), () => property);
    }

    return combined.values.toList(growable: false);
  }

  List<_GroupPropertyDraft> _derivedPropertiesFromItems(
    List<ItemDefinition> items,
  ) {
    final propertySources = <String, Set<String>>{};
    final propertySourceIds = <String, Set<int>>{};
    final propertyTypes = <String, String>{};
    final propertyTypeSet = <String, Set<String>>{};

    for (final item in items.where(
      (item) => _selectedItemIds.contains(item.id),
    )) {
      for (final property in item.topLevelProperties) {
        final propertyName = property.displayName.trim();
        if (propertyName.isEmpty) {
          continue;
        }
        final key = propertyName.toLowerCase();
        propertySources
            .putIfAbsent(key, () => <String>{})
            .add(item.displayName);
        propertySourceIds.putIfAbsent(key, () => <int>{}).add(item.id);
        final inferredType = property.activeChildren.isNotEmpty
            ? 'Dropdown'
            : 'Text';
        propertyTypes[key] = inferredType;
        propertyTypeSet.putIfAbsent(key, () => <String>{}).add(inferredType);
      }
    }

    return propertySources.entries
        .map((entry) {
          final key = entry.key;
          final sourceLabel = entry.value.toList(growable: false)..sort();
          final sourceIds = (propertySourceIds[key] ?? <int>{}).toList(
            growable: false,
          )..sort();
          final hasTypeConflict = (propertyTypeSet[key]?.length ?? 0) > 1;
          return _GroupPropertyDraft(
            name: _titleCaseFromKey(key),
            inputType: hasTypeConflict
                ? 'Text'
                : (propertyTypes[key] ?? 'Text'),
            mandatory: false,
            isInherited: true,
            sourceType: governance.GroupPropertySourceType.inheritedItem,
            sourceLabel: sourceLabel.join(', '),
            sourceItemIds: sourceIds,
            sourceItemNames: sourceLabel,
            hasTypeConflict: hasTypeConflict,
            coverageCount: sourceIds.length,
            selectedItemCountAtResolution: _selectedItemIds.length,
            resolutionSource: hasTypeConflict
                ? 'conflict_default_text'
                : 'inferred_from_items',
          );
        })
        .toList(growable: false);
  }

  List<_SelectedUnitCardData> _derivedUnitCards(
    List<ItemDefinition> items,
    List<UnitDefinition> units,
  ) {
    final unitLabelById = <int, String>{
      for (final unit in units)
        unit.id: unit.isGrouped
            ? '${unit.displayLabel} • ${unit.unitGroupName}'
            : unit.displayLabel,
    };
    final groupedItems = <int, List<ItemDefinition>>{};

    for (final item in items.where(
      (item) => _selectedItemIds.contains(item.id),
    )) {
      groupedItems.putIfAbsent(item.unitId, () => <ItemDefinition>[]).add(item);
    }

    return groupedItems.entries
        .map((entry) {
          final unitId = entry.key;
          final itemNames =
              entry.value
                  .map((item) => item.displayName)
                  .toList(growable: false)
                ..sort();
          return _SelectedUnitCardData(
            unitId: unitId,
            label: unitLabelById[unitId] ?? 'Unit #$unitId',
            linkedItemNames: itemNames,
          );
        })
        .toList(growable: false)
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  String _titleCaseFromKey(String key) {
    return key
        .split(RegExp(r'[\s_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _propertyKey(String value) => value.trim().toLowerCase();

  (String, Color) _itemCompatibilityLabel({
    required ItemDefinition item,
    required List<ItemDefinition> selectedItems,
    required List<UnitDefinition> units,
  }) {
    if (item.isArchived) {
      return ('archived/legacy risk', const Color(0xFF9A3412));
    }
    if (selectedItems.isEmpty) {
      return ('fully compatible', const Color(0xFF047857));
    }
    final selectedUnitIds = selectedItems.map((entry) => entry.unitId).toSet();
    final unitById = {for (final unit in units) unit.id: unit};
    final itemUnit = unitById[item.unitId];
    final selectedUnitGroupIds = selectedUnitIds
        .map((unitId) => unitById[unitId]?.unitGroupId)
        .toSet();
    final selectedExplicitUnits = selectedUnitIds;
    final sharesExplicitUnit = selectedExplicitUnits.contains(item.unitId);
    final sharesUnitGroup =
        itemUnit?.unitGroupId != null &&
        selectedUnitGroupIds.contains(itemUnit!.unitGroupId);
    if (!sharesExplicitUnit && !sharesUnitGroup) {
      return ('unit mismatch', const Color(0xFFB45309));
    }
    if (item.topLevelProperties.isEmpty) {
      return ('schema mismatch', const Color(0xFFB91C1C));
    }
    return ('fully compatible', const Color(0xFF047857));
  }

  void _syncUnitGovernanceDrafts(List<_SelectedUnitCardData> cards) {
    final validUnitIds = cards.map((entry) => entry.unitId).toSet();
    _unitGovernanceByUnitId.removeWhere(
      (unitId, _) => !validUnitIds.contains(unitId),
    );
    for (final card in cards) {
      _unitGovernanceByUnitId.putIfAbsent(
        card.unitId,
        () => _UnitGovernanceDraft(unitId: card.unitId),
      );
    }
    final activeRows = _unitGovernanceByUnitId.values
        .where((row) => row.state == groupcfg.GroupUnitState.active)
        .toList(growable: false);
    if (activeRows.isNotEmpty && !activeRows.any((row) => row.isPrimary)) {
      final first = activeRows.first;
      _unitGovernanceByUnitId[first.unitId] = first.copyWith(isPrimary: true);
    }
  }

  List<groupcfg.GroupUnitGovernance> _effectiveUnitGovernance(
    List<_SelectedUnitCardData> cards,
  ) {
    final validUnitIds = cards.map((entry) => entry.unitId).toSet();
    return _unitGovernanceByUnitId.values
        .where((row) => validUnitIds.contains(row.unitId))
        .map(
          (row) => groupcfg.GroupUnitGovernance(
            unitId: row.unitId,
            state: row.state,
            isPrimary: row.isPrimary,
          ),
        )
        .toList(growable: false);
  }

  bool _hasUnitGroupMismatch(
    List<_SelectedUnitCardData> cards,
    List<UnitDefinition> units,
    List<groupcfg.GroupUnitGovernance> governanceRows,
  ) {
    if (cards.length <= 1) {
      return false;
    }
    final unitById = {for (final unit in units) unit.id: unit};
    final activeUnitIds = governanceRows
        .where((row) => row.state == groupcfg.GroupUnitState.active)
        .map((row) => row.unitId)
        .toSet();
    final scoped = cards
        .where((card) => activeUnitIds.contains(card.unitId))
        .map((card) => unitById[card.unitId])
        .whereType<UnitDefinition>()
        .toList(growable: false);
    final groupKeys = scoped
        .map((unit) => unit.unitGroupId ?? -unit.id)
        .toSet();
    return groupKeys.length > 1;
  }

  void _upsertPropertyDraft(_GroupPropertyDraft draft) {
    final key = _propertyKey(draft.name);
    _properties.removeWhere((property) => _propertyKey(property.name) == key);
    _properties.add(draft);
  }

  List<_GroupPropertyDraft> _finalPropertyDrafts(List<ItemDefinition> items) {
    final inherited = _inheritPropertiesFromItems
        ? _derivedPropertiesFromItems(items)
        : const <_GroupPropertyDraft>[];
    final activeInherited = inherited
        .where(
          (property) => !_unlinkedInheritedPropertyKeys.contains(
            _propertyKey(property.name),
          ),
        )
        .toList(growable: false);
    final unlinkedInherited = inherited
        .where(
          (property) => _unlinkedInheritedPropertyKeys.contains(
            _propertyKey(property.name),
          ),
        )
        .map(
          (property) => property.copyWith(state: _EditorPropertyState.unlinked),
        )
        .toList(growable: false);
    final combined = _combinedProperties(inheritedProperties: activeInherited);
    return [...combined, ...unlinkedInherited];
  }

  governance.GroupPropertyDraft _toDomainPropertyDraft(
    _GroupPropertyDraft property,
  ) {
    final sourceIds = property.sourceItemIds
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    return governance.GroupPropertyDraft(
      name: property.name,
      inputType: property.inputType,
      mandatory: property.mandatory,
      sourceType: property.sourceType,
      state: switch (property.state) {
        _EditorPropertyState.active => governance.GroupPropertyState.active,
        _EditorPropertyState.unlinked => governance.GroupPropertyState.unlinked,
        _EditorPropertyState.overridden =>
          governance.GroupPropertyState.overridden,
      },
      sources: sourceIds
          .map((itemId) => governance.GroupPropertySource(itemId: itemId))
          .toList(growable: false),
      overrideLocked: property.overrideLocked,
      hasTypeConflict: property.hasTypeConflict,
      coverageCount: property.coverageCount,
      selectedItemCountAtResolution: property.selectedItemCountAtResolution,
      resolutionSource: property.resolutionSource,
    );
  }
}

class _GroupPropertyDraft {
  const _GroupPropertyDraft({
    required this.name,
    required this.inputType,
    required this.mandatory,
    this.state = _EditorPropertyState.active,
    this.isInherited = false,
    this.sourceType = governance.GroupPropertySourceType.manual,
    this.sourceLabel,
    this.sourceItemIds = const <int>[],
    this.sourceItemNames = const <String>[],
    this.overrideLocked = false,
    this.hasTypeConflict = false,
    this.coverageCount = 0,
    this.selectedItemCountAtResolution = 0,
    this.resolutionSource,
  });

  final String name;
  final String inputType;
  final bool mandatory;
  final _EditorPropertyState state;
  final bool isInherited;
  final governance.GroupPropertySourceType sourceType;
  final String? sourceLabel;
  final List<int> sourceItemIds;
  final List<String> sourceItemNames;
  final bool overrideLocked;
  final bool hasTypeConflict;
  final int coverageCount;
  final int selectedItemCountAtResolution;
  final String? resolutionSource;

  _GroupPropertyDraft copyWith({
    String? name,
    String? inputType,
    bool? mandatory,
    _EditorPropertyState? state,
    bool? isInherited,
    governance.GroupPropertySourceType? sourceType,
    String? sourceLabel,
    List<int>? sourceItemIds,
    List<String>? sourceItemNames,
    bool? overrideLocked,
    bool? hasTypeConflict,
    int? coverageCount,
    int? selectedItemCountAtResolution,
    String? resolutionSource,
  }) {
    return _GroupPropertyDraft(
      name: name ?? this.name,
      inputType: inputType ?? this.inputType,
      mandatory: mandatory ?? this.mandatory,
      state: state ?? this.state,
      isInherited: isInherited ?? this.isInherited,
      sourceType: sourceType ?? this.sourceType,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      sourceItemIds: sourceItemIds ?? this.sourceItemIds,
      sourceItemNames: sourceItemNames ?? this.sourceItemNames,
      overrideLocked: overrideLocked ?? this.overrideLocked,
      hasTypeConflict: hasTypeConflict ?? this.hasTypeConflict,
      coverageCount: coverageCount ?? this.coverageCount,
      selectedItemCountAtResolution:
          selectedItemCountAtResolution ?? this.selectedItemCountAtResolution,
      resolutionSource: resolutionSource ?? this.resolutionSource,
    );
  }

  String get summary =>
      '$name [$inputType${mandatory ? ', Required' : ''}${sourceLabel == null ? '' : ', $sourceLabel'}]';
}

enum _EditorPropertyState { active, unlinked, overridden }

class _SelectedUnitCardData {
  const _SelectedUnitCardData({
    required this.unitId,
    required this.label,
    required this.linkedItemNames,
  });

  final int unitId;
  final String label;
  final List<String> linkedItemNames;
}

class _UnitGovernanceDraft {
  const _UnitGovernanceDraft({
    required this.unitId,
    this.state = groupcfg.GroupUnitState.active,
    this.isPrimary = false,
  });

  final int unitId;
  final groupcfg.GroupUnitState state;
  final bool isPrimary;

  _UnitGovernanceDraft copyWith({
    groupcfg.GroupUnitState? state,
    bool? isPrimary,
  }) {
    return _UnitGovernanceDraft(
      unitId: unitId,
      state: state ?? this.state,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
}

class _CreateGroupEditorCard extends StatelessWidget {
  const _CreateGroupEditorCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _inventoryInterStyle(
              color: const Color(0xFF0F172A),
              size: 18,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _EditorFieldLabel extends StatelessWidget {
  const _EditorFieldLabel(this.label, {this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: _inventoryInterStyle(
          color: const Color(0xFF334155),
          size: 12,
          weight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: label),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
        ],
      ),
    );
  }
}

class _EditorTextField extends StatelessWidget {
  const _EditorTextField({
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String hintText;
  final int maxLines;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final contentPadding = maxLines > 1
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    return TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: const Color(0xFFF1F8FF),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 18, color: const Color(0xFF94A3B8)),
        contentPadding: contentPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD7E5F5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD7E5F5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF93C5FD)),
        ),
      ),
      style: _inventoryInterStyle(
        color: const Color(0xFF334155),
        size: 14,
        weight: FontWeight.w400,
      ),
    );
  }
}

class _EditorReadOnlyField extends StatelessWidget {
  const _EditorReadOnlyField({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E5F5)),
      ),
      child: Text(
        value,
        style: _inventoryInterStyle(
          color: const Color(0xFF64748B),
          size: 14,
          weight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _EditorDropdownField extends StatelessWidget {
  const _EditorDropdownField({
    required this.value,
    required this.hintText,
    required this.options,
    required this.onSelected,
  });

  final String? value;
  final String hintText;
  final List<String> options;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E5F5)),
      ),
      child: _CreateGroupDropdown(
        value: value,
        placeholder: hintText,
        options: options,
        onSelected: onSelected,
      ),
    );
  }
}

class _EditorCheckboxTile extends StatelessWidget {
  const _EditorCheckboxTile({
    required this.value,
    required this.title,
    required this.onChanged,
    this.subtitle,
    this.dense = false,
  });

  final bool value;
  final String title;
  final String? subtitle;
  final ValueChanged<bool> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 2 : 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (checked) => onChanged(checked ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _inventoryInterStyle(
                      color: const Color(0xFF334155),
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: _inventoryInterStyle(
                        color: const Color(0xFF94A3B8),
                        size: 12,
                        weight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSelectableItemTile extends StatelessWidget {
  const _EditorSelectableItemTile({
    required this.item,
    required this.selected,
    required this.compatibilityLabel,
    required this.compatibilityTone,
    required this.propertyContributionCount,
    this.isDisabled = false,
    required this.onChanged,
  });

  final ItemDefinition item;
  final bool selected;
  final String compatibilityLabel;
  final Color compatibilityTone;
  final int propertyContributionCount;
  final bool isDisabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isDisabled ? null : () => onChanged(!selected),
      hoverColor: const Color(0xFFF8FBFF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: isDisabled
                  ? null
                  : (checked) => onChanged(checked ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    style: _inventoryInterStyle(
                      color: isDisabled
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF334155),
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ITM-${item.id.toString().padLeft(3, '0')} · ${item.alias.ifEmpty(item.name)}',
                    style: _inventoryInterStyle(
                      color: const Color(0xFF94A3B8),
                      size: 11,
                      weight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Badge(label: 'Properties: $propertyContributionCount'),
                      _Badge(label: 'Qty: ${item.quantity.toStringAsFixed(0)}'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: compatibilityTone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          compatibilityLabel,
                          style: _inventoryInterStyle(
                            color: compatibilityTone,
                            size: 10,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorPropertyListTile extends StatelessWidget {
  const _EditorPropertyListTile({
    required this.property,
    required this.inputTypeOptions,
    this.onRemove,
    this.onUnlink,
    this.onConvertToManual,
    this.onToggleLockOverride,
    this.onResolveInputType,
  });

  final _GroupPropertyDraft property;
  final List<String> inputTypeOptions;
  final VoidCallback? onRemove;
  final VoidCallback? onUnlink;
  final VoidCallback? onConvertToManual;
  final VoidCallback? onToggleLockOverride;
  final ValueChanged<String>? onResolveInputType;

  String _originPatternLabel(_GroupPropertyDraft property) {
    if (property.selectedItemCountAtResolution <= 0 ||
        property.coverageCount <= 0) {
      return 'source unknown';
    }
    if (property.coverageCount >= property.selectedItemCountAtResolution) {
      return 'all items';
    }
    if (property.coverageCount == 1) {
      return 'single item';
    }
    return 'most items';
  }

  @override
  Widget build(BuildContext context) {
    final statusStyle = switch (property.state) {
      _EditorPropertyState.active => (
        label: property.isInherited ? 'Inherited' : 'Manual',
        bg: property.isInherited
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFF1F5F9),
        text: property.isInherited
            ? const Color(0xFF1D4ED8)
            : const Color(0xFF475569),
      ),
      _EditorPropertyState.unlinked => (
        label: 'Unlinked',
        bg: const Color(0xFFFFF7ED),
        text: const Color(0xFFB45309),
      ),
      _EditorPropertyState.overridden => (
        label: 'Overridden',
        bg: const Color(0xFFF1F5F9),
        text: const Color(0xFF334155),
      ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      property.name,
                      style: _inventoryInterStyle(
                        color: const Color(0xFF0F172A),
                        size: 13,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusStyle.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusStyle.label,
                        style: _inventoryInterStyle(
                          color: statusStyle.text,
                          size: 10,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (property.mandatory) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDEBEC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Required',
                          style: _inventoryInterStyle(
                            color: const Color(0xFFEF4444),
                            size: 10,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  property.inputType,
                  style: _inventoryInterStyle(
                    color: const Color(0xFF94A3B8),
                    size: 12,
                    weight: FontWeight.w400,
                  ),
                ),
                if (property.coverageCount > 0 &&
                    property.selectedItemCountAtResolution > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Coverage ${property.coverageCount}/${property.selectedItemCountAtResolution} · ${_originPatternLabel(property)}',
                    style: _inventoryInterStyle(
                      color: const Color(0xFF64748B),
                      size: 11,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
                if (property.sourceLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    property.sourceLabel!,
                    style: _inventoryInterStyle(
                      color: property.isInherited
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                      size: 11,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
                if (property.sourceItemNames.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: property.sourceItemNames
                        .map((name) => _Badge(label: name))
                        .toList(growable: false),
                  ),
                ],
                if (property.hasTypeConflict) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Type conflict detected across selected source items.',
                          style: _inventoryInterStyle(
                            color: const Color(0xFF9A3412),
                            size: 11,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Resolve type',
                          style: _inventoryInterStyle(
                            color: const Color(0xFF64748B),
                            size: 11,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value:
                                  inputTypeOptions.contains(property.inputType)
                                  ? property.inputType
                                  : inputTypeOptions.first,
                              isExpanded: true,
                              items: inputTypeOptions
                                  .map(
                                    (type) => DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(
                                        type,
                                        style: _inventoryInterStyle(
                                          color: const Color(0xFF334155),
                                          size: 12,
                                          weight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: onResolveInputType == null
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      onResolveInputType!(value);
                                    },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (property.state == _EditorPropertyState.overridden &&
                    !property.isInherited) ...[
                  const SizedBox(height: 8),
                  Text(
                    property.overrideLocked
                        ? 'Override is locked.'
                        : 'Override is editable.',
                    style: _inventoryInterStyle(
                      color: const Color(0xFF64748B),
                      size: 11,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onUnlink != null)
            OutlinedButton.icon(
              onPressed: onUnlink,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1D4ED8),
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.link_off_rounded, size: 14),
              label: Text(
                'Unlink',
                style: _inventoryInterStyle(
                  color: const Color(0xFF1D4ED8),
                  size: 11,
                  weight: FontWeight.w600,
                ),
              ),
            )
          else if (onConvertToManual != null || onToggleLockOverride != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (onConvertToManual != null)
                  OutlinedButton.icon(
                    onPressed: onConvertToManual,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.draw_rounded, size: 14),
                    label: Text(
                      'Convert to Manual',
                      style: _inventoryInterStyle(
                        color: const Color(0xFF334155),
                        size: 11,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (onToggleLockOverride != null)
                  OutlinedButton.icon(
                    onPressed: onToggleLockOverride,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      property.overrideLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 14,
                    ),
                    label: Text(
                      property.overrideLocked
                          ? 'Unlock Override'
                          : 'Lock Override',
                      style: _inventoryInterStyle(
                        color: const Color(0xFF334155),
                        size: 11,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            )
          else if (onRemove != null)
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditorUnitCard extends StatelessWidget {
  const _EditorUnitCard({
    required this.unitCard,
    required this.state,
    required this.isPrimary,
    required this.onRemove,
    required this.onToggleDetach,
    required this.onSetPrimary,
  });

  final _SelectedUnitCardData unitCard;
  final groupcfg.GroupUnitState state;
  final bool isPrimary;
  final VoidCallback onRemove;
  final VoidCallback onToggleDetach;
  final VoidCallback onSetPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E5F5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unitCard.label,
                  style: _inventoryInterStyle(
                    color: const Color(0xFF0F172A),
                    size: 13,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Linked items: ${unitCard.linkedItemNames.join(', ')}',
                  style: _inventoryInterStyle(
                    color: const Color(0xFF64748B),
                    size: 12,
                    weight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Badge(
                      label: state == groupcfg.GroupUnitState.detached
                          ? 'Detached'
                          : (isPrimary ? 'Primary' : 'Active'),
                    ),
                    ActionChip(
                      label: Text(
                        state == groupcfg.GroupUnitState.detached
                            ? 'Attach'
                            : 'Detach',
                      ),
                      onPressed: onToggleDetach,
                    ),
                    if (state != groupcfg.GroupUnitState.detached)
                      ActionChip(
                        label: const Text('Set primary'),
                        onPressed: onSetPrimary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: Color(0xFF3B82F6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddStockForm extends StatefulWidget {
  const _AddStockForm();

  @override
  State<_AddStockForm> createState() => _AddStockFormState();
}

class _AddStockFormState extends State<_AddStockForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _gradeController = TextEditingController();
  final _thicknessController = TextEditingController();
  final _supplierController = TextEditingController();
  final _childrenController = TextEditingController(text: '0');

  UnitDefinition? _selectedUnit;

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _gradeController.dispose();
    _thicknessController.dispose();
    _supplierController.dispose();
    _childrenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle(
                  title: 'Add Inventory Stock',
                  subtitle:
                      'Create a parent stock record and optionally pre-split it into child barcodes for tracking.',
                ),
                const SizedBox(height: 16),
                _SimpleField(controller: _nameController, label: 'Name'),
                const SizedBox(height: 12),
                _SimpleField(controller: _typeController, label: 'Type'),
                const SizedBox(height: 12),
                _SimpleField(controller: _gradeController, label: 'Grade'),
                const SizedBox(height: 12),
                _SimpleField(
                  controller: _thicknessController,
                  label: 'Thickness',
                ),
                const SizedBox(height: 12),
                _SimpleField(
                  controller: _supplierController,
                  label: 'Supplier',
                ),
                const SizedBox(height: 12),
                _StockUnitField(
                  selectedUnit: _selectedUnit,
                  onPressed: _selectUnit,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _childrenController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cut into X children',
                  ),
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed < 0) {
                      return 'Enter 0 or more';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    AppButton(
                      label: 'Save Parent + Children',
                      isLoading: provider.isSaving,
                      onPressed: () => _submit(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectUnit() async {
    final selected = await showDialog<UnitDefinition>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _UnitPickerSheet(),
        ),
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _selectedUnit = selected;
    });
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await context.read<InventoryProvider>().addParentMaterial(
      CreateParentMaterialInput(
        name: _nameController.text.trim(),
        type: _typeController.text.trim(),
        grade: _gradeController.text.trim(),
        thickness: _thicknessController.text.trim(),
        supplier: _supplierController.text.trim(),
        unitId: _selectedUnit?.id,
        unit: _selectedUnit?.symbol ?? 'Pieces',
        notes: '',
        numberOfChildren: int.tryParse(_childrenController.text.trim()) ?? 0,
      ),
    );

    if (!context.mounted ||
        context.read<InventoryProvider>().errorMessage != null) {
      return;
    }

    Navigator.of(context).pop(true);
  }
}

class _StockUnitField extends StatelessWidget {
  const _StockUnitField({required this.selectedUnit, required this.onPressed});

  final UnitDefinition? selectedUnit;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = selectedUnit == null
        ? 'Select a unit'
        : '${selectedUnit!.name} (${selectedUnit!.symbol})';
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Unit'),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: onPressed, child: Text(label)),
      ),
    );
  }
}

class _UnitPickerSheet extends StatefulWidget {
  const _UnitPickerSheet();

  @override
  State<_UnitPickerSheet> createState() => _UnitPickerSheetState();
}

class _UnitPickerSheetState extends State<_UnitPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    final query = _normalizeUnitQuery(_searchController.text);
    final units = provider.activeUnits
        .where((unit) {
          if (query.isEmpty) {
            return true;
          }
          return _normalizeUnitQuery(unit.name).contains(query) ||
              _normalizeUnitQuery(unit.symbol).contains(query);
        })
        .toList(growable: false);
    final canCreate =
        query.isNotEmpty &&
        !provider.activeUnits.any(
          (unit) =>
              _normalizeUnitQuery(unit.name) == query ||
              _normalizeUnitQuery(unit.symbol) == query,
        );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Select a unit',
            subtitle:
                'Pick an existing unit or create one inline for this stock entry.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search unit name or symbol',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final unit in units)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${unit.name} (${unit.symbol})'),
                      onTap: () => Navigator.of(context).pop(unit),
                    ),
                  if (canCreate)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Create "${_searchController.text.trim()}"'),
                      onTap: () => _openCreateUnit(context),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateUnit(BuildContext context) async {
    final created = await showDialog<UnitDefinition>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _QuickCreateUnitSheet(initialName: _searchController.text),
        ),
      ),
    );
    if (!context.mounted || created == null) {
      return;
    }
    Navigator.of(context).pop(created);
  }

  static String _normalizeUnitQuery(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

class _QuickCreateUnitSheet extends StatefulWidget {
  const _QuickCreateUnitSheet({required this.initialName});

  final String initialName;

  @override
  State<_QuickCreateUnitSheet> createState() => _QuickCreateUnitSheetState();
}

class _QuickCreateUnitSheetState extends State<_QuickCreateUnitSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final TextEditingController _symbolController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName.trim());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _symbolController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle(
              title: 'Create Unit',
              subtitle: 'Add the missing unit without leaving the stock flow.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _symbolController,
              decoration: const InputDecoration(labelText: 'Symbol'),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _submit(context),
                  child: const Text('Create Unit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = context.read<UnitsProvider>();
    final created = await provider.createUnit(
      CreateUnitInput(
        name: _nameController.text.trim(),
        symbol: _symbolController.text.trim(),
      ),
    );
    if (!context.mounted || created == null) {
      return;
    }
    Navigator.of(context).pop(created);
  }
}

enum _BadgeTone { brand, info, neutral, success, warning }

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    this.tone = _BadgeTone.brand,
    this.color,
    this.borderColor,
    this.textColor,
  });

  final String label;
  final _BadgeTone tone;
  final Color? color;
  final Color? borderColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    var (backgroundColor, tColor) = switch (tone) {
      _BadgeTone.brand => (const Color(0xFFEEEAFE), const Color(0xFF5B4FE6)),
      _BadgeTone.info => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
      _BadgeTone.neutral => (const Color(0xFFF1F5F9), const Color(0xFF334155)),
      _BadgeTone.success => (const Color(0xFFECFDF3), const Color(0xFF047857)),
      _BadgeTone.warning => (const Color(0xFFFFF7ED), const Color(0xFFB45309)),
    };

    backgroundColor = color ?? backgroundColor;
    tColor = textColor ?? tColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: tColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InventoryLoadingSkeleton extends StatelessWidget {
  const _InventoryLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F6FA),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InventorySkeletonBox(width: 150, height: 26),
            const SizedBox(height: 18),
            Row(
              children: const [
                _InventorySkeletonBox(width: 140, height: 38, radius: 999),
                SizedBox(width: 12),
                _InventorySkeletonBox(width: 240, height: 38, radius: 10),
                Spacer(),
                _InventorySkeletonBox(width: 120, height: 38, radius: 10),
                SizedBox(width: 10),
                _InventorySkeletonBox(width: 120, height: 38, radius: 10),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE9E9EE)),
            const SizedBox(height: 16),
            Row(
              children: const [
                Expanded(child: _InventorySkeletonBox(height: 62, radius: 14)),
                SizedBox(width: 12),
                Expanded(child: _InventorySkeletonBox(height: 62, radius: 14)),
                SizedBox(width: 12),
                Expanded(child: _InventorySkeletonBox(height: 62, radius: 14)),
              ],
            ),
            const SizedBox(height: 18),
            const _InventorySkeletonBox(height: 44, radius: 12),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 7,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return const _InventorySkeletonBox(height: 68, radius: 12);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventorySkeletonBox extends StatelessWidget {
  const _InventorySkeletonBox({
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF0EFF6),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _NullableStringX on String? {
  String ifEmpty(String fallback) {
    final value = this;
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return value;
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
