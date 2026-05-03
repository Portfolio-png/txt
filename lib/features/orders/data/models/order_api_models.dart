import '../../domain/order_entry.dart';
import '../../domain/order_history.dart';
import '../../domain/order_inputs.dart';
import '../../domain/po_document.dart';

OrderStatus _statusFromJson(String value) {
  return orderStatusFromName(value);
}

class OrderDto {
  const OrderDto({
    required this.id,
    required this.orderNo,
    required this.clientId,
    required this.clientName,
    required this.poNumber,
    required this.clientCode,
    required this.itemId,
    required this.itemName,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    required this.quantity,
    required this.status,
    required this.createdAt,
    required this.startDate,
    required this.endDate,
  });

  final int id;
  final String orderNo;
  final int clientId;
  final String clientName;
  final String poNumber;
  final String clientCode;
  final int itemId;
  final String itemName;
  final int variationLeafNodeId;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final int quantity;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    return OrderDto(
      id: json['id'] as int? ?? 0,
      orderNo: json['orderNo'] as String? ?? '',
      clientId: json['clientId'] as int? ?? 0,
      clientName: json['clientName'] as String? ?? '',
      poNumber: json['poNumber'] as String? ?? '',
      clientCode: json['clientCode'] as String? ?? '',
      itemId: json['itemId'] as int? ?? 0,
      itemName: json['itemName'] as String? ?? '',
      variationLeafNodeId: json['variationLeafNodeId'] as int? ?? 0,
      variationPathLabel: json['variationPathLabel'] as String? ?? '',
      variationPathNodeIds:
          (json['variationPathNodeIds'] as List<dynamic>? ?? const [])
              .map((entry) => entry as int)
              .toList(growable: false),
      quantity: json['quantity'] as int? ?? 0,
      status: _statusFromJson(json['status'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
    );
  }

  OrderEntry toDomain() {
    return OrderEntry(
      id: id,
      orderNo: orderNo,
      clientId: clientId,
      clientName: clientName,
      poNumber: poNumber,
      clientCode: clientCode,
      itemId: itemId,
      itemName: itemName,
      variationLeafNodeId: variationLeafNodeId,
      variationPathLabel: variationPathLabel,
      variationPathNodeIds: variationPathNodeIds,
      quantity: quantity,
      status: status,
      createdAt: createdAt,
      startDate: startDate,
      endDate: endDate,
    );
  }
}

class OrderResponse {
  const OrderResponse({required this.success, this.order, this.error});

  final bool success;
  final OrderDto? order;
  final String? error;

