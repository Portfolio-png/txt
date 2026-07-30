import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/config_service.dart';
import '../providers/units_provider.dart';

class UnitConverterWidget extends StatefulWidget {
  const UnitConverterWidget({
    Key? key,
    this.familyBaseUnitId,
    this.context = 'inventory',
  }) : super(key: key);

  final int? familyBaseUnitId;
  final String context;

  @override
  State<UnitConverterWidget> createState() => _UnitConverterWidgetState();
}

class _UnitConverterWidgetState extends State<UnitConverterWidget> {
  int? _selectedFamilyId;
  int? _fromUnitId;
  String _inputValue = '';

  @override
  void initState() {
    super.initState();
    _selectedFamilyId = widget.familyBaseUnitId;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    final families = provider.activeUnits.where((u) => u.conversionBaseUnitId == null).toList();

    if (_selectedFamilyId == null && families.isNotEmpty) {
      _selectedFamilyId = families.first.id;
    }

    final includedUnits = provider.includedUnitsFor(_selectedFamilyId, widget.context);
    if (_fromUnitId == null && includedUnits.isNotEmpty) {
      _fromUnitId = includedUnits.first.id;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unit Converter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Family'),
              value: _selectedFamilyId,
              items: families.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedFamilyId = val;
                  _fromUnitId = null;
                  _inputValue = '';
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    decoration: const InputDecoration(labelText: 'Value'),
                    onChanged: (val) => setState(() => _inputValue = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'From Unit'),
                    value: _fromUnitId,
                    items: includedUnits.map((u) => DropdownMenuItem(value: u.id, child: Text(u.displayLabel))).toList(),
                    onChanged: (val) => setState(() => _fromUnitId = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_inputValue.isNotEmpty && _fromUnitId != null)
              ...includedUnits.map((u) {
                if (u.id == _fromUnitId) return const SizedBox.shrink();
                final converted = provider.convertValue(_inputValue, _fromUnitId, u.id);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(u.displayLabel),
                      Text(converted ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}
