import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/company_documents.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../../../core/widgets/force_capacity_field.dart';
import '../../../../core/widgets/length_unit_field.dart';
import '../../../dies/domain/die_code.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../process_routes/data/process_route_service.dart';
import '../../../process_routes/domain/part_route.dart';
import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../../production_pipelines/presentation/widgets/raw_sheet_review.dart';
import '../../domain/developed_for.dart';
import '../../domain/item_definition.dart';
import '../../domain/sheet_property.dart';
import '../providers/items_provider.dart';
import '../providers/sheet_properties_provider.dart';

// Everything entered for a part on the item sheet, as plain text: the part,
// who it was made for, its dies and machines, its route and its raw sheet.
// The sheet is a by-product of production, and this is where it is read back.
//
// The die, machine and route lines are the same ones the sheet's folded
// sections show, so the two never say a thing two ways.

/// One line of a die, a machine or a route: a label and its value, or a
/// heading line (no label).
typedef ReportLine = (String? label, String value);

/// A die, line by line: its code first, then what was filled.
List<ReportLine> dieLines(ItemDieLink die, {bool held = false}) {
  final out = <ReportLine>[];
  void add(String? label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) out.add((label, text));
  }

  add(null, '${die.toolCode.isEmpty ? 'Die' : die.toolCode}${held ? ' (not saved yet)' : ''}');
  add('Type', DieTypeChoice.fromStored(die.dieType, die.dieTypeLabel)?.label);
  add('Made by', die.madeBy);
  add('Ordered', die.poAt == null ? null : partStamp(die.poAt!));
  add('Arrived', die.dateInAt == null ? null : partStamp(die.dateInAt!));
  add(
    'Liner',
    die.linerSizeNm == null
        ? null
        : '${formatLengthFromNanometres(die.linerSizeNm, die.linerSizeUnit)} ${die.linerSizeUnit}',
  );
  add('Sets', die.noOfSet);
  add('Kept', die.whereKept);
  return out;
}

/// A machine, line by line: its number first, then what was filled.
List<ReportLine> machineLines(ItemMachineLink machine, {bool held = false}) {
  final out = <ReportLine>[];
  void add(String? label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) out.add((label, text));
  }

  final number = machine.assetId.isNotEmpty ? machine.assetId : machine.name;
  add(null, '${number.isEmpty ? 'Machine' : number}${held ? ' (not saved yet)' : ''}');
  if (machine.assetId.isNotEmpty) add('Name', machine.name);
  add('Type', machine.machineType);
  add('Make', machine.machineMake);
  add(
    'Capacity',
    capacityLabel(CapacityKind.fromWire(machine.capacityKind), machine.capacityKgf, 'Ton'),
  );
  add('Strokes/min', machine.strokesPerMinute);
  add('Feed', machine.dieFeedType);
  add('Feeder', machine.feederMake);
  add('Built', machine.manufacturedYear);
  add('Running', machine.runningHours == null ? null : '${machine.runningHours} h');
  return out;
}

/// "Primary Group Brackets Patti PGBP1 pipeline v1 · Die → Shearing".
String routeLine(PartRoute route) =>
    '${route.title} v${route.version} · '
    '${route.steps.map((step) => step.stageName).join(' → ')}';

/// "Patti — PGBP1 · saved 03/11/2026 02.45 PM": the part, its code, and
/// when it was last saved.
String itemReportHeading(ItemDefinition item) {
  final name = item.displayName.trim().isEmpty ? item.name : item.displayName.trim();
  final code = item.partCode.trim();
  return [
    code.isEmpty ? name : '$name — $code',
    'saved ${partStamp(item.updatedAt)}',
  ].join(' · ');
}

