class ClientDefinition {
  const ClientDefinition({
    required this.id,
    required this.name,
    required this.alias,
    required this.gstNumber,
    required this.address,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
    this.logoUrl = '',
    this.photoUrl = '',
    this.contactName = '',
    this.designation = '',
    this.phone = '',
    this.email = '',
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
  final String logoUrl;
  final String photoUrl;

  /// The company's primary contact — one person, answered here and shown on
  /// every part developed for this client. Distinct from this client's
  /// sub-contractors, who are parties you give work TO; the same human may
  /// legitimately appear in both.
  final String contactName;
  final String designation;
  final String phone;
  final String email;

  /// Whether there is a person to show at all.
  bool get hasContact =>
      contactName.isNotEmpty ||
      designation.isNotEmpty ||
      phone.isNotEmpty ||
      email.isNotEmpty;

  /// The copyWith this class has done without, which is why five hand-built
  /// construction sites in the mock repository keep having to grow a field at
  /// a time.
  ClientDefinition copyWith({
    int? id,
    String? name,
    String? alias,
    String? gstNumber,
    String? address,
    bool? isArchived,
    int? usageCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? logoUrl,
    String? photoUrl,
    String? contactName,
    String? designation,
    String? phone,
    String? email,
  }) {
    return ClientDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      alias: alias ?? this.alias,
      gstNumber: gstNumber ?? this.gstNumber,
      address: address ?? this.address,
      isArchived: isArchived ?? this.isArchived,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      logoUrl: logoUrl ?? this.logoUrl,
      photoUrl: photoUrl ?? this.photoUrl,
      contactName: contactName ?? this.contactName,
      designation: designation ?? this.designation,
      phone: phone ?? this.phone,
      email: email ?? this.email,
    );
  }

  String get displayLabel {
    if (alias.trim().isEmpty) {
      return name;
    }
    return '$name / $alias';
  }
}
