import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/employee_definition.dart';
import '../providers/departments_provider.dart';

class EmployeeEditorDialog extends StatelessWidget {
  const EmployeeEditorDialog({
    super.key,
    required this.departmentId,
    this.employee,
  });

  final int departmentId;
  final EmployeeDefinition? employee;

  static Future<void> open(
    BuildContext context, {
    required int departmentId,
    EmployeeDefinition? employee,
  }) {
    return showErpFormDialog(
      context,
      maxWidth: 520,
      maxHeight: 720,
      child: EmployeeEditorDialog(
        departmentId: departmentId,
        employee: employee,
      ),
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
        ? await provider.createEmployee(
            widget.departmentId,
            name,
            _roleController.text,
            _phoneController.text,
            _emailController.text,
            _employmentType,
            _barcodeIdController.text,
          )
        : await provider.updateEmployee(
            widget.employee!.id,
            widget.departmentId,
            name,
            _roleController.text,
            _phoneController.text,
            _emailController.text,
            _employmentType,
            _barcodeIdController.text,
          );

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
      subtitle:
          'Capture the person\'s details, role, and how they\'re engaged.',
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
                _Field(
                  controller: _phoneController,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                _Field(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ErpDialogSectionCard(
            title: 'Engagement',
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _employmentType,
                  decoration: _decoration('Employment Type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'in-house',
                      child: Text('In-house'),
                    ),
                    DropdownMenuItem(
                      value: 'freelancer',
                      child: Text('Freelancer'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _employmentType = val;
                      if (val == 'freelancer' &&
                          _barcodeIdController.text.isEmpty) {
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
                      onPressed: () => setState(
                        () => _barcodeIdController.text = _generateBarcode(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Text(
                          'This code identifies the freelancer at job hand-off and internal scan points.',
                          style: TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        label: 'Preview ID card',
                        icon: Icons.badge_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: _barcodeIdController.text.trim().isEmpty
                            ? null
                            : _showIdCard,
                      ),
                    ],
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
    final barcodeId = _barcodeIdController.text.trim();
    if (barcodeId.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Freelancer ID card'),
        content: Container(
          width: 390,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFDFCFF), Color(0xFFF2F0FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: SoftErpTheme.borderStrong),
            borderRadius: BorderRadius.circular(22),
            boxShadow: SoftErpTheme.subtleShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: SoftErpTheme.accentGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.handyman_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PAPER ERP',
                          style: TextStyle(
                            color: SoftErpTheme.accentDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          'Freelancer identification',
                          style: TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SoftStatusPill(
                    label: 'ACTIVE',
                    background: SoftErpTheme.successBg,
                    textColor: SoftErpTheme.successText,
                    borderColor: SoftErpTheme.successBg,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                _nameController.text.trim().isNotEmpty
                    ? _nameController.text.trim()
                    : 'Freelancer name',
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_roleController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _roleController.text.trim(),
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SoftErpTheme.border),
                ),
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: barcodeId,
                  width: double.infinity,
                  height: 76,
                  drawText: true,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Freelancer ID card sent to printer.'),
                ),
              );
            },
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print card'),
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
