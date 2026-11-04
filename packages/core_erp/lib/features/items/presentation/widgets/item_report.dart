import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../../../core/app_flow_hooks.dart';
import '../../../../core/services/entity_photos.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mini_photo.dart';
import '../../../../sheet/sheet_style.dart';
import '../../../clients/presentation/widgets/company_view_dialog.dart';
import '../../../links/domain/entity_link.dart';
import '../../../links/presentation/widgets/ecosystem_inspector.dart';


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
import '../../../units/data/unit_family_service.dart';
import '../../../units/domain/unit_family.dart';
import '../../domain/developed_for.dart';
import '../../domain/item_definition.dart';
import '../../domain/sheet_property.dart';
import '../providers/items_provider.dart';
import '../providers/sheet_properties_provider.dart';
import 'part_photo_gallery.dart';

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
  add('Cavity', die.numberOfCavities);
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
  UnitFamily? countFamily,
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
      countFamily: countFamily,
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

  /// Pc, doz, gro — so pieces read down the ladder ("20 gro · 1 doz · 8 Pc")
  /// as they do in the raw panel's Review. Null without the units master:
  /// plain pieces.
  UnitFamily? _countFamily;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    unawaited(_load());
    // Once, not on every build: a failed load would otherwise ask again on
    // the rebuild its own failure causes, without end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(context.read<SheetPropertiesProvider>().ensureLoaded());
      } on ProviderNotFoundException {
        // No property columns in this app: the report shows none.
      }
      unawaited(_loadCountFamily());
    });
  }

  Future<void> _loadCountFamily() async {
    UnitFamilyService service;
    try {
      service = context.read<UnitFamilyService>();
    } on ProviderNotFoundException {
      return;
    }
    try {
      final family = await service.byCode('count');
      if (mounted && family != null) setState(() => _countFamily = family);
    } catch (_) {
      // Plain pieces, as before.
    }
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
    final id = widget.item.id;
    try {
      final fresh = await items.fetchFresh(id);
      final partRoutes = routes == null
          ? const <PartRoute>[]
          : await routes.routesFor(id).catchError((_) => const <PartRoute>[]);
      // Another part was clicked meanwhile: its own load answers for it.
      if (!mounted || widget.item.id != id) return;
      setState(() {
        _item = fresh ?? _item;
        _routes = partRoutes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || widget.item.id != id) return;
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
      final provider = context.watch<SheetPropertiesProvider>();
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

  /// The cards a figure tile scrolls to.
  final GlobalKey _companyKey = GlobalKey();
  final GlobalKey _routeKey = GlobalKey();
  final GlobalKey _diesKey = GlobalKey();
  final GlobalKey _machinesKey = GlobalKey();
  final GlobalKey _rawKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.05,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item!;
    final labels = _propertyLabels();
    final properties = <(String, String)>[
      for (final node in item.variationTree)
        if (node.kind == ItemVariationNodeKind.property && node.children.isNotEmpty)
          (
            labels[node.name.trim().toLowerCase()] ?? node.name,
            node.children
                .map((value) => value.displayName.isEmpty ? value.name : value.displayName)
                .join(', '),
          ),
    ];
    final route = _routes.firstOrNull;
    final raw = item.penPaperBaseline == null
        ? null
        : _withoutMadeUpWeights(item.penPaperBaseline!);

    final company = _CompanyCard(
      key: _companyKey,
      deal: item.developedFor,
      documents: _documents(item),
    );
    final routeCard = _RouteCard(key: _routeKey, route: route);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Column(
          key: const ValueKey<String>('item_report'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading || _error != null) ...[
              _StatusLine(
                loading: _loading,
                error: _error,
                onRetry: () => unawaited(_load()),
              ),
              const SizedBox(height: 12),
            ],
            _ReportHeader(
              item: item,
              groupPath: _groupPath(item),
              properties: properties,
            ),
            const SizedBox(height: 14),
            _FigureStrip(
              tiles: [
                _FigureTile(
                  icon: Icons.currency_rupee_rounded,
                  value: item.developedFor.quotationAmount == null
                      ? null
                      : rupeeStamp(item.developedFor.quotationAmount!),
                  label: 'Quotation',
                  onTap: () => _scrollTo(_companyKey),
                ),
                _FigureTile(
                  icon: Icons.precision_manufacturing_outlined,
                  value: _count(item.dies.length, 'die'),
                  label: 'Dies',
                  onTap: () => _scrollTo(_diesKey),
                ),
                _FigureTile(
                  icon: Icons.settings_suggest_outlined,
                  value: _count(item.machines.length, 'machine'),
                  label: 'Machines',
                  onTap: () => _scrollTo(_machinesKey),
                ),
                _FigureTile(
                  icon: Icons.route_rounded,
                  value: route == null ? null : _count(route.steps.length, 'stage'),
                  label: route == null ? 'Route' : 'Route v${route.version}',
                  onTap: () => _scrollTo(_routeKey),
                ),
                _FigureTile(
                  icon: Icons.grid_on_rounded,
                  // Pieces the plan cuts from a sheet; with no plan laid
                  // out, the pieces recorded coming out.
                  value: _rawFigure(raw, _countFamily),
                  label: raw == null
                      ? 'Raw sheet'
                      : (raw.pieceCount > 0 ? 'Per sheet' : 'Pieces out'),
                  // Too narrow to spell the ladder out; the Raw sheet card
                  // below does.
                  hint: _rawLadder(raw, _countFamily),
                  onTap: () => _scrollTo(_rawKey),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: company),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: routeCard),
                ],
              )
            else ...[
              company,
              const SizedBox(height: 14),
              routeCard,
            ],
            const SizedBox(height: 14),
            _DiesCard(key: _diesKey, dies: item.dies),
            const SizedBox(height: 14),
            _MachinesCard(key: _machinesKey, machines: item.machines),
            const SizedBox(height: 14),
            _RawSheetCard(
              key: _rawKey,
              baseline: raw,
              madeUp: raw != null &&
                  raw.stageReconciliations.isEmpty &&
                  item.penPaperBaseline!.stageReconciliations.isNotEmpty,
              partName: item.displayName.trim().isEmpty ? item.name : item.displayName.trim(),
              countFamily: _countFamily,
            ),
          ],
        );
      },
    );
  }
}

