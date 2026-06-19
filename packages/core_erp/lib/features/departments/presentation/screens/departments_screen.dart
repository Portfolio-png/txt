import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/department_definition.dart';
import '../../domain/employee_definition.dart';
import '../providers/departments_provider.dart';
import 'department_editor_dialog.dart';
import 'employee_editor_dialog.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DepartmentsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DepartmentsProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.departments.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final selectedDept = provider.selectedDepartment;

        return SoftMasterDataPage(
          title: 'Employees Master',
          subtitle: 'Manage departments and their employees.',
          action: AppButton(
            label: selectedDept == null ? 'Add Department' : 'Add Employee',
            icon: Icons.add,
            onPressed: () {
              if (selectedDept == null) {
                DepartmentEditorDialog.open(context);
              } else {
                EmployeeEditorDialog.open(context, departmentId: selectedDept.id);
              }
            },
          ),
          toolbar: _Toolbar(),
          messages: [
            if (provider.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: _DepartmentList(),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _EmployeeList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    return SoftMasterToolbar(
      children: [
        SoftMasterSearchField(
          width: 300,
          hintText: 'Search departments or employees',
          onChanged: provider.setSearchQuery,
        ),
      ],
    );
  }
}

class _DepartmentList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final depts = provider.filteredDepartments;

    if (depts.isEmpty) {
      return const AppEmptyState(
        title: 'No departments',
        message: 'Create a department to get started.',
        icon: Icons.business,
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: SoftErpTheme.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: depts.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: SoftErpTheme.border),
        itemBuilder: (context, index) {
          final dept = depts[index];
          final isSelected = provider.selectedDepartment?.id == dept.id;
          return ListTile(
            selected: isSelected,
            selectedTileColor: SoftErpTheme.accent.withOpacity(0.1),
            title: Text(dept.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(dept.description, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => provider.selectDepartment(isSelected ? null : dept),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => DepartmentEditorDialog.open(context, department: dept),
            ),
          );
        },
      ),
    );
  }
}

class _EmployeeList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final selectedDept = provider.selectedDepartment;

    if (selectedDept == null) {
      return const AppEmptyState(
        title: 'Select a department',
        message: 'Select a department from the left to view employees.',
        icon: Icons.people_outline,
      );
    }

    final emps = provider.employeesForDepartment(selectedDept.id);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                if (selectedDept.photoUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(selectedDept.photoUrl),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.business),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selectedDept.name, style: Theme.of(context).textTheme.titleMedium),
                      Text(selectedDept.description, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: SoftErpTheme.border),
          if (emps.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: Text('No employees found in this department.')),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: emps.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: SoftErpTheme.border),
                itemBuilder: (context, index) {
                  final emp = emps[index];
                  return ListTile(
                    title: Text(emp.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${emp.role} • ${emp.phone} • ${emp.email}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => EmployeeEditorDialog.open(context, departmentId: selectedDept.id, employee: emp),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () => provider.deleteEmployee(emp.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
