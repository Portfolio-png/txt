import 'package:core_erp/features/die_makers/data/die_maker_repository.dart';
import 'package:core_erp/features/die_makers/domain/die_maker.dart';
import 'package:core_erp/features/die_makers/presentation/providers/die_makers_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The master behind "Die Made By".
///
/// Migration 048 made that field free text and argued a master would be
/// "wrong half the time", because a die is made by a fitter on the floor or by
/// an outside toolroom. The shop reversed the call. What these assert is that
/// the reversal kept the half 048 had right: a maker with nothing but a name
/// is a legal record, and a die that names somebody who was never a record
/// still reads back as that name.

DieMakersProvider _provider() {
  ApiDieMakerRepository.debugResetMockStore();
  return DieMakersProvider(
    repository: ApiDieMakerRepository(useMockResponses: true),
  );
}

void main() {
  group('the master', () {
    test('a name is the whole of what a die maker needs', () async {
      final provider = _provider();
      addTearDown(provider.dispose);

      final fitter = await provider.create(
        const DieMakerInput(name: 'Suresh'),
      );
      expect(fitter, isNotNull);
      expect(fitter!.name, 'Suresh');
      expect(
        fitter.gstNumber,
        isEmpty,
        reason: 'a fitter on the floor has no GST number',
      );
    });

    test('a duplicate name answers with the maker that holds it', () async {
      // The caller asked for "a die maker called X" and there is one. Handing
      // it back answers the question that was asked; an error would make the
      // shop resolve a collision it did not cause.
      final provider = _provider();
      addTearDown(provider.dispose);

      final first = await provider.create(
        const DieMakerInput(name: 'Sharma Tool Works'),
      );
      await provider.refresh();
      final second = await provider.create(
        const DieMakerInput(name: 'sharma tool works'),
      );

      expect(second, isNotNull);
      expect(second!.id, first!.id);
    });

    test('byName matches the way the unique index does', () async {
      // Case-insensitively — otherwise the picker offers to create a maker
      // the server then refuses.
      final provider = _provider();
      addTearDown(provider.dispose);

      await provider.create(const DieMakerInput(name: 'Sharma Tool Works'));
      await provider.refresh();

      expect(provider.byName('sharma tool works'), isNotNull);
      expect(provider.byName('  SHARMA TOOL WORKS '), isNotNull);
      expect(provider.byName('Sharma'), isNull);
      expect(provider.byName(''), isNull);
      expect(provider.byName(null), isNull);
    });

    test('ensureLoaded fetches once', () async {
      final provider = _provider();
      addTearDown(provider.dispose);

      await provider.ensureLoaded();
      await provider.ensureLoaded();
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });
  });

  group('what a picker shows', () {
    test('the alias rides along, because that is what the shop says', () {
      const withAlias = DieMaker(
        id: 1,
        name: 'Sharma Tool Works',
        alias: 'STW',
      );
      expect(withAlias.displayLabel, 'Sharma Tool Works (STW)');

      const without = DieMaker(id: 2, name: 'Suresh');
      expect(without.displayLabel, 'Suresh');
    });

    test('the second line is whoever you ring, else where they are', () {
      const withContact = DieMaker(
        id: 1,
        name: 'Sharma Tool Works',
        contactName: 'Ramesh',
        designation: 'Proprietor',
      );
      expect(withContact.pickerSubtitle, 'Ramesh · Proprietor');

      const addressOnly = DieMaker(
        id: 2,
        name: 'Sharma Tool Works',
        address: 'Plot 14, MIDC',
      );
      expect(addressOnly.pickerSubtitle, 'Plot 14, MIDC');

      const bare = DieMaker(id: 3, name: 'Suresh');
      expect(bare.pickerSubtitle, isEmpty);
    });

    test('a search matches more than the name', () {
      // Somebody looking for a toolroom reaches for the number as often as
      // the name.
      const maker = DieMaker(
        id: 1,
        name: 'Sharma Tool Works',
        alias: 'STW',
        phone: '9876543210',
        contactName: 'Ramesh',
      );
      expect(maker.searchText, contains('STW'));
      expect(maker.searchText, contains('9876543210'));
      expect(maker.searchText, contains('Ramesh'));
    });
  });
}
