class VendorDefinition {
  const VendorDefinition({
    required this.id,
    required this.name,
    required this.alias,
    required this.gstNumber,
    required this.address,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
    this.logoUrl = '',
    this.photoUrl = '',
  });

  final int id;
  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final String contactName;
  final String phone;
  final String email;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String logoUrl;
  final String photoUrl;

  factory VendorDefinition.fromJson(Map<String, dynamic> json) {
    return VendorDefinition(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      gstNumber:
          json['gstNumber'] as String? ?? json['gst_number'] as String? ?? '',
      address: json['address'] as String? ?? '',
      contactName:
          json['contactName'] as String? ??
          json['contact_name'] as String? ??
          '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      logoUrl: json['logoUrl'] as String? ?? json['logo_url'] as String? ?? '',
      photoUrl:
          json['photoUrl'] as String? ?? json['photo_url'] as String? ?? '',
      isArchived: json['isArchived'] as bool? ?? json['is_archived'] == 1,
      usageCount:
          json['usageCount'] as int? ?? json['usage_count'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(
            json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
          ) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(
            json['updatedAt'] as String? ?? json['updated_at'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }

  String get displayLabel {
    if (alias.trim().isEmpty) {
      return name;
    }
    return '$name / $alias';
  }
}