/// Pieces the plan cuts from a sheet; with no plan laid out, the pieces
/// recorded coming out. Null when neither is known.
int? _rawPieces(PenPaperBaseline? raw) {
  if (raw == null) return null;
  if (raw.pieceCount > 0) return raw.pieceCount;
  final row = raw.isGranular ? null : raw.stageReconciliations.firstOrNull;
  if (row != null && row.piecesOut > 0) return row.piecesOut;
  return null;
}

String? _rawFigure(PenPaperBaseline? raw, UnitFamily? family) {
  final pieces = _rawPieces(raw);
  return pieces == null ? null : piecesCount(pieces, family);
}

String? _rawLadder(PenPaperBaseline? raw, UnitFamily? family) {
  final pieces = _rawPieces(raw);
  return pieces == null ? null : piecesLadder(pieces, family);
}

String _count(int n, String one) => n == 0 ? '0 ${one}s' : '$n $one${n == 1 ? '' : 's'}';

String _kgText(double value) {
  final text = value.toStringAsFixed(2);
  return '${text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')} kg';
}

// --- the pieces of the report ------------------------------------------------

/// "Reading the latest…", or why it could not, with Retry.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.loading, this.error, required this.onRetry});

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: failed ? SoftErpTheme.dangerBg : SoftErpTheme.infoBg,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.sync_rounded,
            size: 18,
            color: failed ? SoftErpTheme.dangerText : SoftErpTheme.infoText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error ?? 'Reading the latest from the server…',
              style: TextStyle(
                fontSize: 14,
                color: failed ? SoftErpTheme.dangerText : SoftErpTheme.infoText,
              ),
            ),
          ),
          if (failed)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}

