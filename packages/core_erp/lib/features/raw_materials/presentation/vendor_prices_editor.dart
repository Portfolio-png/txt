import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/searchable_select.dart';
import '../../vendors/domain/vendor_definition.dart';
import '../../vendors/presentation/providers/vendors_provider.dart';
import '../domain/rivet.dart';

/// One vendor's quote while it is being typed.
class VendorPriceLine {
  VendorPriceLine({
    this.vendorId,
    String price = '',
    this.basis = RivetPriceBasis.thousand,
  }) : price = TextEditingController(text: price);

  int? vendorId;
  final TextEditingController price;
  RivetPriceBasis basis;

  /// The line as it is sent, or null while it has no vendor.
  RivetVendorPrice? toPrice() => vendorId == null
      ? null
      : RivetVendorPrice(
          vendorId: vendorId!,
          price: price.text.trim().replaceFirst('₹', '').trim(),
          basis: basis,
        );
}

/// The vendors who sell a raw material and what each quotes — shared by the
/// rivet and spring forms so both read alike. Raw-material suppliers are
/// offered first.
///
/// The form owns [lines] (and disposes their controllers); this edits the
/// list in place and calls [onChanged] for the form to rebuild. Keys are
/// `{keyPrefix}-add-vendor`, `{keyPrefix}-vendor-{i}`, `-price-{i}` and
/// `-basis-{i}`.
class VendorPricesEditor extends StatelessWidget {
  const VendorPricesEditor({
    super.key,
    required this.lines,
    required this.onChanged,
    required this.keyPrefix,
    required this.noun,
  });

  final List<VendorPriceLine> lines;
  final VoidCallback onChanged;
  final String keyPrefix;

  /// "rivet", "spring" — for the empty note.
  final String noun;

  List<VendorDefinition> _vendors(BuildContext context) {
    try {
      final vendors = context
          .watch<VendorsProvider>()
          .vendors
          .where((v) => !v.isArchived)
          .toList();
      vendors.sort((a, b) {
        if (a.suppliesRawMaterial != b.suppliesRawMaterial) {
          return a.suppliesRawMaterial ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return vendors;
    } on ProviderNotFoundException {
      return const <VendorDefinition>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <SearchableSelectOption<int>>[
      for (final v in _vendors(context))
        SearchableSelectOption<int>(
          value: v.id,
          label: v.name,
          subtitle: v.suppliesRawMaterial ? 'Raw material supplier' : null,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Vendors and their prices',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ),
            TextButton.icon(
              key: ValueKey<String>('$keyPrefix-add-vendor'),
              onPressed: () {
                lines.add(VendorPriceLine());
                onChanged();
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Add vendor',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No vendor yet. Add the vendors who sell this $noun, each with the price they quote.',
              style: const TextStyle(
                fontSize: 14,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _row(i, options),
          ),
      ],
    );
  }

  Widget _row(int index, List<SearchableSelectOption<int>> options) {
    final line = lines[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 5,
          child: SearchableSelectField<int>(
            key: ValueKey<String>('$keyPrefix-vendor-$index'),
            value: line.vendorId,
            options: options,
            dialogTitle: 'Vendor',
            emptyText: 'No vendors yet. Add them under Masters › Vendors.',
            decoration: const InputDecoration(labelText: 'Vendor'),
            onChanged: (id) {
              line.vendorId = id;
              onChanged();
            },
            validator: (id) => id == null ? 'Pick a vendor' : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: TextFormField(
            key: ValueKey<String>('$keyPrefix-price-$index'),
            controller: line.price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              labelText: 'Price',
              prefixText: '₹ ',
            ),
            validator: (v) {
              final text = (v ?? '').trim();
              if (text.isEmpty) return 'Price needed';
              if (!isValidPrice(text)) return 'Like 32.50';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: DropdownButtonFormField<RivetPriceBasis>(
            key: ValueKey<String>('$keyPrefix-basis-$index'),
            isExpanded: true,
            initialValue: line.basis,
            decoration: const InputDecoration(labelText: 'Per'),
            items: <DropdownMenuItem<RivetPriceBasis>>[
              for (final basis in RivetPriceBasis.values)
                DropdownMenuItem<RivetPriceBasis>(
                  value: basis,
                  child: Text(
                    basis.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            onChanged: (basis) {
              line.basis = basis ?? line.basis;
              onChanged();
            },
          ),
        ),
        IconButton(
          tooltip: 'Remove this vendor',
          onPressed: () {
            lines.removeAt(index).price.dispose();
            onChanged();
          },
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}
