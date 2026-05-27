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

  String get displayLabel {
    if (alias.trim().isEmpty) {
      return name;
    }
    return '$name / $alias';
  }
}
