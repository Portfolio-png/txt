class CreateSubContractorInput {
  final String name;
  final String phone;
  final String email;
  final String notes;
  final String gstNumber;
  final String address;
  final String photoUrl;

  const CreateSubContractorInput({
    required this.name,
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.gstNumber = '',
    this.address = '',
    this.photoUrl = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'notes': notes,
      'gstNumber': gstNumber,
      'address': address,
      'photoUrl': photoUrl,
    };
  }
}

class UpdateSubContractorInput {
  final String? name;
  final String? phone;
  final String? email;
  final String? notes;
  final String? gstNumber;
  final String? address;
  final String? photoUrl;

  const UpdateSubContractorInput({
    this.name,
    this.phone,
    this.email,
    this.notes,
    this.gstNumber,
    this.address,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (phone != null) map['phone'] = phone;
    if (email != null) map['email'] = email;
    if (notes != null) map['notes'] = notes;
    if (gstNumber != null) map['gstNumber'] = gstNumber;
    if (address != null) map['address'] = address;
    if (photoUrl != null) map['photoUrl'] = photoUrl;
    return map;
  }
}
