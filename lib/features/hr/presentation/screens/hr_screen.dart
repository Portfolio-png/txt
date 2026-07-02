import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hr_provider.dart';

/// HR & Payroll module: one screen, five tabs (Payroll runs, Salary structures,
/// Attendance, Leave, Statutory). Consumes the raw-row HR API via [HrProvider].
class HrScreen extends StatelessWidget {
  const HrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('HR & Payroll'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Payroll'),
              Tab(text: 'Salary Structures'),
              Tab(text: 'Attendance'),
              Tab(text: 'Leave'),
              Tab(text: 'Statutory'),
            ],
          ),
        ),
        body: Consumer<HrProvider>(
          builder: (context, hr, _) {
            if (hr.loading && hr.employees.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                if (hr.error != null)
                  _ErrorBanner(hr.error!, onDismiss: () => hr.setError(null)),
                const Expanded(
                  child: TabBarView(
                    children: [
                      _PayrollTab(),
                      _SalaryTab(),
                      _AttendanceTab(),
                      _LeaveTab(),
                      _StatutoryTab(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================ helpers

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _money(dynamic v) => '₹${_num(v).toStringAsFixed(2)}';
const _months = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message, {required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFDECEA),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFB3261E)))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDismiss),
          ],
        ),
      ),
    );
  }
}

Widget _employeeDropdown(
  HrProvider hr,
  int? value,
  ValueChanged<int?> onChanged, {
  String hint = 'Select employee',
}) {
  return DropdownButton<int>(
    value: value,
    hint: Text(hint),
    isExpanded: true,
    items: hr.employees
        .map((e) => DropdownMenuItem<int>(
              value: e['id'] as int,
              child: Text((e['name'] as String?) ?? '#${e['id']}'),
            ))
        .toList(),
    onChanged: onChanged,
  );
}

// ============================================================ Payroll tab

class _PayrollTab extends StatelessWidget {
  const _PayrollTab();

