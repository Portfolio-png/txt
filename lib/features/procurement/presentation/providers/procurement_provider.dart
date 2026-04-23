import 'package:flutter/material.dart';

import '../../data/repositories/procurement_repository.dart';
import '../../domain/procurement_models.dart';

class ProcurementProvider extends ChangeNotifier {
  ProcurementProvider({required ProcurementRepository repository})
    : _repository = repository;

  final ProcurementRepository _repository;

  bool _initialized = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  List<ProcurementQueueRow> _queueRows = const <ProcurementQueueRow>[];
  List<ProcurementRequestSummary> _requests =
      const <ProcurementRequestSummary>[];
  ProcurementRequestDetail? _selectedRequest;
  final Set<String> _selectedQueueKeys = <String>{};

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  List<ProcurementQueueRow> get queueRows =>
      List<ProcurementQueueRow>.unmodifiable(_queueRows);
  List<ProcurementRequestSummary> get requests =>
      List<ProcurementRequestSummary>.unmodifiable(_requests);
  ProcurementRequestDetail? get selectedRequest => _selectedRequest;
  Set<String> get selectedQueueKeys => Set<String>.from(_selectedQueueKeys);

  bool isQueueSelected(ProcurementQueueRow row) {
    return _selectedQueueKeys.contains(row.key);
  }

  void toggleQueueSelection(ProcurementQueueRow row) {
    if (_selectedQueueKeys.contains(row.key)) {
      _selectedQueueKeys.remove(row.key);
    } else {
      _selectedQueueKeys.add(row.key);
    }
    notifyListeners();
  }

  void clearQueueSelection() {
    _selectedQueueKeys.clear();
    notifyListeners();
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
      _queueRows = await _repository.getQueueRows();
      _requests = await _repository.getRequests();
      if (_selectedRequest != null) {
        final selectedId = _selectedRequest!.request.id;
        _selectedRequest = await _repository.getRequestDetail(selectedId);
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshQueue() async {
    try {
      _queueRows = await _repository.refreshQueueRows();
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<List<ProcurementRequestSummary>> createDraftFromSelection() async {
    final selectedRows = _queueRows
        .where((row) => _selectedQueueKeys.contains(row.key))
        .toList(growable: false);
    if (selectedRows.isEmpty) {
      return const <ProcurementRequestSummary>[];
    }
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await _repository.createDraftRequests(rows: selectedRows);
      _selectedQueueKeys.clear();
      _queueRows = await _repository.refreshQueueRows();
      _requests = await _repository.getRequests();
      if (created.isNotEmpty) {
        _selectedRequest = await _repository.getRequestDetail(created.first.id);
      }
      return created;
    } catch (error) {
      _errorMessage = error.toString();
      return const <ProcurementRequestSummary>[];
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> selectRequest(int requestId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _selectedRequest = await _repository.getRequestDetail(requestId);
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSelectedRequest({
    String? expectedDate,
    String? notes,
  }) async {
    final selected = _selectedRequest;
    if (selected == null) {
      return;
    }
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final summary = await _repository.updateRequest(
        requestId: selected.request.id,
        expectedDate: expectedDate,
        notes: notes,
      );
      _selectedRequest = await _repository.getRequestDetail(summary.id);
      _requests = await _repository.getRequests();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> raiseSelectedRequest() async {
    final selected = _selectedRequest;
    if (selected == null) {
      return;
    }
    await _updateRequestLifecycle(
      () => _repository.raiseRequest(selected.request.id),
    );
  }

  Future<void> closeSelectedRequest() async {
    final selected = _selectedRequest;
    if (selected == null) {
      return;
    }
    await _updateRequestLifecycle(
      () => _repository.closeRequest(selected.request.id),
    );
  }

  Future<void> cancelSelectedRequest(String reason) async {
    final selected = _selectedRequest;
    if (selected == null) {
      return;
    }
    await _updateRequestLifecycle(
      () => _repository.cancelRequest(
        requestId: selected.request.id,
        reason: reason,
      ),
    );
  }

  Future<void> receiveOnSelectedRequest({
    required int requestLineId,
    required double receivedQty,
  }) async {
    await receiveOnSelectedRequestLines(
      lines: <ProcurementReceiveLineInput>[
        ProcurementReceiveLineInput(
          requestLineId: requestLineId,
          receivedQty: receivedQty,
        ),
      ],
    );
  }

  Future<void> receiveOnSelectedRequestLines({
    required List<ProcurementReceiveLineInput> lines,
  }) async {
    final selected = _selectedRequest;
    if (selected == null) {
      return;
    }
    if (lines.isEmpty) {
      return;
    }
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _selectedRequest = await _repository.receiveRequestLines(
        requestId: selected.request.id,
        lines: lines,
      );
      _queueRows = await _repository.refreshQueueRows();
      _requests = await _repository.getRequests();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> _updateRequestLifecycle(
    Future<ProcurementRequestSummary> Function() action,
  ) async {
    final selected = _selectedRequest;
    if (selected == null) {
      return;
    }
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final summary = await action();
      _selectedRequest = await _repository.getRequestDetail(summary.id);
      _queueRows = await _repository.refreshQueueRows();
      _requests = await _repository.getRequests();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
