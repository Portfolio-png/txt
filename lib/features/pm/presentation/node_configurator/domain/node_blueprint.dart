import 'package:flutter/material.dart';

/// The Node Configurator's domain.
///
/// A node answers three questions and nothing else: what runs it, what tooling
/// it mounts, and where its loss goes. Each answer is a *slot with a mode*,
/// because a blank is ambiguous — today `ProcessNode.dieId` being empty means
/// both "no tooling" and "nobody picked one yet", and only the second should
/// stop a run.
///
/// Quantities stay out. How much comes off is settled at reconciliation.

// ---------------------------------------------------------------------------
// Tone — the colour language every slot chip shares.
// ---------------------------------------------------------------------------

/// [absent] and [deferred] must never look alike: one closes the question, the
/// other hands it to the operator.
enum SlotTone { absent, bound, pooled, deferred }

class SlotToneStyle {
  const SlotToneStyle({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}

const Map<SlotTone, SlotToneStyle> kSlotToneStyles = <SlotTone, SlotToneStyle>{
  SlotTone.absent: SlotToneStyle(
    foreground: Color(0xFF6C7386),
    background: Color(0xFFF2F3F8),
    border: Color(0xFFE0E3EE),
  ),
  SlotTone.bound: SlotToneStyle(
    foreground: Color(0xFF4740B7),
    background: Color(0xFFF1EEFF),
    border: Color(0xFFD9D3FA),
  ),
  SlotTone.pooled: SlotToneStyle(
    foreground: Color(0xFF2E57C7),
    background: Color(0xFFEBF2FF),
    border: Color(0xFFC7D6F5),
  ),
  SlotTone.deferred: SlotToneStyle(
    foreground: Color(0xFF946200),
    background: Color(0xFFFFF6E9),
    border: Color(0xFFF3DFB8),
  ),
};

SlotToneStyle styleForTone(SlotTone tone) => kSlotToneStyles[tone]!;

// ---------------------------------------------------------------------------
// Slot modes
// ---------------------------------------------------------------------------

enum MachineSlotMode { none, specific, group, open }

extension MachineSlotModeInfo on MachineSlotMode {
  String get label => switch (this) {
    MachineSlotMode.none => 'None',
    MachineSlotMode.specific => 'One machine',
    MachineSlotMode.group => 'A group',
    MachineSlotMode.open => 'At run time',
  };

  String get blurb => switch (this) {
    MachineSlotMode.none => 'Bench work. No asset booked.',
    MachineSlotMode.specific => 'Pinned to one machine.',
    MachineSlotMode.group => 'Operator picks one from the pool.',
    MachineSlotMode.open => 'Operator names the machine before starting.',
  };

  IconData get icon => switch (this) {
    MachineSlotMode.none => Icons.pan_tool,
    MachineSlotMode.specific => Icons.precision_manufacturing,
    MachineSlotMode.group => Icons.workspaces,
    MachineSlotMode.open => Icons.schedule,
  };

  SlotTone get tone => switch (this) {
    MachineSlotMode.none => SlotTone.absent,
    MachineSlotMode.specific => SlotTone.bound,
    MachineSlotMode.group => SlotTone.pooled,
    MachineSlotMode.open => SlotTone.deferred,
  };
}

enum DieSlotMode { none, specific, open }

extension DieSlotModeInfo on DieSlotMode {
  String get label => switch (this) {
    DieSlotMode.none => 'None',
    DieSlotMode.specific => 'One die',
    DieSlotMode.open => 'At run time',
  };

  String get blurb => switch (this) {
    DieSlotMode.none => 'No tooling. Nobody is asked.',
    DieSlotMode.specific => 'Pinned to one tool.',
    DieSlotMode.open => 'Tooling needed. Operator picks before starting.',
  };

  IconData get icon => switch (this) {
    DieSlotMode.none => Icons.layers_clear,
    DieSlotMode.specific => Icons.hexagon,
    DieSlotMode.open => Icons.schedule,
  };

  SlotTone get tone => switch (this) {
    DieSlotMode.none => SlotTone.absent,
    DieSlotMode.specific => SlotTone.bound,
    DieSlotMode.open => SlotTone.deferred,
  };
}

// ---------------------------------------------------------------------------
// Loss — scrap and rejection are not the same thing
// ---------------------------------------------------------------------------

/// Scrap is material that comes off and keeps value; it is weighed back into a
/// Scrap item. A rejection is a piece that came out wrong; it is counted, and
/// it goes to rework, quarantine or the bin. Routing them to the same place
/// would put bad pieces into a material balance.
enum LossKind { scrap, rejection }

extension LossKindInfo on LossKind {
  String get label => switch (this) {
    LossKind.scrap => 'Scrap',
    LossKind.rejection => 'Rejection',
  };

  /// Where a fresh route starts. Only a default — a rejection is often counted
  /// in gross, and trim off a reel is sometimes measured in running metres, so
  /// the unit is the operator's to change.
  String get defaultUnitId => switch (this) {
    LossKind.scrap => 'kg',
    LossKind.rejection => 'pcs',
  };

  IconData get icon => switch (this) {
    LossKind.scrap => Icons.recycling,
    LossKind.rejection => Icons.thumb_down_alt_outlined,
  };
}

/// Where a rejection goes. Fixed set — these are the only honest answers.
enum RejectionRoute { rework, quarantine, writeOff }

extension RejectionRouteInfo on RejectionRoute {
  String get label => switch (this) {
    RejectionRoute.rework => 'Rework',
    RejectionRoute.quarantine => 'Quarantine',
    RejectionRoute.writeOff => 'Write off',
  };

  String get detail => switch (this) {
    RejectionRoute.rework => 'back through this node',
    RejectionRoute.quarantine => 'held for QC',
    RejectionRoute.writeOff => 'leaves the books',
  };
}

/// One way loss leaves this node. A node can have several — the same cut often
/// yields brass and aluminium off one sheet.
class LossRoute {
  const LossRoute({
    required this.id,
    required this.kind,
    this.scrapItemId,
    this.rejection,
    this.unitId,
  });

  final String id;
  final LossKind kind;

  /// Set when [kind] is [LossKind.scrap] — an item in the Scrap item group.
  final String? scrapItemId;

  /// Set when [kind] is [LossKind.rejection].
  final RejectionRoute? rejection;

  /// Null means "whatever this kind defaults to", so seed data and kind
  /// switches do not have to restate the obvious.
  final String? unitId;

  String get effectiveUnitId => unitId ?? kind.defaultUnitId;

  CatalogUnit? get unit => NodeConfiguratorCatalog.unitById(effectiveUnitId);

  String get unitSymbol => unit?.symbol ?? effectiveUnitId;

  bool get isComplete => switch (kind) {
    LossKind.scrap => scrapItemId != null,
    LossKind.rejection => rejection != null,
  };

  String get destinationLabel {
    switch (kind) {
      case LossKind.scrap:
        return NodeConfiguratorCatalog.scrapItemById(scrapItemId)?.name ??
            'Not routed';
      case LossKind.rejection:
        return rejection?.label ?? 'Not routed';
    }
  }

  LossRoute copyWith({
    LossKind? kind,
    Object? scrapItemId = _unset,
    Object? rejection = _unset,
    Object? unitId = _unset,
  }) {
    return LossRoute(
      id: id,
      kind: kind ?? this.kind,
      scrapItemId: scrapItemId == _unset
          ? this.scrapItemId
          : scrapItemId as String?,
      rejection: rejection == _unset
          ? this.rejection
          : rejection as RejectionRoute?,
      unitId: unitId == _unset ? this.unitId : unitId as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Catalogue stand-ins
// ---------------------------------------------------------------------------

class CatalogMachineGroup {
  const CatalogMachineGroup({required this.id, required this.name});

  final String id;
  final String name;
}

class CatalogMachine {
  const CatalogMachine({
    required this.id,
    required this.name,
    required this.assetCode,
    required this.groupId,
  });

  final String id;
  final String name;
  final String assetCode;
  final String groupId;
}

class CatalogDie {
  const CatalogDie({
    required this.id,
    required this.name,
    required this.toolCode,
    required this.compatibleGroupIds,
  });

  final String id;
  final String name;
  final String toolCode;

  /// Mirrors `Die.compatibleMachineGroupIds` — the one rule that ties the
  /// machine and die slots together.
  final List<String> compatibleGroupIds;
}

/// Mirrors the `unit_groups` in unitSystem_grouping.json. Conversion inside a
/// family is a fixed factor; across families it is not (pcs to kg needs a
/// per-piece weight), which is why the family is shown when picking.
enum UnitFamily { mass, quantity, length }

extension UnitFamilyInfo on UnitFamily {
  String get label => switch (this) {
    UnitFamily.mass => 'Mass',
    UnitFamily.quantity => 'Quantity',
    UnitFamily.length => 'Length',
  };
}

class CatalogUnit {
  const CatalogUnit({
    required this.id,
    required this.symbol,
    required this.name,
    required this.family,
  });

  final String id;
  final String symbol;
  final String name;
  final UnitFamily family;
}

/// An item in the "Scrap" item group — what `ProcessNode.scrapItems` points at.
class CatalogScrapItem {
  const CatalogScrapItem({required this.id, required this.name});

  final String id;
  final String name;
}

// ---------------------------------------------------------------------------
// The blueprint
// ---------------------------------------------------------------------------

const Object _unset = Object();

class NodeBlueprint {
  const NodeBlueprint({
    required this.id,
    required this.name,
    required this.processType,
    required this.machineMode,
    required this.dieMode,
    this.machineId,
    this.machineGroupId,
    this.dieId,
    this.lossRoutes = const <LossRoute>[],
    this.notes = '',
  });

  final String id;
  final String name;
  final String processType;

  final MachineSlotMode machineMode;
  final String? machineId;
  final String? machineGroupId;

  final DieSlotMode dieMode;
  final String? dieId;

  final List<LossRoute> lossRoutes;
  final String notes;

  NodeBlueprint copyWith({
    String? id,
    String? name,
    String? processType,
    MachineSlotMode? machineMode,
    Object? machineId = _unset,
    Object? machineGroupId = _unset,
    DieSlotMode? dieMode,
    Object? dieId = _unset,
    List<LossRoute>? lossRoutes,
    String? notes,
  }) {
    return NodeBlueprint(
      id: id ?? this.id,
      name: name ?? this.name,
      processType: processType ?? this.processType,
      machineMode: machineMode ?? this.machineMode,
      machineId: machineId == _unset ? this.machineId : machineId as String?,
      machineGroupId: machineGroupId == _unset
          ? this.machineGroupId
          : machineGroupId as String?,
      dieMode: dieMode ?? this.dieMode,
      dieId: dieId == _unset ? this.dieId : dieId as String?,
      lossRoutes: lossRoutes ?? this.lossRoutes,
      notes: notes ?? this.notes,
    );
  }
}

// ---------------------------------------------------------------------------
// Sample catalogue
// ---------------------------------------------------------------------------

class NodeConfiguratorCatalog {
  const NodeConfiguratorCatalog._();

  static const List<CatalogMachineGroup> machineGroups = [
    CatalogMachineGroup(id: 'mg_slit', name: 'Slitters'),
    CatalogMachineGroup(id: 'mg_press', name: 'Presses'),
    CatalogMachineGroup(id: 'mg_print', name: 'Printers'),
    CatalogMachineGroup(id: 'mg_punch', name: 'Punching'),
    CatalogMachineGroup(id: 'mg_wind', name: 'Winders'),
  ];

  static const List<CatalogMachine> machines = [
    CatalogMachine(id: 'm_sl01', name: 'Slitter', assetCode: 'SL-01', groupId: 'mg_slit'),
    CatalogMachine(id: 'm_sl02', name: 'Slitter', assetCode: 'SL-02', groupId: 'mg_slit'),
    CatalogMachine(id: 'm_pr04', name: 'Hydraulic Press', assetCode: 'PR-04', groupId: 'mg_press'),
    CatalogMachine(id: 'm_pr05', name: 'Hydraulic Press', assetCode: 'PR-05', groupId: 'mg_press'),
    CatalogMachine(id: 'm_fp02', name: 'Flexo Printer', assetCode: 'FP-02', groupId: 'mg_print'),
    CatalogMachine(id: 'm_pn07', name: 'Punch', assetCode: 'PN-07', groupId: 'mg_punch'),
    CatalogMachine(id: 'm_pn08', name: 'Punch', assetCode: 'PN-08', groupId: 'mg_punch'),
    CatalogMachine(id: 'm_wd10', name: 'Winder', assetCode: 'WD-10', groupId: 'mg_wind'),
  ];

  static const List<CatalogDie> dies = [
    CatalogDie(id: 'd_c90', name: 'Cone 90mm', toolCode: 'D-C90', compatibleGroupIds: ['mg_punch']),
    CatalogDie(id: 'd_c120', name: 'Cone 120mm', toolCode: 'D-C120', compatibleGroupIds: ['mg_punch']),
    CatalogDie(id: 'd_handle', name: 'Handle Cut', toolCode: 'D-HDL', compatibleGroupIds: ['mg_press']),
    CatalogDie(id: 'd_r60', name: 'Round Punch 60', toolCode: 'D-R60', compatibleGroupIds: ['mg_punch', 'mg_press']),
    CatalogDie(id: 'd_emboss', name: 'Emboss Plate', toolCode: 'D-EMB', compatibleGroupIds: ['mg_press']),
  ];

  static const List<CatalogScrapItem> scrapItems = [
    CatalogScrapItem(id: 'sc_brass', name: 'Brass Trim'),
    CatalogScrapItem(id: 'sc_alu', name: 'Aluminium Offcut'),
    CatalogScrapItem(id: 'sc_paper', name: 'Paper Waste'),
    CatalogScrapItem(id: 'sc_mixed', name: 'Mixed Waste'),
  ];

  static const List<CatalogUnit> units = [
    CatalogUnit(id: 'g', symbol: 'g', name: 'Gram', family: UnitFamily.mass),
    CatalogUnit(id: 'kg', symbol: 'kg', name: 'Kilogram', family: UnitFamily.mass),
    CatalogUnit(id: 'tonne', symbol: 't', name: 'Tonne', family: UnitFamily.mass),
    CatalogUnit(id: 'pcs', symbol: 'pcs', name: 'Pieces', family: UnitFamily.quantity),
    CatalogUnit(id: 'dozen', symbol: 'dozen', name: 'Dozen — 12', family: UnitFamily.quantity),
    CatalogUnit(id: 'gross', symbol: 'gross', name: 'Gross — 144', family: UnitFamily.quantity),
    CatalogUnit(id: 'mm', symbol: 'mm', name: 'Millimetre', family: UnitFamily.length),
    CatalogUnit(id: 'm', symbol: 'm', name: 'Metre', family: UnitFamily.length),
    CatalogUnit(id: 'inch', symbol: 'in', name: 'Inch', family: UnitFamily.length),
  ];

  static const List<String> processTypes = [
    'Slitting',
    'Printing',
    'Punching',
    'Pressing',
    'Pasting',
    'Winding',
    'Inspection',
    'Packing',
  ];

  static CatalogMachine? machineById(String? id) {
    if (id == null) return null;
    for (final machine in machines) {
      if (machine.id == id) return machine;
    }
    return null;
  }

  static CatalogMachineGroup? groupById(String? id) {
    if (id == null) return null;
    for (final group in machineGroups) {
      if (group.id == id) return group;
    }
    return null;
  }

  static CatalogDie? dieById(String? id) {
    if (id == null) return null;
    for (final die in dies) {
      if (die.id == id) return die;
    }
    return null;
  }

  static CatalogScrapItem? scrapItemById(String? id) {
    if (id == null) return null;
    for (final item in scrapItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  static CatalogUnit? unitById(String? id) {
    if (id == null) return null;
    for (final unit in units) {
      if (unit.id == id) return unit;
    }
    return null;
  }

  static List<CatalogUnit> unitsIn(UnitFamily family) {
    return units.where((unit) => unit.family == family).toList(growable: false);
  }

  static List<CatalogDie> diesForGroup(String groupId) {
    return dies
        .where((die) => die.compatibleGroupIds.contains(groupId))
        .toList(growable: false);
  }

  /// Covers every mode pair worth arguing about, including the two that used to
  /// be indistinguishable — "no die" and "die not assigned".
  static List<NodeBlueprint> seedLibrary() => [
    const NodeBlueprint(
      id: 'nb_slit',
      name: 'Reel Slitting',
      processType: 'Slitting',
      machineMode: MachineSlotMode.group,
      machineGroupId: 'mg_slit',
      dieMode: DieSlotMode.none,
      lossRoutes: [
        LossRoute(id: 'l1', kind: LossKind.scrap, scrapItemId: 'sc_paper'),
      ],
      notes: 'Either slitter takes it. Whoever is free first.',
    ),
    const NodeBlueprint(
      id: 'nb_punch90',
      name: 'Cone Punching — 90mm',
      processType: 'Punching',
      machineMode: MachineSlotMode.specific,
      machineId: 'm_pn07',
      dieMode: DieSlotMode.specific,
      dieId: 'd_c90',
      lossRoutes: [
        LossRoute(id: 'l1', kind: LossKind.scrap, scrapItemId: 'sc_brass'),
        LossRoute(id: 'l2', kind: LossKind.scrap, scrapItemId: 'sc_alu'),
        LossRoute(
          id: 'l3',
          kind: LossKind.rejection,
          rejection: RejectionRoute.rework,
          unitId: 'gross',
        ),
      ],
      notes: 'The 90mm die stays mounted on PN-07. Do not move it.',
    ),
    const NodeBlueprint(
      id: 'nb_punch_any',
      name: 'Cone Punching — Any Size',
      processType: 'Punching',
      machineMode: MachineSlotMode.group,
      machineGroupId: 'mg_punch',
      dieMode: DieSlotMode.open,
      lossRoutes: [
        LossRoute(id: 'l1', kind: LossKind.scrap, scrapItemId: 'sc_brass'),
      ],
      notes: 'One node for the whole cone range. Size comes from the order.',
    ),
    const NodeBlueprint(
      id: 'nb_sort',
      name: 'Hand Sorting',
      processType: 'Inspection',
      machineMode: MachineSlotMode.none,
      dieMode: DieSlotMode.none,
      lossRoutes: [
        LossRoute(
          id: 'l1',
          kind: LossKind.rejection,
          rejection: RejectionRoute.quarantine,
        ),
      ],
      notes: 'Table work. Books no asset and blocks no queue.',
    ),
    const NodeBlueprint(
      id: 'nb_print',
      name: 'Flexo Printing',
      processType: 'Printing',
      machineMode: MachineSlotMode.specific,
      machineId: 'm_fp02',
      dieMode: DieSlotMode.none,
      lossRoutes: [
        LossRoute(
          id: 'l1',
          kind: LossKind.rejection,
          rejection: RejectionRoute.writeOff,
        ),
      ],
      notes: 'Only FP-02 holds the registration we need.',
    ),
    const NodeBlueprint(
      id: 'nb_press',
      name: 'Handle Press Cut',
      processType: 'Pressing',
      machineMode: MachineSlotMode.open,
      dieMode: DieSlotMode.specific,
      dieId: 'd_handle',
      notes: 'Die is fixed, press is not — the die itself fences the choice.',
    ),
  ];
}

// ---------------------------------------------------------------------------
// Run-time prompts — what the node still owes the operator
// ---------------------------------------------------------------------------

enum PromptKind { constrained, open }

class RuntimePrompt {
  const RuntimePrompt({
    required this.slot,
    required this.detail,
    required this.kind,
  });

  final String slot;
  final String detail;
  final PromptKind kind;
}

// ---------------------------------------------------------------------------
// Binding rules
// ---------------------------------------------------------------------------

enum IssueLevel { error, warning, info }

class BindingIssue {
  const BindingIssue({required this.level, required this.message});

  final IssueLevel level;
  final String message;
}

class NodeBindingRules {
  const NodeBindingRules._();

  static String machineSummary(NodeBlueprint blueprint) {
    switch (blueprint.machineMode) {
      case MachineSlotMode.none:
        return 'No machine';
      case MachineSlotMode.specific:
        final machine = NodeConfiguratorCatalog.machineById(blueprint.machineId);
        return machine == null
            ? 'Not picked'
            : '${machine.assetCode} · ${machine.name}';
      case MachineSlotMode.group:
        final group = NodeConfiguratorCatalog.groupById(blueprint.machineGroupId);
        return group == null ? 'Not picked' : 'Any ${group.name}';
      case MachineSlotMode.open:
        return 'At run time';
    }
  }

  static String dieSummary(NodeBlueprint blueprint) {
    switch (blueprint.dieMode) {
      case DieSlotMode.none:
        return 'No die';
      case DieSlotMode.specific:
        final die = NodeConfiguratorCatalog.dieById(blueprint.dieId);
        return die == null ? 'Not picked' : '${die.toolCode} · ${die.name}';
      case DieSlotMode.open:
        return 'At run time';
    }
  }

  static String lossSummary(NodeBlueprint blueprint) {
    final routes = blueprint.lossRoutes;
    if (routes.isEmpty) return 'Nothing routed';
    if (routes.any((route) => !route.isComplete)) return 'Route incomplete';
    if (routes.length == 1) return routes.single.destinationLabel;

    final scrap = routes.where((r) => r.kind == LossKind.scrap).length;
    final rejects = routes.length - scrap;
    if (rejects == 0) return '$scrap scrap items';
    if (scrap == 0) return '$rejects rejection routes';
    return '$scrap scrap · $rejects rejection';
  }

  static SlotTone lossTone(NodeBlueprint blueprint) {
    if (blueprint.lossRoutes.isEmpty) return SlotTone.absent;
    if (blueprint.lossRoutes.any((route) => !route.isComplete)) {
      return SlotTone.deferred;
    }
    return SlotTone.bound;
  }

  /// The groups a run-time machine may come from, given a pinned die.
  static List<CatalogMachineGroup> groupsAllowedByDie(NodeBlueprint blueprint) {
    if (blueprint.dieMode != DieSlotMode.specific) return const [];
    final die = NodeConfiguratorCatalog.dieById(blueprint.dieId);
    if (die == null) return const [];
    return NodeConfiguratorCatalog.machineGroups
        .where((group) => die.compatibleGroupIds.contains(group.id))
        .toList(growable: false);
  }

  /// The group both slots are effectively bound to, if any.
  static String? boundGroupId(NodeBlueprint blueprint) {
    if (blueprint.machineMode == MachineSlotMode.group) {
      return blueprint.machineGroupId;
    }
    if (blueprint.machineMode == MachineSlotMode.specific) {
      return NodeConfiguratorCatalog.machineById(blueprint.machineId)?.groupId;
    }
    return null;
  }

  /// Everything the node will ask a human for before it can run.
  static List<RuntimePrompt> runtimePrompts(NodeBlueprint blueprint) {
    final prompts = <RuntimePrompt>[];

    switch (blueprint.machineMode) {
      case MachineSlotMode.group:
        final group = NodeConfiguratorCatalog.groupById(blueprint.machineGroupId);
        final count = group == null
            ? 0
            : NodeConfiguratorCatalog.machines
                  .where((machine) => machine.groupId == group.id)
                  .length;
        prompts.add(
          RuntimePrompt(
            slot: 'Machine',
            detail: group == null
                ? 'group not picked'
                : 'one of $count in ${group.name}',
            kind: PromptKind.constrained,
          ),
        );
      case MachineSlotMode.open:
        final allowed = groupsAllowedByDie(blueprint);
        prompts.add(
          RuntimePrompt(
            slot: 'Machine',
            detail: allowed.isEmpty
                ? 'anything on the floor'
                : '${allowed.map((group) => group.name).join(' or ')} — the die says so',
            kind: PromptKind.open,
          ),
        );
      case MachineSlotMode.none:
      case MachineSlotMode.specific:
        break;
    }

    if (blueprint.dieMode == DieSlotMode.open) {
      final groupId = boundGroupId(blueprint);
      final group = NodeConfiguratorCatalog.groupById(groupId);
      prompts.add(
        RuntimePrompt(
          slot: 'Die',
          detail: group == null
              ? 'any of ${NodeConfiguratorCatalog.dies.length}'
              : 'one of ${NodeConfiguratorCatalog.diesForGroup(groupId!).length} that fit ${group.name}',
          kind: group == null ? PromptKind.open : PromptKind.constrained,
        ),
      );
    }

    return prompts;
  }

  /// Live validation. Errors block saving.
  static List<BindingIssue> validate(NodeBlueprint blueprint) {
    final issues = <BindingIssue>[];

    if (blueprint.name.trim().isEmpty) {
      issues.add(
        const BindingIssue(
          level: IssueLevel.error,
          message: 'Give the node a name.',
        ),
      );
    }

    // Half-made slots: a mode was chosen but its subject was not.
    if (blueprint.machineMode == MachineSlotMode.specific &&
        NodeConfiguratorCatalog.machineById(blueprint.machineId) == null) {
      issues.add(
        const BindingIssue(
          level: IssueLevel.error,
          message: 'Pick the machine.',
        ),
      );
    }
    if (blueprint.machineMode == MachineSlotMode.group &&
        NodeConfiguratorCatalog.groupById(blueprint.machineGroupId) == null) {
      issues.add(
        const BindingIssue(level: IssueLevel.error, message: 'Pick the group.'),
      );
    }
    if (blueprint.dieMode == DieSlotMode.specific &&
        NodeConfiguratorCatalog.dieById(blueprint.dieId) == null) {
      issues.add(
        const BindingIssue(level: IssueLevel.error, message: 'Pick the die.'),
      );
    }

    // The cross-slot rule: a die only mounts in the groups it fits.
    final die = blueprint.dieMode == DieSlotMode.specific
        ? NodeConfiguratorCatalog.dieById(blueprint.dieId)
        : null;

    if (die != null && blueprint.machineMode == MachineSlotMode.specific) {
      final machine = NodeConfiguratorCatalog.machineById(blueprint.machineId);
      if (machine != null && !die.compatibleGroupIds.contains(machine.groupId)) {
        final group = NodeConfiguratorCatalog.groupById(machine.groupId);
        issues.add(
          BindingIssue(
            level: IssueLevel.error,
            message:
                '${die.name} does not mount in ${machine.assetCode} — that is '
                'a ${group?.name ?? 'different group'}.',
          ),
        );
      }
    }

    if (die != null && blueprint.machineMode == MachineSlotMode.group) {
      final groupId = blueprint.machineGroupId;
      if (groupId != null && !die.compatibleGroupIds.contains(groupId)) {
        final group = NodeConfiguratorCatalog.groupById(groupId);
        issues.add(
          BindingIssue(
            level: IssueLevel.error,
            message:
                '${die.name} does not fit ${group?.name ?? 'that group'}.',
          ),
        );
      }
    }

    if (die != null && blueprint.machineMode == MachineSlotMode.none) {
      issues.add(
        BindingIssue(
          level: IssueLevel.warning,
          message: '${die.name} has no machine to mount in.',
        ),
      );
    }

    if (blueprint.dieMode == DieSlotMode.open) {
      final groupId = boundGroupId(blueprint);
      if (groupId != null &&
          NodeConfiguratorCatalog.diesForGroup(groupId).isEmpty) {
        final group = NodeConfiguratorCatalog.groupById(groupId);
        issues.add(
          BindingIssue(
            level: IssueLevel.error,
            message:
                'No die fits ${group?.name ?? 'that group'} — nothing to pick.',
          ),
        );
      }
    }

    // Loss routes.
    for (final route in blueprint.lossRoutes) {
      if (!route.isComplete) {
        issues.add(
          BindingIssue(
            level: IssueLevel.error,
            message: 'A ${route.kind.label.toLowerCase()} route has no '
                'destination.',
          ),
        );
        break;
      }
    }

    final scrapDestinations = blueprint.lossRoutes
        .where((route) => route.kind == LossKind.scrap)
        .map((route) => route.scrapItemId)
        .toList();
    if (scrapDestinations.length != scrapDestinations.toSet().length) {
      issues.add(
        const BindingIssue(
          level: IssueLevel.error,
          message: 'Two scrap routes point at the same item.',
        ),
      );
    }

    return issues;
  }

  static bool isSaveable(NodeBlueprint blueprint) {
    return !validate(
      blueprint,
    ).any((issue) => issue.level == IssueLevel.error);
  }
}
