import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import 'package:core_erp/core/services/barcode_codec.dart';
import 'package:core_erp/core/services/barcode_label_service.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_info_panel.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';

class BarcodeTraceBadge extends StatelessWidget {
  const BarcodeTraceBadge({super.key, required this.scanCount});

  final int scanCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Scanned $scanCount times',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF5B4FE6),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class InlineBarcodePreview extends StatelessWidget {
  const InlineBarcodePreview({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7F0)),
      ),
      child: BarcodeWidget(
        barcode: Barcode.code128(),
        data: value,
        drawText: false,
        width: 220,
        height: 48,
        color: const Color(0xFF111827),
        backgroundColor: Colors.white,
      ),
    );
  }
}

class ShowBarcodeButton extends StatelessWidget {
  const ShowBarcodeButton({
    super.key,
    required this.material,
    this.buttonLabel = 'Show Barcode',
  });

  final MaterialRecord material;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: buttonLabel,
      icon: Icons.qr_code_2_outlined,
      variant: AppButtonVariant.secondary,
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: BarcodeSheetDialog(material: material),
            ),
          ),
        );
      },
    );
  }
}

class BarcodeSheetDialog extends StatelessWidget {
  const BarcodeSheetDialog({super.key, required this.material});

  final MaterialRecord material;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '${material.name} Barcode',
            subtitle: material.isParent
                ? 'Desktop-generated barcode sheet for the parent and its linked children.'
                : 'Desktop-generated barcode sheet for this selected child material.',
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  BarcodeSheetCard(
                    title: material.name,
                    subtitle: material.isParent
                        ? 'Parent Sheet'
                        : 'Child Sheet',
                    barcode: material.barcode,
                  ),
                  ...material.linkedChildBarcodes.map(
                    (barcode) => BarcodeSheetCard(
                      title: 'Linked Child',
                      subtitle: barcode,
                      barcode: barcode,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _BarcodeSheetActions(material: material),
        ],
      ),
    );
  }
}

/// Getting the sheet off the screen and onto stock.
///
/// A parent material plus its linked children is the real batch case: receive a
/// coil, split it, and every piece needs its own label in one run. Until this
/// existed the dialog could show them all and print none of them.
class _BarcodeSheetActions extends StatefulWidget {
  const _BarcodeSheetActions({required this.material});

  final MaterialRecord material;

  @override
  State<_BarcodeSheetActions> createState() => _BarcodeSheetActionsState();
}

class _BarcodeSheetActionsState extends State<_BarcodeSheetActions> {
  LabelStock _stock = LabelStock.materialSticker;
  bool _busy = false;

  /// Canonical codes, not the raw stored ids.
  ///
  /// The raw id still scans — the resolver falls back to the legacy columns —
  /// but it resolves *unverified*, with no check character, and the inspector
  /// then has to say so. A label being printed today should not be born legacy.
  List<BarcodeLabel> get _labels {
    final material = widget.material;
    final descriptor = <String>[
      material.grade,
      material.thickness,
    ].where((part) => part.trim().isNotEmpty).join(' · ');

    return <BarcodeLabel>[
      BarcodeLabel(
        code: BarcodeCodec.canonicalOr('MAT', material.barcode),
        title: material.name,
        subtitle: descriptor,
        lines: <BarcodeFact>[
          if (material.unit.trim().isNotEmpty)
            BarcodeFact(label: 'Unit', value: material.unit),
          if (material.supplier.trim().isNotEmpty)
            BarcodeFact(label: 'Supplier', value: material.supplier),
          if (material.location.trim().isNotEmpty)
            BarcodeFact(label: 'Location', value: material.location),
        ],
        footer: material.isParent ? 'Parent' : 'Material',
      ),
      for (final child in material.linkedChildBarcodes)
        BarcodeLabel(
          code: BarcodeCodec.canonicalOr('MAT', child),
          title: material.name,
          subtitle: descriptor,
          footer: 'Child of ${material.barcode}',
        ),
    ];
  }

  Future<void> _print({required bool multiUp}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BarcodeLabelService.printLabels(
        labels: _labels,
        stock: _stock,
        multiUp: multiUp,
      );
    } catch (error) {
      // A printer that is off, out of paper or not installed is ordinary, and a
      // button that just stays spinning tells nobody what went wrong.
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Could not print those labels: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _labels.length;
    return Row(
      children: [
        Flexible(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<LabelStock>(
              value: _stock,
              isDense: true,
              isExpanded: true,
              items: <DropdownMenuItem<LabelStock>>[
                for (final stock in LabelStock.all)
                  DropdownMenuItem<LabelStock>(
                    value: stock,
                    child: Text(
                      stock.description,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (stock) {
                      if (stock != null) setState(() => _stock = stock);
                    },
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Two ways out, because a workshop on day one has a plain office
        // printer and buys a thermal roll later.
        AppButton(
          label: count == 1 ? 'Print label' : 'Print $count labels',
          icon: Icons.print_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: _busy ? null : () => _print(multiUp: false),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: 'Print on A4',
          icon: Icons.grid_on_outlined,
          onPressed: _busy ? null : () => _print(multiUp: true),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class BarcodeSheetCard extends StatelessWidget {
  const BarcodeSheetCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.barcode,
  });

  final String title;
  final String subtitle;
  final String barcode;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SizedBox(
        width: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: barcode,
              width: 252,
              height: 80,
              color: const Color(0xFF111827),
              backgroundColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

List<AppInfoRow> buildMaterialBarcodeInfoRows(
  MaterialRecord material, {
  bool includeBarcodeImage = false,
}) {
  return [
    AppInfoRow(label: 'Barcode', value: material.barcode),
    if (includeBarcodeImage)
      AppInfoRow(
        label: 'Barcode image',
        child: InlineBarcodePreview(value: material.barcode),
      ),
    AppInfoRow(label: 'Type', value: material.type),
    AppInfoRow(label: 'Grade', value: material.grade),
    AppInfoRow(label: 'Thickness', value: material.thickness),
    AppInfoRow(label: 'Supplier', value: material.supplier),
    if (material.unit.isNotEmpty)
      AppInfoRow(label: 'Unit', value: material.unit),
    AppInfoRow(
      label: 'Relationship',
      value: material.isParent
          ? 'Parent of ${material.numberOfChildren} children'
          : 'Child of ${material.parentBarcode}',
    ),
    AppInfoRow(
      label: 'Scan trace',
      value: 'Scanned ${material.scanCount} times',
    ),
  ];
}

class SmallBarcodePreview extends StatelessWidget {
  const SmallBarcodePreview({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3C3C3C),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 24,
          child: BarcodeWidget(
            barcode: Barcode.code128(),
            data: value,
            drawText: false,
            color: const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}
