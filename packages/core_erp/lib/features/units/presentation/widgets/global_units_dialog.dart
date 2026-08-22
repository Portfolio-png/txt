import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/unit_inputs.dart';
import '../providers/units_provider.dart';

class GlobalUnitsLibraryDialog extends StatefulWidget {
  const GlobalUnitsLibraryDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const GlobalUnitsLibraryDialog(),
    );
  }

  @override
  State<GlobalUnitsLibraryDialog> createState() =>
      _GlobalUnitsLibraryDialogState();
}

class _GlobalUnitsLibraryDialogState extends State<GlobalUnitsLibraryDialog> {
  // Hardcoded standard global units
  final Map<String, List<Map<String, dynamic>>> _globalUnitsByFamily = {
    'Length': [
      {'name': 'meter', 'symbol': 'm', 'conversion': 1.0, 'base': true},
      {'name': 'centimeter', 'symbol': 'cm', 'conversion': 0.01, 'base': false},
      {
        'name': 'millimeter',
        'symbol': 'mm',
        'conversion': 0.001,
        'base': false,
      },
      {'name': 'inch', 'symbol': 'in', 'conversion': 0.0254, 'base': false},
      {'name': 'foot', 'symbol': 'ft', 'conversion': 0.3048, 'base': false},
      {
        'name': 'thou',
        'symbol': 'thou',
        'conversion': 0.0000254,
        'base': false,
      },
      {'name': 'gauge', 'symbol': 'ga', 'conversion': 1.0, 'base': false},
    ],
    'Weight': [
      {'name': 'kilogram', 'symbol': 'kg', 'conversion': 1.0, 'base': true},
      {'name': 'gram', 'symbol': 'g', 'conversion': 0.001, 'base': false},
      {
        'name': 'milligram',
        'symbol': 'mg',
        'conversion': 0.000001,
        'base': false,
      },
      {'name': 'pound', 'symbol': 'lb', 'conversion': 0.453592, 'base': false},
      {'name': 'ounce', 'symbol': 'oz', 'conversion': 0.0283495, 'base': false},
      {
        'name': 'metric ton',
        'symbol': 't',
        'conversion': 1000.0,
        'base': false,
      },
    ],
    'Volume': [
      {'name': 'liter', 'symbol': 'L', 'conversion': 1.0, 'base': true},
      {
        'name': 'milliliter',
        'symbol': 'mL',
        'conversion': 0.001,
        'base': false,
      },
      {'name': 'gallon', 'symbol': 'gal', 'conversion': 3.78541, 'base': false},
    ],
    'Area': [
      {
        'name': 'square meter',
        'symbol': 'sq m',
        'conversion': 1.0,
        'base': true,
      },
      {
        'name': 'square foot',
        'symbol': 'sq ft',
        'conversion': 0.092903,
        'base': false,
      },
      {
        'name': 'square inch',
        'symbol': 'sq in',
        'conversion': 0.00064516,
        'base': false,
      },
    ],
    'Count': [
      {'name': 'piece', 'symbol': 'pc', 'conversion': 1.0, 'base': true},
      {'name': 'dozen', 'symbol': 'dz', 'conversion': 12.0, 'base': false},
      {'name': 'gross', 'symbol': 'gr', 'conversion': 144.0, 'base': false},
      {
        'name': 'box',
        'symbol': 'box',
        'conversion': 1.0,
        'base': true,
      }, // Note: separate base or 1x? Let's just make it base for simplicity
    ],
  };

  bool _isSaving = false;

