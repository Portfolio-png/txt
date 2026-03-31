import 'package:flutter/material.dart';

import '../../domain/models/aging_row.dart';

const double _partyColumnWidth = 336;
const double _valueColumnWidth = 120;
const double _columnGap = 69;

class PPAgingTable extends StatelessWidget {
  const PPAgingTable({
    super.key,
    required this.rows,
    required this.onToggleRow,
    required this.minWidth,
  });

  final List<AgingRow> rows;
  final ValueChanged<String> onToggleRow;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final targetWidth = constraints.maxWidth > minWidth
                ? constraints.maxWidth
                : minWidth;

            return SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: targetWidth,
                  child: Column(
                    children: [
                      const _AgingHeaderRow(),
                      for (var i = 0; i < rows.length; i++)
                        _AgingDataRow(
                          row: rows[i],
                          isEven: i.isEven,
                          onTap: () => onToggleRow(rows[i].id),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AgingHeaderRow extends StatelessWidget {
  const _AgingHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          _AgingHeaderCell(width: _partyColumnWidth, child: Text('Party Name')),
          SizedBox(width: _columnGap),
          _AgingHeaderCell(
            width: _valueColumnWidth,
            child: Text('Total Outstanding'),
          ),
          SizedBox(width: _columnGap),
          _AgingHeaderCell(width: _valueColumnWidth, child: Text('0 - 30')),
          SizedBox(width: _columnGap),
          _AgingHeaderCell(width: _valueColumnWidth, child: Text('31 - 60')),
          SizedBox(width: _columnGap),
          _AgingHeaderCell(width: _valueColumnWidth, child: Text('61 - 90')),
          SizedBox(width: _columnGap),
          _AgingHeaderCell(width: _valueColumnWidth, child: Text('> 90')),
          SizedBox(width: _columnGap),
          _AgingHeaderCell(width: _valueColumnWidth, child: Text('Advance')),
        ],
      ),
    );
  }
}

class _AgingDataRow extends StatelessWidget {
  const _AgingDataRow({
    required this.row,
    required this.isEven,
    required this.onTap,
  });

  final AgingRow row;
  final bool isEven;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Container(
          color: isEven ? const Color(0xFFF9F9F9) : Colors.white,
          child: SizedBox(
            height: 55,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _AgingValueCell(
                    width: _partyColumnWidth,
                    child: Text(
                      row.partyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF3C3C3C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: _columnGap),
                  _AgingValueCell(
                    width: _valueColumnWidth,
                    child: Text(_currency(row.totalOutstanding)),
                  ),
                  const SizedBox(width: _columnGap),
                  _AgingValueCell(
                    width: _valueColumnWidth,
                    child: Text(_currency(row.bucket0To30)),
                  ),
                  const SizedBox(width: _columnGap),
                  _AgingValueCell(
                    width: _valueColumnWidth,
                    child: Text(_currency(row.bucket31To60)),
                  ),
                  const SizedBox(width: _columnGap),
                  _AgingValueCell(
                    width: _valueColumnWidth,
                    child: Text(_currency(row.bucket61To90)),
                  ),
                  const SizedBox(width: _columnGap),
                  _AgingValueCell(
                    width: _valueColumnWidth,
                    child: Text(_currency(row.bucketOver90)),
                  ),
                  const SizedBox(width: _columnGap),
                  _AgingValueCell(
                    width: _valueColumnWidth,
                    child: Text(_currency(row.advance)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgingHeaderCell extends StatelessWidget {
  const _AgingHeaderCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF3C3C3C),
          fontWeight: FontWeight.w600,
        ),
        child: child,
      ),
    );
  }
}

class _AgingValueCell extends StatelessWidget {
  const _AgingValueCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF4B4B4B),
          fontWeight: FontWeight.w400,
        ),
        child: child,
      ),
    );
  }
}

String _currency(double value) {
  final integer = value.round().toString();
  final chunks = <String>[];

  for (var end = integer.length; end > 0; end -= 3) {
    final start = end - 3 < 0 ? 0 : end - 3;
    chunks.add(integer.substring(start, end));
  }

  return '₹ ${chunks.reversed.join(',')}.00';
}
