import 'package:flutter/material.dart';

import '../../domain/models/aging_row.dart';

class PPSummaryCardsRow extends StatelessWidget {
  const PPSummaryCardsRow({
    super.key,
    required this.cards,
    required this.compact,
    required this.selectedCardId,
    required this.onCardTap,
  });

  final List<SummaryMetric> cards;
  final bool compact;
  final String? selectedCardId;
  final ValueChanged<String> onCardTap;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => SizedBox(
            width: 220,
            child: _SummaryMetricCard(
              card: cards[index],
              active: selectedCardId == cards[index].id,
              onTap: () => onCardTap(cards[index].id),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          Expanded(
            child: _SummaryMetricCard(
              card: cards[i],
              active: selectedCardId == cards[i].id,
              onTap: () => onCardTap(cards[i].id),
            ),
          ),
          if (i != cards.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  const _SummaryMetricCard({
    required this.card,
    required this.active,
    required this.onTap,
  });

  final SummaryMetric card;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 190;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFF6F4FF) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? const Color(0xFF8E7EF5)
                      : const Color(0xFFE8E8E8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.label,
                          style: const TextStyle(
                            color: Color(0xFF5E5E5E),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE1DBFF)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            card.periodLabel,
                            style: const TextStyle(
                              color: Color(0xFF3C3C3C),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: isNarrow ? 52 : 64,
                    height: isNarrow ? 34 : 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${card.value}',
                        style: TextStyle(
                          color: const Color(0xFF3C3C3C),
                          fontSize: isNarrow ? 19 : 23,
                          height: 0.9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
