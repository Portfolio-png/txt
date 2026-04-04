import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/clients/data/repositories/api_client_repository.dart';
import 'package:paper/features/clients/domain/client_inputs.dart';
import 'package:paper/features/clients/presentation/providers/clients_provider.dart';

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
}
