import 'package:flutter/material.dart';

import '../../data/repositories/client_repository.dart';
import '../../domain/client_definition.dart';
import '../../domain/client_inputs.dart';

enum ClientStatusFilter { active, archived, all }

enum ClientDuplicateWarning { none, nameOnly, gstOnly, nameAndGst }

class ClientDuplicateCheck {
  const ClientDuplicateCheck({
    required this.blockingDuplicate,
    required this.warning,
  });

  final bool blockingDuplicate;
  final ClientDuplicateWarning warning;
}

class ClientsProvider extends ChangeNotifier {
  ClientsProvider({required ClientRepository repository})
    : _repository = repository;

  final ClientRepository _repository;

  List<ClientDefinition> _clients = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';
  ClientStatusFilter _statusFilter = ClientStatusFilter.active;
  bool _initialized = false;

  List<ClientDefinition> get clients => _clients;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  ClientStatusFilter get statusFilter => _statusFilter;

  List<ClientDefinition> get filteredClients {
    final query = _normalize(_searchQuery);
    return _clients
        .where((client) {
          final matchesStatus = switch (_statusFilter) {
            ClientStatusFilter.active => !client.isArchived,
            ClientStatusFilter.archived => client.isArchived,
            ClientStatusFilter.all => true,
          };
          if (!matchesStatus) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return _normalize(client.name).contains(query) ||
              _normalize(client.alias).contains(query) ||
              _normalize(client.gstNumber).contains(query) ||
              _normalize(client.address).contains(query);
        })
        .toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.init();
      final clients = await _repository.getClients();
      clients.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final nameCompare = a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        );
        if (nameCompare != 0) {
          return nameCompare;
        }
        return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
      });
      _clients = clients;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void setStatusFilter(ClientStatusFilter value) {
    _statusFilter = value;
    notifyListeners();
  }

  ClientDuplicateCheck checkDuplicate({
    required String name,
    required String gstNumber,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    final normalizedGst = _normalizeGstNumber(gstNumber);
    var nameMatch = false;
    var gstMatch = false;

    for (final client in _clients) {
      if (excludeId != null && client.id == excludeId) {
        continue;
      }
      if (_normalize(client.name) == normalizedName) {
        nameMatch = true;
      }
      if (normalizedGst.isNotEmpty &&
          _normalizeGstNumber(client.gstNumber) == normalizedGst) {
        gstMatch = true;
      }
    }

    if (nameMatch && gstMatch) {
      return const ClientDuplicateCheck(
        blockingDuplicate: true,
        warning: ClientDuplicateWarning.nameAndGst,
      );
    }
    if (nameMatch) {
      return const ClientDuplicateCheck(
        blockingDuplicate: true,
        warning: ClientDuplicateWarning.nameOnly,
      );
    }
    if (gstMatch) {
      return const ClientDuplicateCheck(
        blockingDuplicate: true,
        warning: ClientDuplicateWarning.gstOnly,
      );
    }
    return const ClientDuplicateCheck(
      blockingDuplicate: false,
      warning: ClientDuplicateWarning.none,
    );
  }

  Future<ClientDefinition?> createClient(CreateClientInput input) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await _repository.createClient(input);
      await refresh();
      return _clients.where((client) => client.id == created.id).firstOrNull ??
          created;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<ClientDefinition?> updateClient(UpdateClientInput input) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.updateClient(input);
      await refresh();
      return _clients.where((client) => client.id == updated.id).firstOrNull ??
          updated;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<ClientDefinition?> archiveClient(int id) async {
    return _changeStatus(() => _repository.archiveClient(id));
  }

  Future<ClientDefinition?> restoreClient(int id) async {
    return _changeStatus(() => _repository.restoreClient(id));
  }

  Future<ClientDefinition?> _changeStatus(
    Future<ClientDefinition> Function() action,
  ) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await action();
      await refresh();
      return _clients.where((client) => client.id == updated.id).firstOrNull ??
          updated;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  static String normalizeGstNumber(String value) => _normalizeGstNumber(value);

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _normalizeGstNumber(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
