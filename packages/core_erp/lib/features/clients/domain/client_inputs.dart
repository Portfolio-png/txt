class CreateClientInput {
  const CreateClientInput({
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
    this.logoUrl = '',
    this.photoUrl = '',
    this.contactName = '',
    this.designation = '',
    this.phone = '',
    this.email = '',
  });

  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final String logoUrl;
  final String photoUrl;

  /// The company's primary contact.
  final String contactName;
  final String designation;
  final String phone;
  final String email;
}

class UpdateClientInput {
  const UpdateClientInput({
    required this.id,
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
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
  final String logoUrl;
  final String photoUrl;

  /// The company's primary contact.
  final String contactName;
  final String designation;
  final String phone;
  final String email;
}
