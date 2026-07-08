import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';

class DemoPasscodeScreen extends StatefulWidget {
  final String expectedPasscode;

  const DemoPasscodeScreen({
    super.key,
    this.expectedPasscode = '0000',
  });

  @override
  State<DemoPasscodeScreen> createState() => _DemoPasscodeScreenState();
}

class _DemoPasscodeScreenState extends State<DemoPasscodeScreen> {
  String _enteredDigits = '';

  int get _passcodeLength => widget.expectedPasscode.length;

  void _onDigitPressed(String digit) {
    setState(() {
      if (_enteredDigits.length < _passcodeLength) {
        _enteredDigits += digit;
      }

      if (_enteredDigits.length == _passcodeLength) {
        if (_enteredDigits == widget.expectedPasscode) {
          // Success! Login
          _performLogin();
        } else {
          // Wrong digits, reset
          _enteredDigits = '';
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incorrect passcode')),
          );
        }
      }
    });
  }

  void _onBackspacePressed() {
    setState(() {
      if (_enteredDigits.isNotEmpty) {
        _enteredDigits = _enteredDigits.substring(0, _enteredDigits.length - 1);
      }
    });
  }

  void _performLogin() {
    final provider = context.read<AuthProvider>();
    // Call login with dummy credentials to authenticate
    provider.login(
      email: 'super@paper.local',
      password: 'Paper@12345',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const Text(
              'Enter Passcode',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            _buildPasscodeIndicators(),
            const Spacer(),
            _buildNumberPad(),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildPasscodeIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_passcodeLength, (index) {
        final isFilled = index < _enteredDigits.length;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 40,
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isFilled ? const Color(0xFF6366F1) : Colors.white38,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            isFilled ? '*' : '', // Obfuscate digits
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNumberPad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKey('1', onTap: () => _onDigitPressed('1')),
              _buildKey('2', onTap: () => _onDigitPressed('2')),
              _buildKey('3', onTap: () => _onDigitPressed('3')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKey('4', onTap: () => _onDigitPressed('4')),
              _buildKey('5', onTap: () => _onDigitPressed('5')),
              _buildKey('6', onTap: () => _onDigitPressed('6')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKey('7', onTap: () => _onDigitPressed('7')),
              _buildKey('8', onTap: () => _onDigitPressed('8')),
              _buildKey('9', onTap: () => _onDigitPressed('9')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72, height: 72), // Empty space for alignment
              _buildKey('0', onTap: () => _onDigitPressed('0')),
              _buildKey(
                '⌫',
                onTap: _onBackspacePressed,
                isAction: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label, {required VoidCallback onTap, bool isAction = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(36),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1E293B).withValues(alpha: 0.8),
            border: Border.all(
              color: const Color(0xFF334155).withValues(alpha: 0.5),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isAction ? const Color(0xFF94A3B8) : Colors.white,
              fontSize: isAction ? 24 : 28,
              fontWeight: isAction ? FontWeight.normal : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
