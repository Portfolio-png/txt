class CreateClientInput {
  const CreateClientInput({
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
    this.logoUrl = '',
    this.photoUrl = '',
  });

  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final String logoUrl;
  final String photoUrl;
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
  });

  final int id;
  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final String logoUrl;
  final String photoUrl;
}
