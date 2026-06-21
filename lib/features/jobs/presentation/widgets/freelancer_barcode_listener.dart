import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FreelancerBarcodeListener extends StatefulWidget {
  const FreelancerBarcodeListener({super.key, required this.child});
  final Widget child;

  @override
  State<FreelancerBarcodeListener> createState() => _FreelancerBarcodeListenerState();
}

class _FreelancerBarcodeListenerState extends State<FreelancerBarcodeListener> {
  String _barcodeBuffer = '';
  DateTime? _lastKeystrokeTime;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastKeystrokeTime != null && now.difference(_lastKeystrokeTime!).inMilliseconds > 50) {
      _barcodeBuffer = '';
    }
    _lastKeystrokeTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_barcodeBuffer.startsWith('FR-')) {
        _processBarcode(_barcodeBuffer);
        _barcodeBuffer = '';
        return true;
      }
      _barcodeBuffer = '';
      return false;
    }

    if (event.character != null) {
      _barcodeBuffer += event.character!;
    }
    return false;
  }

  void _processBarcode(String barcode) {
    // Show a modal with freelancer details.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Freelancer Scanned'),
        content: Text('Barcode: $barcode'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
