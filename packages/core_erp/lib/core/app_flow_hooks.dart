import 'package:flutter/widgets.dart';

/// Flows that live in the app shell but are needed from inside shared dialogs.
///
/// Creating a pipeline means pushing the pipeline builder, which the app owns
/// and this package cannot import. Without a way back to it, a dialog can offer
/// "create item" but the item it creates arrives with no way to give it a
/// pipeline — a dead end exactly where someone entering a factory's books needs
/// to keep going.
///
/// The app registers these once at startup; anything unset is simply not
/// offered, so a host that does not provide a flow degrades to hiding it.
/// What an embedded editor hands back on save: enough to list the record in
/// a host without the host knowing its type.
class CreatedRecord {
  const CreatedRecord({required this.id, required this.title, this.subtitle});

  final String id;
  final String title;
  final String? subtitle;
}

/// Builds a full editor for a host to embed rather than open as a route.
/// [onSaved] gets the saved record; [onCancel] replaces closing.
typedef EmbeddedEditorBuilder =
    Widget Function(
      BuildContext context, {
      required ValueChanged<CreatedRecord> onSaved,
      required VoidCallback onCancel,
    });

/// A die as the sheet beside a part describes it.
///
/// Every field is what someone typed into the wizard; the host turns it into
/// whatever its own Die type needs. This package cannot see that type — `Die`
/// lives in the app, not here — which is the whole reason this seam exists.
class DieSheetDraft {
  const DieSheetDraft({
    this.dieId,
    required this.toolCode,
    required this.dieType,
    this.dieTypeLabel = '',
    this.madeBy = '',
    this.dieMakerId,
    this.poAt,
    this.dateInAt,
    this.linerSizeNm,
    this.linerSizeUnit = 'mm',
    this.noOfSet,
    this.storeArea = '',
    this.rackNo = '',
    this.partCode = '',
    this.partName = '',
  });

  /// The die being corrected, or null to make a new one. A part holds several
  /// dies, so editing one has to say WHICH — and the same seam does both
  /// because the route behind it is an upsert.
  final String? dieId;

  /// Already derived or typed over, never empty.
  final String toolCode;

  /// `cutting` | `bending`, or a slug the shop's own words were reduced to.
  final String dieType;

  /// The words, for a type that was typed rather than picked. Empty for the
  /// four built-ins, whose label is looked up from the slug on both sides.
  /// Without it a typed type derives no code at all.
  final String dieTypeLabel;

  /// Who made it, as text. Survives beside [dieMakerId] rather than being
  /// replaced by it: every die made before the master has a name and no id.
  final String madeBy;

  /// The die maker master row, when the name resolved to one.
  final int? dieMakerId;

  /// UTC instants: when the die was ordered, and when it came into store.
  final DateTime? poAt;
  final DateTime? dateInAt;

  /// An integer count of nanometres — the base the units contract requires,
  /// and small enough that thou and SWG land on it exactly.
  final int? linerSizeNm;

  /// How that size was read. Display only; it never enters arithmetic.
  final String linerSizeUnit;
  final int? noOfSet;
  final String storeArea;
  final String rackNo;

  /// The part this die was made for. Sent so the server can derive the code
  /// the same way, and so the host can name the die after the part — not as a
  /// second link, which is `item_dies`.
  final String partCode;
  final String partName;

  Map<String, dynamic> toJson() => {
    if (dieId != null) 'id': dieId,
    'toolCode': toolCode,
    'dieType': dieType,
    'dieTypeLabel': dieTypeLabel,
    'madeBy': madeBy,
    'dieMakerId': dieMakerId,
    'poAt': poAt?.toUtc().toIso8601String(),
    'dateInAt': dateInAt?.toUtc().toIso8601String(),
    'linerSizeNm': linerSizeNm,
    'linerSizeUnit': linerSizeUnit,
    'noOfSet': noOfSet,
    'storeArea': storeArea,
    'rackNo': rackNo,
    'partCode': partCode,
  };
}

/// What came back from writing one.
///
/// A bare null could not tell a taken code from a dead network, and the two
/// need different answers — the same reason `ItemsProvider` carries an
/// `errorCode` beside its message.
class DieCreateOutcome {
  const DieCreateOutcome.created(CreatedRecord this.record)
    : message = null,
      code = null,
      suggestedToolCode = null;

  const DieCreateOutcome.failed({
    required this.message,
    this.code,
    this.suggestedToolCode,
  }) : record = null;

  final CreatedRecord? record;
  final String? message;

  /// `die_tool_code_duplicate` when the code is taken.
  final String? code;

  /// The first free code in the series, when the server offered one.
  final String? suggestedToolCode;

  bool get isCreated => record != null;
}