  Future<void> _newRun(BuildContext context) async {
    final hr = context.read<HrProvider>();
    final now = DateTime.now();
    int month = now.month;
    int year = now.year;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New payroll run'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: month,
                items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(_months[m]))],
                onChanged: (v) => setState(() => month = v ?? month),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: '$year',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Year'),
                  onChanged: (v) => year = int.tryParse(v) ?? year,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final done = await hr.guard(() => hr.repo.createRun(month: month, year: year));
    if (done) await hr.refreshRuns();
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text('Payroll runs', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _newRun(context),
                icon: const Icon(Icons.add),
                label: const Text('New run'),
              ),
            ],
          ),
        ),
        Expanded(
          child: hr.runs.isEmpty
              ? const Center(child: Text('No payroll runs yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: hr.runs.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RunCard(hr.runs[i]),
                ),
        ),
      ],
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard(this.run);
  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    final hr = context.read<HrProvider>();
    final id = run['id'] as int;
    final status = (run['status'] as String?) ?? 'draft';
    final finalized = status == 'finalized';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_months[_num(run['month']).toInt()]} ${run['year']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text('Gross ${_money(run['total_gross'])}  ·  '
                    'Ded ${_money(run['total_deduction'])}  ·  '
                    'Net ${_money(run['total_net'])}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
            const SizedBox(width: 12),
            _StatusChip(status),
            const Spacer(),
            if (!finalized)
              TextButton(
                onPressed: () async {
                  final done = await hr.guard(() => hr.repo.processRun(id).then((_) {}));
                  if (done) await hr.refreshRuns();
                },
                child: const Text('Process'),
              ),
            if (!finalized && status == 'processed')
              TextButton(
                onPressed: () async {
                  final done = await hr.guard(() => hr.repo.finalizeRun(id));
                  if (done) await hr.refreshRuns();
                },
                child: const Text('Finalize'),
              ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _RunDetailsDialog(id),
              ),
              child: const Text('View'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'processed' => const Color(0xFF1E90FF),
      'finalized' => const Color(0xFF32CD32),
      _ => const Color(0xFFFFA500),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _RunDetailsDialog extends StatelessWidget {
  const _RunDetailsDialog(this.runId);
  final int runId;

  @override
  Widget build(BuildContext context) {
    final hr = context.read<HrProvider>();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: FutureBuilder<Map<String, dynamic>>(
          future: hr.repo.runDetails(runId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            final details = (snap.data!['details'] as List).cast<Map<String, dynamic>>();
            // Group detail lines by employee for a readable payslip view.
            final byEmp = <int, List<Map<String, dynamic>>>{};
            for (final d in details) {
              (byEmp[d['employee_id'] as int] ??= []).add(d);
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payslips', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: byEmp.isEmpty
                        ? const Center(child: Text('Not processed yet — hit Process on the run.'))
                        : ListView(
                            children: byEmp.entries.map((e) {
                              final gross = e.value.where((l) => l['is_deduction'] == 0).fold<double>(0, (s, l) => s + _num(l['amount']));
                              final ded = e.value.where((l) => l['is_deduction'] == 1).fold<double>(0, (s, l) => s + _num(l['amount']));
                              return ExpansionTile(
                                title: Text(hr.employeeName(e.key).isEmpty ? 'Employee #${e.key}' : hr.employeeName(e.key)),
                                subtitle: Text('Gross ${_money(gross)}  ·  Ded ${_money(ded)}  ·  Net ${_money(gross - ded)}'),
                                children: e.value
                                    .map((l) => ListTile(
                                          dense: true,
                                          title: Text((l['label'] as String?)?.isNotEmpty == true ? l['label'] as String : 'Component ${l['component_id']}'),
                                          trailing: Text(
                                            '${l['is_deduction'] == 1 ? '-' : ''}${_money(l['amount'])}',
                                            style: TextStyle(color: l['is_deduction'] == 1 ? Colors.red : Colors.green.shade700),
                                          ),
                                        ))
                                    .toList(),
                              );
                            }).toList(),
                          ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================ Salary tab

class _SalaryTab extends StatefulWidget {
  const _SalaryTab();
  @override
  State<_SalaryTab> createState() => _SalaryTabState();
}

class _SalaryTabState extends State<_SalaryTab> {
  int? _employeeId;
  String _effectiveDate = DateTime.now().toIso8601String().substring(0, 10);
  final List<Map<String, dynamic>> _lines = []; // {component_id, amount_or_formula}
  bool _loading = false;

  Future<void> _load(int employeeId) async {
    setState(() => _loading = true);
    final hr = context.read<HrProvider>();
    try {
      final data = await hr.repo.getStructure(employeeId);
      final structure = data['structure'] as Map<String, dynamic>?;
      final lines = (data['lines'] as List? ?? const []).cast<Map<String, dynamic>>();
      _lines
        ..clear()
        ..addAll(lines.map((l) => {
              'component_id': l['component_id'],
              'amount_or_formula': '${l['amount_or_formula'] ?? ''}',
            }));
      if (structure != null && structure['effective_from'] != null) {
        _effectiveDate = '${structure['effective_from']}'.substring(0, 10);
      }
    } catch (e) {
      hr.setError(e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final hr = context.read<HrProvider>();
    if (_employeeId == null) return;
    final ok = await hr.guard(() => hr.repo.saveStructure(
          employeeId: _employeeId!,
          effectiveDate: _effectiveDate,
          lines: _lines
              .where((l) => l['component_id'] != null)
              .map((l) => {'component_id': l['component_id'], 'amount_or_formula': l['amount_or_formula']})
              .toList(),
        ));
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salary structure saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrProvider>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _employeeDropdown(hr, _employeeId, (v) {
                  setState(() => _employeeId = v);
                  if (v != null) _load(v);
                }),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () => _manageComponents(context),
                icon: const Icon(Icons.tune),
                label: const Text('Components'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_employeeId != null) ...[
            Row(
              children: [
                const Text('Effective from: '),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.tryParse(_effectiveDate) ?? DateTime.now(),
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _effectiveDate = picked.toIso8601String().substring(0, 10));
                    }
                  },
                  child: Text(_effectiveDate),
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _lines.length,
                      itemBuilder: (_, i) => _lineRow(hr, i),
                    ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _lines.add({'component_id': null, 'amount_or_formula': '0'})),
                  icon: const Icon(Icons.add),
                  label: const Text('Add line'),
                ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Save structure')),
              ],
            ),
          ] else
            const Expanded(child: Center(child: Text('Pick an employee to edit their salary structure.'))),
        ],
      ),
    );
  }

  Widget _lineRow(HrProvider hr, int i) {
    final line = _lines[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButton<int>(
              value: line['component_id'] as int?,
              isExpanded: true,
              hint: const Text('Component'),
              items: hr.components
                  .map((c) => DropdownMenuItem<int>(
                        value: c['id'] as int,
                        child: Text('${c['name']} (${c['type']})'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => line['component_id'] = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: '${line['amount_or_formula'] ?? ''}',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount / %'),
              onChanged: (v) => line['amount_or_formula'] = v,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _lines.removeAt(i)),
          ),
        ],
      ),
    );
  }

  Future<void> _manageComponents(BuildContext context) async {
    await showDialog<void>(context: context, builder: (_) => const _ComponentsDialog());
  }
}

class _ComponentsDialog extends StatefulWidget {
  const _ComponentsDialog();
  @override
  State<_ComponentsDialog> createState() => _ComponentsDialogState();
}

class _ComponentsDialogState extends State<_ComponentsDialog> {
  final _name = TextEditingController();
  String _type = 'earning';
  String _method = 'fixed';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrProvider>();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Payroll components', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: hr.components
                      .map((c) => ListTile(
                            dense: true,
                            title: Text('${c['name']}'),
                            subtitle: Text('${c['type']} · ${c['calculation_method']}'),
                            trailing: c['is_statutory'] == 1 ? const Chip(label: Text('statutory')) : null,
                          ))
                      .toList(),
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'))),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _type,
                    items: const [
                      DropdownMenuItem(value: 'earning', child: Text('earning')),
                      DropdownMenuItem(value: 'deduction', child: Text('deduction')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'earning'),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _method,
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('fixed')),
                      DropdownMenuItem(value: 'percent_of_basic', child: Text('% of basic')),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? 'fixed'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    if (_name.text.trim().isEmpty) return;
                    final ok = await hr.guard(() => hr.repo.createComponent(
                          name: _name.text.trim(),
                          type: _type,
                          calculationMethod: _method,
                        ));
                    if (ok) {
                      _name.clear();
                      await hr.refreshComponents();
                    }
                  },
                  child: const Text('Add component'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ Attendance tab

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab();
  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  int? _employeeId;
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  List<Map<String, dynamic>> _records = [];
  bool _loading = false;

  Future<void> _load() async {
    if (_employeeId == null) return;
    setState(() => _loading = true);
    final hr = context.read<HrProvider>();
    try {
      _records = await hr.repo.attendance(employeeId: _employeeId!, month: _month, year: _year);
    } catch (e) {
      hr.setError(e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _mark() async {
    if (_employeeId == null) return;
    final hr = context.read<HrProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_year, _month),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    String status = 'present';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Mark ${picked.toIso8601String().substring(0, 10)}'),
          content: DropdownButton<String>(
            value: status,
            items: const [
              DropdownMenuItem(value: 'present', child: Text('present')),
              DropdownMenuItem(value: 'half', child: Text('half day')),
              DropdownMenuItem(value: 'absent', child: Text('absent')),
              DropdownMenuItem(value: 'paid_leave', child: Text('paid leave')),
            ],
            onChanged: (v) => setState(() => status = v ?? 'present'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final done = await hr.guard(() => hr.repo.upsertAttendance(
          employeeId: _employeeId!,
          date: picked.toIso8601String().substring(0, 10),
          status: status,
        ));
    if (done) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrProvider>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _employeeDropdown(hr, _employeeId, (v) {
                  setState(() => _employeeId = v);
                  _load();
                }),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _month,
                items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(_months[m]))],
                onChanged: (v) {
                  setState(() => _month = v ?? _month);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextFormField(
                  initialValue: '$_year',
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    _year = int.tryParse(v) ?? _year;
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _employeeId == null ? null : _mark, icon: const Icon(Icons.add), label: const Text('Mark')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const Center(child: Text('No attendance for this month.'))
                    : ListView(
                        children: _records
                            .map((r) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.event_available_outlined),
                                  title: Text('${r['date']}'),
                                  trailing: Text('${r['status']}'),
                                ))
                            .toList(),
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ Leave tab

class _LeaveTab extends StatefulWidget {
  const _LeaveTab();
  @override
  State<_LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<_LeaveTab> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final hr = context.read<HrProvider>();
    try {
      _requests = await hr.repo.leaveRequests();
    } catch (e) {
      hr.setError(e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(int id, String status) async {
    final hr = context.read<HrProvider>();
    final done = await hr.guard(() => hr.repo.decideLeaveRequest(id, status));
    if (done) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrProvider>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Leave requests', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _manageTypes(context),
                icon: const Icon(Icons.category_outlined),
                label: const Text('Types'),
              ),
              FilledButton.icon(
                onPressed: hr.leaveTypes.isEmpty ? null : () => _newRequest(context),
                icon: const Icon(Icons.add),
                label: const Text('Request'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _requests.isEmpty
                    ? const Center(child: Text('No leave requests.'))
                    : ListView(
                        children: _requests.map((r) {
                          final pending = r['status'] == 'pending';
                          return Card(
                            child: ListTile(
                              title: Text('${hr.employeeName(r['employee_id'] as int)} · ${_num(r['days']).toStringAsFixed(1)} day(s)'),
                              subtitle: Text('${r['from_date']} → ${r['to_date']}  ·  ${r['status']}'),
                              trailing: pending
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Approve',
                                          icon: const Icon(Icons.check, color: Colors.green),
                                          onPressed: () => _decide(r['id'] as int, 'approved'),
                                        ),
                                        IconButton(
                                          tooltip: 'Reject',
                                          icon: const Icon(Icons.close, color: Colors.red),
                                          onPressed: () => _decide(r['id'] as int, 'rejected'),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _manageTypes(BuildContext context) async {
    await showDialog<void>(context: context, builder: (_) => const _LeaveTypesDialog());
  }

  Future<void> _newRequest(BuildContext context) async {
    final hr = context.read<HrProvider>();
    int? employeeId;
    int? typeId = hr.leaveTypes.isNotEmpty ? hr.leaveTypes.first['id'] as int : null;
    DateTime from = DateTime.now();
    DateTime to = DateTime.now();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New leave request'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _employeeDropdown(hr, employeeId, (v) => setState(() => employeeId = v)),
                DropdownButton<int>(
                  value: typeId,
                  isExpanded: true,
                  hint: const Text('Leave type'),
                  items: hr.leaveTypes.map((t) => DropdownMenuItem<int>(value: t['id'] as int, child: Text('${t['name']}'))).toList(),
                  onChanged: (v) => setState(() => typeId = v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final p = await showDatePicker(context: ctx, initialDate: from, firstDate: DateTime(2015), lastDate: DateTime(2100));
                          if (p != null) setState(() => from = p);
                        },
                        child: Text('From ${from.toIso8601String().substring(0, 10)}'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final p = await showDatePicker(context: ctx, initialDate: to, firstDate: DateTime(2015), lastDate: DateTime(2100));
                          if (p != null) setState(() => to = p);
                        },
                        child: Text('To ${to.toIso8601String().substring(0, 10)}'),
                      ),
                    ),
                  ],
                ),
                TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (ok != true || employeeId == null || typeId == null) return;
    final days = to.difference(from).inDays + 1;
    final done = await hr.guard(() => hr.repo.createLeaveRequest(
          employeeId: employeeId!,
          leaveTypeId: typeId!,
          fromDate: from.toIso8601String().substring(0, 10),
          toDate: to.toIso8601String().substring(0, 10),
          days: days.toDouble(),
          reason: reason.text.trim(),
        ));
    if (done) await _load();
  }
}

class _LeaveTypesDialog extends StatefulWidget {
  const _LeaveTypesDialog();
  @override
  State<_LeaveTypesDialog> createState() => _LeaveTypesDialogState();
}

class _LeaveTypesDialogState extends State<_LeaveTypesDialog> {
  final _name = TextEditingController();
  bool _paid = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrProvider>();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Leave types', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: hr.leaveTypes
                      .map((t) => ListTile(
                            dense: true,
                            title: Text('${t['name']}'),
                            trailing: Text(t['paid'] == 1 ? 'paid' : 'unpaid'),
                          ))
                      .toList(),
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'))),
                  const SizedBox(width: 8),
                  const Text('Paid'),
                  Switch(value: _paid, onChanged: (v) => setState(() => _paid = v)),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    if (_name.text.trim().isEmpty) return;
                    final ok = await hr.guard(() => hr.repo.createLeaveType(name: _name.text.trim(), paid: _paid));
                    if (ok) {
                      _name.clear();
                      await hr.refreshLeaveTypes();
                    }
                  },
                  child: const Text('Add type'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ Statutory tab

class _StatutoryTab extends StatefulWidget {
  const _StatutoryTab();
  @override
  State<_StatutoryTab> createState() => _StatutoryTabState();
}

class _StatutoryTabState extends State<_StatutoryTab> {
  final _c = <String, TextEditingController>{};
  bool _seeded = false;

  final _fields = const {
    'pf_wage_ceiling': 'PF wage ceiling',
    'pf_employee_rate': 'PF employee %',
    'pf_employer_rate': 'PF employer %',
    'esi_eligible_threshold': 'ESI eligibility threshold',
    'esi_employee_rate': 'ESI employee %',
    'esi_employer_rate': 'ESI employer %',
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(Map<String, dynamic>? cfg) {
    if (_seeded) return;
    _seeded = true;
    for (final k in _fields.keys) {
      _c[k] = TextEditingController(text: '${cfg?[k] ?? ''}');
    }
    _c['pt_slabs_json'] = TextEditingController(text: '${cfg?['pt_slabs_json'] ?? '[]'}');
    _c['tds_config_json'] = TextEditingController(text: '${cfg?['tds_config_json'] ?? '{}'}');
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrProvider>();
    _seed(hr.statutory);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Statutory configuration', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Company-wide PF / ESI / PT / TDS settings used by the payroll engine.',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _fields.entries
                .map((e) => SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _c[e.key],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder()),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c['pt_slabs_json'],
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Professional Tax slabs (JSON)',
              helperText: '[{"upTo":7500,"amount":0},{"upTo":null,"amount":200}]',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c['tds_config_json'],
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'TDS config (JSON)',
              helperText: '{"monthly":0}',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                // Validate JSON before sending so a typo doesn't silently persist.
                try {
                  jsonDecode(_c['pt_slabs_json']!.text);
                  jsonDecode(_c['tds_config_json']!.text);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PT/TDS JSON is invalid')));
                  return;
                }
                final cfg = <String, dynamic>{
                  for (final k in _fields.keys) k: double.tryParse(_c[k]!.text) ?? 0,
                  'pt_slabs_json': _c['pt_slabs_json']!.text,
                  'tds_config_json': _c['tds_config_json']!.text,
                };
                final ok = await hr.guard(() => hr.repo.saveStatutory(cfg));
                if (ok) {
                  await hr.refreshStatutory();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Statutory config saved')));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
