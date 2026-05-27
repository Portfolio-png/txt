import '../../domain/client_definition.dart';
import '../../domain/client_inputs.dart';

abstract class ClientRepository {
  Future<void> init();
  Future<List<ClientDefinition>> getClients();
  Future<ClientDefinition> createClient(CreateClientInput input);
  Future<ClientDefinition> updateClient(UpdateClientInput input);
  Future<ClientDefinition> archiveClient(int id);
  Future<ClientDefinition> restoreClient(int id);
}
