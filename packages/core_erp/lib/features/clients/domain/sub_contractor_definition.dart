class SubContractorDefinition {
  final int id;
  final int clientId;
  final String name;
  final String phone;
  final String email;
  final String notes;
  final String gstNumber;
  final String address;
  final String photoUrl;
  final String? clientName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SubContractorDefinition({
    required this.id,
    required this.clientId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.gstNumber = '',
    this.address = '',
    this.photoUrl = '',
    this.clientName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SubContractorDefinition.fromJson(Map<String, dynamic> json) {
    return SubContractorDefinition(
      id: json['id'] as int? ?? 0,
      clientId: json['clientId'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      gstNumber: json['gstNumber'] as String? ?? '',
      address: json['address'] as String? ?? '',
      photoUrl: json['photoUrl'] as String? ?? '',
      clientName: json['clientName'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      'name': name,
      'phone': phone,
      'email': email,
      'notes': notes,
      'gstNumber': gstNumber,
      'address': address,
      'photoUrl': photoUrl,
      'clientName': clientName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  SubContractorDefinition copyWith({
    int? id,
    int? clientId,
    String? name,
    String? phone,
    String? email,
    String? notes,
    String? gstNumber,
    String? address,
    String? photoUrl,
    String? clientName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SubContractorDefinition(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      gstNumber: gstNumber ?? this.gstNumber,
      address: address ?? this.address,
      photoUrl: photoUrl ?? this.photoUrl,
      clientName: clientName ?? this.clientName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
