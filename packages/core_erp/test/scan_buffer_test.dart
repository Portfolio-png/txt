import 'package:core_erp/core/services/scan_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scanner gun is a keyboard, so the only thing separating a scan from
/// someone typing is speed. This is that judgement, and it is worth pinning
/// because being wrong is expensive both ways: too eager and a global listener
/// fights every text field in the app; too strict and a real scan does nothing
/// at all and no one can see why.

/// Types [text] with a fixed gap between characters, starting from a fixed
/// instant. Time is supplied rather than waited for — a test should describe a
/// scan, not sit through one.
String? type(ScanBuffer buffer, String text, {required int gapMs}) {
  var at = DateTime(2026, 1, 1);
  for (final character in text.split('')) {
    buffer.add(character, at);
    at = at.add(Duration(milliseconds: gapMs));
  }
  return buffer.complete();
}

void main() {
  test('a scanner gun is recognised', () {
    // Real guns emit at roughly 5-15ms per character.
    expect(type(ScanBuffer(), 'MAT-REC-1-L1-K', gapMs: 8), 'MAT-REC-1-L1-K');
  });

  test('a person typing is not', () {
    // Even fast typing does not come close; 120ms is a brisk 100wpm.
    expect(type(ScanBuffer(), 'hello world', gapMs: 120), isNull);
  });

  test('a pause splits one burst from the next rather than joining them', () {
    // A gun emits without pausing. A pause means a person, so whatever came
    // before it is theirs and must not be glued to what follows — otherwise a
    // half-typed word ends up prefixed onto the next scan.
    final buffer = ScanBuffer();
    var at = DateTime(2026, 1, 1);
    for (final character in 'MAT-REC'.split('')) {
      buffer.add(character, at);
      at = at.add(const Duration(milliseconds: 8));
    }
    at = at.add(const Duration(milliseconds: 400)); // a person, thinking
    for (final character in 'DC-9'.split('')) {
      buffer.add(character, at);
      at = at.add(const Duration(milliseconds: 8));
    }
    // Only the second burst survives, and it stands on its own merits.
    expect(buffer.complete(), 'DC-9');
  });

  test('a fast burst too short to be a code is left alone', () {
    final buffer = ScanBuffer();
    var at = DateTime(2026, 1, 1);
    for (final character in 'MAT-REC'.split('')) {
      buffer.add(character, at);
      at = at.add(const Duration(milliseconds: 8));
    }
    at = at.add(const Duration(milliseconds: 400));
    for (final character in '-1'.split('')) {
      buffer.add(character, at);
      at = at.add(const Duration(milliseconds: 8));
    }
    expect(buffer.complete(), isNull, reason: 'two characters is not a code');
  });

  test('a scan after typing does not inherit the typed prefix', () {
    // The failure this prevents: someone types in a field, then scans, and the
    // gun's code arrives glued to the end of what they typed.
    final buffer = ScanBuffer();
    var at = DateTime(2026, 1, 1);
    for (final character in 'note'.split('')) {
      buffer.add(character, at);
      at = at.add(const Duration(milliseconds: 200));
    }
    at = at.add(const Duration(milliseconds: 500));
    for (final character in 'MAT-REC-1-L1-K'.split('')) {
      buffer.add(character, at);
      at = at.add(const Duration(milliseconds: 8));
    }
    expect(buffer.complete(), 'MAT-REC-1-L1-K');
  });

  test('something too short is left to the app', () {
    // A scanner *could* emit "OK", but Enter after two characters much more
    // often means confirm-this-dialog, and stealing it would be worse than
    // missing an unusually short code.
    expect(type(ScanBuffer(), 'OK', gapMs: 8), isNull);
  });

  test('completing always clears, whichever way it went', () {
    // A buffer left behind would prefix the next scan — the same bug as
    // inheriting a typed prefix, arriving by a different route.
    final buffer = ScanBuffer();
    expect(type(buffer, 'typed slowly', gapMs: 300), isNull);
    expect(buffer.isEmpty, isTrue);
    expect(type(buffer, 'MAT-REC-1-L1-K', gapMs: 8), 'MAT-REC-1-L1-K');
    expect(buffer.isEmpty, isTrue);
  });

  test('a bare Enter is not a scan', () {
    expect(ScanBuffer().complete(), isNull);
  });

  test('the thresholds are adjustable for an unusual gun', () {
    // Some scanners are slower, and a shop should not be stuck with a gun the
    // app refuses to believe in.
    final tolerant = ScanBuffer(scannerGapMs: 200, minimumLength: 2);
    expect(type(tolerant, 'AB', gapMs: 150), 'AB');
  });
}
