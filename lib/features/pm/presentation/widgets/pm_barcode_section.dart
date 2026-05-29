import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';
import '../barcode/material_barcode_toolkit.dart';

class PMBarcodeSection extends StatelessWidget {
  const PMBarcodeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Barcode toolkit',
            subtitle:
                'Reusable barcode UI lives in PM so Inventory can keep its own UX while future modules reuse the same building blocks.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 860;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: _BarcodeToolkitDocCard(
                      title: 'What is reusable',
                      bullets: [
                        'Scan trace badge',
                        'Inline barcode preview',
                        'Desktop barcode sheet dialog',
                        'Shared material barcode detail rows',
                      ],
                    ),
                  ),
                  const SizedBox(width: 16, height: 16),
                  Expanded(
                    child: AppCard(
                      padding: const EdgeInsets.all(18),
                      backgroundColor: const Color(0xFFF8F7FF),
                      borderColor: const Color(0xFFE0DEFF),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Reference components',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          SizedBox(height: 14),
                          BarcodeTraceBadge(scanCount: 4),
                          SizedBox(height: 14),
                          InlineBarcodePreview(value: 'CHD-8266-01'),
                          SizedBox(height: 14),
                          Text(
                            'Docs path: lib/features/pm/BARCODE_TOOLKIT.md',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarcodeToolkitDocCard extends StatelessWidget {
  const _BarcodeToolkitDocCard({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...bullets.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFF6C63FF),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
