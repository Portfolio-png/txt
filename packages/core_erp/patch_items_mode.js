const fs = require('fs');

const path = 'f:/Rutu/txt/packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart';
let content = fs.readFileSync(path, 'utf8');

const targetOld = `
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
`;

const targetNew = `
      final itemsRecordsList = scopedRecords
          .where((record) => record.linkedItemId != null)
          .toList();

      final recordsByItemId = <int, List<MaterialRecord>>{};
      for (final r in itemsRecordsList) {
        recordsByItemId.putIfAbsent(r.linkedItemId!, () => []).add(r);
      }

      final rows = <_InventoryRowEntry>[];
      
      for (final itemId in recordsByItemId.keys) {
        final itemRecords = recordsByItemId[itemId]!;
        final linkedItem = itemById[itemId];
        if (linkedItem == null) continue;
        if (_activeGroupIdFilter != null && linkedItem.groupId != _activeGroupIdFilter) {
          continue;
        }

        final itemName = linkedItem.displayName.trim().isEmpty ? linkedItem.name : linkedItem.displayName;
        final linkedGroupName = groupNameById[linkedItem.groupId];
        
        // Filter records by activeSet
        final validItemRecords = <MaterialRecord>[];
        for (final record in itemRecords) {
           final setLineKey = _inventorySetLineKey(
              itemId: linkedItem.id,
              variationLeafNodeId: record.linkedVariationLeafNodeId ?? 0,
           );
           final setLine = activeSetLinesByKey[setLineKey];
           if (activeSet != null && setLine == null) continue;
           
           coveredSetLineKeys.add(setLineKey);
           coveredItemIds.add(linkedItem.id);
           validItemRecords.add(record);
        }
        
        if (validItemRecords.isEmpty) continue;

        final hasVariations = validItemRecords.any((r) => (r.linkedVariationLeafNodeId != null && r.linkedVariationLeafNodeId! > 0) || (r.customVariationValues != null && r.customVariationValues!.isNotEmpty));

        if (!hasVariations && validItemRecords.length == 1) {
          final record = validItemRecords.first;
          final setLineKey = _inventorySetLineKey(itemId: linkedItem.id, variationLeafNodeId: record.linkedVariationLeafNodeId ?? 0);
          final setLine = activeSetLinesByKey[setLineKey];
          
          rows.add(_InventoryRowEntry(
            record: record,
            displayName: itemName,
            displayId: record.barcode,
            displayMetadata: _itemMetadataText(record, linkedGroupName),
            itemGroupId: linkedItem.groupId,
            setQuantity: setLine?.quantity,
          ));
        } else {
          final parentBarcode = 'item-\${itemId}';
          final isExpanded = expandedParents.contains(parentBarcode);
          
          double totalStock = 0;
          for(final r in validItemRecords) {
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
              numberOfChildren: validItemRecords.length,
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
            for (final record in validItemRecords) {
              final setLineKey = _inventorySetLineKey(itemId: linkedItem.id, variationLeafNodeId: record.linkedVariationLeafNodeId ?? 0);
              final setLine = activeSetLinesByKey[setLineKey];
              
              String? resolvedVariationPathLabel = setLine?.variationPathLabel;
              if ((resolvedVariationPathLabel == null || resolvedVariationPathLabel.isEmpty) && record.name.contains(' - ')) {
                resolvedVariationPathLabel = record.name.substring(record.name.lastIndexOf(' - ') + 3);
              } else if (record.customVariationValues != null && record.customVariationValues!.isNotEmpty) {
                 resolvedVariationPathLabel = record.customVariationValues!.values.join(' / ');
              }

              rows.add(_InventoryRowEntry(
                record: record,
                displayName: resolvedVariationPathLabel ?? record.name,
                displayId: record.barcode,
                displayMetadata: _itemMetadataText(
                  record,
                  null,
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
`;

content = content.replace(targetOld.trim(), targetNew.trim());
fs.writeFileSync(path, content, 'utf8');
console.log('Patched items view mode grouping');
