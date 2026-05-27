class CreateClientInput {
  const CreateClientInput({
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
  });

  final String name;
  final String alias;
  final String gstNumber;
  final String address;
}

class UpdateClientInput {
  const UpdateClientInput({
    required this.id,
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
  });

  final int id;
  final String name;
  final String alias;
  final String gstNumber;
  final String address;
}
