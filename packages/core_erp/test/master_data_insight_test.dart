import 'package:core_erp/features/items/domain/item_master_data.dart';
import 'package:flutter_test/flutter_test.dart';

// The Track board reads a variant's baseline against its peers on the same
// pipeline, so the two things that must hold are: the roster's average counts
// only what was actually measured, and the resolution says which of the four
// steps produced the numbers.

ItemMasterDataRecord record({
  required int itemId,
  required MasterDataOrigin origin,
  required double yieldPercent,
}) {
  return ItemMasterDataRecord.fromJson(<String, dynamic>{
    'id': itemId,
    'itemId': itemId,
    'pipelineId': 'pl-cut',
    'itemDisplayName': 'Alloy - ${itemId}A - MS Sheet',
    'origin': originToWire(origin),
    'isVariant': true,
    'yieldPercent': yieldPercent,
    'baseline': <String, dynamic>{},
  });
}

void main() {
  group('PipelineMasterDataRoster', () {
    test('averages only the records that were measured on this pipeline', () {
      final roster = PipelineMasterDataRoster(
        pipelineId: 'pl-cut',
        measuredCount: 2,
        inheritedCount: 1,
        blankCount: 1,
        entries: <ItemMasterDataRecord>[
          record(itemId: 1, origin: MasterDataOrigin.manual, yieldPercent: 90),
          record(itemId: 2, origin: MasterDataOrigin.manual, yieldPercent: 80),
          // Inherited from the pipeline: averaging it in would quote the
          // pipeline's own figure back as if it were a second measurement.
          record(itemId: 3, origin: MasterDataOrigin.pipeline, yieldPercent: 50),
          record(itemId: 4, origin: MasterDataOrigin.fresh, yieldPercent: 0),
        ],
      );

      expect(roster.count, 4);
      expect(roster.measuredYieldPercent, 85);
    });

    test('no measured record means no average, not zero-by-division', () {
      final roster = PipelineMasterDataRoster(
        pipelineId: 'pl-cut',
        blankCount: 1,
        entries: <ItemMasterDataRecord>[
          record(itemId: 1, origin: MasterDataOrigin.fresh, yieldPercent: 0),
        ],
      );

      expect(roster.measuredYieldPercent, 0);
    });

    test('reads a server roster payload, entries and counts together', () {
      final roster = PipelineMasterDataRoster.fromJson(<String, dynamic>{
        'pipelineId': 'pl-cut',
        'measuredCount': 1,
        'inheritedCount': 1,
        'blankCount': 0,
        'entries': <dynamic>[
          <String, dynamic>{
            'id': 7,
            'itemId': 11,
            'pipelineId': 'pl-cut',
            'itemDisplayName': 'Alloy - 16A - MS Sheet',
            'origin': 'manual',
            'isVariant': true,
            'inputKg': 100,
            'outputKg': 92,
            'inputQty': 40,
            'outputQty': 38,
            'yieldPercent': 92,
            'baseline': <String, dynamic>{'inputKg': 100},
          },
          <String, dynamic>{
            'id': 8,
            'itemId': 12,
            'pipelineId': 'pl-cut',
            'itemName': 'Alloy - 18A - MS Sheet',
            'origin': 'pipeline',
            'yieldPercent': 85,
            'baseline': <String, dynamic>{},
          },
        ],
      });

      expect(roster.count, 2);
      expect(roster.entries.first.itemDisplayName, 'Alloy - 16A - MS Sheet');
      expect(roster.entries.first.isMeasured, isTrue);
      expect(roster.entries.first.inputKg, 100);
      expect(roster.entries.last.isInherited, isTrue);
      // itemName stands in when the server sends no display name.
      expect(roster.entries.last.itemDisplayName, 'Alloy - 18A - MS Sheet');
      expect(roster.measuredYieldPercent, 92);
    });
  });

  group('MasterDataResolution', () {
    MasterDataResolution parse(String source, {bool matched = true}) {
      return MasterDataResolution.fromJson(<String, dynamic>{
        'itemId': 11,
        'pipelineId': 'pl-cut',
        'matched': matched,
        'source': source,
        'origin': 'manual',
        'baseline': <String, dynamic>{},
      });
    }

    test('each step describes itself differently', () {
      expect(
        parse('pair').describe(pipelineName: 'Cut → Punch'),
        'Measured against Cut → Punch',
      );
      expect(
        parse('item').describe(pipelineName: 'Cut → Punch'),
        "Matched from this variant's own record",
      );
      expect(
        parse('pipeline').describe(pipelineName: 'Cut → Punch'),
        'Matched from Cut → Punch',
      );
      expect(
        parse('new', matched: false).describe(pipelineName: 'Cut → Punch'),
        'New data for this variant on Cut → Punch',
      );
    });

    test('an unnamed pipeline still reads as a sentence', () {
      expect(parse('pipeline').describe(), 'Matched from this pipeline');
      expect(
        parse('new', matched: false).describe(pipelineName: '   '),
        'New data for this variant on this pipeline',
      );
    });

    test('only the fourth step is unmatched', () {
      expect(parse('pair').matched, isTrue);
      expect(parse('item').matched, isTrue);
      expect(parse('pipeline').matched, isTrue);
      expect(parse('new', matched: false).matched, isFalse);
      expect(parse('new', matched: false).source, MasterDataSource.fresh);
    });

    test('an unknown source falls back to new rather than claiming a match', () {
      final resolution = parse('something-else', matched: false);
      expect(resolution.source, MasterDataSource.fresh);
    });
  });
}
