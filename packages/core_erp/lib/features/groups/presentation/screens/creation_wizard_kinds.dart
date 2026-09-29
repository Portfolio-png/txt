import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../clients/presentation/screens/clients_screen.dart';
import '../../../departments/presentation/screens/department_editor_dialog.dart';
import '../../../departments/presentation/screens/employee_editor_dialog.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../inventory/presentation/widgets/inventory_set_editor_dialog.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../materials/presentation/screens/materials_screen.dart';
import '../../../units/presentation/screens/units_screen.dart';
import '../../../vendors/presentation/screens/vendors_screen.dart';
import '../widgets/structured_group_editor_dialog.dart';

/// One kind of record the creation wizard can put in its middle column.
class CreationKindSpec {
  const CreationKindSpec({
    required this.key,
    required this.label,
    required this.icon,
    this.plural,
    this.editor,
  });

  final String key;
  final String label;
  final IconData icon;
  final String? plural;

  String get pluralLabel => plural ?? '${label}s';

  /// The embedded editor, looked up when needed: die and machine come from
  /// app hooks that may not be registered. Null for the item, which the
  /// wizard hosts itself; a null result means "not available here".
  final EmbeddedEditorBuilder? Function()? editor;
}

/// Everything the wizard's + can add, and the lineup it opens with.
class CreationKinds {
  const CreationKinds._();

  static const item = 'item';
  static const die = 'die';
  static const machine = 'machine';

  static const List<String> defaults = [item, die, machine];

  static CreationKindSpec byKey(String key) =>
      catalog.firstWhere((spec) => spec.key == key);

  static final List<CreationKindSpec> catalog = [
    const CreationKindSpec(
      key: item,
      label: 'Item',
      icon: Icons.inventory_2_outlined,
    ),
    CreationKindSpec(
      key: die,
      label: 'Die',
      icon: Icons.build_circle_outlined,
      editor: () => AppFlowHooks.dieEditor,
    ),
    CreationKindSpec(
      key: machine,
      label: 'Machine',
      icon: Icons.precision_manufacturing_outlined,
      editor: () => AppFlowHooks.machineEditor,
    ),
    CreationKindSpec(
      key: 'client',
      label: 'Client',
      icon: Icons.groups_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              ClientsScreen.editorPanel(
                onSaved: (client) => onSaved(
                  CreatedRecord(
                    id: '${client.id}',
                    title: client.name,
                    subtitle: client.alias,
                  ),
                ),
                onCancel: onCancel,
              ),
    ),
    CreationKindSpec(
      key: 'sub_contractor',
      label: 'Sub-contractor',
      icon: Icons.handshake_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              ClientsScreen.subContractorEditorPanel(
                onSaved: (sub) => onSaved(
                  CreatedRecord(
                    id: '${sub.id}',
                    title: sub.name,
                    subtitle: sub.phone,
                  ),
                ),
                onCancel: onCancel,
              ),
    ),
    CreationKindSpec(
      key: 'vendor',
      label: 'Vendor',
      icon: Icons.storefront_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              VendorsScreen.editorPanel(
                onSaved: (vendor) => onSaved(
                  CreatedRecord(
                    id: '${vendor.id}',
                    title: vendor.name,
                    subtitle: vendor.alias,
                  ),
                ),
                onCancel: onCancel,
              ),
    ),
    CreationKindSpec(
      key: 'unit',
      label: 'Unit',
      icon: Icons.straighten_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              UnitsScreen.editorPanel(
                onSaved: (unit) => onSaved(
                  CreatedRecord(
                    id: '${unit.id}',
                    title: unit.name,
                    subtitle: unit.symbol,
                  ),
                ),
                onCancel: onCancel,
              ),
    ),
    CreationKindSpec(
      key: 'item_group',
      label: 'Item group',
      icon: Icons.account_tree_outlined,
      editor: () => _groupEditor('item'),
    ),
    CreationKindSpec(
      key: 'machine_group',
      label: 'Machine group',
      icon: Icons.workspaces_outlined,
      editor: () => _groupEditor('machine'),
    ),
    CreationKindSpec(
      key: 'material',
      label: 'Material',
      icon: Icons.layers_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              MaterialsScreen.editorPanel(
                onSaved: (material) => onSaved(
                  CreatedRecord(
                    id: '${material.id}',
                    title: material.name,
                    subtitle: material.category,
                  ),
                ),
                onCancel: onCancel,
              ),
    ),
    CreationKindSpec(
      key: 'set',
      label: 'Set',
      icon: Icons.category_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              InventorySetEditorDialog(
                onSaved: (set) => onSaved(
                  CreatedRecord(
                    id: '${set.id}',
                    title: set.name,
                    subtitle: '${set.lines.length} lines',
                  ),
                ),
                onCancel: onCancel,
              ),
    ),
    CreationKindSpec(
      key: 'department',
      label: 'Department',
      icon: Icons.apartment_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              DepartmentEditorDialog.editorPanel(
                onSaved: (department) => onSaved(
                  CreatedRecord(id: '${department.id}', title: department.name),
                ),
                onCancel: onCancel,
              ),
    ),
    CreationKindSpec(
      key: 'employee',
      label: 'Person',
      plural: 'People',
      icon: Icons.badge_outlined,
      editor: () =>
          (context, {required onSaved, required onCancel}) =>
              EmployeeEditorDialog.editorPanel(
                onSaved: (employee) => onSaved(
                  CreatedRecord(
                    id: '${employee.id}',
                    title: employee.name,
                    subtitle: employee.role,
                  ),
                ),
                onCancel: onCancel,
              ),
    ),
  ];

  /// Item and machine groups share one editor. A new group changes what the
  /// item and inventory masters show, so they are refreshed as
  /// `GroupsScreen.openEditor` does after its dialog.
  static EmbeddedEditorBuilder _groupEditor(String groupType) =>
      (context, {required onSaved, required onCancel}) =>
          StructuredGroupEditorDialog(
            groupType: groupType,
            onSaved: (group) {
              try {
                context.read<InventoryProvider>().refresh();
              } catch (_) {}
              try {
                context.read<ItemsProvider>().refresh();
              } catch (_) {}
              onSaved(CreatedRecord(id: '${group.id}', title: group.name));
            },
            onCancel: onCancel,
          );
}
