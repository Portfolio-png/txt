import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';
import 'package:flutter/material.dart';

/// The entity-kind palette, documented where the rest of the design system
/// lives. These are the colours that tell a base item apart from a spawned
/// variant wherever the two share a list — combination groups, inventory sets,
/// variant pickers. Read straight off [SoftErpTheme] rather than restated, so
/// the swatches cannot drift from what the app paints.
class PMEntityColorSection extends StatelessWidget {
  const PMEntityColorSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Entity colours',
            subtitle:
                'Item vs variant. Used wherever both kinds appear in one list, '
                'so membership can be read without opening anything.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 860;
              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Expanded(
                    child: _EntitySwatchCard(
                      kind: 'Item',
                      meaning:
                          'A base item — one you created directly. It owns a '
                          'variation tree and can spawn variants.',
                      foreground: SoftErpTheme.entityItem,
                      background: SoftErpTheme.entityItemBg,
                      border: SoftErpTheme.entityItemBorder,
                      tokens: [
                        'SoftErpTheme.entityItem',
                        'SoftErpTheme.entityItemBg',
                        'SoftErpTheme.entityItemBorder',
                      ],
                    ),
                  ),
                  SizedBox(width: 16, height: 16),
                  Expanded(
                    child: _EntitySwatchCard(
                      kind: 'Variant',
                      meaning:
                          'A basic item — spawned from a base item by Variation '
                          'Creation. It has no variation tree of its own and '
                          'inherits group, unit and naming from its base.',
                      foreground: SoftErpTheme.entityVariant,
                      background: SoftErpTheme.entityVariantBg,
                      border: SoftErpTheme.entityVariantBorder,
                      tokens: [
                        'SoftErpTheme.entityVariant',
                        'SoftErpTheme.entityVariantBg',
                        'SoftErpTheme.entityVariantBorder',
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            backgroundColor: const Color(0xFFF8F7FF),
            borderColor: const Color(0xFFE0DEFF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Why not success green / warning amber',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'The same rows already use green for "filed into a group" and '
                  'amber for "unbalanced" or "no code". Reusing either for a '
                  'kind would make one dot mean two unrelated things, so the '
                  'pair is blue vs teal — distinct from both, and from the '
                  'accent indigo that marks selection.',
                  style: TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Where it appears',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '• Item workflow, step 3 — expanding a combination group or '
                  'an inventory set lists its members with these dots.\n'
                  '• The legend beside those lists.',
                  style: TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12.5,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntitySwatchCard extends StatelessWidget {
  const _EntitySwatchCard({
    required this.kind,
    required this.meaning,
    required this.foreground,
    required this.background,
    required this.border,
    required this.tokens,
  });

  final String kind;
  final String meaning;
  final Color foreground;
  final Color background;
  final Color border;
  final List<String> tokens;

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The row exactly as the app draws it, so this is a specimen rather
          // than a description of one.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: foreground,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  kind == 'Variant'
                      ? 'patti - 16 amp - mildsteel'
                      : 'patti',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            kind,
            style: TextStyle(
              color: foreground,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meaning,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          for (final (index, token) in tokens.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: [foreground, background, border][index],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      token,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                  Text(
                    _hex([foreground, background, border][index]),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
