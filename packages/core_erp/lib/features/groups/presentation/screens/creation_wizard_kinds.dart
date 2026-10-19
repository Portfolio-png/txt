import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../clients/presentation/screens/clients_screen.dart';
import '../../../departments/presentation/screens/department_editor_dialog.dart';
import '../../../departments/presentation/screens/employee_editor_dialog.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../inventory/presentation/widgets/inventory_set_editor_dialog.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../process_routes/presentation/widgets/route_editor.dart';
import '../../../materials/presentation/screens/materials_screen.dart';
import '../../../units/presentation/screens/units_screen.dart';
import '../../../vendors/presentation/screens/vendors_screen.dart';
import '../widgets/structured_group_editor_dialog.dart';

/// Which group of the chooser a kind belongs to.
///
/// A **reading order, not a gate**: every card stays enabled, and somebody who
/// already has units goes straight to [output]. The order is the order a
/// factory has to set things up in, and the only hard dependency in it is the
/// first one — `groupId` and `unitId` are both `required` on an item write
/// (`backend/modules/items/contract.js`). The rest is how the work reads, not
/// what the server enforces.
enum CreationTier {
  foundations(
    'Foundations',
    'An item cannot be saved without a unit and a group.',
  ),
  partners(
    'Machines and partners',
    'Who and what you work with. A sub-contractor needs its client first.',
  ),
  tooling(
    'Materials and tooling',
    'These get attached to the parts that use them.',
  ),
  output(
    'What you make',
    'A set is built from items and a route is the stages one goes through, '
    'so the items come first.',
  );

  const CreationTier(this.label, this.reason);

  final String label;

  /// One line saying why this group comes where it does. Lives here so the
  /// chooser holds no copy of its own.
  final String reason;
}

/// One kind of record the creation wizard can put in its middle column.
class CreationKindSpec {
  const CreationKindSpec({
    required this.key,
    required this.label,
    required this.icon,
    required this.tier,
    this.plural,
    this.editor,
  });

  final String key;
  final String label;
  final IconData icon;

  /// Required on purpose. A kind added without a tier would be a card the
  /// chooser never draws, and a default would hide that rather than ask.
  final CreationTier tier;

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
  static const route = 'route';

  static const List<String> defaults = [item, die, machine];

  static CreationKindSpec byKey(String key) =>
      catalog.firstWhere((spec) => spec.key == key);

  static bool knows(String key) => catalog.any((spec) => spec.key == key);

  /// A remembered lineup, made safe to open a window with.
  ///
  /// A kind that has since left the catalogue is dropped rather than thrown
  /// over — [byKey] has no fallback, so an unknown key would throw while the
  /// window was being built.
  ///
  /// **Empty stays empty.** This used to substitute the three defaults, on the
  /// grounds that a window with no form in it reads as broken; it does not any
  /// more, because an empty bench is now a real state with a chooser in it.
  /// The fallback to the defaults lives where it belongs — the workspace's
  /// `initialKinds ?? defaults`, which Add Item reaches by passing nothing and
  /// Express does not reach at all.
  static List<String> sanitizeLineup(List<String> kinds) =>
      kinds.where(knows).toList(growable: false);

  /// Every kind the chooser offers, **in tier order**.
  ///
  /// One order drives three surfaces — the chooser's groups, the `+` menu in
  /// the lineup column, and the order "Add them all" fills the bench — so they
  /// cannot disagree about what comes first. Nothing indexes this list; every
  /// reader looks a kind up by key, which is what makes reordering it safe.
  static final List<CreationKindSpec> catalog = [
    // Foundations — an item write requires both a unit and a group.
    CreationKindSpec(
      key: 'unit',
      label: 'Unit',
      icon: Icons.straighten_outlined,
      tier: CreationTier.foundations,
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
      key: 'department',
      label: 'Department',
      icon: Icons.apartment_outlined,
      tier: CreationTier.foundations,
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
      key: 'item_group',
      label: 'Item group',
      icon: Icons.account_tree_outlined,
      tier: CreationTier.foundations,
      editor: () => _groupEditor('item'),
    ),
    CreationKindSpec(
      key: 'machine_group',
      label: 'Machine group',
      icon: Icons.workspaces_outlined,
      tier: CreationTier.foundations,
      editor: () => _groupEditor('machine'),
    ),

    // Machines and partners. Client comes before Sub-contractor deliberately:
    // `sub_contractors.client_id` is NOT NULL and the only create route is
    // nested under a client, so one cannot be made without the other.
    CreationKindSpec(
      key: machine,
      label: 'Machine',
      icon: Icons.precision_manufacturing_outlined,
      tier: CreationTier.partners,
      editor: () => AppFlowHooks.machineEditor,
    ),
    CreationKindSpec(
      key: 'client',
      label: 'Client',
      icon: Icons.groups_outlined,
      tier: CreationTier.partners,
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
      tier: CreationTier.partners,
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
      tier: CreationTier.partners,
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
      key: 'employee',
      label: 'Person',
      plural: 'People',
      icon: Icons.badge_outlined,
      tier: CreationTier.partners,
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

    // Materials and tooling.
    CreationKindSpec(
      key: 'material',
      label: 'Material',
      icon: Icons.layers_outlined,
      tier: CreationTier.tooling,
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
      key: die,
      label: 'Die',
      icon: Icons.build_circle_outlined,
      tier: CreationTier.tooling,
      editor: () => AppFlowHooks.dieEditor,
    ),

    // What you make. A set's lines point at items, so items come first.
    const CreationKindSpec(
      key: item,
      label: 'Item',
      icon: Icons.inventory_2_outlined,
      tier: CreationTier.output,
    ),
    // The one card here that is not a master of its own: a route belongs TO a
    // part, so its panel leads with a part picker and cannot be saved without
    // one. It sits straight after Item for that reason.
    CreationKindSpec(
      key: route,
      label: 'Route',
      icon: Icons.conveyor_belt,
      tier: CreationTier.output,
      editor: () => routeEditorPanel(),
    ),
    CreationKindSpec(
      key: 'set',
      label: 'Set',
      icon: Icons.category_outlined,
      tier: CreationTier.output,
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