/// A machine as the "Machine in Plant" sheet beside a part describes it.
///
/// Every field is what someone typed into the wizard; the host turns it into
/// whatever its own Machine type needs. This package cannot see that type —
/// `Machine` lives in the app, not here — which is why this seam exists.
class MachineSheetDraft {
  const MachineSheetDraft({
    this.machineId,
    required this.assetId,
    required this.name,
    this.groupId,
    this.machineMake = '',
    this.manufacturedYear,
    this.feederMake = '',
    this.runningHours,
    this.strokesPerMinute,
    this.capacityKind = '',
    this.capacityKgf,
    this.dieFeedType = '',
  });

  /// The machine being corrected, or null to add one. A part runs on several,
  /// so editing one has to say WHICH — and the same seam does both because the
  /// route behind it is an upsert.
  final String? machineId;

  /// The Machine No. Already suggested or typed over, never empty.
  final String assetId;

  /// What it is called. Falls back to the number when nobody named it, because
  /// a machine with no name reads as blank throughout its own master.
  final String name;

  /// The machine group — Power Press, Punching M — which is the same list a
  /// die declares itself compatible with.
  final int? groupId;

  final String machineMake;

  /// A year, not a date: a press everyone knows was built in 2011 has one
  /// fact, and a stored 2011-01-01 would print a day nobody recorded.
  final int? manufacturedYear;

  /// The make of the feeder attached to it. Not the pipeline sense of the
  /// word, which is an upstream node in a graph.
  final String feederMake;

  final int? runningHours;
  final int? strokesPerMinute;

  /// `''` | `rated` | `free_hand`. Stored rather than inferred: a bench with
  /// no rated tonnage is a fact, and a blank is the absence of one.
  final String capacityKind;

  /// An integer count of kilograms-force — the base the units contract
  /// requires, and one that Ton and kgf both land on exactly.
  final int? capacityKgf;

  /// What tooling it takes. NOT a die's own type.
  final String dieFeedType;

  Map<String, dynamic> toJson() => {
    if (machineId != null) 'id': machineId,
    'assetId': assetId,
    'name': name,
    'groupId': groupId,
    'machineMake': machineMake,
    'manufacturedYear': manufacturedYear,
    'feederMake': feederMake,
    'runningHours': runningHours,
    'strokesPerMinute': strokesPerMinute,
    'capacityKind': capacityKind,
    'capacityKgf': capacityKgf,
    'dieFeedType': dieFeedType,
  };
}

/// What came back from writing one.
class MachineCreateOutcome {
  const MachineCreateOutcome.created(CreatedRecord this.record)
    : message = null,
      code = null,
      suggestedAssetId = null;

  const MachineCreateOutcome.failed({
    required this.message,
    this.code,
    this.suggestedAssetId,
  }) : record = null;

  final CreatedRecord? record;
  final String? message;

  /// `machine_asset_id_duplicate` when the number is taken.
  final String? code;

  /// The next free number in the series, when the server offered one.
  final String? suggestedAssetId;

  bool get isCreated => record != null;
}

/// The three free-text columns' existing answers, for their suggestion chips.
///
/// One hook rather than three: the host makes them in one pass over the
/// machines it has already loaded, and three round trips to say the same thing
/// would be three chances to forget one.
class MachineSheetSuggestions {
  const MachineSheetSuggestions({
    this.makes = const <String>[],
    this.feederMakes = const <String>[],
    this.dieFeedTypes = const <String>[],
    this.names = const <String>[],
    this.years = const <String>[],
    this.runningHours = const <String>[],
    this.strokesPerMinute = const <String>[],
    this.capacitiesKgf = const <int>[],
  });

  final List<String> makes;
  final List<String> feederMakes;
  final List<String> dieFeedTypes;

  /// Every other field on the sheet is a dropdown of what was used before,
  /// too — the same answers recur across a shop's machines.
  final List<String> names;
  final List<String> years;
  final List<String> runningHours;
  final List<String> strokesPerMinute;

  /// Rated capacities in kgf; the sheet shows them in whichever unit is picked.
  final List<int> capacitiesKgf;
}

/// The die sheet's answers from every die already in the master, for its
/// dropdowns — and the codes those dies hold, so a new die is offered a free
/// one before the server has to refuse it.
class DieSheetSuggestions {
  const DieSheetSuggestions({
    this.madeBy = const <String>[],
    this.storeAreas = const <String>[],
    this.rackNos = const <String>[],
    this.noOfSets = const <String>[],
    this.linerSizesNm = const <int>[],
    this.typedTypes = const <({String slug, String label})>[],
    this.toolCodes = const <String>{},
  });

  final List<String> madeBy;
  final List<String> storeAreas;
  final List<String> rackNos;
  final List<String> noOfSets;

  /// Liner sizes in whole nanometres; the sheet shows them in whichever unit
  /// is picked.
  final List<int> linerSizesNm;

  /// Die types the shop typed rather than picked, so they can be picked next
  /// time. The four built-ins are never in here.
  final List<({String slug, String label})> typedTypes;

