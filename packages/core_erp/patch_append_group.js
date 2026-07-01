const fs = require('fs');

const path = 'f:/Rutu/txt/packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart';
let content = fs.readFileSync(path, 'utf8');

const oldBlock = `
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
            itemGroupId: linkedItem?.groupId,
            depth: depth + 1,
          ),
        );
      }
`;

const newBlock = `
      final recordsByItemId = <int, List<MaterialRecord>>{};
      for (final childRecord in childRecords) {
        if (childRecord.linkedItemId != null) {
          recordsByItemId.putIfAbsent(childRecord.linkedItemId!, () => []).add(childRecord);
        } else {
          rows.add(
            _InventoryRowEntry(
              record: childRecord,
              displayName: childRecord.name,
              displayId: childRecord.barcode,
              displayMetadata: _itemMetadataText(childRecord, linkedGroupName),
              depth: depth + 1,
            ),
          );
        }
      }

      for (final itemId in recordsByItemId.keys) {
        final itemRecords = recordsByItemId[itemId]!;
        final linkedItem = itemById[itemId];
        if (linkedItem == null) continue;
        
        final itemName = linkedItem.displayName.trim().isEmpty ? linkedItem.name : linkedItem.displayName;
        
        final hasVariations = itemRecords.any((r) => (r.linkedVariationLeafNodeId != null && r.linkedVariationLeafNodeId! > 0) || (r.customVariationValues != null && r.customVariationValues!.isNotEmpty));
        
        if (!hasVariations && itemRecords.length == 1) {
          final record = itemRecords.first;
          rows.add(_InventoryRowEntry(
            record: record,
            displayName: itemName,
            displayId: record.barcode,
            displayMetadata: _itemMetadataText(record, linkedGroupName),
            itemGroupId: linkedItem.groupId,
            depth: depth + 1,
          ));
        } else {
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
            depth: depth + 1,
          ));
          
          if (isExpanded) {
            for (final record in itemRecords) {
              String? resolvedVariationPathLabel;
              
              if (record.name.contains(' - ')) {
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
                  null, // omit group name for variations
                  variationPathLabel: resolvedVariationPathLabel,
                ),
                itemGroupId: linkedItem.groupId,
                depth: depth + 2,
              ));
            }
          }
        }
      }
`;

content = content.replace(oldBlock.trim(), newBlock.trim());
fs.writeFileSync(path, content, 'utf8');
console.log('Patched appendGroupRows for variations!');
