import 'package:flutter/material.dart';

import 'component_group_editor_dialog.dart' show FocusedCard;

class BentoGridDialogLayout extends StatelessWidget {
  const BentoGridDialogLayout({
    super.key,
    required this.focusedCard,
    required this.detailsCard,
    required this.sectionsCard,
    required this.itemsCard,
    required this.pipelinesCard,
    required this.machinesCard,
    required this.diesCard,
  });

  final FocusedCard focusedCard;
  final Widget detailsCard;
  final Widget sectionsCard;
  final Widget itemsCard;
  final Widget pipelinesCard;
  final Widget machinesCard;
  final Widget diesCard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = constraints.maxWidth;
          final double totalHeight = constraints.maxHeight;
          const double spacing = 12.0;

          // Helper to calculate exact pixel Rect for a card given grid dimensions
          Rect getRect({
            required int colSpan,
            required int rowSpan,
            required int colIndex,
            required int rowIndex,
            required int totalCols,
            required int totalRows,
          }) {
            final double cellWidth = (totalWidth - (totalCols - 1) * spacing) / totalCols;
            final double cellHeight = (totalHeight - (totalRows - 1) * spacing) / totalRows;

            final double left = colIndex * (cellWidth + spacing);
            final double top = rowIndex * (cellHeight + spacing);
            final double width = colSpan * cellWidth + (colSpan - 1) * spacing;
            final double height = rowSpan * cellHeight + (rowSpan - 1) * spacing;

            return Rect.fromLTWH(left, top, width, height);
          }

          Rect getCardRect(FocusedCard cardType) {
            if (focusedCard == FocusedCard.none) {
              // 6 columns x 4 rows
              switch (cardType) {
                case FocusedCard.details:
                  return getRect(colSpan: 3, rowSpan: 2, colIndex: 0, rowIndex: 0, totalCols: 6, totalRows: 4);
                case FocusedCard.sections:
                  return getRect(colSpan: 3, rowSpan: 2, colIndex: 3, rowIndex: 0, totalCols: 6, totalRows: 4);
                case FocusedCard.items:
                  return getRect(colSpan: 2, rowSpan: 2, colIndex: 0, rowIndex: 2, totalCols: 6, totalRows: 4);
                case FocusedCard.pipelines:
                  return getRect(colSpan: 2, rowSpan: 2, colIndex: 2, rowIndex: 2, totalCols: 6, totalRows: 4);
                case FocusedCard.machines:
                  return getRect(colSpan: 1, rowSpan: 2, colIndex: 4, rowIndex: 2, totalCols: 6, totalRows: 4);
                case FocusedCard.dies:
                  return getRect(colSpan: 1, rowSpan: 2, colIndex: 5, rowIndex: 2, totalCols: 6, totalRows: 4);
                default:
                  return Rect.zero;
              }
            } else {
              // Focused mode: 6 columns x 5 rows
              // The focused card gets 4x5, the other 5 cards get 2x1 each stacked vertically.
              final List<FocusedCard> allCards = [
                FocusedCard.details,
                FocusedCard.sections,
                FocusedCard.items,
                FocusedCard.pipelines,
                FocusedCard.machines,
                FocusedCard.dies,
              ];
              
              if (cardType == focusedCard) {
                return getRect(colSpan: 4, rowSpan: 5, colIndex: 0, rowIndex: 0, totalCols: 6, totalRows: 5);
              } else {
                allCards.remove(focusedCard);
                int contextIndex = allCards.indexOf(cardType);
                return getRect(colSpan: 2, rowSpan: 1, colIndex: 4, rowIndex: contextIndex, totalCols: 6, totalRows: 5);
              }
            }
          }

          Widget buildAnimatedCard(FocusedCard type, Widget child) {
            final Rect rect = getCardRect(type);
            return AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.fastOutSlowIn,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: child,
            );
          }

          return Stack(
            children: [
              buildAnimatedCard(FocusedCard.details, detailsCard),
              buildAnimatedCard(FocusedCard.sections, sectionsCard),
              buildAnimatedCard(FocusedCard.items, itemsCard),
              buildAnimatedCard(FocusedCard.pipelines, pipelinesCard),
              buildAnimatedCard(FocusedCard.machines, machinesCard),
              buildAnimatedCard(FocusedCard.dies, diesCard),
            ],
          );
        },
      ),
    );
  }
}
