import 'package:flutter/material.dart';

class SalaryStructureDesigner extends StatefulWidget {
  final int employeeId;
  const SalaryStructureDesigner({super.key, required this.employeeId});

  @override
  State<SalaryStructureDesigner> createState() => _SalaryStructureDesignerState();
}

class _SalaryStructureDesignerState extends State<SalaryStructureDesigner> {
  final _components = <Map<String, dynamic>>[];
  double _grossSalary = 0;

  @override
  void initState() {
    super.initState();
    _loadStructure();
  }

  Future<void> _loadStructure() async {
    // Mock load
    setState(() {
      _components.add({'name': 'Basic Pay', 'amount': 25000.0, 'type': 'earning'});
      _components.add({'name': 'HRA', 'amount': 10000.0, 'type': 'earning'});
      _components.add({'name': 'PF', 'amount': 1800.0, 'type': 'deduction'});
      _grossSalary = 35000.0;
    });
  }

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salary structure saved.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary Structure Designer'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _save),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                title: const Text('Gross Salary'),
                trailing: Text('₹$_grossSalary', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _components.length,
                itemBuilder: (context, index) {
                  final c = _components[index];
                  final isEarning = c['type'] == 'earning';
                  return Card(
                    child: ListTile(
                      leading: Icon(isEarning ? Icons.add_circle : Icons.remove_circle, color: isEarning ? Colors.green : Colors.red),
                      title: Text(c['name']),
                      trailing: Text('₹${c['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add component dialog
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
