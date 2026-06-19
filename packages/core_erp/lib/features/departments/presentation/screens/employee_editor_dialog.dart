import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/employee_definition.dart';
import '../providers/departments_provider.dart';

class EmployeeEditorDialog extends StatefulWidget {
  const EmployeeEditorDialog({super.key, required this.departmentId, this.employee});

  final int departmentId;
  final EmployeeDefinition? employee;

  static Future<void> open(BuildContext context, {required int departmentId, EmployeeDefinition? employee}) {
    return showDialog(
      context: context,
      builder: (_) => EmployeeEditorDialog(departmentId: departmentId, employee: employee),
    );
  }

  @override
  State<EmployeeEditorDialog> createState() => _EmployeeEditorDialogState();
}

class _EmployeeEditorDialogState extends State<EmployeeEditorDialog> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  String _employmentType = 'in-house';

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      _nameController.text = widget.employee!.name;
      _roleController.text = widget.employee!.role;
      _phoneController.text = widget.employee!.phone;
      _emailController.text = widget.employee!.email;
      _employmentType = widget.employee!.employmentType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final provider = context.read<DepartmentsProvider>();
    final success = widget.employee == null
        ? await provider.createEmployee(widget.departmentId, name, _roleController.text, _phoneController.text, _emailController.text, _employmentType)
        : await provider.updateEmployee(widget.employee!.id, widget.departmentId, name, _roleController.text, _phoneController.text, _emailController.text, _employmentType);

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    return AlertDialog(
      title: Text(widget.employee == null ? 'New Employee' : 'Edit Employee'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Employee Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roleController,
              decoration: const InputDecoration(labelText: 'Role / Position'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppButton(
          label: 'Save',
          isLoading: provider.isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}

