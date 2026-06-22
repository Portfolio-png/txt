import 'package:flutter/material.dart';
import '../../../core/services/activation_service.dart';
import '../../../../main.dart'; // Or wherever routing logic exists. Wait, I should just use Navigator for now.

class ActivationScreen extends StatefulWidget {
  final VoidCallback onActivated;
  
  const ActivationScreen({super.key, required this.onActivated});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _clientIdController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMsg;

  Future<void> _activate() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final clientId = _clientIdController.text.trim();
    final pin = _pinController.text.trim();

    if (clientId.isEmpty || pin.isEmpty) {
      setState(() {
        _errorMsg = 'Please enter both Client ID and Activation PIN.';
        _isLoading = false;
      });
      return;
    }

    // Assuming PAPER_API_BASE_URL is set via --dart-define
    const baseUrl = String.fromEnvironment('PAPER_API_BASE_URL', defaultValue: 'http://localhost:18080');

    final result = await ActivationService.activate(baseUrl, clientId, pin);

    if (result['success'] == true) {
      widget.onActivated();
    } else {
      setState(() {
        _errorMsg = result['error'];
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, size: 64, color: Color(0xFF8B5CF6)),
              const SizedBox(height: 16),
              const Text(
                'Machine Activation',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This device must be activated to connect to your workspace.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _clientIdController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Client ID',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.business, color: Colors.white54),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                obscureText: true,
                style: const TextStyle(color: Colors.white, letterSpacing: 4),
                decoration: InputDecoration(
                  labelText: 'Activation PIN',
                  labelStyle: const TextStyle(color: Colors.white54, letterSpacing: 0),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.vpn_key, color: Colors.white54),
                ),
              ),
              const SizedBox(height: 24),
              if (_errorMsg != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.5))
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _activate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Activate Machine', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
