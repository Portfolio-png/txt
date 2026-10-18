import 'package:flutter_test/flutter_test.dart';
import 'package:core_erp/features/clients/data/repositories/api_client_repository.dart';
import 'package:core_erp/features/clients/domain/client_inputs.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';

void main() {
  setUp(() {
    ApiClientRepository.debugResetMockStore();
  });

  test(
    'mock repository creates, updates, archives, and restores clients',
    () async {
      final repository = ApiClientRepository(useMockResponses: true);

      await repository.init();
      final seeded = await repository.getClients();
      expect(
        seeded.any((client) => client.name == 'Acme Packaging Pvt. Ltd.'),
        isTrue,
      );

      final created = await repository.createClient(
        const CreateClientInput(
          name: 'Northwind Papers',
          alias: 'Northwind',
          gstNumber: '29ABCDE1234F1Z5',
          address: 'Bengaluru',
        ),
      );
      final updated = await repository.updateClient(
        UpdateClientInput(
          id: created.id,
          name: 'Northwind Paper Products',
          alias: 'Northwind',
          gstNumber: '29ABCDE1234F1Z5',
          address: 'Peenya, Bengaluru',
        ),
      );
      final archived = await repository.archiveClient(updated.id);
      final restored = await repository.restoreClient(updated.id);

      expect(updated.name, 'Northwind Paper Products');
      expect(updated.address, 'Peenya, Bengaluru');
      expect(archived.isArchived, isTrue);
      expect(restored.isArchived, isFalse);
    },
  );

  test('clients provider filters and blocks duplicate name or GST', () async {
    final provider = ClientsProvider(
      repository: ApiClientRepository(useMockResponses: true),
    );

    await provider.initialize();

    provider.setSearchQuery('sunrise');
    expect(provider.filteredClients.map((client) => client.name), [
      'Sunrise Retail LLP',
    ]);

    provider.setSearchQuery('');
    provider.setStatusFilter(ClientStatusFilter.archived);
    expect(provider.filteredClients.map((client) => client.name), [
      'Legacy Trading Co.',
    ]);

    final duplicateName = provider.checkDuplicate(
      name: 'Acme Packaging Pvt. Ltd.',
      gstNumber: '',
    );
    final duplicateGst = provider.checkDuplicate(
      name: 'Fresh Client',
      gstNumber: '27ABCDE1234F1Z5',
    );

    expect(duplicateName.blockingDuplicate, isTrue);
    expect(duplicateGst.blockingDuplicate, isTrue);
  });

  group('archiving through the provider', () {
    // The repository test above proves the two calls; this proves the thing a
    // user sees — that an archived client leaves the view it was archived from
    // and that Restore brings it back. The provider's default filter is
    // `active`, so these two facts are the whole feature.

    Future<ClientsProvider> ready() async {
      final provider = ClientsProvider(
        repository: ApiClientRepository(useMockResponses: true),
      );
      await provider.initialize();
      return provider;
    }

    test('an archived client leaves the active list and comes back', () async {
      final provider = await ready();
      final target = provider.filteredClients.firstWhere(
        (client) => client.name == 'Sunrise Retail LLP',
      );

      expect(await provider.archiveClient(target.id), isTrue);
      expect(
        provider.filteredClients.map((client) => client.name),
        isNot(contains('Sunrise Retail LLP')),
        reason: 'the default filter is active, so it must drop out of view',
      );

      provider.setStatusFilter(ClientStatusFilter.archived);
      expect(
        provider.filteredClients.map((client) => client.name),
        contains('Sunrise Retail LLP'),
        reason: 'archived is not deleted — it has to be findable',
      );

      expect(await provider.restoreClient(target.id), isTrue);
      provider.setStatusFilter(ClientStatusFilter.active);
      expect(
        provider.filteredClients.map((client) => client.name),
        contains('Sunrise Retail LLP'),
      );
    });

    test('a client that is not there fails without throwing', () async {
      // The screen leaves provider.errorMessage in a banner, so a refusal has
      // to come back as false with a message rather than as an exception
      // nobody catches.
      final provider = await ready();

      expect(await provider.archiveClient(999999), isFalse);
      expect(provider.errorMessage, isNotNull);
      expect(provider.isSaving, isFalse);
    });
  });
}
