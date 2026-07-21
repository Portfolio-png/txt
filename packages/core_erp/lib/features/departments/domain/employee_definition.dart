/// The login/profile account connected to an in-house employee (unified People).
class EmployeeLogin {
  final int userId;
  final String email;
  final String role;
  final bool isActive;

  /// The staff member's simple 4-digit login code (derived from DOB).
  final String loginCode;

  const EmployeeLogin({
    required this.userId,
    this.email = '',
    this.role = '',
    this.isActive = true,
    this.loginCode = '',
  });

  factory EmployeeLogin.fromJson(Map<String, dynamic> json) {
    return EmployeeLogin(
      userId: json['userId'] as int,
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      loginCode: json['loginCode'] as String? ?? '',
    );
  }
}

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
  final String email;
  final String dateOfBirth;
  final int? userId;
  final EmployeeLogin? login;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  bool get isInHouse => employmentType == 'in-house';
  bool get hasLogin => login != null;

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
    this.email = '',
    this.dateOfBirth = '',
    this.userId,
    this.login,
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
      email: json['email'] as String? ?? '',
      dateOfBirth: json['dateOfBirth'] as String? ?? '',
      userId: json['userId'] as int?,
      login: json['login'] is Map<String, dynamic>
          ? EmployeeLogin.fromJson(json['login'] as Map<String, dynamic>)
          : null,
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
      'email': email,
      'dateOfBirth': dateOfBirth,
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
    String? email,
    String? dateOfBirth,
    int? userId,
    EmployeeLogin? login,
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
      email: email ?? this.email,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      userId: userId ?? this.userId,
      login: login ?? this.login,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
