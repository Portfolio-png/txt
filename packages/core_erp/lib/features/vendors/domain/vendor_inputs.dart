class CreateVendorInput {
  const CreateVendorInput({
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
    this.contactName = '',
    this.phone = '',
    this.email = '',
    this.logoUrl = '',
    this.photoUrl = '',
    this.suppliesRawMaterial = false,
    this.doesOutsourcing = false,
  });

  final bool suppliesRawMaterial;
  final bool doesOutsourcing;
  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final String contactName;
  final String phone;
  final String email;
  final String logoUrl;
  final String photoUrl;
}

class UpdateVendorInput {
  const UpdateVendorInput({
    required this.id,
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
    this.contactName = '',
    this.phone = '',
    this.email = '',
    this.logoUrl = '',
    this.photoUrl = '',
    this.suppliesRawMaterial,
    this.doesOutsourcing,
  });

  /// Null says nothing: the server keeps what it has.
  final bool? suppliesRawMaterial;
  final bool? doesOutsourcing;
  final int id;
  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final String contactName;
  final String phone;
  final String email;
  final String logoUrl;
  final String photoUrl;
}
