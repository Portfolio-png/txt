import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';

/// The print-preview rendering of a challan: an A4-ish white page with the
/// company header, party/reference band, line-item table and signature footer.
///
/// Renders purely from the passed [challan] and never reads an id or hits a
/// repository, so an unsaved draft previews exactly like a persisted record —
/// that's what lets the mobile Purchase wizard show the document before submit.
///
/// Laid out at a fixed [documentWidth]; wrap in a `FittedBox` to scale it down
/// on narrow screens.
class ChallanPrintableDocument extends StatelessWidget {
  const ChallanPrintableDocument({
    super.key,
    required this.challan,
    this.companyProfile,
  });

  final DeliveryChallan challan;

  /// Overrides the letterhead. Falls back to the challan's own snapshot, then
  /// to [DeliveryChallanProvider.companyProfile]; pass this when no provider is
  /// available above the widget.
  final CompanyProfile? companyProfile;

  /// Intrinsic width of the page. The layout assumes it and does not reflow.
  static const double documentWidth = 760;

  @override
  Widget build(BuildContext context) {
    final profile =
        companyProfile ??
        challan.companyProfileSnapshot ??
        context.watch<DeliveryChallanProvider>().companyProfile ??
        CompanyProfile.empty();
    final isReception = challan.isReception;
    final docTitle = _challanTypeTitle(challan);
    final partyLabel = isReception ? 'Vendor' : 'M/s';
    final partyName = isReception ? challan.vendorName : challan.customerName;
    final partyGstin = isReception
        ? challan.vendorGstin
        : challan.customerGstin;
    final referenceLabel = isReception ? 'Source Ref.' : 'Challan No.';
    final referenceValue = isReception
        ? (challan.sourceReference.trim().isEmpty
              ? challan.challanNo
              : challan.sourceReference)
        : challan.challanNo;

    return Container(
      width: documentWidth,
      color: Colors.white,
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      Expanded(
                        flex: 2,
                        child: Text(
                          docTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          profile.mobile.isEmpty
                              ? ''
                              : 'Mobile: ${profile.mobile}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.companyName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (profile.businessDescription.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      profile.businessDescription,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (profile.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(profile.address, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            const Divider(color: Colors.black, height: 1),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$partyLabel: $partyName'),
                          const SizedBox(height: 8),
                          Text('GSTIN: $partyGstin'),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.black),
                  SizedBox(
                    width: 230,
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$referenceLabel: $referenceValue'),
                          const SizedBox(height: 8),
                          Text('Challan No.: ${challan.challanNo}'),
                          const SizedBox(height: 8),
                          Text('Date: ${_formatDate(challan.date)}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.black, height: 1),
            Table(
              border: TableBorder.all(color: Colors.black),
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.3),
              },
              children: [
                _tableRow([
                  'Particulars',
                  'HSN Code',
                  'QTY. Pcs.',
                  'Weight',
                ], header: true),
                ...challan.items.map(
                  (item) => _tableRow([
                    _itemParticulars(item),
                    item.hsnCode,
                    item.quantityPcs,
                    item.weight,
                  ]),
                ),
                for (var i = challan.items.length; i < 9; i++)
                  _tableRow(['', '', '', '']),
              ],
            ),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('State Code: ${profile.stateCode}'),
                          const SizedBox(height: 8),
                          Text('GSTIN: ${profile.gstin}'),
                          const SizedBox(height: 52),
                          const Text('Receiver\'s Signature'),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.black),
                  SizedBox(
                    width: 270,
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'For ${profile.companyName}',
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 64),
                          Text(
                            profile.signatureLabel.isEmpty
                                ? 'Checked by / Authorized Signatory'
                                : profile.signatureLabel,
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docCell(Widget child) {
    return Padding(padding: const EdgeInsets.all(10), child: child);
  }

  TableRow _tableRow(List<String> values, {bool header = false}) {
    return TableRow(
      children: values
          .map(
            (value) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: header ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  String _itemParticulars(DeliveryChallanItem item) {
    final custom = item.customVariationValues.values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' / ');
    return [
      item.particulars.trim().isEmpty ? 'Item' : item.particulars.trim(),
      if (item.variationPathLabel.trim().isNotEmpty)
        item.variationPathLabel.trim(),
      if (custom.isNotEmpty) custom,
      if (item.note.trim().isNotEmpty) item.note.trim(),
    ].join('\n');
  }
}

String _challanTypeTitle(DeliveryChallan challan) {
  if (challan.isReception) return 'RECEPTION CHALLAN';
  if (challan.isInternal) return 'INTERNAL CHALLAN';
  return 'DELIVERY CHALLAN';
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day-$month-${value.year}';
}
