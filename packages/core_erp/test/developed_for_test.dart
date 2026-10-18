import 'package:core_erp/core/utils/stamp_format.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Developed For block, away from any widget: the money, the stamp, and
/// the difference between "developed in-house" and "nobody has said".

void main() {
  group('parseRupees', () {
    test('takes a figure however it was written on the quotation', () {
      expect(parseRupees('85000'), 85000);
      expect(parseRupees('85000/-'), 85000);
      expect(parseRupees('₹85,000'), 85000);
      expect(parseRupees('₹ 85,000 /-'), 85000);
      expect(parseRupees('Rs. 85,000'), 85000);
      expect(parseRupees('85,000.50'), 85000.50);
      expect(parseRupees('0'), 0);
    });

    test('junk and nothing are both null, never zero', () {
      // The whole reason the column is nullable: never quoted and quoted at
      // zero are different facts, and reading junk as 0 would print a figure
      // nobody gave.
      expect(parseRupees(''), isNull);
      expect(parseRupees('   '), isNull);
      expect(parseRupees(null), isNull);
      expect(parseRupees('eighty five thousand'), isNull);
      expect(parseRupees('abc'), isNull);
    });
  });

  group('rupeeStamp', () {
    test('groups the Indian way, not the Western one', () {
      expect(rupeeStamp(85000), '₹85,000/-');
      expect(rupeeStamp(100000), '₹1,00,000/-');
      expect(rupeeStamp(12500000), '₹1,25,00,000/-');
      expect(rupeeStamp(999), '₹999/-');
      expect(rupeeStamp(0), '₹0/-');
    });

    test('shows paise only when there are paise', () {
      expect(rupeeStamp(4200.5), '₹4,200.50/-');
      expect(rupeeStamp(4200), '₹4,200/-');
      expect(rupeeStamp(-500), '-₹500/-');
      expect(rupeeStamp(85000, trailingDash: false), '₹85,000');
    });

    test('round-trips through the parser', () {
      for (final value in [0.0, 999.0, 85000.0, 100000.0, 4200.5]) {
        expect(parseRupees(rupeeStamp(value)), value, reason: '$value');
      }
    });
  });

  group('the stamp', () {
    test('a UTC instant reads as the local wall clock', () {
      // 04:35Z is 10.05 AM at +05:30. Reading the UTC fields straight out
      // would print 04.35 AM, and anything before 05:30 the day before.
      final at = DateTime.utc(2026, 5, 15, 4, 35);
      final local = at.toLocal();
      expect(partStamp(at), '${partStampDate(local)} ${partStampTime(local)}');
      if (local.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        expect(partStamp(at), '15/05/2026 10.05 AM');
      }
    });
  });

  group('DevelopedFor', () {
    test('round-trips the part\'s own fields, and only those', () {
      final block = DevelopedFor(
        kind: DevelopedForKind.client,
        clientId: 7,
        clientName: 'Gold Madel',
        companyName: 'Gold Madel',
        contactName: 'Kissan Jain',
        designation: 'Director',
        phone: '986565656',
        email: 'kissan@example.com',
        at: DateTime.utc(2026, 5, 15, 4, 35),
        quotationAmount: 85000,
      );

      final json = block.toJson();
      expect(json['kind'], 'client');
      expect(json['clientId'], 7);
      expect(json['subContractorId'], isNull);
      expect(json['at'], '2026-05-15T04:35:00.000Z');
      expect(json['quotationAmount'], 85000);

      // The resolved person is read-only: it comes from the party on every
      // read, and sending it back would invite an item save to rewrite a
      // client's phone number.
      expect(json.containsKey('contactName'), isFalse);
      expect(json.containsKey('companyName'), isFalse);

      // What comes back from the server carries both halves.
      final read = DevelopedFor.fromJson({
        ...json,
        'clientName': 'Gold Madel',
        'companyName': 'Gold Madel',
        'contactName': 'Kissan Jain',
        'designation': 'Director',
        'phone': '986565656',
        'email': 'kissan@example.com',
      });
      expect(read, block);
    });

    test('a local time goes out in UTC', () {
      final local = DateTime(2026, 5, 15, 10, 5);
      final json = DevelopedFor(at: local).toJson();
      expect(json['at'], local.toUtc().toIso8601String());
      expect(DevelopedFor.fromJson(json).at, local.toUtc());
    });

    test('an unknown kind reads as "nobody has said", not as a crash', () {
      // A client one version behind the server still has to open the part.
      expect(
        DevelopedFor.fromJson({'kind': 'a-kind-from-the-future'}).kind,
        DevelopedForKind.none,
      );
      expect(DevelopedForKind.fromWire(null), DevelopedForKind.none);
      expect(DevelopedForKind.fromWire('contractor'), DevelopedForKind.contractor);
    });

    test('self is a recorded answer; none is the absence of one', () {
      expect(DevelopedFor.empty.isEmpty, isTrue);
      expect(const DevelopedFor(kind: DevelopedForKind.self).isEmpty, isFalse);
      // A date alone counts: someone opened the form and put something in.
      expect(DevelopedFor(at: DateTime(2026)).isEmpty, isFalse);
      expect(const DevelopedFor(quotationAmount: 0).isEmpty, isFalse);
    });

    test('a kind that needs a party says so until it has one', () {
      expect(const DevelopedFor(kind: DevelopedForKind.client).needsParty, isTrue);
      expect(
        const DevelopedFor(kind: DevelopedForKind.client, clientId: 3).needsParty,
        isFalse,
      );
      expect(
        const DevelopedFor(kind: DevelopedForKind.contractor, clientId: 3).needsParty,
        isTrue,
        reason: 'a parent client is not a contractor',
      );
      expect(const DevelopedFor(kind: DevelopedForKind.self).needsParty, isFalse);
    });

    test('switching to self drops the party, so the form cannot lie', () {
      const filled = DevelopedFor(
        kind: DevelopedForKind.client,
        clientId: 7,
        clientName: 'Gold Madel',
        companyName: 'Gold Madel',
        contactName: 'Kissan Jain',
        quotationAmount: 85000,
      );

      final toSelf = filled.withKind(DevelopedForKind.self);
      expect(toSelf.kind, DevelopedForKind.self);
      expect(toSelf.clientId, isNull);
      expect(toSelf.companyName, isEmpty);
      expect(toSelf.contactName, isEmpty);
      // The figure and the stamp are about the part, not the party, so they
      // survive the switch.
      expect(toSelf.quotationAmount, 85000);
      expect(toSelf.toJson()['clientId'], isNull);
    });

    test('contractor to client keeps the company and drops the person', () {
      const viaContractor = DevelopedFor(
        kind: DevelopedForKind.contractor,
        clientId: 7,
        clientName: 'Owning Client',
        subContractorId: 3,
        subContractorName: 'Shree Fabrication',
        companyName: 'Owning Client',
      );

      final toClient = viaContractor.withKind(DevelopedForKind.client);
      expect(toClient.clientId, 7, reason: 'the company is still the answer');
      expect(toClient.subContractorId, isNull);
      expect(toClient.subContractorName, isEmpty);
    });

    test('partyName names whoever you actually deal with', () {
      expect(
        const DevelopedFor(
          kind: DevelopedForKind.contractor,
          subContractorName: 'Shree Fabrication',
          companyName: 'Owning Client',
        ).partyName,
        'Shree Fabrication',
      );
      expect(
        const DevelopedFor(
          kind: DevelopedForKind.client,
          companyName: 'Gold Madel',
        ).partyName,
        'Gold Madel',
      );
      expect(const DevelopedFor(kind: DevelopedForKind.self).partyName, isEmpty);
    });
  });
}
