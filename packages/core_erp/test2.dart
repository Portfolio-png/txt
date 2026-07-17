class V {
  final String name;
  V(this.name);
}
void main() {
  var items = [V('B'), V('A')];
  var list = items.map((x) => x).toList(growable: false);
  try {
    list.sort((a, b) => a.name.compareTo(b.name));
    print("Success: ${list.map((x) => x.name)}");
  } catch (e) {
    print("Failed: $e");
  }
}
