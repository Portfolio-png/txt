import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
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
          subtitle: 'Manage departments and the people who work in them.',
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
          toolbar: const _Toolbar(),
          messages: [
            if (provider.errorMessage != null)
              SoftSurface(
                color: const Color(0xFFFEF2F2),
                radius: 12,
                elevated: false,
                showBorder: true,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Expanded(flex: 2, child: _DepartmentList()),
              SizedBox(width: 16),
              Expanded(flex: 3, child: _EmployeePanel()),
            ],
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    return SoftMasterToolbar(
      children: [
        SoftMasterSearchField(
          width: 320,
          hintText: 'Search departments or employees',
          onChanged: provider.setSearchQuery,
        ),
      ],
    );
  }
}

class _DepartmentList extends StatelessWidget {
  const _DepartmentList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final depts = provider.filteredDepartments;

    if (depts.isEmpty) {
      return const AppEmptyState(
        title: 'No departments',
        message: 'Create a department to get started.',
        icon: Icons.business_outlined,
      );
    }

    return ListView.separated(
      itemCount: depts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final dept = depts[index];
        final isSelected = provider.selectedDepartment?.id == dept.id;
        final count = provider.employeesForDepartment(dept.id).length;
        return SoftRowCard(
          isSelected: isSelected,
          onTap: () => provider.selectDepartment(isSelected ? null : dept),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _DeptAvatar(url: dept.photoUrl, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SoftInlineText(dept.name, weight: FontWeight.w700),
                      if (dept.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        SoftInlineText(
                          dept.description,
                          color: SoftErpTheme.textSecondary,
                          weight: FontWeight.w500,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SoftStatusPill(
                  label: '$count',
                  background: SoftErpTheme.accentSoft,
                  textColor: SoftErpTheme.accentDark,
                  borderColor: SoftErpTheme.accentSoft,
                ),
                const SizedBox(width: 6),
                SoftIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit department',
                  onTap: () => DepartmentEditorDialog.open(context, department: dept),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmployeePanel extends StatelessWidget {
  const _EmployeePanel();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final selectedDept = provider.selectedDepartment;

    if (selectedDept == null) {
      return const AppEmptyState(
        title: 'Select a department',
        message: 'Pick a department on the left to view its employees.',
        icon: Icons.people_outline,
      );
    }

    final emps = provider.employeesForDepartment(selectedDept.id);

    return SoftSurface(
      padding: const EdgeInsets.all(18),
      radius: SoftErpTheme.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DeptAvatar(url: selectedDept.photoUrl, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedDept.name,
                      style: const TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (selectedDept.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        selectedDept.description,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AppButton(
                label: 'Add Employee',
                icon: Icons.add,
                variant: AppButtonVariant.secondary,
                onPressed: () => EmployeeEditorDialog.open(context, departmentId: selectedDept.id),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (emps.isEmpty)
            const Expanded(
              child: AppEmptyState(
                title: 'No employees yet',
                message: 'Add the first employee to this department.',
                icon: Icons.person_add_alt,
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: emps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _EmployeeRow(
                  emp: emps[index],
                  departmentId: selectedDept.id,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.emp, required this.departmentId});

  final EmployeeDefinition emp;
  final int departmentId;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DepartmentsProvider>();
    final isFreelancer = emp.employmentType == 'freelancer';
    final contact = [emp.phone, emp.email].where((s) => s.isNotEmpty).join(' • ');
    return SoftRowCard(
      onTap: () => EmployeeEditorDialog.open(context, departmentId: departmentId, employee: emp),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: SoftErpTheme.accentSoft,
              child: Text(
                emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: SoftErpTheme.accentDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SoftInlineText(emp.name, weight: FontWeight.w700),
                  const SizedBox(height: 3),
                  SoftInlineText(
                    [emp.role, contact].where((s) => s.isNotEmpty).join(' • '),
                    color: SoftErpTheme.textSecondary,
                    weight: FontWeight.w500,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SoftStatusPill(
              label: isFreelancer ? 'Freelancer' : 'In-house',
              background: isFreelancer ? SoftErpTheme.infoBg : SoftErpTheme.successBg,
              textColor: isFreelancer ? SoftErpTheme.infoText : SoftErpTheme.successText,
              borderColor: isFreelancer ? SoftErpTheme.infoBg : SoftErpTheme.successBg,
            ),
            const SizedBox(width: 6),
            SoftIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onTap: () => EmployeeEditorDialog.open(context, departmentId: departmentId, employee: emp),
            ),
            const SizedBox(width: 6),
            SoftIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              iconColor: const Color(0xFFB91C1C),
              onTap: () => provider.deleteEmployee(emp.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeptAvatar extends StatelessWidget {
  const _DeptAvatar({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.business, color: SoftErpTheme.textSecondary),
            )
          : const Icon(Icons.business, color: SoftErpTheme.textSecondary),
    );
  }
}