  /// Every die code in the factory, upper-cased. `dies.tool_code` is unique
  /// across all of them, not just one part's.
  final Set<String> toolCodes;
}

class AppFlowHooks {
  const AppFlowHooks._();

  /// Writes one row in the machines master from a part's machine sheet — a new
  /// one, or the one [MachineSheetDraft.machineId] names.
  ///
  /// Deliberately does NOT link it to anything: the item side of that lives in
  /// this package, where ItemsProvider is.
  static Future<MachineCreateOutcome> Function(
    BuildContext context,
    MachineSheetDraft draft,
  )?
  createMachineFromSheet;

  /// What has been typed into the sheet's free-text columns before.
  static Future<MachineSheetSuggestions> Function(BuildContext context)?
  machineSheetSuggestions;

  static bool get canCreateMachineFromSheet => createMachineFromSheet != null;

  /// Writes one row in the dies master from a part's die sheet — a new one, or
  /// the one [DieSheetDraft.dieId] names.
  ///
  /// Deliberately does NOT link it to anything: the item side of that lives in
  /// this package, where ItemsProvider is.
  static Future<DieCreateOutcome> Function(
    BuildContext context,
    DieSheetDraft draft,
  )?
  createDieFromSheet;

  /// What has been typed into the die sheet before, newest first. Unset means
  /// no suggestions — every field is free text either way.
  static Future<DieSheetSuggestions> Function(BuildContext context)?
  dieSheetSuggestions;

  static bool get canCreateDieFromSheet => createDieFromSheet != null;

  /// Opens the pipeline builder and resolves to the saved template id, or null
  /// if the user backed out.
  static Future<String?> Function(BuildContext context)? createPipeline;

  /// Opens the machine editor; resolves true when one was saved. Typed as a
  /// bool rather than a Machine so this package need not know that type.
  static Future<bool> Function(BuildContext context)? createMachine;

  /// Deletes a machine permanently.
  static Future<void> Function(BuildContext context, String machineId)?
  deleteMachine;

  /// Opens the die editor; resolves true when one was saved.
  static Future<bool> Function(BuildContext context)? createDie;

  /// Deletes a die permanently.
  static Future<void> Function(BuildContext context, String dieId)? deleteDie;

  /// Builds the full die editor for a host to embed rather than open as a
  /// route.
  static EmbeddedEditorBuilder? dieEditor;

  /// Builds the full machine editor for embedding; same contract as
  /// [dieEditor].
  static EmbeddedEditorBuilder? machineEditor;

  /// Builds a **read-only** inspector for one die, by id.
  ///
  /// Why a hook rather than a widget in this package: a die's specs — tool
  /// code, rack, cavities, strokes — live on the host app's `Die` type, which
  /// `core_erp` deliberately cannot see. The ecosystem ribbon can name a die
  /// from the link graph alone, but it cannot show what the die IS.
  ///
  /// Read-only on purpose. Walking the graph to look at a neighbour must not
  /// become a chance to change it by accident, which is what opening the editor
  /// would make it; each inspector offers its own explicit Edit instead.
  ///
  /// Unregistered means not offered, as with every hook here, so a chip whose
  /// inspector is missing simply does not open.
  static Widget Function(BuildContext context, String dieId)? dieInspector;

  /// The same, for one machine.
  static Widget Function(BuildContext context, String machineId)?
  machineInspector;

  /// The same, for one item (part).
  static Widget Function(BuildContext context, String itemId)?
  itemInspector;

  /// Whether a read-only inspector exists for this link type.
  static bool canInspect(String type) => switch (type) {
    'die' => dieInspector != null,
    'machine' => machineInspector != null,
    'item' => itemInspector != null,
    _ => false,
  };

  /// The inspector for a link type, or null when the host provides none.
  static Widget? inspectorFor(BuildContext context, String type, String id) =>
      switch (type) {
        'die' => dieInspector?.call(context, id),
        'machine' => machineInspector?.call(context, id),
        'item' => itemInspector?.call(context, id),
        _ => null,
      };

  static bool get canCreatePipeline => createPipeline != null;

  static Future<bool> Function()? createMachineFor(BuildContext context) {
    final handler = createMachine;
    if (handler == null) return null;
    return () => handler(context);
  }

  static Future<void> Function(String machineId)? deleteMachineFor(
    BuildContext context,
  ) {
    final handler = deleteMachine;
    if (handler == null) return null;
    return (id) => handler(context, id);
  }

  static Future<bool> Function()? createDieFor(BuildContext context) {
    final handler = createDie;
    if (handler == null) return null;
    return () => handler(context);
  }

  static Future<void> Function(String dieId)? deleteDieFor(
    BuildContext context,
  ) {
    final handler = deleteDie;
    if (handler == null) return null;
    return (id) => handler(context, id);
  }

  static Future<String?> Function()? createPipelineFor(BuildContext context) {
    final handler = createPipeline;
    if (handler == null) return null;
    return () => handler(context);
  }
}
