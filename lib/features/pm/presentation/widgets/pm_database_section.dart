import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';

class PMDatabaseIdeasSection extends StatelessWidget {
  const PMDatabaseIdeasSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Database ideas -> UX ideas',
            subtitle:
                'These are proposals only. Nothing here changes the real database, but each model suggests a different product experience.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 980;
              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Expanded(
                    child: _PMDatabaseIdeaCard(
                      title: 'Draft + publish model',
                      databaseIdea:
                          'Store groups as drafts first, then publish a versioned snapshot when approved.',
                      uxIdea:
                          'Lets us build a studio-like editor with autosave, review, and publish instead of a single save button.',
                    ),
                  ),
                  SizedBox(width: 16, height: 16),
                  Expanded(
                    child: _PMDatabaseIdeaCard(
                      title: 'Template + instance model',
                      databaseIdea:
                          'Separate reusable group templates from actual inventory groups created from them.',
                      uxIdea:
                          'Unlocks a gallery-first UX where users start from patterns rather than blank forms.',
                    ),
                  ),
                  SizedBox(width: 16, height: 16),
                  Expanded(
                    child: _PMDatabaseIdeaCard(
                      title: 'Relationship graph model',
                      databaseIdea:
                          'Represent sub-groups, items, and properties as linked nodes instead of packing meaning into notes.',
                      uxIdea:
                          'Supports a visual canvas or map-based builder where users attach pieces spatially and inspect dependencies.',
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

class _PMDatabaseIdeaCard extends StatelessWidget {
  const _PMDatabaseIdeaCard({
    required this.title,
    required this.databaseIdea,
    required this.uxIdea,
  });

  final String title;
  final String databaseIdea;
  final String uxIdea;

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
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'Database proposal',
            style: TextStyle(
              color: Color(0xFF4338CA),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            databaseIdea,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF374151)),
          ),
          const SizedBox(height: 12),
          const Text(
            'UX implication',
            style: TextStyle(
              color: Color(0xFF0F766E),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            uxIdea,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF374151)),
          ),
        ],
      ),
    );
  }
}
