import '../../domain/procurement_models.dart';

abstract class ProcurementRepository {
  Future<void> init();
  Future<List<ProcurementQueueRow>> getQueueRows();
  Future<List<ProcurementQueueRow>> refreshQueueRows();
  Future<List<ProcurementRequestSummary>> getRequests();
  Future<List<ProcurementRequestSummary>> createDraftRequests({
    required List<ProcurementQueueRow> rows,
  });
  Future<ProcurementRequestDetail> getRequestDetail(int requestId);
  Future<ProcurementRequestSummary> updateRequest({
    required int requestId,
    String? expectedDate,
    String? notes,
  });
  Future<ProcurementRequestSummary> raiseRequest(int requestId);
  Future<ProcurementRequestSummary> cancelRequest({
    required int requestId,
    required String reason,
  });
  Future<ProcurementRequestSummary> closeRequest(int requestId);
  Future<ProcurementRequestDetail> receiveRequestLines({
    required int requestId,
    required List<ProcurementReceiveLineInput> lines,
  });
}