/// The report, section by section. Pure: everything it says is handed in.
///
/// [groupPath] is "Group › Type". [propertyLabels] maps a property's stored
/// name to the label the sheet shows it under now (a renamed column keeps
/// its stored name). [documents] are the company's document titles.
List<RawSheetReviewSection> itemReportSections({
  required ItemDefinition item,
  String groupPath = '',
  Map<String, String> propertyLabels = const {},
  List<PartRoute> routes = const [],
  List<String> documents = const [],
}) {
  String said(String? value, [String otherwise = 'Not recorded']) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? otherwise : text;
  }

  final name = item.displayName.trim().isEmpty ? item.name : item.displayName.trim();
  final sections = <RawSheetReviewSection>[];

  // --- the part --------------------------------------------------------------
  final properties = <(String, String)>[
    for (final node in item.variationTree)
      if (node.kind == ItemVariationNodeKind.property && node.children.isNotEmpty)
        (
          propertyLabels[node.name.trim().toLowerCase()] ?? node.name,
          node.children.map((value) => value.displayName.isEmpty ? value.name : value.displayName).join(', '),
        ),
  ];
  sections.add(RawSheetReviewSection('Part', [
    ('Part', name),
    ('Part code', said(item.partCode, 'No code yet')),
    if (item.partNo != null) ('Part No', '${item.partNo}'),
    ('Filed under', said(groupPath, '—')),
    ...properties,
    ('Created', partStamp(item.createdAt)),
    ('Last saved', partStamp(item.updatedAt)),
  ]));

  // --- who it was made for -----------------------------------------------------
  final deal = item.developedFor;
  final company = deal.companyName.trim().isNotEmpty ? deal.companyName : deal.clientName;
  final people = deal.contacts.isNotEmpty
      ? [
          for (final person in deal.contacts)
            [
              person.name,
              person.designation,
              person.phone,
              person.email,
            ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(' · '),
        ]
      : [
          if (deal.contactName.trim().isNotEmpty)
            [deal.contactName, deal.designation, deal.phone, deal.email]
                .map((part) => part.trim())
                .where((part) => part.isNotEmpty)
                .join(' · '),
        ];
  sections.add(RawSheetReviewSection('Company', [
    if (deal.kind == DevelopedForKind.self && company.trim().isEmpty)
      ('Made for', 'Ourselves (in-house)')
    else if (deal.kind == DevelopedForKind.none && company.trim().isEmpty)
      ('Made for', 'No company recorded')
    else ...[
      ('Made for', said(company)),
      if (deal.kind == DevelopedForKind.contractor)
        ('Contractor', said(deal.subContractorName)),
    ],
    if (deal.quotationAmount != null) ('Quotation', rupeeStamp(deal.quotationAmount!)),
    if (deal.costAmount != null) ('Development cost', rupeeStamp(deal.costAmount!)),
    if (deal.at != null) ('Recorded', partStamp(deal.at!)),
    for (final person in people) ('Dealt with', person),
    if (documents.isNotEmpty) ('Documents', documents.join(', ')),
  ]));

  // --- dies and machines -------------------------------------------------------
  List<(String, String)> asRows(List<ReportLine> lines) => [
        for (final (label, value) in lines) (label ?? '', value),
      ];
  sections.add(RawSheetReviewSection(
    'Dies',
    item.dies.isEmpty
        ? const [('', 'No dies on this part')]
        : [for (final die in item.dies) ...asRows(dieLines(die))],
  ));
  sections.add(RawSheetReviewSection(
    'Machines',
    item.machines.isEmpty
        ? const [('', 'No machines on this part')]
        : [for (final machine in item.machines) ...asRows(machineLines(machine))],
  ));

  // --- the route: the pipeline at a glance --------------------------------------
  final route = routes.firstOrNull;
  sections.add(RawSheetReviewSection(
    'Route (pipeline)',
    route == null
        ? const [('', 'No route yet')]
        : [
            ('Pipeline', route.title),
            ('Version', 'v${route.version} · ${route.status.wire}'),
            (
              'Stages',
              route.steps.isEmpty
                  ? 'None'
                  : route.steps.map((step) => step.stageName).join(' → '),
            ),
            if (route.note.trim().isNotEmpty) ('Note', route.note.trim()),
          ],
  ));

  // --- the raw sheet ------------------------------------------------------------
  final baseline = item.penPaperBaseline;
  if (baseline == null) {
    sections.add(const RawSheetReviewSection('Raw sheet', [('', 'No raw sheet recorded')]));
  } else {
    final recorded = _withoutMadeUpWeights(baseline);
    final weightsMadeUp = recorded.stageReconciliations.isEmpty &&
        baseline.stageReconciliations.isNotEmpty;
    final raw = rawSheetReviewSections(
      baseline: recorded,
      partName: name,
      sheetLabel: _sheetLabelOf(recorded),
    );
    // Its own "Part" heading repeats the one above.
    sections.addAll(raw.where((section) => section.title != 'Part'));
    if (weightsMadeUp) {
      sections.add(const RawSheetReviewSection(
        'Material in and out',
        [('', 'Not recorded')],
      ));
    }
  }
  return sections;
}

