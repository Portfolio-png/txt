import 'package:flutter/material.dart';

class PayrollRunWizard extends StatefulWidget {
  const PayrollRunWizard({super.key});

  @override
  State<PayrollRunWizard> createState() => _PayrollRunWizardState();
}

class _PayrollRunWizardState extends State<PayrollRunWizard> {
  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Run Payroll')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Payroll Generated!')));
            Navigator.of(context).pop();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        steps: const [
          Step(
            title: Text('Select Period'),
            content: TextField(
              decoration: InputDecoration(labelText: 'Month / Year'),
            ),
          ),
          Step(
            title: Text('Review Attendance & Leaves'),
            content: Text(
              'All employee attendance and leaves have been synced.',
            ),
          ),
          Step(
            title: Text('Generate & Finalize'),
            content: Text(
              'This will generate payslips for all eligible employees. Continue?',
            ),
          ),
        ],
      ),
    );
  }
}
