import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../domain/employee_definition.dart';
import '../providers/departments_provider.dart';

class EmployeeEditorDialog extends StatelessWidget {
  const EmployeeEditorDialog({super.key, required this.departmentId, this.employee});

  final int departmentId;
  final EmployeeDefinition? employee;

  static Future<void> open(BuildContext context, {required int departmentId, EmployeeDefinition? employee}) {
    return showErpFormDialog(
      context,
      maxWidth: 520,
      maxHeight: 720,
      child: EmployeeEditorDialog(departmentId: departmentId, employee: employee),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _EmployeeEditorSheet(departmentId: departmentId, employee: employee);
  }
}

class _EmployeeEditorSheet extends StatefulWidget {
  const _EmployeeEditorSheet({required this.departmentId, this.employee});

  final int departmentId;
  final EmployeeDefinition? employee;

  @override
  State<_EmployeeEditorSheet> createState() => _EmployeeEditorSheetState();
}

class _EmployeeEditorSheetState extends State<_EmployeeEditorSheet> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _barcodeIdController = TextEditingController();
  String _employmentType = 'in-house';

  @override
  void initState() {
    super.initState();
    final emp = widget.employee;
    if (emp != null) {
      _nameController.text = emp.name;
      _roleController.text = emp.role;
      _phoneController.text = emp.phone;
      _emailController.text = emp.email;
      _barcodeIdController.text = emp.barcodeId;
      _employmentType = emp.employmentType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _barcodeIdController.dispose();
    super.dispose();
  }

  String _generateBarcode() =>
      'FR-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final provider = context.read<DepartmentsProvider>();
    final success = widget.employee == null
        ? await provider.createEmployee(widget.departmentId, name, _roleController.text, _phoneController.text, _emailController.text, _employmentType, _barcodeIdController.text)
        : await provider.updateEmployee(widget.employee!.id, widget.departmentId, name, _roleController.text, _phoneController.text, _emailController.text, _employmentType, _barcodeIdController.text);

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final isFreelancer = _employmentType == 'freelancer';
    return ErpFormScaffold(
      title: widget.employee == null ? 'New Employee' : 'Edit Employee',
      subtitle: 'Capture the person\'s details, role, and how they\'re engaged.',
      errorBanner: provider.errorMessage == null
          ? null
          : ErpFormMessageBanner(message: provider.errorMessage!),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErpDialogSectionCard(
            title: 'Details',
            child: Column(
              children: [
                _Field(controller: _nameController, label: 'Employee Name'),
                const SizedBox(height: 14),
                _Field(controller: _roleController, label: 'Role / Position'),
                const SizedBox(height: 14),
                _Field(controller: _phoneController, label: 'Phone', keyboardType: TextInputType.phone),
                const SizedBox(height: 14),
                _Field(controller: _emailController, label: 'Email', keyboardType: TextInputType.emailAddress),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ErpDialogSectionCard(
            title: 'Engagement',
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _employmentType,
                  decoration: _decoration('Employment Type'),
                  items: const [
                    DropdownMenuItem(value: 'in-house', child: Text('In-house')),
                    DropdownMenuItem(value: 'freelancer', child: Text('Freelancer')),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _employmentType = val;
                      if (val == 'freelancer' && _barcodeIdController.text.isEmpty) {
                        _barcodeIdController.text = _generateBarcode();
                      }
                    });
                  },
                ),
                if (isFreelancer) ...[
                  const SizedBox(height: 14),
                  _Field(
                    controller: _barcodeIdController,
                    label: 'Freelancer Barcode ID',
                    suffix: IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Regenerate',
                      onPressed: () => setState(() => _barcodeIdController.text = _generateBarcode()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      label: 'Print ID Card',
                      icon: Icons.print,
                      variant: AppButtonVariant.secondary,
                      onPressed: _showIdCard,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Save',
            isLoading: provider.isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  void _showIdCard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Freelancer ID Card'),
        content: Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: SoftErpTheme.textPrimary, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _nameController.text.isNotEmpty ? _nameController.text : 'Freelancer Name',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Icon(Icons.qr_code_2, size: 64),
              const SizedBox(height: 8),
              Text(
                _barcodeIdController.text,
                style: const TextStyle(fontSize: 16, letterSpacing: 2),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sent to printer...')),
              );
            },
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
        ],
      ),
    );
  }
}

InputDecoration _decoration(String label, {Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _decoration(label, suffix: suffix),
    );
  }
}
