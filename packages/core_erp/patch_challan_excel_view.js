const fs = require('fs');

const path = 'f:/Rutu/txt/packages/core_erp/lib/features/delivery_challans/presentation/widgets/challan_excel_view.dart';
let content = fs.readFileSync(path, 'utf8');

const filterMatchOld = `
    if (widget.filterItemId != null || widget.filterVariationLeafNodeId != null) {
      for (final c in provider.challans) {
        if (c.items.any((item) {
          final itemMatch = widget.filterItemId == null || item.itemId == widget.filterItemId;
          final varMatch = widget.filterVariationLeafNodeId == null || item.variationLeafNodeId == widget.filterVariationLeafNodeId;
          return itemMatch && varMatch;
        }) && c.itemsCount == c.items.length) {
`;

const filterMatchNew = `
    if (widget.filterItemId != null || widget.filterVariationLeafNodeId != null || widget.filterCustomVariationValues != null) {
      for (final c in provider.challans) {
        if (c.items.any((item) {
          final itemMatch = widget.filterItemId == null || item.itemId == widget.filterItemId;
          final varMatch = widget.filterVariationLeafNodeId == null || item.variationLeafNodeId == widget.filterVariationLeafNodeId;
          
          bool customMatch = true;
          if (widget.filterCustomVariationValues != null) {
            final iv = item.customVariationValues ?? {};
            final fv = widget.filterCustomVariationValues!;
            if (iv.length != fv.length) {
               customMatch = false;
            } else {
               for (final k in fv.keys) {
                  if (iv[k] != fv[k]) {
                     customMatch = false;
                     break;
                  }
               }
            }
          }
          
          return itemMatch && varMatch && customMatch;
        }) && c.itemsCount == c.items.length) {
`;

content = content.replace(filterMatchOld.trim(), filterMatchNew.trim());

const rowFilterOld = `
        for (final item in challan.items) {
          final itemMatch = widget.filterItemId == null || item.itemId == widget.filterItemId;
          final varMatch = widget.filterVariationLeafNodeId == null || item.variationLeafNodeId == widget.filterVariationLeafNodeId;
          if (itemMatch && varMatch) {
            rows.add(_FlattenedRow(challan: challan, item: item));
          }
        }
`;

const rowFilterNew = `
        for (final item in challan.items) {
          final itemMatch = widget.filterItemId == null || item.itemId == widget.filterItemId;
          final varMatch = widget.filterVariationLeafNodeId == null || item.variationLeafNodeId == widget.filterVariationLeafNodeId;
          bool customMatch = true;
          if (widget.filterCustomVariationValues != null) {
            final iv = item.customVariationValues ?? {};
            final fv = widget.filterCustomVariationValues!;
            if (iv.length != fv.length) {
               customMatch = false;
            } else {
               for (final k in fv.keys) {
                  if (iv[k] != fv[k]) {
                     customMatch = false;
                     break;
                  }
               }
            }
          }
          if (itemMatch && varMatch && customMatch) {
            rows.add(_FlattenedRow(challan: challan, item: item));
          }
        }
`;

content = content.replace(rowFilterOld.trim(), rowFilterNew.trim());

fs.writeFileSync(path, content, 'utf8');
console.log('Patched challan_excel_view.dart');
