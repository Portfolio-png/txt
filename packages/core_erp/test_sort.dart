void main() {
  var list = [1, 2, 3].map((x) => x).toList(growable: false);
  try {
    list.sort();
    print("Success");
  } catch (e) {
    print("Failed: $e");
  }
}
