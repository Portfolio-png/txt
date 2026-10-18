import 'package:core_erp/core/utils/stamp_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server stamps a part in UTC and the floor reads it in local time. These
/// exist because reading the UTC fields straight out is the easy mistake: at
/// +05:30 it shows a part stamped at 10.05 AM as 4.35 AM, and one stamped
/// before half past five as the day before.

void main() {
  test('a stamp is rendered in local time, not UTC', () {
    final utc = DateTime.utc(2026, 5, 15, 4, 35);
    final local = utc.toLocal();

    // Asserted against the local fields rather than a fixed string, because a
    // test run in another zone is still entitled to be right.
    expect(
      partStampDate(utc),
      '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}',
    );
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    expect(
      partStampTime(utc),
      '${hour.toString().padLeft(2, '0')}.'
      '${local.minute.toString().padLeft(2, '0')} '
      '${local.hour >= 12 ? 'PM' : 'AM'}',
    );

    // The bug in one line: the UTC fields are not what gets rendered, wherever
    // this runs that the offset is not zero.
    if (local.hour != utc.hour) {
      expect(partStampTime(utc).startsWith('04.35'), isFalse);
    }
  });

  test('an instant early enough to be yesterday in UTC still reads as today', () {
    // 00:30 local on the 15th is the 14th in UTC east of Greenwich.
    final localMidnightish = DateTime(2026, 5, 15, 0, 30);
    expect(partStampDate(localMidnightish), '15/05/2026');
  });

  test('midday and midnight read as 12, and the hour is padded', () {
    expect(partStampTime(DateTime(2026, 5, 15, 12, 5)), '12.05 PM');
    expect(partStampTime(DateTime(2026, 5, 15, 0, 5)), '12.05 AM');
    expect(partStampTime(DateTime(2026, 5, 15, 9, 5)), '09.05 AM');
    expect(partStampTime(DateTime(2026, 5, 15, 23, 59)), '11.59 PM');
  });

  test('both halves on one line', () {
    expect(partStamp(DateTime(2026, 5, 15, 10, 5)), '15/05/2026 10.05 AM');
  });
}
