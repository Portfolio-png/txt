class EmployeeDefinition {
  final int id;
  final int departmentId;
  final String name;
  final String role;
  final String phone;
  final String aadharNumber;
  final String aadharPhotoUrl;
  final String panNumber;
  final String panPhotoUrl;
  final String address;
  final String employeePhotoUrl;
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
    this.aadharNumber = '',
    this.aadharPhotoUrl = '',
    this.panNumber = '',
    this.panPhotoUrl = '',
    this.address = '',
    this.employeePhotoUrl = '',
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
      aadharNumber: json['aadharNumber'] as String? ?? '',
      aadharPhotoUrl: json['aadharPhotoUrl'] as String? ?? '',
      panNumber: json['panNumber'] as String? ?? '',
      panPhotoUrl: json['panPhotoUrl'] as String? ?? '',
      address: json['address'] as String? ?? '',
      employeePhotoUrl: json['employeePhotoUrl'] as String? ?? '',
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
      'aadharNumber': aadharNumber,
      'aadharPhotoUrl': aadharPhotoUrl,
      'panNumber': panNumber,
      'panPhotoUrl': panPhotoUrl,
      'address': address,
      'employeePhotoUrl': employeePhotoUrl,
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
    String? aadharNumber,
    String? aadharPhotoUrl,
    String? panNumber,
    String? panPhotoUrl,
    String? address,
    String? employeePhotoUrl,
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
      aadharNumber: aadharNumber ?? this.aadharNumber,
      aadharPhotoUrl: aadharPhotoUrl ?? this.aadharPhotoUrl,
      panNumber: panNumber ?? this.panNumber,
      panPhotoUrl: panPhotoUrl ?? this.panPhotoUrl,
      address: address ?? this.address,
      employeePhotoUrl: employeePhotoUrl ?? this.employeePhotoUrl,
      employmentType: employmentType ?? this.employmentType,
      status: status ?? this.status,
      barcodeId: barcodeId ?? this.barcodeId,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
