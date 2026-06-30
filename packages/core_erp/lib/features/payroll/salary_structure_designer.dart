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

  Future<void> _editGrossSalary() async {
    final controller = TextEditingController(text: _grossSalary.toString());
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Gross Salary'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );

    if (result != null && double.tryParse(result) != null) {
      setState(() {
        _grossSalary = double.parse(result);
      });
    }
  }

  Future<void> _addComponent() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'earning';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Component'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Bonus)')),
                TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
                DropdownButton<String>(
                  value: type,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'earning', child: Text('Earning')),
                    DropdownMenuItem(value: 'deduction', child: Text('Deduction')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => type = val);
                  },
                ),
              ],
            );
          }
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final amt = double.tryParse(amountCtrl.text);
              if (nameCtrl.text.isNotEmpty && amt != null) {
                Navigator.pop(context, {'name': nameCtrl.text, 'amount': amt, 'type': type});
              }
            },
            child: const Text('Add')
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _components.add(result);
      });
    }
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
                onTap: _editGrossSalary,
                subtitle: const Text('Tap to edit'),
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('₹${c['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.grey, size: 20),
                            onPressed: () {
                              setState(() => _components.removeAt(index));
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addComponent,
        child: const Icon(Icons.add),
      ),
    );
  }
}
