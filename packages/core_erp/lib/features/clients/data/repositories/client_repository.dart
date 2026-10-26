import '../../domain/party_contact.dart';
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

  /// Adds a person at [clientId] and answers the saved row.
  ///
  /// A company has as many people as it has, and this is how one more gets on
  /// file without leaving whatever screen is open.
  Future<PartyContact> addContact(int clientId, PartyContact contact);

  /// Saves a change to a person already on file. Name is required.
  Future<PartyContact> updateContact(int clientId, PartyContact contact);

  /// Archives (or, with `archived: false`, restores) a person. Never a delete:
  /// parts that dealt with them keep saying so.
  Future<PartyContact> archiveContact(
    int clientId,
    int contactId, {
    bool archived = true,
  });
}
