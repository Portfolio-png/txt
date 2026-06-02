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
  });

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
  });

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