/// A record read with no material rows is given three made-up stages (100 kg
/// in, 90 out, "Log for …") by [PenPaperBaseline.fromJson]. Those are not
/// what anybody weighed, so the report leaves them out rather than print them
/// as data.
PenPaperBaseline _withoutMadeUpWeights(PenPaperBaseline baseline) {
  // The model's default note is another thing nobody wrote — and the panel
  // copies the record's note onto its material row, so it is there too.
  final madeUpNote = const PenPaperBaseline().notes;
  if (baseline.notes == madeUpNote) baseline = baseline.copyWith(notes: '');
  if (baseline.stageReconciliations.any((row) => row.notes == madeUpNote)) {
    baseline = baseline.copyWith(stageReconciliations: [
      for (final row in baseline.stageReconciliations)
        row.notes == madeUpNote ? row.copyWith(notes: '') : row,
    ]);
  }
  final made = PenPaperBaseline.createDefaultForStages().stageReconciliations;
  final rows = baseline.stageReconciliations;
  if (rows.length != made.length) return baseline;
  for (var i = 0; i < rows.length; i += 1) {
    final a = rows[i];
    final b = made[i];
    if (a.stageId != b.stageId ||
        a.inputKg != b.inputKg ||
        a.outputKg != b.outputKg ||
        a.notes != b.notes) {
      return baseline;
    }
  }
  return baseline.copyWith(stageReconciliations: const []);
}

/// "MS sheet · 48 × 96 in · 1.2 mm" — stamped on the record when it was
/// saved; rebuilt from its sizes when an older record has none.
String _sheetLabelOf(PenPaperBaseline baseline) {
  final stamped = baseline.stageReconciliations.firstOrNull?.inputLabel.trim() ?? '';
  if (stamped.isNotEmpty) return stamped;
  String size(double inches) =>
      inches == inches.roundToDouble() ? inches.toStringAsFixed(0) : inches.toString();
  return [
    baseline.materialName.trim().isEmpty ? 'Sheet' : baseline.materialName.trim(),
    if (baseline.sheetWidthInches > 0 && baseline.sheetHeightInches > 0)
      '${size(baseline.sheetWidthInches)} × ${size(baseline.sheetHeightInches)} in',
  ].join(' · ');
}

/// The report for one part, read fresh from the server each time it opens —
/// not from the local copy, which can lag a save made a moment ago.
class ItemReportView extends StatefulWidget {
  const ItemReportView({super.key, required this.item});

  /// The part as the caller has it; the report reads it again.
  final ItemDefinition item;

  @override
  State<ItemReportView> createState() => _ItemReportViewState();
}

class _ItemReportViewState extends State<ItemReportView> {
  ItemDefinition? _item;
  List<PartRoute> _routes = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ItemReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _item = widget.item;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final items = context.read<ItemsProvider>();
    ProcessRouteService? routes;
    try {
      routes = context.read<ProcessRouteService>();
    } catch (_) {
      routes = null;
    }
    try {
      final fresh = await items.fetchFresh(widget.item.id);
      final partRoutes = routes == null
          ? const <PartRoute>[]
          : await routes.routesFor(widget.item.id).catchError((_) => const <PartRoute>[]);
      if (!mounted) return;
      setState(() {
        _item = fresh ?? _item;
        _routes = partRoutes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read this part from the server: $error';
      });
    }
  }

  String _groupPath(ItemDefinition item) {
    GroupsProvider? groups;
    try {
      groups = context.watch<GroupsProvider>();
    } catch (_) {
      return '';
    }
    final group = groups.findById(item.groupId);
    if (group == null) return '';
    final parent = group.parentGroupId == null ? null : groups.findById(group.parentGroupId);
    return parent == null ? group.name : '${parent.name} › ${group.name}';
  }

  Map<String, String> _propertyLabels() {
    List<SheetProperty> properties;
    try {
      final provider = context.watch<SheetPropertiesProvider>()..ensureLoaded();
      properties = provider.properties;
    } catch (_) {
      properties = const [];
    }
    return {
      for (final property in properties)
        property.propertyName.trim().toLowerCase(): property.name,
    };
  }

  List<String> _documents(ItemDefinition item) {
    final clientId = item.developedFor.clientId;
    if (clientId == null) return const [];
    try {
      final provider = context.watch<CompanyDocumentsProvider>()
        ..request('client', '$clientId');
      return [
        for (final document in provider.documentsOf('client', '$clientId') ?? const <CompanyDocument>[])
          document.title.trim().isEmpty ? document.fileName : document.title.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item!;
    final sections = itemReportSections(
      item: item,
      groupPath: _groupPath(item),
      propertyLabels: _propertyLabels(),
      routes: _routes,
      documents: _documents(item),
    );
    return Column(
      key: const ValueKey<String>('item_report'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          itemReportHeading(item),
          key: const ValueKey<String>('item_report_heading'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _loading
              ? 'Reading the latest from the server…'
              : 'Everything entered for this part on the item sheet.',
          style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 14, color: SoftErpTheme.dangerText),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(_load()),
                child: const Text('Retry', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        RawSheetReviewCard(sections: sections),
      ],
    );
  }
}