/// The part itself: photo, name, code (click to copy), where it is filed,
/// when it was saved, and its properties as chips.
class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.item,
    required this.groupPath,
    required this.properties,
  });

  final ItemDefinition item;
  final String groupPath;
  final List<(String, String)> properties;

  @override
  Widget build(BuildContext context) {
    final name = item.displayName.trim().isEmpty ? item.name : item.displayName.trim();
    final code = item.partCode.trim();
    return _Card(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MiniPhoto.isAvailable(context)) ...[
            MiniPhoto(
              owner: PhotoOwner.item,
              id: '${item.id}',
              size: 72,
              what: 'part photo',
              fallbackUrl: item.photoUrl,
              onOpen: () => showPartPhotoGallery(context, itemId: '${item.id}', partName: name),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        key: const ValueKey<String>('item_report_heading'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: SoftErpTheme.textPrimary,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _Badge(
                      icon: Icons.check_circle_rounded,
                      label: 'Saved ${partStamp(item.updatedAt)}',
                      foreground: SoftErpTheme.successText,
                      background: SoftErpTheme.successBg,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (code.isNotEmpty) _CodePill(code: code) else const _Muted('No code yet'),
                    if (groupPath.isNotEmpty)
                      _IconText(icon: Icons.folder_outlined, text: groupPath),
                    if (item.partNo != null)
                      _IconText(icon: Icons.tag_rounded, text: 'Part No ${item.partNo}'),
                    _IconText(
                      icon: Icons.history_rounded,
                      text: 'Created ${partStamp(item.createdAt)}',
                    ),
                  ],
                ),
                if (properties.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, value) in properties)
                        _PropertyChip(label: label, value: value),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The part code, as a pill that copies itself.
class _CodePill extends StatelessWidget {
  const _CodePill({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy the part code',
      child: InkWell(
        key: const ValueKey<String>('item_report_code'),
        borderRadius: BorderRadius.circular(999),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) showAppToast(context, 'Copied $code');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SoftErpTheme.accentSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: SoftErpTheme.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: SoftErpTheme.accent,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 15, color: SoftErpTheme.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Alloy  MS" — the name quiet, the value bold.
class _PropertyChip extends StatelessWidget {
  const _PropertyChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary)),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The five figures that answer "what is there" at a glance; each takes you
/// to its card.
class _FigureStrip extends StatelessWidget {
  const _FigureStrip({required this.tiles});

  final List<_FigureTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: tile),
              ],
            ],
          );
        }
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _FigureTile extends StatelessWidget {
  const _FigureTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final IconData icon;

  /// Said on hover — what the figure is, in more words than fit.
  final String? hint;

  /// Null when nothing is recorded: drawn as a quiet dash, never as 0.
  final String? value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: SoftErpTheme.cardSurface,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
            border: Border.all(color: SoftErpTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SoftErpTheme.accentSoft,
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                ),
                child: Icon(icon, size: 19, color: SoftErpTheme.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: value == null ? SoftErpTheme.textMuted : SoftErpTheme.textPrimary,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: SoftErpTheme.textMuted),
            ],
          ),
        ),
      ),
    );
    final hint = this.hint;
    return hint == null ? tile : Tooltip(message: hint, child: tile);
  }
}

/// A white card with a title row: the frame every part of the report sits in.
class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: SoftErpTheme.surfaceDecoration(
        color: SoftErpTheme.cardSurface,
        radius: SoftErpTheme.radiusMd,
        elevated: true,
        strongBorder: false,
        showBorder: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  SheetStyle.iconTile(icon!),
                  const SizedBox(width: 10),
                ],
                Expanded(child: Text(title!, style: SheetStyle.sectionTitle)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: foreground),
          ),
        ],
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: SoftErpTheme.textSecondary),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary)),
      ],
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 14, color: SoftErpTheme.textMuted));
}

