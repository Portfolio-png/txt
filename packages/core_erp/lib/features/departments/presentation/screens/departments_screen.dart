import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/employee_definition.dart';
import '../providers/departments_provider.dart';
import 'department_editor_dialog.dart';
import 'employee_editor_dialog.dart';
import 'employee_view_dialog.dart';

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
        final selectedDept = provider.selectedDepartment;

        return SoftMasterDataPage(
          title: 'Employees Master',
          subtitle:
              'Manage departments, in-house staff, and freelancer barcode identities for outsourced work.',
          action: AppButton(
            label: selectedDept == null ? 'Add Department' : 'Add Employee',
            icon: Icons.add,
            onPressed: () {
              if (selectedDept == null) {
                DepartmentEditorDialog.open(context);
              } else {
                EmployeeEditorDialog.open(
                  context,
                  departmentId: selectedDept.id,
                );
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
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
          body: provider.isLoading && provider.departments.isEmpty
              ? const _DepartmentsLoadingState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    _RosterOverview(),
                    SizedBox(height: 14),
                    Expanded(child: _PeopleDirectory()),
                  ],
                ),
        );
      },
    );
  }
}

class _RosterOverview extends StatelessWidget {
  const _RosterOverview();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final employees = provider.employees;
    final freelancers = employees
        .where((employee) => employee.employmentType == 'freelancer')
        .toList(growable: false);
    final inHouse = employees.length - freelancers.length;
    final barcodeReady = freelancers
        .where((employee) => employee.barcodeId.trim().isNotEmpty)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth < 820
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _RosterMetricTile(
              width: tileWidth,
              icon: Icons.apartment_rounded,
              label: 'Departments',
              value: '${provider.departments.length}',
              tone: _PeopleTone.accent,
            ),
            _RosterMetricTile(
              width: tileWidth,
              icon: Icons.badge_outlined,
              label: 'In-house staff',
              value: '$inHouse',
              tone: _PeopleTone.success,
            ),
            _RosterMetricTile(
              width: tileWidth,
              icon: Icons.handyman_outlined,
              label: 'Freelancers',
              value: '${freelancers.length}',
              tone: _PeopleTone.info,
            ),
            _RosterMetricTile(
              width: tileWidth,
              icon: Icons.qr_code_2_rounded,
              label: 'Barcode ready',
              value: '$barcodeReady/${freelancers.length}',
              tone: barcodeReady == freelancers.length
                  ? _PeopleTone.success
                  : _PeopleTone.warning,
            ),
          ],
        );
      },
    );
  }
}

