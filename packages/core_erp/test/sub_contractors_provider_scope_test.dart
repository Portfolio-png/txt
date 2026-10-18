import 'package:core_erp/features/clients/data/repositories/sub_contractor_repository.dart';
import 'package:core_erp/features/clients/domain/sub_contractor_definition.dart';
import 'package:core_erp/features/clients/domain/sub_contractor_inputs.dart';
import 'package:core_erp/features/clients/presentation/providers/sub_contractors_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// One list, two scopes, and a create that only landed in one of them.
///
/// `loadAll()` and `loadForClient()` used to take turns overwriting a single
/// list, and `create()` appended only when the scope happened to match. That
/// survived while the clients screen was the only caller — it loads, then
/// creates, in that order. It does not survive an item editor picking a
/// contractor for a part: load everything to fill the picker, create one
/// inline, and the row came back from the server and then appeared in no
/// list, so it could not be selected.

SubContractorDefinition _contractor(int id, int clientId, String name) =>
    SubContractorDefinition(
      id: id,
      clientId: clientId,
      name: name,
      designation: 'Proprietor',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _FakeRepository implements SubContractorRepository {
  _FakeRepository(this._rows);

  final List<SubContractorDefinition> _rows;
  int nextId = 100;
  int allCalls = 0;
  int clientCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<List<SubContractorDefinition>> getAllSubContractors() async {
    allCalls += 1;
    return List<SubContractorDefinition>.of(_rows);
  }

  @override
  Future<List<SubContractorDefinition>> getSubContractors(int clientId) async {
    clientCalls += 1;
    return _rows.where((row) => row.clientId == clientId).toList();
  }

  @override
  Future<SubContractorDefinition> createSubContractor(
    int clientId,
    CreateSubContractorInput input,
  ) async {
    final created = _contractor(nextId++, clientId, input.name);
    _rows.add(created);
    return created;
  }

  @override
  Future<SubContractorDefinition> updateSubContractor(
    int id,
    UpdateSubContractorInput input,
  ) async {
    final index = _rows.indexWhere((row) => row.id == id);
    final updated = _rows[index].copyWith(name: input.name);
    _rows[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteSubContractor(int id) async {
    _rows.removeWhere((row) => row.id == id);
  }
}

void main() {
  test('a row created after loadAll is visible in the live scope', () async {
    final repo = _FakeRepository([_contractor(1, 5, 'Shree Fabrication')]);
    final provider = SubContractorsProvider(repository: repo);

    await provider.loadAll();
    await provider.loadForClient(5);
    final created = await provider.create(
      5,
      const CreateSubContractorInput(name: 'New Press Works'),
    );

    expect(created, isNotNull);
    // The scope on screen is client 5, and the new row is in it.
    expect(
      provider.subContractors.map((row) => row.name),
      containsAll(<String>['Shree Fabrication', 'New Press Works']),
    );
    // And in the all-clients cache, which is what a picker elsewhere reads.
    expect(
      provider.allSubContractors.map((row) => row.name),
      contains('New Press Works'),
    );
    expect(provider.forClient(5).map((row) => row.name),
        contains('New Press Works'));
  });

  test('a row created while the all scope is showing is still visible', () async {
    final repo = _FakeRepository([_contractor(1, 5, 'Shree Fabrication')]);
    final provider = SubContractorsProvider(repository: repo);

    await provider.loadAll();
    // No loadForClient at all: this is the item editor's path, where the
    // picker lists everyone and the create names a client inline.
    await provider.create(
      9,
      const CreateSubContractorInput(name: 'Other Client Works'),
    );

    expect(
      provider.allSubContractors.map((row) => row.name),
      contains('Other Client Works'),
    );
    expect(provider.subContractors.map((row) => row.name),
        contains('Other Client Works'));
    expect(provider.forClient(9).map((row) => row.name),
        contains('Other Client Works'));
  });

  test('a create before anything is loaded does not invent a one-row factory',
      () async {
    final repo = _FakeRepository(<SubContractorDefinition>[]);
    final provider = SubContractorsProvider(repository: repo);

    await provider.create(5, const CreateSubContractorInput(name: 'First'));

    // Empty reads as "not loaded", which is honest; one row would read as
    // "this is every contractor there is", which is not.
    expect(provider.allSubContractors, isEmpty);
    await provider.loadAll();
    expect(provider.allSubContractors.map((row) => row.name), contains('First'));
  });

  test('switching scopes does not refetch what is already cached', () async {
    final repo = _FakeRepository([_contractor(1, 5, 'Shree Fabrication')]);
    final provider = SubContractorsProvider(repository: repo);

    await provider.loadForClient(5);
    expect(repo.clientCalls, 1);
    await provider.ensureLoadedForClient(5);
    expect(repo.clientCalls, 1, reason: 'already cached');

    await provider.loadAll();
    await provider.ensureLoadedForClient(77);
    expect(
      repo.clientCalls,
      1,
      reason: 'the all-clients list already answers for every client',
    );
  });

  test('an update and a delete reach both caches', () async {
    final repo = _FakeRepository([
      _contractor(1, 5, 'Shree Fabrication'),
      _contractor(2, 5, 'Press Works'),
    ]);
    final provider = SubContractorsProvider(repository: repo);

    await provider.loadAll();
    await provider.loadForClient(5);

    await provider.update(1, const UpdateSubContractorInput(name: 'Shree Fab'));
    expect(
      provider.allSubContractors.where((row) => row.id == 1).single.name,
      'Shree Fab',
    );
    expect(provider.forClient(5).where((row) => row.id == 1).single.name,
        'Shree Fab');

    await provider.delete(1);
    expect(provider.allSubContractors.any((row) => row.id == 1), isFalse);
    expect(provider.forClient(5).any((row) => row.id == 1), isFalse);
  });
}