  Future<void> _enableUnit(
    String family,
    Map<String, dynamic> unitDef,
    UnitsProvider provider,
  ) async {
    setState(() => _isSaving = true);
    try {
      // Find base unit for this family if this isn't the base
      int? baseUnitId;
      if (!unitDef['base']) {
        // Try to find if the base unit exists in active units
        final baseUnit = provider.activeUnits
            .where((u) => u.unitGroupName == family && u.isBaseUnit)
            .firstOrNull;
        if (baseUnit != null) {
          baseUnitId = baseUnit.id;
        } else {
          // Find the base unit def in our hardcoded map
          final baseUnitDef = _globalUnitsByFamily[family]!.firstWhere(
            (u) => u['base'] == true,
          );
          // First create the base unit
          final createdBase = await provider.createUnit(
            CreateUnitInput(
              name: baseUnitDef['name'],
              symbol: baseUnitDef['symbol'],
              notes: 'Global base unit for $family',
              unitGroupName: family,
              conversionFactor: 1.0,
            ),
          );
          if (createdBase != null) {
            baseUnitId = createdBase.id;
          }
        }
      }

      await provider.createUnit(
        CreateUnitInput(
          name: unitDef['name'],
          symbol: unitDef['symbol'],
          notes: 'Standard global unit',
          unitGroupName: family,
          // conversionBaseUnitId: baseUnitId, // Derived implicitly by the backend using unitGroupName and conversionFactor
          conversionFactor: unitDef['conversion'],
        ),
      );
    } catch (e) {
      debugPrint('Failed to enable unit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to enable ${unitDef['name']}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    final activeUnitNames = provider.activeUnits
        .map((u) => u.name.toLowerCase())
        .toSet();
    final activeUnitSymbols = provider.activeUnits
        .map((u) => u.symbol.toLowerCase())
        .toSet();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.public,
                      color: SoftErpTheme.accent,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Global Units Library',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Select standard units from the global catalog to enable them for your team.',
              style: TextStyle(color: SoftErpTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _globalUnitsByFamily.length,
                itemBuilder: (context, index) {
                  final family = _globalUnitsByFamily.keys.elementAt(index);
                  final units = _globalUnitsByFamily[family]!;
                  final isFamilyFullyEnabled = units.every((u) {
                    return activeUnitNames.contains(
                          u['name'].toString().toLowerCase(),
                        ) ||
                        (u['symbol'].toString().isNotEmpty &&
                            activeUnitSymbols.contains(
                              u['symbol'].toString().toLowerCase(),
                            ));
                  });

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: isFamilyFullyEnabled,
                              onChanged: (isFamilyFullyEnabled || _isSaving)
                                  ? null
                                  : (value) async {
                                      if (value == true) {
                                        for (final u in units) {
                                          final isEnabled =
                                              activeUnitNames.contains(
                                                u['name']
                                                    .toString()
                                                    .toLowerCase(),
                                              ) ||
                                              (u['symbol']
                                                      .toString()
                                                      .isNotEmpty &&
                                                  activeUnitSymbols.contains(
                                                    u['symbol']
                                                        .toString()
                                                        .toLowerCase(),
                                                  ));
                                          if (!isEnabled) {
                                            await _enableUnit(
                                              family,
                                              u,
                                              provider,
                                            );
                                          }
                                        }
                                      }
                                    },
                              activeColor: SoftErpTheme.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              family,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: SoftErpTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: units.map((unitDef) {
                              final isEnabled =
                                  activeUnitNames.contains(
                                    unitDef['name'].toString().toLowerCase(),
                                  ) ||
                                  (unitDef['symbol'].toString().isNotEmpty &&
                                      activeUnitSymbols.contains(
                                        unitDef['symbol']
                                            .toString()
                                            .toLowerCase(),
                                      ));

                              return CheckboxListTile(
                                title: Row(
                                  children: [
                                    Text(
                                      unitDef['name'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isEnabled
                                            ? SoftErpTheme.textSecondary
                                            : SoftErpTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        unitDef['symbol'],
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: SoftErpTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  unitDef['base']
                                      ? 'Base unit'
                                      : '${unitDef['conversion']}x base',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                value: isEnabled,
                                onChanged: (isEnabled || _isSaving)
                                    ? null
                                    : (value) {
                                        if (value == true) {
                                          _enableUnit(
                                            family,
                                            unitDef,
                                            provider,
                                          );
                                        }
                                      },
                                activeColor: SoftErpTheme.accent,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
