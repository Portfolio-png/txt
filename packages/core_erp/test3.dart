class VendorDefinition {
  final int id;
  final String name;
  final String alias;
  final bool isArchived;
  const VendorDefinition({required this.id, required this.name, required this.alias, required this.isArchived});
}
void main() {
  var list = [
    VendorDefinition(id: 1, name: 'B', alias: 'B', isArchived: false),
    VendorDefinition(id: 2, name: 'A', alias: 'A', isArchived: false)
  ].map((x) => x).toList(growable: false);
  
  try {
    list.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final nameCompare = a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        );
        if (nameCompare != 0) {
          return nameCompare;
        }
        return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
      });
    print("Success: ${list.map((x) => x.name)}");
  } catch (e) {
    print("Failed: $e");
  }
}
