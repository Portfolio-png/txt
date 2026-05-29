import 'package:flutter/material.dart';

import '../widgets/pm_hero.dart';
import '../widgets/pm_segmented_control_section.dart';
import '../widgets/pm_sandbox_section.dart';
import '../widgets/pm_ux_exploration.dart';
import '../widgets/pm_database_section.dart';
import '../widgets/pm_button_library.dart';
import '../widgets/pm_barcode_section.dart';

class PMScreen extends StatefulWidget {
  const PMScreen({super.key});

  @override
  State<PMScreen> createState() => _PMScreenState();
}

class _PMScreenState extends State<PMScreen> {
  final _sandboxNameController = TextEditingController(text: 'Paper Cone');
  final _sandboxPropertyController = TextEditingController();
  String _selectedSegment = 'group';
  String _selectedSegmentSoft = 'group';
  String _uxFamily = 'context';
  String _uxMethod = 'workspace';
  String _sandboxType = 'Primary';
  bool _sandboxAddSubGroup = true;
  bool _sandboxAddItem = false;
  bool _sandboxAddProperties = true;
  String? _sandboxSubGroup = 'Cone';
  String? _sandboxItem;
  final List<String> _sandboxProperties = <String>['GSM', 'Width'];
  String _sandboxLayout = 'workspace';

  @override
  void initState() {
    super.initState();
    _sandboxNameController.addListener(_refreshSandbox);
    _sandboxPropertyController.addListener(_refreshSandbox);
  }

  @override
  void dispose() {
    _sandboxNameController.removeListener(_refreshSandbox);
    _sandboxPropertyController.removeListener(_refreshSandbox);
    _sandboxNameController.dispose();
    _sandboxPropertyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PMHero(),
            const SizedBox(height: 24),
            FigmaSegmentSection(
              selectedValue: _selectedSegment,
              onChanged: (value) {
                setState(() {
                  _selectedSegment = value;
                });
              },
            ),
            const SizedBox(height: 24),
            FigmaSoftSegmentSection(
              selectedValue: _selectedSegmentSoft,
              onChanged: (value) {
                setState(() {
                  _selectedSegmentSoft = value;
                });
              },
            ),
            const SizedBox(height: 24),
            PMInventorySandboxSection(
              nameController: _sandboxNameController,
              propertyController: _sandboxPropertyController,
              groupType: _sandboxType,
              addSubGroup: _sandboxAddSubGroup,
              addItem: _sandboxAddItem,
              addProperties: _sandboxAddProperties,
              selectedSubGroup: _sandboxSubGroup,
              selectedItem: _sandboxItem,
              properties: _sandboxProperties,
              layout: _sandboxLayout,
              onLayoutChanged: (value) {
                setState(() {
                  _sandboxLayout = value;
                });
              },
              onGroupTypeChanged: (value) {
                setState(() {
                  _sandboxType = value;
                });
              },
              onAddSubGroupChanged: (value) {
                setState(() {
                  _sandboxAddSubGroup = value;
                  if (!value) {
                    _sandboxSubGroup = null;
                  } else {
                    _sandboxSubGroup ??= 'Cone';
                  }
                });
              },
              onAddItemChanged: (value) {
                setState(() {
                  _sandboxAddItem = value;
                  if (!value) {
                    _sandboxItem = null;
                  } else {
                    _sandboxItem ??= 'Funnel Small';
                  }
                });
              },
              onAddPropertiesChanged: (value) {
                setState(() {
                  _sandboxAddProperties = value;
                  if (!value) {
                    _sandboxPropertyController.clear();
                  }
                });
              },
              onSubGroupChanged: (value) {
                setState(() {
                  _sandboxSubGroup = value;
                });
              },
              onItemChanged: (value) {
                setState(() {
                  _sandboxItem = value;
                });
              },
              onQuickAddItem: _quickAddSandboxItem,
              onAddProperty: _addSandboxProperty,
              onRemoveProperty: (property) {
                setState(() {
                  _sandboxProperties.remove(property);
                });
              },
              onReset: _resetSandbox,
            ),
            const SizedBox(height: 24),
            PMInventoryUxExplorationSection(
              selectedFamily: _uxFamily,
              selectedMethod: _uxMethod,
              onFamilyChanged: (value) {
                setState(() {
                  _uxFamily = value;
                  _uxMethod = switch (value) {
                    'context' => 'workspace',
                    'guided' => 'stepper',
                    'fast' => 'sheet',
                    _ => 'workspace',
                  };
                });
              },
              onMethodChanged: (value) {
                setState(() {
                  _uxMethod = value;
                });
              },
            ),
            const SizedBox(height: 24),
            const PMDatabaseIdeasSection(),
            const SizedBox(height: 24),
            const PMButtonLibrary(),
            const SizedBox(height: 24),
            const PMBarcodeSection(),
          ],
        ),
      ),
    );
  }

  void _refreshSandbox() {
    if (mounted) {
      setState(() {});
    }
  }

  void _addSandboxProperty() {
    final value = _sandboxPropertyController.text.trim();
    if (value.isEmpty || _sandboxProperties.contains(value)) {
      return;
    }

    setState(() {
      _sandboxProperties.add(value);
      _sandboxPropertyController.clear();
      _sandboxAddProperties = true;
    });
  }

  void _resetSandbox() {
    setState(() {
      _sandboxNameController.text = 'Paper Cone';
      _sandboxPropertyController.clear();
      _sandboxType = 'Primary';
      _sandboxAddSubGroup = true;
      _sandboxAddItem = false;
      _sandboxAddProperties = true;
      _sandboxSubGroup = 'Cone';
      _sandboxItem = null;
      _sandboxProperties
        ..clear()
        ..addAll(['GSM', 'Width']);
      _sandboxLayout = 'workspace';
    });
  }

  void _quickAddSandboxItem() {
    setState(() {
      _sandboxAddItem = true;
      _sandboxItem = 'New Inline Item';
    });
  }
}
