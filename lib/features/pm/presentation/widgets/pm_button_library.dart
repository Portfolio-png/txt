import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';

class PMButtonLibrary extends StatelessWidget {
  const PMButtonLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Button library',
            subtitle:
                'A starter home for shared custom buttons and reusable UI states across Paper ERP.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 780;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Expanded(
                    child: _ButtonGroupCard(
                      title: 'Primary actions',
                      description:
                          'High-emphasis actions for save, create, and proceed flows.',
                      children: [
                        AppButton(
                          label: 'Create Item',
                          icon: Icons.add_rounded,
                          onPressed: null,
                        ),
                        AppButton(
                          label: 'Sync Pipeline',
                          icon: Icons.sync_rounded,
                          onPressed: null,
                        ),
                        AppButton(
                          label: 'Saving',
                          onPressed: null,
                          isLoading: true,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16, height: 16),
                  Expanded(
                    child: _ButtonGroupCard(
                      title: 'Secondary actions',
                      description:
                          'Lower-emphasis actions for support flows, filters, and previews.',
                      children: [
                        AppButton(
                          label: 'Preview',
                          icon: Icons.visibility_outlined,
                          onPressed: null,
                          variant: AppButtonVariant.secondary,
                        ),
                        AppButton(
                          label: 'Export',
                          icon: Icons.file_download_outlined,
                          onPressed: null,
                          variant: AppButtonVariant.secondary,
                        ),
                        AppButton(
                          label: 'Open Config',
                          icon: Icons.tune_outlined,
                          onPressed: null,
                          variant: AppButtonVariant.secondary,
                        ),
                      ],
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

class _ButtonGroupCard extends StatelessWidget {
  const _ButtonGroupCard({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: children),
        ],
      ),
    );
  }
}
