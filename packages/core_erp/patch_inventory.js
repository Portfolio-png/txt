const fs = require('fs');

const path = 'f:/Rutu/txt/packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart';
let content = fs.readFileSync(path, 'utf8');

// The target _buildRows block for Items mode
const targetOld = `
    if (_viewMode == _InventoryViewMode.items) {
      final activeSetLinesByKey = activeSet == null
          ? const <String, InventorySetLineDefinition>{}
          : <String, InventorySetLineDefinition>{
              for (final line in activeSet.lines)
                _inventorySetLineKey(
                  itemId: line.itemId,
                  variationLeafNodeId: line.variationLeafNodeId,
                ): line,
            };
      final coveredSetLineKeys = <String>{};
      final coveredItemIds = <int>{};
      final rows = scopedRecords
          .where((record) => record.linkedItemId != null)
          .map((record) {
            final linkedItem = record.linkedItemId == null
                ? null
                : itemById[record.linkedItemId];
            final setLineKey = linkedItem == null
                ? null
                : _inventorySetLineKey(
                    itemId: linkedItem.id,
                    variationLeafNodeId: record.linkedVariationLeafNodeId ?? 0,
                  );
            final setLine = setLineKey == null
                ? null
                : activeSetLinesByKey[setLineKey];
            if (_activeGroupIdFilter != null &&
                linkedItem?.groupId != _activeGroupIdFilter) {
              return null;
            }
            if (activeSet != null && setLine == null) {
              return null;
            }
            if (setLineKey != null) {
              coveredSetLineKeys.add(setLineKey);
              if (linkedItem != null) {
                coveredItemIds.add(linkedItem.id);
              }
            }
            final linkedGroupName = linkedItem == null
                ? null
                : groupNameById[linkedItem.groupId];
            String? resolvedVariationPathLabel = setLine?.variationPathLabel;
            if ((resolvedVariationPathLabel == null ||
                    resolvedVariationPathLabel.isEmpty) &&
                record.name.contains(' - ')) {
              resolvedVariationPathLabel = record.name.substring(
                record.name.lastIndexOf(' - ') + 3,
              );
            }
            return _InventoryRowEntry(
              record: record,
              displayName: linkedItem == null
                  ? record.name
                  : linkedItem.displayName.trim().isEmpty
                  ? linkedItem.name
                  : linkedItem.displayName,
              displayId: record.barcode,
              displayMetadata: _itemMetadataText(
                record,
                linkedGroupName,
                variationPathLabel: resolvedVariationPathLabel,
              ),
              itemGroupId: linkedItem?.groupId,
              setQuantity: setLine?.quantity,
            );
          })
          .whereType<_InventoryRowEntry>()
          .toList(growable: true);

      if (activeSet != null) {
        for (final line in activeSet.lines) {
          final setLineKey = _inventorySetLineKey(
            itemId: line.itemId,
            variationLeafNodeId: line.variationLeafNodeId,
          );
          if (!coveredSetLineKeys.contains(setLineKey)) {
            final linkedItem = itemById[line.itemId];
            if (_activeGroupIdFilter != null &&
                linkedItem?.groupId != _activeGroupIdFilter) {
              continue;
            }
            if (linkedItem != null) {
              coveredItemIds.add(linkedItem.id);
              final linkedGroupName = groupNameById[linkedItem.groupId];
              rows.add(
                _InventoryRowEntry(
                  record: MaterialRecord(
                    id: 0,
                    barcode: 'set-req-$setLineKey',
                    name: linkedItem.name,
                    type: 'Item',
                    grade: '',
                    thickness: '',
                    supplier: '',
                    unitId: linkedItem.unitId,
                    unit: linkedItem.unit,
                    createdAt: DateTime.now(),
                    kind: 'set_requirement',
                    parentBarcode: null,
                    numberOfChildren: 0,
                    linkedChildBarcodes: [],
                    scanCount: 0,
                    displayStock: 'Missing',
                    createdBy: 'System',
                    workflowStatus: 'notStarted',
                    linkedItemId: linkedItem.id,
                    linkedVariationLeafNodeId: line.variationLeafNodeId,
                  ),
                  displayName: linkedItem.displayName.trim().isEmpty
                      ? linkedItem.name
                      : linkedItem.displayName,
                  displayId: 'set-req-$setLineKey',
                  displayMetadata: _itemMetadataText(
                    MaterialRecord(
                      id: 0,
                      barcode: 'set-req-$setLineKey',
                      name: linkedItem.name,
                      type: 'Item',
                      grade: '',
                      thickness: '',
                      supplier: '',
                      createdAt: DateTime.now(),
                      kind: 'set_requirement',
                      parentBarcode: null,
                      numberOfChildren: 0,
                      linkedChildBarcodes: [],
                      scanCount: 0,
                    ),
                    linkedGroupName,
                    variationPathLabel: line.variationPathLabel,
                  ),
                  itemGroupId: linkedItem.groupId,
                  setQuantity: line.quantity,
                ),
              );
            }
          }
        }
      }

      return rows;
    }
`;

