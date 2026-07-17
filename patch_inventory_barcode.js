const fs = require('fs');

const path = 'packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart';
let code = fs.readFileSync(path, 'utf8');

const oldCell = `                    if (!isGroupView && !isSetView)
                      _DataCell(
                        _displayPrimaryId(widget.entry),
                        width: widget.metrics.barcodeWidth,
                        metrics: widget.metrics,
                      ),`;

const newCell = `                    if (!isGroupView && !isSetView)
                      _BarcodeCell(
                        _displayPrimaryId(widget.entry),
                        width: widget.metrics.barcodeWidth,
                        metrics: widget.metrics,
                      ),`;

code = code.replace(oldCell, newCell);

const dataCellDef = `class _DataCell extends StatelessWidget {`;
const barcodeCellDef = `class _BarcodeCell extends StatelessWidget {
  const _BarcodeCell(this.text, {required this.width, required this.metrics});

  final String text;
  final double width;
  final _InventoryTableMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Tooltip(
          message: text,
          waitDuration: const Duration(milliseconds: 450),
          child: SmallBarcodePreview(value: text),
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {`;

code = code.replace(dataCellDef, barcodeCellDef);

fs.writeFileSync(path, code);
console.log('Patched inventory_screen.dart successfully');
