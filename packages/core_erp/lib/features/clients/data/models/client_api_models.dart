import '../../domain/client_definition.dart';
import '../../domain/client_inputs.dart';

class ClientDto {
  const ClientDto({
    required this.id,
    required this.name,
    required this.alias,
    required this.gstNumber,
    required this.address,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ClientDto.fromJson(Map<String, dynamic> json) {
    return ClientDto(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      gstNumber: json['gstNumber'] as String? ?? '',
      address: json['address'] as String? ?? '',
      isArchived: json['isArchived'] as bool? ?? false,
      usageCount: json['usageCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ClientDefinition toDomain() {
    return ClientDefinition(
      id: id,
      name: name,
      alias: alias,
      gstNumber: gstNumber,
      address: address,
      isArchived: isArchived,
      usageCount: usageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class ClientResponse {
  const ClientResponse({required this.success, this.client, this.error});

  final bool success;
  final ClientDto? client;
  final String? error;

  factory ClientResponse.fromJson(Map<String, dynamic> json) {
    return ClientResponse(
      success: json['success'] as bool? ?? false,
      client: json['client'] == null
          ? null
          : ClientDto.fromJson(json['client'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class ClientsListResponse {
  const ClientsListResponse({required this.success, required this.clients});

  final bool success;
  final List<ClientDto> clients;

  factory ClientsListResponse.fromJson(Map<String, dynamic> json) {
    return ClientsListResponse(
      success: json['success'] as bool? ?? false,
      clients: (json['clients'] as List<dynamic>? ?? const [])
          .map((item) => ClientDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class CreateClientRequest {
  const CreateClientRequest({
    required this.name,
    required this.alias,
    required this.gstNumber,
    required this.address,
  });

  final String name;
  final String alias;
  final String gstNumber;
  final String address;

  factory CreateClientRequest.fromInput(CreateClientInput input) {
    return CreateClientRequest(
      name: input.name,
      alias: input.alias,
      gstNumber: input.gstNumber,
      address: input.address,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'alias': alias,
      'gstNumber': gstNumber,
      'address': address,
    };
  }
}

class UpdateClientRequest {
  const UpdateClientRequest({
    required this.name,
    required this.alias,
    required this.gstNumber,
    required this.address,
  });

  final String name;
  final String alias;
  final String gstNumber;
  final String address;

  factory UpdateClientRequest.fromInput(UpdateClientInput input) {
    return UpdateClientRequest(
      name: input.name,
      alias: input.alias,
      gstNumber: input.gstNumber,
      address: input.address,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'alias': alias,
      'gstNumber': gstNumber,
      'address': address,
    };
  }
}
