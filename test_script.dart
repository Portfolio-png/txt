import 'dart:convert';
import 'dart:io';

void main() async {
  final dbFile = File('backend/paper.db');
  if (await dbFile.exists()) {
    print('DB exists');
    // Using sqlite3 CLI
    final result = await Process.run('sqlite3', ['backend/paper.db', 'SELECT id, name, variation_tree FROM items WHERE name LIKE "%alloy%";']);
    print(result.stdout);
  }
}
