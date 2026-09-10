import 'package:flutter/material.dart';
import 'app/shell/prototype_shell.dart';
import 'app/shell/prototype_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PaperPrototypeApp());
}

class PaperPrototypeApp extends StatelessWidget {
  const PaperPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paper MES Pipeline & CAD Simulator',
      debugShowCheckedModeBanner: false,
      theme: PrototypeTheme.lightTheme,
      home: const PrototypeShell(),
    );
  }
}