const targetNew = `
    if (_viewMode == _InventoryViewMode.items) {
      final activeSetLinesByKey = activeSet == null
          ? const <String, InventorySetLineDefinition>{}
          : <String, InventorySetLineDefinition>{
              for (final line in activeSet.lines)
                _inventorySetLineKey(
                  itemId: line.itemId,
                  variationLeafNodeId: line.variationLeafNodeId,
                ): line,
            };
      final coveredSetLineKeys = <String>{};
      final coveredItemIds = <int>{};
      
      final recordsByItemId = <int, List<MaterialRecord>>{};
      
      for (final record in scopedRecords) {
        if (record.linkedItemId != null) {
          recordsByItemId.putIfAbsent(record.linkedItemId!, () => []).add(record);
        }
      }
      
      final rows = <_InventoryRowEntry>[];
      
      for (final itemId in recordsByItemId.keys) {
        final linkedItem = itemById[itemId];
        if (linkedItem == null) continue;
        if (_activeGroupIdFilter != null && linkedItem.groupId != _activeGroupIdFilter) {
          continue;
        }
        
        final itemRecords = recordsByItemId[itemId]!;
        final linkedGroupName = groupNameById[linkedItem.groupId];
        final itemName = linkedItem.displayName.trim().isEmpty ? linkedItem.name : linkedItem.displayName;
        
        final hasVariations = itemRecords.any((r) => r.linkedVariationLeafNodeId != null && r.linkedVariationLeafNodeId! > 0);
        
        if (!hasVariations && itemRecords.length == 1) {
          final record = itemRecords.first;
          final setLineKey = _inventorySetLineKey(itemId: itemId, variationLeafNodeId: 0);
          final setLine = activeSetLinesByKey[setLineKey];
          if (activeSet != null && setLine == null) continue;
          if (setLine != null) coveredSetLineKeys.add(setLineKey);
          
          rows.add(_InventoryRowEntry(
            record: record,
            displayName: itemName,
            displayId: record.barcode,
            displayMetadata: _itemMetadataText(record, linkedGroupName),
            itemGroupId: linkedItem.groupId,
            setQuantity: setLine?.quantity,
          ));
        } else {
          // Parent Row
          final parentBarcode = 'item-\${itemId}';
          final isExpanded = expandedParents.contains(parentBarcode);
          
          double totalStock = 0;
          for(final r in itemRecords) {
             if (r.onHand > 0) totalStock += r.onHand;
          }
          final aggLabel = '\${totalStock.toStringAsFixed(2)} \${linkedItem.unit}';
          
          rows.add(_InventoryRowEntry(
            record: MaterialRecord(
              id: 0,
              barcode: parentBarcode,
              name: itemName,
              type: 'Item',
              grade: '',
              thickness: '',
              supplier: '',
              createdAt: DateTime.now(),
              kind: 'item_parent',
              parentBarcode: null,
              numberOfChildren: itemRecords.length,
              linkedChildBarcodes: [],
              scanCount: 0,
              linkedItemId: itemId,
            ),
            displayName: itemName,
            displayId: parentBarcode,
            displayMetadata: linkedGroupName ?? 'Item',
            itemGroupId: linkedItem.groupId,
            canExpand: true,
            isExpanded: isExpanded,
            opensDetails: false,
            aggregateStockLabel: aggLabel,
          ));
          
          if (isExpanded) {
            for (final record in itemRecords) {
              final setLineKey = _inventorySetLineKey(
                itemId: itemId,
                variationLeafNodeId: record.linkedVariationLeafNodeId ?? 0,
              );
              final setLine = activeSetLinesByKey[setLineKey];
              if (activeSet != null && setLine == null) continue;
              if (setLine != null) coveredSetLineKeys.add(setLineKey);
              
              String? resolvedVariationPathLabel = setLine?.variationPathLabel;
              if ((resolvedVariationPathLabel == null || resolvedVariationPathLabel.isEmpty) && record.name.contains(' - ')) {
                resolvedVariationPathLabel = record.name.substring(record.name.lastIndexOf(' - ') + 3);
              }
              
              // Formatting Custom Variations if present
              if ((resolvedVariationPathLabel == null || resolvedVariationPathLabel.isEmpty) && record.customVariationValues != null && record.customVariationValues!.isNotEmpty) {
                 resolvedVariationPathLabel = record.customVariationValues!.values.join(' / ');
              }

              rows.add(_InventoryRowEntry(
                record: record,
                displayName: resolvedVariationPathLabel ?? record.name,
                displayId: record.barcode,
                displayMetadata: _itemMetadataText(
                  record,
                  null, // Omit group name for children
                  variationPathLabel: resolvedVariationPathLabel,
                ),
                itemGroupId: linkedItem.groupId,
                setQuantity: setLine?.quantity,
                depth: 1,
              ));
            }
          }
        }
      }
      
      // Handle Missing Set Lines (omitted for brevity unless needed)
      // Actually we should include them so the code matches.
      if (activeSet != null) {
        for (final line in activeSet.lines) {
          final setLineKey = _inventorySetLineKey(
            itemId: line.itemId,
            variationLeafNodeId: line.variationLeafNodeId,
          );
          if (!coveredSetLineKeys.contains(setLineKey)) {
            final linkedItem = itemById[line.itemId];
            if (_activeGroupIdFilter != null &&
                linkedItem?.groupId != _activeGroupIdFilter) {
              continue;
            }
            if (linkedItem != null) {
              coveredItemIds.add(linkedItem.id);
              final linkedGroupName = groupNameById[linkedItem.groupId];
              rows.add(
                _InventoryRowEntry(
                  record: MaterialRecord(
                    id: 0,
                    barcode: 'set-req-$setLineKey',
                    name: linkedItem.name,
                    type: 'Item',
                    grade: '',
                    thickness: '',
                    supplier: '',
                    unitId: linkedItem.unitId,
                    unit: linkedItem.unit,
                    createdAt: DateTime.now(),
                    kind: 'set_requirement',
                    parentBarcode: null,
                    numberOfChildren: 0,
                    linkedChildBarcodes: [],
                    scanCount: 0,
                    displayStock: 'Missing',
                    createdBy: 'System',
                    workflowStatus: 'notStarted',
                    linkedItemId: linkedItem.id,
                    linkedVariationLeafNodeId: line.variationLeafNodeId,
                  ),
                  displayName: linkedItem.displayName.trim().isEmpty
                      ? linkedItem.name
                      : linkedItem.displayName,
                  displayId: 'set-req-$setLineKey',
                  displayMetadata: _itemMetadataText(
                    MaterialRecord(
                      id: 0,
                      barcode: 'set-req-$setLineKey',
                      name: linkedItem.name,
                      type: 'Item',
                      grade: '',
                      thickness: '',
                      supplier: '',
                      createdAt: DateTime.now(),
                      kind: 'set_requirement',
                      parentBarcode: null,
                      numberOfChildren: 0,
                      linkedChildBarcodes: [],
                      scanCount: 0,
                    ),
                    linkedGroupName,
                    variationPathLabel: line.variationPathLabel,
                  ),
                  itemGroupId: linkedItem.groupId,
                  setQuantity: line.quantity,
                ),
              );
            }
          }
        }
      }

      return rows;
    }
`;

content = content.replace(targetOld.trim(), targetNew.trim());
fs.writeFileSync(path, content, 'utf8');
console.log('Patched inventory_screen.dart');
