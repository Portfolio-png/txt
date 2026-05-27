import 'package:flutter/material.dart';

import '../../data/delivery_challan_repository.dart';
import 'package:paper/app/reports/domain/reconciliation_report.dart';
import '../../domain/challan_template.dart';
import '../../domain/delivery_challan.dart';

class ChallanProvider extends ChangeNotifier {
  ChallanProvider({required ChallanRepository repository})
    : _repository = repository;

  final ChallanRepository _repository;

  List<DeliveryChallan> _challans = const <DeliveryChallan>[];
  CompanyProfile? _companyProfile;
  String _searchQuery = '';
  ChallanType? _typeFilter;
  DeliveryChallanStatus? _statusFilter;
  int? _orderFilterId;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _initialized = false;

  List<DeliveryChallan> get challans =>
      List<DeliveryChallan>.unmodifiable(_challans);
  CompanyProfile? get companyProfile => _companyProfile;
  String get searchQuery => _searchQuery;
  ChallanType? get typeFilter => _typeFilter;
  DeliveryChallanStatus? get statusFilter => _statusFilter;
  int? get orderFilterId => _orderFilterId;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _repository.lastWarningMessage;
  ChallanRepository get repository => _repository;

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
      final results = await Future.wait([
        _repository.getCompanyProfile(),
        _repository.getChallans(
          type: _typeFilter,
          status: _statusFilter,
          search: _searchQuery,
          orderId: _orderFilterId,
        ),
      ]);
      _companyProfile = results[0] as CompanyProfile;
      _challans = results[1] as List<DeliveryChallan>;
    } catch (error) {
      _logError(error);
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DeliveryChallan?> loadChallan(int id) async {
    try {
      return _repository.getChallan(id);
    } catch (error) {
      _logError(error);
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> setSearchQuery(String value) async {
    _searchQuery = value;
    await refresh();
  }

  Future<void> setTypeFilter(ChallanType? value) async {
    _typeFilter = value;
    await refresh();
  }

  Future<void> setStatusFilter(DeliveryChallanStatus? value) async {
    _statusFilter = value;
    await refresh();
  }

  Future<void> setOrderFilter(int? value) async {
    _orderFilterId = value;
    await refresh();
  }

  Future<List<DeliveryChallan>> getOrderChallans(int orderId) {
    return _repository.getOrderChallans(orderId);
  }

  Future<CompanyProfile?> saveCompanyProfile(CompanyProfile profile) async {
    return _save(() async {
      final saved = await _repository.updateCompanyProfile(profile);
      _companyProfile = saved;
      return saved;
    });
  }

  Future<DeliveryChallan?> createChallan(
    DeliveryChallanDraftInput input,
  ) async {
    return _saveChallan(() => _repository.createChallan(input));
  }

  Future<DeliveryChallan?> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  ) async {
    return _saveChallan(() => _repository.updateChallan(id, input));
  }

  Future<DeliveryChallan?> issueChallan(int id) async {
    return _saveChallan(() => _repository.issueChallan(id));
  }

  Future<DeliveryChallan?> cancelChallan(int id) async {
    return _saveChallan(() => _repository.cancelChallan(id));
  }

  Future<void> deleteChallan(int id) async {
    await _save(() async {
      await _repository.deleteChallan(id);
      await refresh();
      return null;
    });
  }

  Future<void> recordPrint(int id) => _repository.recordPrint(id);

  Future<DeliveryChallan?> updateChallanReportGroups(
    int id,
    List<String> reportGroupCodes,
  ) async {
    final saved = await _save(
      () => _repository.updateChallanReportGroups(id, reportGroupCodes),
    );
    if (saved != null) {
      await refresh();
    }
    return saved;
  }

  Future<InvoiceHeader?> updateInvoiceStatus(int id, String status) async {
    return _save(() => _repository.updateInvoiceStatus(id, status));
  }

  Future<List<CompletedProductionRun>> loadCompletedProductionRuns({
    String search = '',
    int limit = 25,
  }) async {
    try {
      return await _repository.getCompletedProductionRuns(
        search: search,
        limit: limit,
      );
    } catch (error) {
      _logError(error);
      _errorMessage = error.toString();
      notifyListeners();
      return const <CompletedProductionRun>[];
    }
  }

  Future<List<ChallanTemplate>> loadTemplates({
    ChallanTemplatePartyType? partyType,
    int? partyId,
    ChallanType? challanType,
    bool activeOnly = false,
  }) async {
    try {
      return await _repository.getTemplates(
        partyType: partyType,
        partyId: partyId,
        challanType: challanType,
        activeOnly: activeOnly,
      );
    } catch (error) {
      _logError(error);
      _errorMessage = error.toString();
      notifyListeners();
      return const <ChallanTemplate>[];
    }
  }

  Future<List<ChallanTemplateScan>> loadTemplateScans({int limit = 24}) async {
    try {
      return await _repository.getTemplateScans(limit: limit);
    } catch (error) {
      _logError(error);
      _errorMessage = error.toString();
      notifyListeners();
      return const <ChallanTemplateScan>[];
    }
  }

  Future<ChallanTemplate?> saveTemplate({
    int? id,
    required ChallanTemplateInput input,
  }) async {
    return _save(() async {
      if (id == null || id <= 0) {
        return _repository.createTemplate(input);
      }
      return _repository.updateTemplate(id, input);
    });
  }

  Future<void> deleteTemplate(int id) async {
    await _save(() async {
      await _repository.deleteTemplate(id);
      return null;
    });
  }

  Future<ChallanTemplateUploadTarget?> createTemplateUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) async {
    return _save(() => _repository.createTemplateUploadIntent(input));
  }

  Future<ChallanTemplateBackground?> completeTemplateUpload({
    required String uploadSessionId,
    required String objectKey,
  }) async {
    return _save(
      () => _repository.completeTemplateUpload(
        uploadSessionId: uploadSessionId,
        objectKey: objectKey,
      ),
    );
  }

  Future<ChallanTemplateUploadTarget?> createTemplateStampUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) async {
    return _save(() => _repository.createTemplateStampUploadIntent(input));
  }

  Future<ChallanTemplateBackground?> completeTemplateStampUpload({
    required String uploadSessionId,
    required String objectKey,
  }) async {
    return _save(
      () => _repository.completeTemplateStampUpload(
        uploadSessionId: uploadSessionId,
        objectKey: objectKey,
      ),
    );
  }

  Future<DeliveryChallan?> _saveChallan(
    Future<DeliveryChallan> Function() action,
  ) async {
    final saved = await _save(action);
    if (saved != null) {
      await refresh();
    }
    return saved;
  }

  Future<T?> _save<T>(Future<T> Function() action) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _logError(error);
      _errorMessage = error.toString();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _logError(Object error) {
    if (error is ChallanApiException &&
        error.debugMessage != null &&
        error.debugMessage!.isNotEmpty) {
      debugPrint(
        '[DeliveryChallan API] ${error.debugMessage}',
        wrapWidth: 2048,
      );
    }
  }
}

typedef DeliveryChallanProvider = ChallanProvider;
