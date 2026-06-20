class EmployeeDefinition {
  final int id;
  final int departmentId;
  final String name;
  final String role;
  final String phone;
  final String email;
  final String employmentType;
  final String status;
  final String barcodeId;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  const EmployeeDefinition({
    required this.id,
    required this.departmentId,
    required this.name,
    this.role = '',
    this.phone = '',
    this.email = '',
    this.employmentType = 'in-house',
    this.status = 'active',
    this.barcodeId = '',
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmployeeDefinition.fromJson(Map<String, dynamic> json) {
    return EmployeeDefinition(
      id: json['id'] as int,
      departmentId: json['departmentId'] as int,
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      employmentType: json['employmentType'] as String? ?? 'in-house',
      status: json['status'] as String? ?? 'active',
      barcodeId: json['barcodeId'] as String? ?? '',
      isArchived: json['isArchived'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'departmentId': departmentId,
      'name': name,
      'role': role,
      'phone': phone,
      'email': email,
      'employmentType': employmentType,
      'status': status,
      'barcodeId': barcodeId,
      'isArchived': isArchived,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  EmployeeDefinition copyWith({
    int? id,
    int? departmentId,
    String? name,
    String? role,
    String? phone,
    String? email,
    String? employmentType,
    String? status,
    String? barcodeId,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return EmployeeDefinition(
      id: id ?? this.id,
      departmentId: departmentId ?? this.departmentId,
      name: name ?? this.name,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      employmentType: employmentType ?? this.employmentType,
      status: status ?? this.status,
      barcodeId: barcodeId ?? this.barcodeId,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