/// "No dies on this part" — an icon and a sentence, where a card has nothing.
class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: SoftErpTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// A label over its value, for facts laid out in a grid.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.width = 200});

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SheetStyle.label),
          const SizedBox(height: 3),
          Text(
            empty ? '—' : value.trim(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: empty ? SoftErpTheme.textMuted : SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A table: a header band, then rows — each one clickable when it opens
/// something, with a › to say so.
class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.columns, required this.rows});

  final List<(String, int)> columns;
  final List<_ReportRow> rows;

  @override
  Widget build(BuildContext context) {
    final clickable = rows.any((row) => row.onTap != null);
    Widget cells(List<Widget> children) => Row(
          children: [
            for (final (i, child) in children.indexed)
              Expanded(flex: columns[i].$2, child: child),
            if (clickable) const SizedBox(width: 24),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: SoftErpTheme.sectionSurface,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          ),
          child: cells([
            for (final (label, _) in columns)
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
          ]),
        ),
        for (final row in rows)
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: row.key,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              hoverColor: SoftErpTheme.accentSoft.withValues(alpha: 0.6),
              onTap: row.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
                ),
                child: Row(
                  children: [
                    for (final (i, cell) in row.cells.indexed)
                      Expanded(flex: columns[i].$2, child: cell),
                    if (clickable)
                      SizedBox(
                        width: 24,
                        child: row.onTap == null
                            ? null
                            : const Icon(Icons.chevron_right_rounded, size: 20, color: SoftErpTheme.accent),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportRow {
  const _ReportRow({required this.cells, this.onTap, this.key});

  final List<Widget> cells;
  final VoidCallback? onTap;
  final Key? key;
}

/// One cell: the text, or a quiet dash. [strong] for the row's identity.
Widget _cell(String? text, {bool strong = false, bool selectable = false, int maxLines = 1}) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return const Text('—', style: TextStyle(fontSize: 14, color: SoftErpTheme.textMuted));
  final style = TextStyle(
    fontSize: 14,
    fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
    color: SoftErpTheme.textPrimary,
  );
  if (selectable) return SelectableText(value, style: style, maxLines: maxLines);
  return Text(value, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
}

/// Who it was made for: the company (opens its view), the quotation, who
/// was dealt with, and the company's documents.
class _CompanyCard extends StatelessWidget {
  const _CompanyCard({super.key, required this.deal, required this.documents});

  final DevelopedFor deal;
  final List<String> documents;

  @override
  Widget build(BuildContext context) {
    final company = deal.companyName.trim().isNotEmpty ? deal.companyName.trim() : deal.clientName.trim();
    final clientId = deal.clientId;
    final kind = switch (deal.kind) {
      DevelopedForKind.client => 'Client',
      DevelopedForKind.contractor => 'Contractor',
      DevelopedForKind.self => 'Self (in-house)',
      DevelopedForKind.none => null,
    };
    if (company.isEmpty) {
      return _Card(
        title: 'Company',
        icon: Icons.storefront_rounded,
        child: _Empty(
          icon: Icons.home_work_outlined,
          text: deal.kind == DevelopedForKind.self ? 'Made for ourselves (in-house)' : 'No company recorded',
        ),
      );
    }
    final people = deal.contacts;
    return _Card(
      title: 'Company',
      icon: Icons.storefront_rounded,
      trailing: kind == null
          ? null
          : _Badge(label: kind, foreground: SoftErpTheme.infoText, background: SoftErpTheme.infoBg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (MiniPhoto.isAvailable(context) && clientId != null) ...[
                MiniPhoto(owner: PhotoOwner.client, id: '$clientId', size: 48, what: 'company logo'),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: clientId == null ? '' : 'Open the company',
                      child: InkWell(
                        key: const ValueKey<String>('item_report_company'),
                        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                        onTap: clientId == null ? null : () => CompanyView.openClient(context, clientId),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                company,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: SoftErpTheme.accent,
                                ),
                              ),
                            ),
                            if (clientId != null) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.open_in_new_rounded, size: 16, color: SoftErpTheme.accent),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (deal.at != null)
                      Text(
                        'Recorded ${partStamp(deal.at!)}',
                        style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _Fact(
                label: 'Quotation',
                value: deal.quotationAmount == null ? '' : rupeeStamp(deal.quotationAmount!),
                width: 180,
              ),
              if (deal.costAmount != null)
                _Fact(label: 'Development cost', value: rupeeStamp(deal.costAmount!), width: 180),
              if (deal.kind == DevelopedForKind.contractor)
                _Fact(label: 'Contractor', value: deal.subContractorName, width: 220),
            ],
          ),
          const SizedBox(height: 16),
          Text('Dealt with', style: SheetStyle.label),
          const SizedBox(height: 8),
          if (people.isEmpty)
            const _Empty(icon: Icons.person_outline_rounded, text: 'Nobody ticked on this deal')
          else
            _ReportTable(
              columns: const [('Name', 5), ('Designation', 4), ('Phone', 4), ('Email', 6)],
              rows: [
                for (final person in people)
                  // Names and emails run long: two lines, not an ellipsis.
                  _ReportRow(cells: [
                    _cell(person.name, strong: true, maxLines: 2),
                    _cell(person.designation, maxLines: 2),
                    _cell(person.phone, selectable: true),
                    _cell(person.email, selectable: true, maxLines: 2),
                  ]),
              ],
            ),
          if (documents.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Documents', style: SheetStyle.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final title in documents)
                  _Badge(
                    icon: Icons.description_outlined,
                    label: title,
                    foreground: SoftErpTheme.textPrimary,
                    background: SoftErpTheme.cardSurfaceAlt,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The route: the pipeline's name, its version, and the stages in order.
class _RouteCard extends StatelessWidget {
  const _RouteCard({super.key, required this.route});

  final PartRoute? route;

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    if (route == null) {
      return const _Card(
        title: 'Route (pipeline)',
        icon: Icons.route_rounded,
        child: _Empty(icon: Icons.alt_route_rounded, text: 'No route yet'),
      );
    }
    final (fg, bg) = switch (route.status) {
      RouteStatus.active => (SoftErpTheme.successText, SoftErpTheme.successBg),
      RouteStatus.draft => (SoftErpTheme.warningText, SoftErpTheme.warningBg),
      RouteStatus.retired => (SoftErpTheme.textSecondary, SoftErpTheme.cardSurfaceAlt),
    };
    return _Card(
      title: 'Route (pipeline)',
      icon: Icons.route_rounded,
      trailing: _Badge(label: 'v${route.version} · ${route.status.wire}', foreground: fg, background: bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            route.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary),
          ),
          const SizedBox(height: 14),
          if (route.steps.isEmpty)
            const _Empty(icon: Icons.alt_route_rounded, text: 'No stages')
          else
            Wrap(
              spacing: 6,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (i, step) in route.steps.indexed) ...[
                  if (i > 0) const Icon(Icons.arrow_forward_rounded, size: 16, color: SoftErpTheme.textMuted),
                  _StageChip(number: i + 1, name: step.stageName),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.number, required this.name});

  final int number;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: SoftErpTheme.accent, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The dies on the part, a row each; a row opens the die.
class _DiesCard extends StatelessWidget {
  const _DiesCard({super.key, required this.dies});

  final List<ItemDieLink> dies;

  @override
  Widget build(BuildContext context) {
    final canOpen = AppFlowHooks.canInspect('die');
    return _Card(
      title: 'Dies',
      icon: Icons.precision_manufacturing_rounded,
      trailing: _Badge(
        label: '${dies.length}',
        foreground: SoftErpTheme.accent,
        background: SoftErpTheme.accentSoft,
      ),
      child: dies.isEmpty
          ? const _Empty(icon: Icons.precision_manufacturing_outlined, text: 'No dies on this part')
          : _ReportTable(
              columns: const [
                ('Code', 26),
                ('Type', 12),
                ('Made by', 15),
                ('Ordered', 12),
                ('Arrived', 12),
                ('Liner', 10),
                ('Sets', 7),
                ('Kept', 12),
              ],
              rows: [
                for (final die in dies)
                  _ReportRow(
                    key: ValueKey<String>('item_report_die_${die.id}'),
                    onTap: canOpen
                        ? () => showEcosystemInspector(
                              context,
                              subject: LinkRef(type: 'die', id: die.id, label: die.toolCode),
                            )
                        : null,
                    cells: [
                      Row(
                        children: [
                          if (MiniPhoto.isAvailable(context)) ...[
                            MiniPhoto(
                              owner: PhotoOwner.die,
                              id: die.id,
                              size: 32,
                              what: 'die photo',
                              fallbackUrl: die.photoUrl,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: _cell(die.toolCode, strong: true)),
                        ],
                      ),
                      _cell(DieTypeChoice.fromStored(die.dieType, die.dieTypeLabel)?.label),
                      _cell(die.madeBy),
                      _cell(die.poAt == null ? null : partStampDate(die.poAt!)),
                      _cell(die.dateInAt == null ? null : partStampDate(die.dateInAt!)),
                      _cell(die.linerSizeNm == null
                          ? null
                          : '${formatLengthFromNanometres(die.linerSizeNm, die.linerSizeUnit)} ${die.linerSizeUnit}'),
                      _cell(die.noOfSet?.toString()),
                      _cell(die.whereKept),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// The machines the part runs on, a row each; a row opens the machine.
class _MachinesCard extends StatelessWidget {
  const _MachinesCard({super.key, required this.machines});

  final List<ItemMachineLink> machines;

  @override
  Widget build(BuildContext context) {
    final canOpen = AppFlowHooks.canInspect('machine');
    return _Card(
      title: 'Machines',
      icon: Icons.settings_suggest_rounded,
      trailing: _Badge(
        label: '${machines.length}',
        foreground: SoftErpTheme.accent,
        background: SoftErpTheme.accentSoft,
      ),
      child: machines.isEmpty
          ? const _Empty(icon: Icons.settings_suggest_outlined, text: 'No machines on this part')
          : _ReportTable(
              columns: const [
                ('Machine No', 16),
                ('Name', 16),
                ('Type', 16),
                ('Make', 14),
                ('Capacity', 13),
                ('Strokes', 10),
                ('Built', 8),
              ],
              rows: [
                for (final machine in machines)
                  _ReportRow(
                    key: ValueKey<String>('item_report_machine_${machine.id}'),
                    onTap: canOpen
                        ? () => showEcosystemInspector(
                              context,
                              subject: LinkRef(
                                type: 'machine',
                                id: machine.id,
                                label: machine.assetId.isEmpty ? machine.name : machine.assetId,
                              ),
                            )
                        : null,
                    cells: [
                      Row(
                        children: [
                          if (MiniPhoto.isAvailable(context)) ...[
                            MiniPhoto(
                              owner: PhotoOwner.machine,
                              id: machine.id,
                              size: 32,
                              what: 'machine photo',
                              fallbackUrl: machine.photoUrl,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: _cell(
                              machine.assetId.isEmpty ? machine.name : machine.assetId,
                              strong: true,
                            ),
                          ),
                        ],
                      ),
                      _cell(machine.name),
                      _cell(machine.machineType),
                      _cell(machine.machineMake),
                      _cell(capacityLabel(
                        CapacityKind.fromWire(machine.capacityKind),
                        machine.capacityKgf,
                        'Ton',
                      )),
                      _cell(machine.strokesPerMinute?.toString()),
                      _cell(machine.manufacturedYear?.toString()),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// The raw sheet: what it is, what went in and came out (as figures), and
/// the cut plan.
class _RawSheetCard extends StatelessWidget {
  const _RawSheetCard({
    super.key,
    required this.baseline,
    required this.madeUp,
    required this.partName,
    this.countFamily,
  });

  final PenPaperBaseline? baseline;
  final UnitFamily? countFamily;

  /// The weights were the model's placeholders: shown as not recorded.
  final bool madeUp;
  final String partName;

  @override
  Widget build(BuildContext context) {
    final baseline = this.baseline;
    if (baseline == null) {
      return const _Card(
        title: 'Raw sheet',
        icon: Icons.grid_on_rounded,
        child: _Empty(icon: Icons.grid_off_rounded, text: 'No raw sheet recorded'),
      );
    }
    final row = baseline.isGranular ? null : baseline.stageReconciliations.firstOrNull;
    final sections = rawSheetReviewSections(
      baseline: baseline,
      partName: partName,
      sheetLabel: _sheetLabelOf(baseline),
      countFamily: countFamily,
    );
    // What the tiles and facts above do not already say.
    final more = sections
        .where((s) => s.title != 'Part' && s.title != 'Sheet' && s.title != 'Material in and out')
        .toList();
    final delta = row?.balanceDeltaKg ?? 0;
    final balances = delta.abs() < 0.05;

    return _Card(
      title: 'Raw sheet',
      icon: Icons.grid_on_rounded,
      trailing: baseline.lastForm.isBand
          ? _Badge(
              label: baseline.lastForm.label,
              foreground: SoftErpTheme.infoText,
              background: SoftErpTheme.infoBg,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _Fact(label: 'Sheet', value: _sheetLabelOf(baseline), width: 280),
              _Fact(label: 'Alloy', value: baseline.materialName, width: 140),
              _Fact(
                label: 'Grade',
                value: baseline.materialGrade.isEmpty ? '' : '${baseline.materialGrade} grade',
                width: 140,
              ),
              _Fact(label: 'Vendor', value: baseline.vendorName, width: 240),
            ],
          ),
          const SizedBox(height: 16),
          Text('Material in and out', style: SheetStyle.label),
          const SizedBox(height: 8),
          if (row == null || madeUp)
            const _Empty(icon: Icons.scale_outlined, text: 'Not recorded')
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatTile(label: 'In', value: _kgText(row.inputKg)),
                _StatTile(label: 'Out', value: _kgText(row.outputKg)),
                if (row.piecesOut > 0)
                  _StatTile(
                    key: const ValueKey<String>('report_pieces_out'),
                    label: 'Pieces',
                    value: piecesCount(row.piecesOut, countFamily),
                    detail: piecesLadder(row.piecesOut, countFamily),
                  ),
                if (row.recordScrap) _StatTile(label: 'Scrap', value: _kgText(row.scrapKg)),
                if (row.recordRejection && row.rejectionKg > 0)
                  _StatTile(label: 'Rejection', value: _kgText(row.rejectionKg)),
                if (row.recordWeightLoss && row.weightLossKg > 0)
                  _StatTile(label: 'Loss', value: _kgText(row.weightLossKg)),
                _Badge(
                  icon: balances ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                  label: balances
                      ? 'Balances'
                      : '${_kgText(delta.abs())} ${delta > 0 ? 'unaccounted' : 'over'}',
                  foreground: balances ? SoftErpTheme.successText : SoftErpTheme.warningText,
                  background: balances ? SoftErpTheme.successBg : SoftErpTheme.warningBg,
                ),
              ],
            ),
          for (final section in more) ...[
            const SizedBox(height: 16),
            Text(section.title, style: SheetStyle.label),
            const SizedBox(height: 8),
            // Nothing laid out: one line saying so, not "0 pcs · 0.0%".
            if (section.title == 'Cut plan' && baseline.pieceCount <= 0)
              const _Empty(icon: Icons.grid_4x4_rounded, text: 'Nothing laid out on the sheet yet')
            else
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                for (final (label, value) in section.rows)
                  label.isEmpty
                      ? SizedBox(
                          width: double.infinity,
                          child: Text(value, style: const TextStyle(fontSize: 14, color: SoftErpTheme.textPrimary)),
                        )
                      : _Fact(label: label, value: value, width: 180),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A figure in a box: the value large, its name small above it.
class _StatTile extends StatelessWidget {
  const _StatTile({super.key, required this.label, required this.value, this.detail});

  final String label;
  final String value;

  /// A line under the value — a count down its ladder.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary),
          ),
          if (detail != null)
            Text(detail!, style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary)),
        ],
      ),
    );
  }
}
