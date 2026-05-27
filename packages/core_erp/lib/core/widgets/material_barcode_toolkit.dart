import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

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
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Close',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
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
