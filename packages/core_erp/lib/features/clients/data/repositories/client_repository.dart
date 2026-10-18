import '../../domain/client_definition.dart';
import '../../domain/client_inputs.dart';

abstract class ClientRepository {
  Future<void> init();
  Future<List<ClientDefinition>> getClients();
  Future<ClientDefinition?> getClient(int id);
  Future<ClientDefinition> createClient(CreateClientInput input);
  Future<ClientDefinition> updateClient(UpdateClientInput input);

  /// Takes a client out of use without destroying it, and puts it back.
  ///
  /// Both answer with the updated row, so a caller knows the new state without
  /// refetching the list. Archiving refuses — 409, `client_in_use` — while
  /// anything still names the client.
  Future<ClientDefinition> archiveClient(int id);
  Future<ClientDefinition> restoreClient(int id);

  Future<void> deleteClient(int id);
}
