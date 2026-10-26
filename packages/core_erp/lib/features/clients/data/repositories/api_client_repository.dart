import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/client_definition.dart';
import '../../domain/party_contact.dart';
import '../../domain/client_inputs.dart';
import '../models/client_api_models.dart';
import 'client_repository.dart';

class ApiClientRepository implements ClientRepository {
  ApiClientRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<ClientDefinition> _mockClients = <ClientDefinition>[];
  static int _mockNextId = 1;
  static bool _mockSeeded = false;

  static void debugResetMockStore() {
    _mockClients.clear();
    _mockNextId = 1;
    _mockSeeded = false;
  }

  @override
  Future<void> init() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
    }
  }

  @override
  Future<List<ClientDefinition>> getClients() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return List<ClientDefinition>.from(_mockClients);
    }

    final uri = Uri.parse('$baseUrl/api/clients');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientsListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw ClientApiException(
        payload['error'] as String? ?? 'Failed to fetch clients.',
      );
    }
    return parsed.clients
        .map((client) => client.toDomain())
        .toList(growable: false);
  }

  @override
  Future<ClientDefinition?> getClient(int id) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      try {
        return _mockClients.firstWhere((c) => c.id == id);
      } catch (e) {
        return null;
      }
    }

    final uri = Uri.parse('$baseUrl/api/clients/$id');
    final response = await _client.get(uri);

    if (response.statusCode == 404) return null;

    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false) {
      throw ClientApiException(
        payload['error'] as String? ?? 'Failed to fetch client.',
      );
    }

    return ClientDto.fromJson(
      payload['client'] as Map<String, dynamic>,
    ).toDomain();
  }

  @override
  Future<ClientDefinition> createClient(CreateClientInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      _assertNoDuplicate(name: input.name, gstNumber: input.gstNumber);
      final now = DateTime.now();
      final created = ClientDefinition(
        id: _mockNextId++,
        name: input.name.trim(),
        alias: input.alias.trim(),
        gstNumber: _normalizeGstNumber(input.gstNumber),
        address: input.address.trim(),
        isArchived: false,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
        logoUrl: input.logoUrl.trim(),
        photoUrl: input.photoUrl.trim(),
        contactName: input.contactName.trim(),
        designation: input.designation.trim(),
        phone: input.phone.trim(),
        email: input.email.trim(),
      );
      _mockClients.add(created);
      return created;
    }

    final uri = Uri.parse('$baseUrl/api/clients');
    final request = CreateClientRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.client == null) {
      throw ClientApiException(parsed.error ?? 'Failed to create client.');
    }
    return parsed.client!.toDomain();
  }

  @override
  Future<ClientDefinition> updateClient(UpdateClientInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockClients.indexWhere((client) => client.id == input.id);
      if (index == -1) {
        throw ClientApiException('Client not found.');
      }
      _assertNoDuplicate(
        name: input.name,
        gstNumber: input.gstNumber,
        excludeId: input.id,
      );
      final current = _mockClients[index];
      final updated = ClientDefinition(
        id: current.id,
        name: input.name.trim(),
        alias: input.alias.trim(),
        gstNumber: _normalizeGstNumber(input.gstNumber),
        address: input.address.trim(),
        isArchived: current.isArchived,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        logoUrl: input.logoUrl.trim(),
        photoUrl: input.photoUrl.trim(),
        contactName: input.contactName.trim(),
        designation: input.designation.trim(),
        phone: input.phone.trim(),
        email: input.email.trim(),
      );
      _mockClients[index] = updated;
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/clients/${input.id}');
    final request = UpdateClientRequest.fromInput(input);
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.client == null) {
      throw ClientApiException(parsed.error ?? 'Failed to update client.');
    }
    return parsed.client!.toDomain();
  }

  @override
  Future<ClientDefinition> archiveClient(int id) => _setArchived(id, true);

  @override
  Future<ClientDefinition> restoreClient(int id) => _setArchived(id, false);

  /// One body for both directions: the two routes differ only in their last
  /// path segment and the flag they set.
  Future<ClientDefinition> _setArchived(int id, bool archived) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockClients.indexWhere((client) => client.id == id);
      if (index == -1) {
        throw ClientApiException('Client not found.');
      }
      final updated = _mockClients[index].copyWith(
        isArchived: archived,
        updatedAt: DateTime.now(),
      );
      _mockClients[index] = updated;
      return updated;
    }

    final segment = archived ? 'archive' : 'unarchive';
    final uri = Uri.parse('$baseUrl/api/clients/$id/$segment');
    final response = await _client.patch(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.client == null) {
      throw ClientApiException(
        parsed.error ??
            (archived
                ? 'Failed to archive client.'
                : 'Failed to restore client.'),
      );
    }
    return parsed.client!.toDomain();
  }

  @override
  Future<void> deleteClient(int id) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      _mockClients.removeWhere((c) => c.id == id);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/clients/$id');
    final response = await _client.delete(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw ClientApiException(parsed.error ?? 'Failed to delete client.');
    }
  }

  @override
  Future<PartyContact> addContact(int clientId, PartyContact contact) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockClients.indexWhere((c) => c.id == clientId);
      if (index < 0) throw ClientApiException('No such client.');
      if (contact.name.trim().isEmpty) {
        throw ClientApiException('A person needs a name.');
      }
      final client = _mockClients[index];
      final made = contact.copyWith(
        id: DateTime.now().microsecondsSinceEpoch % 1000000,
        partyType: 'client',
        partyId: clientId,
        name: contact.name.trim(),
        isPrimary: client.activeContacts.isEmpty,
        isArchived: false,
      );
      _mockClients[index] = _withMirroredPrimary(
        client.copyWith(contacts: [...client.contacts, made]),
      );
      return made;
    }

    // Nested under the client on purpose: the route inherits the clients
    // module's permissions AND its per-record grants, which a flat
    // /party-contacts/:id would get wrong — see modules/parties/contacts.js.
    final uri = Uri.parse('$baseUrl/api/clients/$clientId/contacts');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(contact.toJson()),
    );
    return _contactFrom(response, 'Failed to add the person.');
  }

  @override
  Future<PartyContact> updateContact(int clientId, PartyContact contact) async {
    final id = contact.id;
    if (id == null) throw ClientApiException('That person is not saved yet.');
    if (contact.name.trim().isEmpty) {
      throw ClientApiException('A person needs a name.');
    }
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return _mockReplaceContact(
        clientId,
        id,
        (stored) => stored.copyWith(
          name: contact.name.trim(),
          designation: contact.designation,
          phone: contact.phone,
          email: contact.email,
          notes: contact.notes,
        ),
      );
    }

    final uri = Uri.parse('$baseUrl/api/clients/$clientId/contacts/$id');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(contact.toJson()),
    );
    return _contactFrom(response, 'Failed to save the person.');
  }

  @override
  Future<PartyContact> archiveContact(
    int clientId,
    int contactId, {
    bool archived = true,
  }) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return _mockReplaceContact(
        clientId,
        contactId,
        (stored) => stored.copyWith(
          isArchived: archived,
          isPrimary: archived ? false : stored.isPrimary,
        ),
      );
    }

    final uri =
        Uri.parse('$baseUrl/api/clients/$clientId/contacts/$contactId/archive');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'isArchived': archived}),
    );
    return _contactFrom(response, 'Failed to archive the person.');
  }

  PartyContact _contactFrom(http.Response response, String fallback) {
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ClientApiException(payload['error'] as String? ?? fallback);
    }
    return PartyContact.fromJson(payload['contact'] as Map<String, dynamic>);
  }

  PartyContact _mockReplaceContact(
    int clientId,
    int contactId,
    PartyContact Function(PartyContact stored) change,
  ) {
    final index = _mockClients.indexWhere((c) => c.id == clientId);
    if (index < 0) throw ClientApiException('No such client.');
    final client = _mockClients[index];
    final at = client.contacts.indexWhere((c) => c.id == contactId);
    if (at < 0) throw ClientApiException('No such person at this client.');
    final changed = change(client.contacts[at]);
    final contacts = [...client.contacts]..[at] = changed;
    _mockClients[index] = _withMirroredPrimary(client.copyWith(contacts: contacts));
    return changed;
  }

  /// The flat fields follow the primary, as the server's mirror does.
  ClientDefinition _withMirroredPrimary(ClientDefinition client) {
    PartyContact? primary;
    for (final contact in client.contacts) {
      if (contact.isPrimary && !contact.isArchived) primary = contact;
    }
    return client.copyWith(
      contactName: primary?.name ?? '',
      designation: primary?.designation ?? '',
      phone: primary?.phone ?? '',
      email: primary?.email ?? '',
    );
  }

  void _assertNoDuplicate({
    required String name,
    required String gstNumber,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    final normalizedGstNumber = _normalizeGstNumber(gstNumber);

    for (final client in _mockClients) {
      if (excludeId != null && client.id == excludeId) {
        continue;
      }
      if (_normalize(client.name) == normalizedName) {
        throw const ClientApiException(
          'A client with the same name already exists.',
        );
      }
      if (normalizedGstNumber.isNotEmpty &&
          _normalizeGstNumber(client.gstNumber) == normalizedGstNumber) {
        throw const ClientApiException(
          'A client with the same GST number already exists.',
        );
      }
    }
  }

  void _seedMockStoreIfNeeded() {
    if (_mockSeeded) {
      return;
    }
    _mockSeeded = true;
    final now = DateTime.now();
    _mockClients
      ..clear()
      ..addAll([
        ClientDefinition(
          id: _mockNextId++,
          name: 'Acme Packaging Pvt. Ltd.',
          alias: 'Acme',
          gstNumber: '27ABCDE1234F1Z5',
          address: 'MIDC Industrial Area, Pune, Maharashtra 411019',
          isArchived: false,
          usageCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
        ClientDefinition(
          id: _mockNextId++,
          name: 'Sunrise Retail LLP',
          alias: 'Sunrise',
          gstNumber: '24AAKCS9988M1Z2',
          address: 'Satellite Road, Ahmedabad, Gujarat 380015',
          isArchived: false,
          usageCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
        ClientDefinition(
          id: _mockNextId++,
          name: 'Legacy Trading Co.',
          alias: 'Legacy',
          gstNumber: '',
          address: 'Old Market Road, Indore, Madhya Pradesh 452001',
          isArchived: true,
          usageCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    if (body.isEmpty) {
      return const {'success': false, 'error': 'Empty response from server.'};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {
        'success': false,
        'error': 'Unexpected response format from server.',
      };
    } on FormatException {
      return {
        'success': false,
        'error': body.trim().isEmpty
            ? 'Unexpected response from server.'
            : body.trim(),
      };
    }
  }

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _normalizeGstNumber(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }
}

class ClientApiException implements Exception {
  const ClientApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