  factory OrderResponse.fromJson(Map<String, dynamic> json) {
    return OrderResponse(
      success: json['success'] as bool? ?? false,
      order: json['order'] == null
          ? null
          : OrderDto.fromJson(json['order'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class OrdersListResponse {
  const OrdersListResponse({required this.success, required this.orders});

  final bool success;
  final List<OrderDto> orders;

  factory OrdersListResponse.fromJson(Map<String, dynamic> json) {
    return OrdersListResponse(
      success: json['success'] as bool? ?? false,
      orders: (json['orders'] as List<dynamic>? ?? const [])
          .map((item) => OrderDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class CreateOrderRequest {
  const CreateOrderRequest({
    required this.orderNo,
    required this.clientId,
    required this.clientName,
    required this.poNumber,
    required this.clientCode,
    required this.itemId,
    required this.itemName,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    required this.quantity,
    required this.status,
    this.startDate,
    this.endDate,
    this.poDocumentIds = const <int>[],
  });

  final String orderNo;
  final int clientId;
  final String clientName;
  final String poNumber;
  final String clientCode;
  final int itemId;
  final String itemName;
  final int variationLeafNodeId;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final int quantity;
  final OrderStatus status;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<int> poDocumentIds;

  factory CreateOrderRequest.fromInput(CreateOrderInput input) {
    return CreateOrderRequest(
      orderNo: input.orderNo,
      clientId: input.clientId,
      clientName: input.clientName,
      poNumber: input.poNumber,
      clientCode: input.clientCode,
      itemId: input.itemId,
      itemName: input.itemName,
      variationLeafNodeId: input.variationLeafNodeId,
      variationPathLabel: input.variationPathLabel,
      variationPathNodeIds: input.variationPathNodeIds,
      quantity: input.quantity,
      status: input.status,
      startDate: input.startDate,
      endDate: input.endDate,
      poDocumentIds: input.poDocumentIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderNo': orderNo,
      'clientId': clientId,
      'clientName': clientName,
      'poNumber': poNumber,
      'clientCode': clientCode,
      'itemId': itemId,
      'itemName': itemName,
      'variationLeafNodeId': variationLeafNodeId,
      'variationPathLabel': variationPathLabel,
      'variationPathNodeIds': variationPathNodeIds,
      'quantity': quantity,
      'status': status.name,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'poDocumentIds': poDocumentIds,
    };
  }
}

class PoDocumentDto {
  const PoDocumentDto({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.objectKey,
    required this.status,
    this.createdAt,
    this.uploadedAt,
    this.linkedAt,
  });

  final int id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String objectKey;
  final String status;
  final DateTime? createdAt;
  final DateTime? uploadedAt;
  final DateTime? linkedAt;

  factory PoDocumentDto.fromJson(Map<String, dynamic> json) {
    return PoDocumentDto(
      id: json['id'] as int? ?? 0,
      fileName: json['fileName'] as String? ?? '',
      contentType: json['contentType'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      status: json['status'] as String? ?? 'uploaded',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      uploadedAt: DateTime.tryParse(json['uploadedAt'] as String? ?? ''),
      linkedAt: DateTime.tryParse(json['linkedAt'] as String? ?? ''),
    );
  }

  PoDocumentEntry toDomain() {
    return PoDocumentEntry(
      id: id,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
      sha256: sha256,
      objectKey: objectKey,
      status: status,
      createdAt: createdAt,
      uploadedAt: uploadedAt,
      linkedAt: linkedAt,
    );
  }
}

class PoUploadIntentResponse {
  const PoUploadIntentResponse({
    required this.success,
    this.intent,
    this.error,
  });

  final bool success;
  final PoUploadIntent? intent;
  final String? error;

  factory PoUploadIntentResponse.fromJson(Map<String, dynamic> json) {
    final intentJson = json['intent'];
    return PoUploadIntentResponse(
      success: json['success'] as bool? ?? false,
      intent: intentJson is Map<String, dynamic>
          ? PoUploadIntentDto.fromJson(intentJson).toDomain()
          : null,
      error: json['error'] as String?,
    );
  }
}

class PoUploadIntentDto {
  const PoUploadIntentDto({
    required this.alreadyUploaded,
    this.document,
    this.upload,
  });

  final bool alreadyUploaded;
  final PoDocumentDto? document;
  final PoUploadTargetDto? upload;

  factory PoUploadIntentDto.fromJson(Map<String, dynamic> json) {
    return PoUploadIntentDto(
      alreadyUploaded: json['alreadyUploaded'] as bool? ?? false,
      document: json['document'] is Map<String, dynamic>
          ? PoDocumentDto.fromJson(json['document'] as Map<String, dynamic>)
          : null,
      upload: json['upload'] is Map<String, dynamic>
          ? PoUploadTargetDto.fromJson(json['upload'] as Map<String, dynamic>)
          : null,
    );
  }

  PoUploadIntent toDomain() {
    return PoUploadIntent(
      alreadyUploaded: alreadyUploaded,
      document: document?.toDomain(),
      upload: upload?.toDomain(),
    );
  }
}

class PoUploadTargetDto {
  const PoUploadTargetDto({
    required this.uploadSessionId,
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
    this.expiresAt,
  });

  final String uploadSessionId;
  final String objectKey;
  final String uploadUrl;
  final Map<String, String> headers;
  final DateTime? expiresAt;

  factory PoUploadTargetDto.fromJson(Map<String, dynamic> json) {
    return PoUploadTargetDto(
      uploadSessionId: json['uploadSessionId'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      uploadUrl: json['uploadUrl'] as String? ?? '',
      headers: (json['headers'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, '$value'),
      ),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }

  PoUploadTarget toDomain() {
    return PoUploadTarget(
      uploadSessionId: uploadSessionId,
      objectKey: objectKey,
      uploadUrl: Uri.parse(uploadUrl),
      headers: headers,
      expiresAt: expiresAt,
    );
  }
}

class PoDocumentResponse {
  const PoDocumentResponse({required this.success, this.document, this.error});

  final bool success;
  final PoDocumentDto? document;
  final String? error;

  factory PoDocumentResponse.fromJson(Map<String, dynamic> json) {
    return PoDocumentResponse(
      success: json['success'] as bool? ?? false,
      document: json['document'] is Map<String, dynamic>
          ? PoDocumentDto.fromJson(json['document'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
    );
  }
}

class PoDocumentsListResponse {
  const PoDocumentsListResponse({
    required this.success,
    required this.documents,
    this.error,
  });

  final bool success;
  final List<PoDocumentDto> documents;
  final String? error;

  factory PoDocumentsListResponse.fromJson(Map<String, dynamic> json) {
    return PoDocumentsListResponse(
      success: json['success'] as bool? ?? false,
      documents: (json['documents'] as List<dynamic>? ?? const [])
          .map((item) => PoDocumentDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}

class PoReadUrlResponse {
  const PoReadUrlResponse({required this.success, this.readUrl, this.error});

  final bool success;
  final Uri? readUrl;
  final String? error;

  factory PoReadUrlResponse.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['readUrl'] as String?;
    return PoReadUrlResponse(
      success: json['success'] as bool? ?? false,
      readUrl: rawUrl == null ? null : Uri.tryParse(rawUrl),
      error: json['error'] as String?,
    );
  }
}

class OrderActivityDto {
  const OrderActivityDto({
    required this.id,
    required this.orderId,
    required this.activityType,
    required this.createdAt,
    this.actorUserId,
    this.actorName,
    this.actorRole,
    this.source,
    this.details,
  });

  final int id;
  final int orderId;
  final String activityType;
  final int? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String? source;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  factory OrderActivityDto.fromJson(Map<String, dynamic> json) {
    return OrderActivityDto(
      id: json['id'] as int? ?? 0,
      orderId: json['orderId'] as int? ?? 0,
      activityType: json['activityType'] as String? ?? '',
      actorUserId: json['actorUserId'] as int?,
      actorName: json['actorName'] as String?,
      actorRole: json['actorRole'] as String?,
      source: json['source'] as String?,
      details: json['details'] is Map<String, dynamic>
          ? json['details'] as Map<String, dynamic>
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  OrderActivityEntry toDomain() {
    return OrderActivityEntry(
      id: id,
      orderId: orderId,
      activityType: activityType,
      actorUserId: actorUserId,
      actorName: actorName,
      actorRole: actorRole,
      source: source,
      details: details,
      createdAt: createdAt,
    );
  }
}

class OrderActivitiesResponse {
  const OrderActivitiesResponse({
    required this.success,
    required this.activities,
    this.error,
  });

  final bool success;
  final List<OrderActivityDto> activities;
  final String? error;

  factory OrderActivitiesResponse.fromJson(Map<String, dynamic> json) {
    return OrderActivitiesResponse(
      success: json['success'] as bool? ?? false,
      activities: (json['activities'] as List<dynamic>? ?? const [])
          .map(
            (item) => OrderActivityDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}

class OrderStatusHistoryDto {
  const OrderStatusHistoryDto({
    required this.id,
    required this.orderId,
    required this.newStatus,
    required this.changedAt,
    this.previousStatus,
    this.changedByUserId,
  });

  final int id;
  final int orderId;
  final String? previousStatus;
  final String newStatus;
  final int? changedByUserId;
  final DateTime changedAt;

  factory OrderStatusHistoryDto.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryDto(
      id: json['id'] as int? ?? 0,
      orderId: json['orderId'] as int? ?? 0,
      previousStatus: json['previousStatus'] as String?,
      newStatus: json['newStatus'] as String? ?? '',
      changedByUserId: json['changedByUserId'] as int?,
      changedAt:
          DateTime.tryParse(json['changedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  OrderStatusHistoryEntry toDomain() {
    return OrderStatusHistoryEntry(
      id: id,
      orderId: orderId,
      previousStatus: previousStatus,
      newStatus: newStatus,
      changedByUserId: changedByUserId,
      changedAt: changedAt,
    );
  }
}

class OrderStatusHistoryResponse {
  const OrderStatusHistoryResponse({
    required this.success,
    required this.history,
    this.error,
  });

  final bool success;
  final List<OrderStatusHistoryDto> history;
  final String? error;

  factory OrderStatusHistoryResponse.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryResponse(
      success: json['success'] as bool? ?? false,
      history: (json['history'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                OrderStatusHistoryDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}

class UpdateOrderLifecycleRequest {
  const UpdateOrderLifecycleRequest({
    required this.status,
    this.startDate,
    this.endDate,
  });

  final OrderStatus status;
  final DateTime? startDate;
  final DateTime? endDate;

  factory UpdateOrderLifecycleRequest.fromInput(
    UpdateOrderLifecycleInput input,
  ) {
    return UpdateOrderLifecycleRequest(
      status: input.status,
      startDate: input.startDate,
      endDate: input.endDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }
}