class _RosterMetricTile extends StatelessWidget {
  const _RosterMetricTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final _PeopleTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _peopleToneColors(tone);
    return SoftSurface(
      width: width,
      radius: 18,
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: colors.$2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleDirectory extends StatelessWidget {
  const _PeopleDirectory();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final departmentList = compact
            ? const SizedBox(height: 240, child: _DepartmentList())
            : const Expanded(flex: 2, child: _DepartmentList());
        final employeePanel = compact
            ? const Expanded(child: _EmployeePanel())
            : const Expanded(flex: 3, child: _EmployeePanel());

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              departmentList,
              const SizedBox(height: 14),
              employeePanel,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [departmentList, const SizedBox(width: 16), employeePanel],
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
          hintText: 'Search name, role, or barcode',
          onChanged: provider.setSearchQuery,
        ),
        SoftSegmentedFilter<String>(
          selected: provider.employmentFilter,
          onChanged: provider.setEmploymentFilter,
          options: [
            SoftSegmentOption(
              value: 'all',
              label: 'All people',
              count: provider.employees.length,
            ),
            SoftSegmentOption(
              value: 'in-house',
              label: 'In-house',
              count: provider.employees
                  .where((employee) => employee.employmentType == 'in-house')
                  .length,
            ),
            SoftSegmentOption(
              value: 'freelancer',
              label: 'Freelancers',
              count: provider.employees
                  .where((employee) => employee.employmentType == 'freelancer')
                  .length,
            ),
          ],
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
      return AppEmptyState(
        title: 'No departments',
        message: 'Create a department to get started.',
        icon: Icons.business_outlined,
        action: AppButton(
          label: 'Add Department',
          icon: Icons.add,
          variant: AppButtonVariant.secondary,
          onPressed: () => DepartmentEditorDialog.open(context),
        ),
      );
    }

    return ListView.separated(
      itemCount: depts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final dept = depts[index];
        final isSelected = provider.selectedDepartment?.id == dept.id;
        final allEmployees = provider.employees
            .where((employee) => employee.departmentId == dept.id)
            .toList(growable: false);
        final visibleCount = provider.employeesForDepartment(dept.id).length;
        final freelancerCount = allEmployees
            .where((employee) => employee.employmentType == 'freelancer')
            .length;
        final inHouseCount = allEmployees.length - freelancerCount;
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
                      const SizedBox(height: 4),
                      SoftInlineText(
                        dept.description.isNotEmpty
                            ? dept.description
                            : '$inHouseCount in-house • $freelancerCount freelancers',
                        color: SoftErpTheme.textSecondary,
                        weight: FontWeight.w500,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SoftStatusPill(
                  label: '$visibleCount',
                  background: SoftErpTheme.accentSoft,
                  textColor: SoftErpTheme.accentDark,
                  borderColor: SoftErpTheme.accentSoft,
                ),
                const SizedBox(width: 6),
                SoftIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit department',
                  onTap: () =>
                      DepartmentEditorDialog.open(context, department: dept),
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
      final rosterMatches = _filteredRoster(provider);
      final hasActiveRosterFilter =
          provider.searchQuery.isNotEmpty || provider.employmentFilter != 'all';
      if (!hasActiveRosterFilter) {
        return const AppEmptyState(
          title: 'Select a department',
          message: 'Pick a department on the left to view its employees.',
          icon: Icons.people_outline,
        );
      }
      return _RosterSearchPanel(employees: rosterMatches);
    }

    final emps = provider.employeesForDepartment(selectedDept.id);
    final freelancers = emps
        .where((employee) => employee.employmentType == 'freelancer')
        .toList(growable: false);
    final barcodeReady = freelancers
        .where((employee) => employee.barcodeId.trim().isNotEmpty)
        .length;

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
                onPressed: () => EmployeeEditorDialog.open(
                  context,
                  departmentId: selectedDept.id,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PanelStatPill(
                icon: Icons.groups_2_outlined,
                label: '${emps.length} people',
                tone: _PeopleTone.accent,
              ),
              _PanelStatPill(
                icon: Icons.handyman_outlined,
                label: '${freelancers.length} freelancers',
                tone: _PeopleTone.info,
              ),
              _PanelStatPill(
                icon: Icons.qr_code_2_rounded,
                label: '$barcodeReady barcode ready',
                tone: barcodeReady == freelancers.length
                    ? _PeopleTone.success
                    : _PeopleTone.warning,
              ),
            ],
          ),
          if (freelancers.isNotEmpty) ...[
            const SizedBox(height: 14),
            _FreelancerBarcodeLane(freelancers: freelancers),
          ],
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
                separatorBuilder: (_, _) => const SizedBox(height: 10),
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

class _RosterSearchPanel extends StatelessWidget {
  const _RosterSearchPanel({required this.employees});

  final List<EmployeeDefinition> employees;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(18),
      radius: SoftErpTheme.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: SoftErpTheme.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.manage_search_rounded,
                  color: SoftErpTheme.accentDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Roster search',
                      style: TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${employees.length} people match the active filters',
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (employees.isEmpty)
            const Expanded(
              child: AppEmptyState(
                title: 'No people match',
                message: 'Try another name, role, barcode, or filter.',
                icon: Icons.person_search_outlined,
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: employees.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final employee = employees[index];
                  return _EmployeeRow(
                    emp: employee,
                    departmentId: employee.departmentId,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelStatPill extends StatelessWidget {
  const _PanelStatPill({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final _PeopleTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _peopleToneColors(tone);
    return SoftPill(
      label: label,
      leading: Icon(icon, size: 15, color: colors.$2),
      background: colors.$1,
      foreground: colors.$2,
      borderColor: colors.$1,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    );
  }
}

class _FreelancerBarcodeLane extends StatelessWidget {
  const _FreelancerBarcodeLane({required this.freelancers});

  final List<EmployeeDefinition> freelancers;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      color: SoftErpTheme.cardSurfaceAlt,
      radius: 16,
      elevated: false,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.qr_code_scanner_rounded,
                size: 18,
                color: SoftErpTheme.accentDark,
              ),
              SizedBox(width: 8),
              Text(
                'Freelancer barcode lane',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: freelancers
                  .map(
                    (freelancer) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _BarcodeChip(employee: freelancer),
                    ),
                  )
                  .toList(growable: false),
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
    final contact = [emp.phone].where((s) => s.isNotEmpty).join(' • ');
    return SoftRowCard(
      onTap: () => EmployeeViewDialog.open(
        context,
        departmentId: departmentId,
        employee: emp,
      ),
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
            if (isFreelancer) ...[
              _BarcodeChip(employee: emp, compact: true),
              const SizedBox(width: 6),
            ],
            SoftStatusPill(
              label: isFreelancer ? 'Freelancer' : 'In-house',
              background: isFreelancer
                  ? SoftErpTheme.infoBg
                  : SoftErpTheme.successBg,
              textColor: isFreelancer
                  ? SoftErpTheme.infoText
                  : SoftErpTheme.successText,
              borderColor: isFreelancer
                  ? SoftErpTheme.infoBg
                  : SoftErpTheme.successBg,
            ),
            const SizedBox(width: 6),
            SoftIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onTap: () => EmployeeEditorDialog.open(
                context,
                departmentId: departmentId,
                employee: emp,
              ),
            ),
            const SizedBox(width: 6),
            SoftIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              iconColor: const Color(0xFFB91C1C),
              onTap: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: 'Delete employee?',
                  message:
                      'Permanently delete "${emp.name}"? You can restore them later from the Action Center.',
                );
                if (ok) provider.deleteEmployee(emp.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BarcodeChip extends StatelessWidget {
  const _BarcodeChip({required this.employee, this.compact = false});

  final EmployeeDefinition employee;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final barcode = employee.barcodeId.trim();
    final hasBarcode = barcode.isNotEmpty;
    final label = hasBarcode ? barcode : 'Barcode missing';
    final tone = hasBarcode ? _PeopleTone.accent : _PeopleTone.warning;
    final colors = _peopleToneColors(tone);
    return Tooltip(
      message: hasBarcode
          ? 'Copy ${employee.name} barcode'
          : 'Add a barcode before assigning scan-based jobs',
      child: SoftPill(
        label: compact ? label : '${employee.name} • $label',
        leading: Icon(Icons.qr_code_2_rounded, size: 16, color: colors.$2),
        trailing: hasBarcode && !compact
            ? Icon(Icons.copy_rounded, size: 14, color: colors.$2)
            : null,
        background: colors.$1,
        foreground: colors.$2,
        borderColor: colors.$1,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: hasBarcode
            ? () async {
                await Clipboard.setData(ClipboardData(text: barcode));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text('${employee.name} barcode copied.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              }
            : null,
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
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.business, color: SoftErpTheme.textSecondary),
            )
          : const Icon(Icons.business, color: SoftErpTheme.textSecondary),
    );
  }
}

class _DepartmentsLoadingState extends StatelessWidget {
  const _DepartmentsLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(
            4,
            (index) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 3 ? 0 : 10),
                child: const _PeopleSkeleton(height: 70),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Expanded(child: _PeopleSkeleton()),
      ],
    );
  }
}

class _PeopleSkeleton extends StatelessWidget {
  const _PeopleSkeleton({this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF0F6),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
        border: Border.all(color: SoftErpTheme.border),
      ),
    );
  }
}

enum _PeopleTone { accent, info, success, warning }

(Color, Color) _peopleToneColors(_PeopleTone tone) => switch (tone) {
  _PeopleTone.accent => (SoftErpTheme.accentSoft, SoftErpTheme.accentDark),
  _PeopleTone.info => (SoftErpTheme.infoBg, SoftErpTheme.infoText),
  _PeopleTone.success => (SoftErpTheme.successBg, SoftErpTheme.successText),
  _PeopleTone.warning => (SoftErpTheme.warningBg, SoftErpTheme.warningText),
};

List<EmployeeDefinition> _filteredRoster(DepartmentsProvider provider) {
  var employees = provider.employees;
  if (provider.employmentFilter != 'all') {
    employees = employees
        .where(
          (employee) => employee.employmentType == provider.employmentFilter,
        )
        .toList(growable: false);
  }
  if (provider.searchQuery.isNotEmpty) {
    final query = provider.searchQuery;
    employees = employees
        .where(
          (employee) =>
              employee.name.toLowerCase().contains(query) ||
              employee.role.toLowerCase().contains(query) ||
              employee.phone.toLowerCase().contains(query) ||
              employee.aadharNumber.toLowerCase().contains(query) ||
              employee.panNumber.toLowerCase().contains(query) ||
              employee.barcodeId.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }
  return employees;
}
