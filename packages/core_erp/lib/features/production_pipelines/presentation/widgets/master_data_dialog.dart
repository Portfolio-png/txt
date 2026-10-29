import 'dart:async' show unawaited;
import 'dart:convert' show jsonEncode;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../sheet/sheet_style.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/length_unit_field.dart';
import '../../domain/pen_paper_baseline.dart';
import '../../domain/pipeline_stage_node.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../units/data/unit_family_service.dart';
import '../../../vendors/domain/vendor_inputs.dart';
import '../../../vendors/presentation/providers/vendors_provider.dart';
import '../../../units/domain/global_length_units.dart';
import '../../../units/domain/unit_family.dart';
import '../../../materials/domain/material_definition.dart';
import '../../domain/raw_stock_form.dart';
import '../../domain/thickness_label.dart';
import '../../domain/sheet_part.dart';
import 'band_form_animation.dart';
import 'pen_paper_baseline_widget.dart';
import 'raw_sheet_review.dart';
import 'sheet_dimension_figure.dart';

/// Records Master Data in a window of its own: the sheet being described in the
/// top left, the figures it produced in the bottom right.
///
/// The two halves are the same act. Someone recording a baseline is holding a
/// sheet of a certain size and reporting what came out of it, so the sheet is
/// drawn from the dimensions as they are typed and the weights are entered
/// beside it, rather than the dimensions being three more numbers in a table
/// that never adds up to a picture.
Future<PenPaperBaseline?> showMasterDataDialog(
  BuildContext context, {
  required PenPaperBaseline baseline,
  String? pipelineId,
  String pipelineName = '',
  String itemName = '',
  List<PipelineStageNode> stageNodes = const <PipelineStageNode>[],
  List<SheetPart> parts = const <SheetPart>[],
  List<MaterialDefinition> materials = const <MaterialDefinition>[],
  bool readOnly = false,
}) {
  return showDialog<PenPaperBaseline>(
    context: context,
    barrierDismissible: false,
    // The dialog is only the frame now: the editing lives in [MasterDataPanel]
    // so the same panel can sit in a side panel without a route around it.
    // Popping with the saved value (or null) keeps every caller's contract
    // exactly what it was when the editor was private to this function.
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: MasterDataPanel(
        baseline: baseline,
        pipelineId: pipelineId,
        pipelineName: pipelineName,
        itemName: itemName,
        stageNodes: stageNodes,
        parts: parts,
        materials: materials,
        readOnly: readOnly,
        onSave: (saved) => Navigator.of(dialogContext).pop(saved),
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );
}

/// The Master Data editor itself, with no route of its own.
///
/// It used to exist only inside [showMasterDataDialog], which meant the one
/// place a baseline could be read was a modal that covered the screen it was
/// about. Pulled out, it can sit beside the thing it describes: [embedded]
/// drops the dialog's card and sizes itself from the space it is given rather
/// than from the window, so a narrow side panel gets the stacked layout instead
/// of a squeezed side-by-side one.
///
/// The panel never pops anything. It reports through [onSave] with the
/// baseline as it will be recorded (blank typing rows stripped) and through
/// [onCancel] when the person backs out; whoever hosts it decides what that
/// means — closing a dialog, collapsing a panel, or nothing at all.
class MasterDataPanel extends StatefulWidget {
  const MasterDataPanel({
    super.key,
    required this.baseline,
    required this.onSave,
    this.onCancel,
    this.pipelineId,
    this.pipelineName = '',
    this.unattachedHint,
    this.itemName = '',
    this.stageNodes = const <PipelineStageNode>[],
    this.parts = const <SheetPart>[],
    this.materials = const <MaterialDefinition>[],
    this.readOnly = false,
    this.showHeader = true,
    this.embedded = false,
    this.onEdit,
    this.saving = false,
    this.alloy,
    this.grade,
    this.thickness,
    this.onThicknessChanged,
  });

  /// The baseline the panel opens on. Edits are made to a working copy, so the
  /// caller's value is only replaced when [onSave] says so.
  ///
  /// While [readOnly] the panel follows this value: a save made somewhere else
  /// shows up here live instead of the panel sitting on what it was opened
  /// with. While editing it does not — swapping the record out from under
  /// someone mid-sentence would throw their typing away.
  final PenPaperBaseline baseline;
  final String? pipelineId;
  final String pipelineName;

  /// See [PenPaperBaselineWidget.unattachedHint].
  final String? unattachedHint;
  final String itemName;
  final List<PipelineStageNode> stageNodes;

  /// Parts the catalogue already knows the blank size of. Empty when the caller
  /// has none, in which case the panel stays a place to type sizes by hand.
  final List<SheetPart> parts;

  /// The material master, to pick the alloy from when the host has no Alloy
  /// column of its own ([alloy] null). Names only: no weight is worked out.
  final List<MaterialDefinition> materials;
  final bool readOnly;

  /// Called with the baseline as it will be recorded, without the blank rows
  /// the editor keeps at the end of every region for typing into.
  final ValueChanged<PenPaperBaseline> onSave;

  /// Called by Close and Cancel. When null there is nothing to back out of —
  /// an always-open side panel — so neither control is drawn.
  final VoidCallback? onCancel;

  /// Whether the title strip is drawn. A host that already names the record
  /// in its own chrome turns it off rather than saying it twice.
  final bool showHeader;

  /// No dialog card, and sized from the parent's constraints rather than the
  /// window. The host must give it a bounded height: the step body takes
  /// whatever is left between the step bar and the footer.
  final bool embedded;

  /// Called by the footer's Edit while [readOnly]. Null when there is nothing
  /// to edit yet (no saved part), and the footer says so instead.
  final VoidCallback? onEdit;

  /// A save is on its way: Save spins and cannot be pressed twice.
  final bool saving;

  /// The part's own Alloy, from the sheet's Alloy column. Given, the panel
  /// shows it and does not pick one of its own — alloy and the sheet's
  /// material are one thing, changed in one place. Null for a host with no
  /// Alloy column, which keeps the panel's own picker.
  final String? alloy;

  /// The part's own Grade, from the sheet's Grade column — shown read-only,
  /// like [alloy]. Empty when the part has none yet; null for a host with no
  /// Grade column, which keeps the panel's own grade picker.
  final String? grade;

  /// The part's Thickness cell as the sheet shows it — "23 Gauge", "1.2 mm".
  /// Given, the panel's thickness IS the part's: it opens on it, follows it,
  /// and every change made here goes back through [onThicknessChanged]. Null
  /// keeps a thickness of the panel's own.
  final String? thickness;
  final ValueChanged<String>? onThicknessChanged;

  @override
  State<MasterDataPanel> createState() => _MasterDataPanelState();
}

/// The steps Master Data is captured in. Sheet planning comes first because
/// everything after it is measured against the sheet that was planned.
enum _MasterStep {
  sheet('Sheet planning', 'What is being cut, and how it comes off the sheet'),
  material('Material data', 'What the pipeline consumed and produced'),
  review('Review', 'The plan as it will be recorded');

  const _MasterStep(this.title, this.caption);

  final String title;
  final String caption;
}

class _MasterDataPanelState extends State<MasterDataPanel> {
  late PenPaperBaseline _baseline;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _thicknessController;
  late final TextEditingController _trimController;

  /// So the part's thickness arriving does not overwrite one being typed.
  final FocusNode _thicknessFocus = FocusNode();

  /// The part's Thickness cell when it holds something that is not a
  /// measurement — shown under the field rather than guessed at.
  String? _thicknessUnreadable;

  /// The sheet-wide split's own key, so it sits in the same map as the
  /// per-strip sub-cuts and one walk reads them all.
  static const int _primaryRegion = -2;

  /// One pair of controllers per band, per region. Regions come and go as the
  /// primary split changes, so these are grown and disposed alongside them.
  final Map<int, List<_BandControllers>> _bandControllers =
      <int, List<_BandControllers>>{_primaryRegion: <_BandControllers>[]};

  /// The unit each region is being typed in. Storage is always millimetres;
  /// this only decides what the fields show, because a 40 mm band and a
  /// 1.575 in band are the same cut and should not be two records.
  final Map<int, String> _regionUnit = <int, String>{};

  GlobalLengthUnit _unitFor(int region) =>
      lengthUnitBySymbol(_regionUnit[region]);

  /// Which strip's sub-cuts are open. Only one at a time: a panel showing every
  /// strip's blanking at once is the wall of numbers this replaced.
  int? _openRegion;

  _MasterStep _step = _MasterStep.sheet;

  /// Which form of stock the steps are showing. All four stand equal; the
  /// panel opens on the one last worked on.
  late RawForm _form;

  /// The strip, coil or roll on screen. Rewritten when the form changes.
  final TextEditingController _bandWidthController = TextEditingController();
  final TextEditingController _bandLengthController = TextEditingController();
  final TextEditingController _bandPitchController = TextEditingController();

  /// Forms whose length was set to Known but not typed yet: the field stays
  /// open rather than snapping back to Undefined while it is empty.
  final Set<RawForm> _lengthOpen = <RawForm>{};

  /// A measurement typed that cannot be stored exactly, by field.
  final Map<String, String> _bandErrors = <String, String>{};

  /// The unit each axis is being typed in. Storage is always millimetres; this
  /// only decides what the fields show, because a 40 mm band and a 1.575 in
  /// band are the same cut and should not be two records.
  final Map<SheetCutAxis, bool> _axisInInches = <SheetCutAxis, bool>{
    SheetCutAxis.columns: false,
    SheetCutAxis.rows: false,
  };

  /// Below this the two halves stop being side by side and stack, so the sheet
  /// keeps a readable drawing area instead of being squeezed into a sliver.
  /// Measured against the space the panel is actually given — the window for
  /// the dialog, the parent's constraints when embedded.
  static const double _sideBySideWidth = 900;

  /// Below this the step bar drops its caption and lets the chips scroll, so a
  /// side panel gets three readable steps instead of an overflow stripe.
  static const double _compactStepBarWidth = 640;

  @override
  void initState() {
    super.initState();
    _baseline = _withoutSheetPitch(widget.baseline);
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _thicknessController = TextEditingController();
    _trimController = TextEditingController();
    _form = widget.baseline.lastForm;
    _writeFields();
    _writeBandFields();
    _loadCountFamily();
    _watchVendors();
  }

  /// Pc, doz, gro — what the output pieces are typed in. A host without the
  /// units master (a test, an old database) gets whole pieces instead.
  UnitFamily? _countFamily;

  /// The Vendors master, for who supplied the sheet. Null for a host
  /// without it (a test), and the vendor row is not drawn.
  VendorsProvider? _vendors;

  void _watchVendors() {
    try {
      _vendors = Provider.of<VendorsProvider>(context, listen: false);
    } on ProviderNotFoundException {
      return;
    }
    // A vendor added in another window joins the list here.
    _vendors!.addListener(_onVendorsChanged);
    // After the first frame: a refresh notifies at once, and notifying from
    // initState marks the provider dirty in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vendors = _vendors;
      if (!mounted || vendors == null) return;
      if (vendors.vendors.isEmpty && !vendors.isLoading) {
        unawaited(vendors.refresh());
      }
    });
  }

  void _onVendorsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCountFamily() async {
    UnitFamilyService? service;
    try {
      service = context.read<UnitFamilyService>();
    } on ProviderNotFoundException {
      return;
    }
    try {
      final family = await service.byCode('count');
      if (mounted && family != null) setState(() => _countFamily = family);
    } catch (_) {
      // No families to offer: the field takes whole pieces.
    }
  }

  /// Writes every field from [_baseline] — the dimensions, the machine row and
  /// each region's bands — so what is typed and what is drawn start agreeing.
  void _writeFields() {
    _widthController.text = _faceText(
      _baseline.sheetWidthInches,
      _baseline.faceUnit,
    );
    _heightController.text = _faceText(
      _baseline.sheetHeightInches,
      _baseline.faceUnit,
    );
    _thicknessController.text = _showUnit(
      _baseline.sheetThicknessMm,
      lengthUnitBySymbol(_baseline.gaugeUnit),
    );
    _trimController.text = _initial(_baseline.edgeTrimMm);
    _seedControllers();
    _ensureTrailingBlank(_primaryRegion);
    _adoptPartThickness();
  }

  /// The sheet no longer has a pitch: blanks sit edge to edge, and a gap an
  /// older plan kept is not carried on as a number nobody can see. (A strip,
  /// coil or roll took that pitch as its own when it was read.)
  static PenPaperBaseline _withoutSheetPitch(PenPaperBaseline baseline) =>
      baseline.kerfMm == 0 ? baseline : baseline.copyWith(kerfMm: 0);

  /// Takes the part's thickness, when the host gives one, as this plan's.
  void _adoptPartThickness() {
    final text = widget.thickness;
    if (text == null) return;
    final reading = readThickness(text);
    _thicknessUnreadable =
        reading == null && text.trim().isNotEmpty ? text.trim() : null;
    final unit = reading?.unit ?? lengthUnitBySymbol(_baseline.gaugeUnit);
    _baseline = _baseline.copyWith(
      gaugeUnit: unit.symbol,
      sheetThicknessMm: reading?.mm ?? 0,
    );
    _thicknessController.text =
        reading == null ? '' : _showUnit(reading.mm, unit);
  }

  /// Tells the host the thickness typed here, as the part's cell writes it.
  void _sendThickness() {
    final send = widget.onThicknessChanged;
    if (send == null) return;
    final unit = lengthUnitBySymbol(_baseline.gaugeUnit);
    final typed = double.tryParse(_thicknessController.text.trim()) ?? 0;
    send(writeThickness(typed, unit));
  }

  void _onThicknessTyped() {
    _onDimensionChanged();
    setState(() => _thicknessUnreadable = null);
    _sendThickness();
  }

  @override
  void didUpdateWidget(covariant MasterDataPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The part's thickness is followed whatever the panel is doing — it is
    // one value in two places — unless it is the one being typed here.
    if (widget.thickness != oldWidget.thickness && !_thicknessFocus.hasFocus) {
      _adoptPartThickness();
    }
    // Only a panel nobody is typing into follows its input. A read-only panel
    // is a view of the record, so a save made elsewhere belongs on it the
    // moment it lands; an editing panel holds a working copy that is the
    // person's, and replacing it would discard what they typed.
    if (!widget.readOnly) return;
    if (identical(oldWidget.baseline, widget.baseline)) return;
    if (_sameRecord(_withoutSheetPitch(widget.baseline), _baseline)) return;
    _baseline = _withoutSheetPitch(widget.baseline);
    // Region units are a typing convenience, not part of the record, and the
    // incoming plan may not have the regions they were set for.
    _regionUnit.clear();
    if (_openRegion != null && _baseline.subCutsFor(_openRegion!).isEmpty) {
      _openRegion = null;
    }
    _writeFields();
    _writeBandFields();
  }

  /// Whether two baselines record the same thing. The baseline has no value
  /// equality of its own, and its JSON is exactly what gets stored, so two
  /// that serialise alike are the same record whatever object holds them.
  static bool _sameRecord(PenPaperBaseline a, PenPaperBaseline b) =>
      jsonEncode(a.toJson()) == jsonEncode(b.toJson());

  /// Builds a controller pair for every band the baseline holds — the
  /// sheet-wide split, then each strip's own blanking.
  void _seedControllers() {
    for (final list in _bandControllers.values) {
      for (final band in list) {
        band.dispose();
      }
    }
    List<_BandControllers> pairs(List<SheetCutGroup> groups) => groups
        .map(
          (group) => _BandControllers(
            size: _initial(group.sizeMm),
            count: group.count > 0 ? '${group.count}' : '',
          ),
        )
        .toList();
    _bandControllers
      ..clear()
      ..[_primaryRegion] = pairs(_baseline.bands);
    for (final entry in _baseline.subCuts.entries) {
      _bandControllers[entry.key] = pairs(entry.value);
    }
  }

  static String _initial(double value) {
    if (value <= 0) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _vendors?.removeListener(_onVendorsChanged);
    _widthController.dispose();
    _heightController.dispose();
    _thicknessController.dispose();
    _thicknessFocus.dispose();
    _trimController.dispose();
    _bandWidthController.dispose();
    _bandLengthController.dispose();
    _bandPitchController.dispose();
    for (final list in _bandControllers.values) {
      for (final band in list) {
        band.dispose();
      }
    }
    super.dispose();
  }

  /// Every keystroke redraws the sheet — that is the point of the figure, so
  /// the reading is live rather than waiting for a commit.
  void _onDimensionChanged() {
    setState(() {
      final face = lengthUnitBySymbol(_baseline.faceUnit, fallback: 'in');
      final gauge = lengthUnitBySymbol(_baseline.gaugeUnit);
      // Straight through when the unit already is the storage unit: 48 inches
      // converted to millimetres and back is 47.99999999999999, and a sheet
      // that shrinks by a millionth every time it is read is not a sheet.
      double faceIn(TextEditingController field) {
        final typed = double.tryParse(field.text.trim()) ?? 0;
        if (face.symbol == 'in') return typed;
        return face.toMm(typed) / _mmPerInch;
      }

      _baseline = _baseline.copyWith(
        sheetWidthInches: faceIn(_widthController),
        sheetHeightInches: faceIn(_heightController),
        sheetThicknessMm: gauge.toMm(
          double.tryParse(_thicknessController.text.trim()) ?? 0,
        ),
      );
    });
  }

  /// The sheet's face is stored in inches and its gauge in millimetres; the
  /// unit only decides how they are written. Changing one rewrites the fields
  /// so the sheet stays the size it was.
  void _onFaceUnitChanged(GlobalLengthUnit unit) {
    if (unit.symbol == _baseline.faceUnit) return;
    setState(() {
      _baseline = _baseline.copyWith(faceUnit: unit.symbol);
      _widthController.text = _faceText(
        _baseline.sheetWidthInches,
        unit.symbol,
      );
      _heightController.text = _faceText(
        _baseline.sheetHeightInches,
        unit.symbol,
      );
    });
  }

  /// A stored inch value written in [unit], without a needless round trip
  /// through millimetres when the unit is already inches.
  static String _faceText(double inches, String symbol) {
    if (inches <= 0) return '';
    final unit = lengthUnitBySymbol(symbol, fallback: 'in');
    // Straight through when the unit already is the storage unit, so 48 inches
    // does not come back as 47.99999999999999.
    if (unit.symbol == 'in') {
      return _showUnit(inches, lengthUnitBySymbol('mm'));
    }
    return _showUnit(inches * _mmPerInch, unit);
  }

  void _onGaugeUnitChanged(GlobalLengthUnit unit) {
    if (unit.symbol == _baseline.gaugeUnit) return;
    setState(() {
      final mm = _baseline.sheetThicknessMm;
      _baseline = _baseline.copyWith(gaugeUnit: unit.symbol);
      _thicknessController.text = _showUnit(mm, unit);
    });
    _sendThickness();
  }

  static const double _mmPerInch = 25.4;

  /// Reads one region's bands off their fields, in millimetres whatever unit
  /// that region is being typed in.
  List<SheetCutGroup> _readRegion(int region) {
    final unit = _unitFor(region);
    return (_bandControllers[region] ?? const <_BandControllers>[])
        .map((band) {
          final typed = double.tryParse(band.size.text.trim()) ?? 0;
          return SheetCutGroup(
            sizeMm: unit.toMm(typed),
            count: int.tryParse(band.count.text.trim()) ?? 0,
          );
        })
        .toList(growable: false);
  }

  /// Folds every region's fields back into the baseline in one go, so the
  /// drawing and the readouts can never be reading a half-updated plan.
  PenPaperBaseline _withFields(PenPaperBaseline from) {
    final subs = <int, List<SheetCutGroup>>{};
    for (final region in _bandControllers.keys) {
      if (region == _primaryRegion) continue;
      final groups = _readRegion(region);
      if (groups.isNotEmpty) subs[region] = groups;
    }
    return from.copyWith(bands: _readRegion(_primaryRegion), subCuts: subs);
  }

  void _onBandsChanged() {
    setState(() {
      _baseline = _withFields(_baseline);
      // A blank row always waits at the end of every region, so typing is what
      // adds a band. There is nothing to press first.
      _ensureTrailingBlank(_primaryRegion);
      for (final region in _bandControllers.keys.toList()) {
        if (region != _primaryRegion) _ensureTrailingBlank(region);
      }
    });
  }

  /// Keeps exactly one empty row at the end of a region, and clears away any
  /// empty rows before it — so a band deleted in the middle closes the gap
  /// rather than leaving a hole to tidy up by hand.
  void _ensureTrailingBlank(int region) {
    final bands = _bandControllers[region] ??= <_BandControllers>[];
    bool blank(_BandControllers band) =>
        band.size.text.trim().isEmpty && band.count.text.trim().isEmpty;
    for (var i = bands.length - 2; i >= 0; i--) {
      if (blank(bands[i])) bands.removeAt(i).dispose();
    }
    if (bands.isEmpty || !blank(bands.last)) {
      bands.add(_BandControllers());
    }
  }

  /// The + on a region. A new band starts empty rather than guessing a size —
  /// the drawing should not gain cuts the user did not ask for.
  void _addBand(int region) {
    setState(() {
      (_bandControllers[region] ??= <_BandControllers>[]).add(
        _BandControllers(),
      );
      _baseline = _withFields(_baseline);
    });
  }

  void _removeBand(int region) {
    final bands = _bandControllers[region];
    if (bands == null || bands.isEmpty) return;
    setState(() {
      bands.removeLast().dispose();
      _baseline = _withFields(_baseline);
    });
  }

  /// Which way the sheet is sheared first. Changing it invalidates every
  /// sub-cut, because a strip that ran one way is not the strip that runs the
  /// other — so they are cleared rather than silently reinterpreted.
  void _onPrimaryAxisChanged(SheetCutAxis axis) {
    if (axis == _baseline.primaryAxis) return;
    setState(() {
      for (final region in _bandControllers.keys.toList()) {
        if (region == _primaryRegion) continue;
        for (final band in _bandControllers.remove(region)!) {
          band.dispose();
        }
      }
      _openRegion = null;
      _baseline = _withFields(_baseline.copyWith(primaryAxis: axis));
    });
  }

  /// Switching a region's unit rewrites its fields rather than reinterpreting
  /// them: 40 mm becomes 1.57 in, not 40 in.
  void _onRegionUnitChanged(int region, GlobalLengthUnit unit) {
    if (_unitFor(region).symbol == unit.symbol) return;
    final current = _readRegion(region);
    setState(() {
      _regionUnit[region] = unit.symbol;
      final bands = _bandControllers[region] ?? const <_BandControllers>[];
      for (var i = 0; i < bands.length && i < current.length; i++) {
        bands[i].size.text = _showUnit(current[i].sizeMm, unit);
      }
    });
  }

  /// A millimetre value written in [unit], trimmed the way a shop writes it.
  static String _showUnit(double mm, GlobalLengthUnit unit) {
    if (mm <= 0) return '';
    final shown = unit.fromMm(mm);
    if (shown == shown.roundToDouble()) return shown.toStringAsFixed(0);
    return shown
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// What the drawing calls the sheet: its alloy when there is one.
  String get _materialLabel => _alloy.isEmpty ? 'sheet' : _alloy;

  /// The sheet planned here, in words, for the Input row of Material data:
  /// "MS · First grade · 48 × 14 in · 23 ga".
  String get _sheetLabel {
    final face = lengthUnitBySymbol(_baseline.faceUnit, fallback: 'in');
    final width = _faceText(_baseline.sheetWidthInches, face.symbol);
    // The record's height is the sheet's length.
    final length = _faceText(_baseline.sheetHeightInches, face.symbol);
    final gauge = lengthUnitBySymbol(_baseline.gaugeUnit);
    final thickness = _baseline.sheetThicknessMm > 0
        ? _showUnit(_baseline.sheetThicknessMm, gauge)
        : '';
    final grade = _baseline.materialGrade;
    return <String>[
      _alloy.isEmpty ? 'Sheet' : _alloy,
      if (grade.isNotEmpty) '$grade grade',
      // Width × length, the order the fields are typed in.
      if (width.isNotEmpty && length.isNotEmpty)
        '$width × $length ${face.symbol}',
      if (thickness.isNotEmpty) '$thickness ${gauge.symbol}',
    ].join(' · ');
  }

  void _onMachineChanged() {
    setState(() {
      _baseline = _baseline.copyWith(
        edgeTrimMm: double.tryParse(_trimController.text.trim()) ?? 0,
      );
    });
  }

  /// Picking a part replans the sheet from its blank: strips one blank wide,
  /// then that strip blanked at the blank's own pitch. Both levels, one choice.
  void _applyPart(SheetPart part) {
    setState(() {
      _baseline = _baseline.planFor(part);
      // A part is quoted in millimetres, so every region reads that way after
      // one is applied, whatever it was switched to before.
      _regionUnit.clear();
      _openRegion = _baseline.subCuts.isEmpty ? null : 0;
      _seedControllers();
    });
  }

  /// The primary split in the inches the sheet is drawn in. The baseline worked
  /// out where the strips fall; the drawing only colours where it is told, so
  /// the picture and the cut list cannot disagree.
  List<SheetFigureBand> _primaryFigureBands() => _baseline
      .bandSpansMm(_baseline.primaryAxis)
      .map(
        (span) => SheetFigureBand(
          startInches: _baseline.sizeInInches(span.startMm),
          endInches: _baseline.sizeInInches(span.endMm),
          sizeInches: _baseline.sizeInInches(span.sizeMm),
          count: span.count,
          colourIndex: span.index,
        ),
      )
      .toList(growable: false);

  /// Every region's own cuts, each with the stretch of sheet it belongs to.
  ///
  /// All of them, because the plan is the whole plan: a strip cut ten minutes
  /// ago is still cut, and having it vanish when another strip is opened made
  /// the drawing look like it forgets. Each is clipped to its own region, so
  /// showing them together is not the lattice the two-level model replaced.
  List<SheetRegionCuts> _allRegionCuts() {
    final out = <SheetRegionCuts>[];

    void add(int region, double startMm, double endMm) {
      final groups = _baseline.subCutsFor(region);
      if (groups.isEmpty || endMm <= startMm) return;
      final bands = _regionBands(region, groups);
      if (bands.isEmpty) return;
      out.add(
        SheetRegionCuts(
          fromInches: _baseline.sizeInInches(startMm),
          toInches: _baseline.sizeInInches(endMm),
          bands: bands,
          highlighted: _openRegion == region,
        ),
      );
    }

    for (final span in _baseline.bandSpansMm(_baseline.primaryAxis)) {
      add(span.index, span.startMm, span.endMm);
    }
    add(
      PenPaperBaseline.offcutRegion,
      _baseline.planEndMm(_baseline.primaryAxis),
      _baseline.trimMm(_baseline.primaryAxis) +
          _baseline.usableSpanMm(_baseline.primaryAxis),
    );
    return out;
  }

  /// One region's cuts walked into bands, in the inches the sheet is drawn in.
  List<SheetFigureBand> _regionBands(int region, List<SheetCutGroup> groups) {
    final gap = _baseline.kerfMm;
    final trim = _baseline.trimMm(_baseline.secondaryAxis);
    final limit =
        trim + _baseline.regionExtentMm(region, _baseline.secondaryAxis);
    final out = <SheetFigureBand>[];
    var at = trim;
    var first = true;
    var index = -1;
    for (final group in groups) {
      index++;
      if (!group.isComplete) continue;
      final start = at;
      var placed = 0;
      for (var i = 0; i < group.count; i++) {
        final step = (first ? 0.0 : gap) + group.sizeMm;
        if (at + step > limit + 0.001) break;
        at += step;
        first = false;
        placed++;
      }
      if (placed == 0) continue;
      out.add(
        SheetFigureBand(
          startInches: _baseline.sizeInInches(start),
          endInches: _baseline.sizeInInches(at),
          sizeInches: _baseline.sizeInInches(group.sizeMm),
          count: placed,
          // Continued past the strips, so a blanking band never borrows a
          // strip's colour and means something else by it.
          colourIndex: _baseline.bands.length + index,
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // Sized by the host, not the window: a 520 px side panel on a 1600 px
      // screen is a narrow editor, and reading the window would hand it the
      // side-by-side layout it has no room for.
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : _sideBySideWidth;
          return ColoredBox(color: SoftErpTheme.cardSurface, child: _body(width));
        },
      );
    }

    final media = MediaQuery.of(context);
    final width = (media.size.width * 0.94).clamp(360.0, 1440.0);
    final height = (media.size.height * 0.92).clamp(420.0, 980.0);

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
        boxShadow: SoftErpTheme.raisedShadow,
      ),
      child: _body(width),
    );
  }

  /// Everything inside the frame: title, steps, the step itself, and the
  /// buttons. [width] is the room the panel has, which picks the layout.
  Widget _body(double width) {
    final narrow = width < _sideBySideWidth;
    return Column(
      children: [
        if (widget.showHeader) _header(),
        _formBar(width),
        _stepBar(width),
        Expanded(
          child: Padding(
            padding: narrow && widget.embedded
                ? const EdgeInsets.fromLTRB(16, 14, 16, 8)
                : const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: switch (_step) {
              _MasterStep.sheet => _sheetStep(width),
              _MasterStep.material when _form.isBand => _bandMaterialStep(),
              _MasterStep.material => _materialStep(),
              _MasterStep.review => _reviewStep(),
            },
          ),
        ),
        _footer(width),
      ],
    );
  }

  Widget _stepBar(double width) {
    final compact = width < _compactStepBarWidth;
    final chips = <Widget>[
      for (final step in _MasterStep.values) ...[
        if (step.index > 0)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 8),
            child: const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: SoftErpTheme.textSecondary,
            ),
          ),
        _StepChip(
          index: step.index + 1,
          label: _stepTitle(step),
          selected: step == _step,
          onTap: () => setState(() => _step = step),
        ),
      ],
    ];
    if (compact) {
      // No caption: in a side panel the chips are the whole bar, and they
      // scroll rather than overflow if the panel is narrower still.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: SoftErpTheme.shellSurface,
          border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chips),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      decoration: const BoxDecoration(
        color: SoftErpTheme.shellSurface,
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: [
          for (final step in _MasterStep.values) ...[
            if (step.index > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            _StepChip(
              index: step.index + 1,
              label: _stepTitle(step),
              selected: step == _step,
              // Every step is reachable: this is a record being described, not
              // a wizard with prerequisites, and forcing an order would only
              // stop someone correcting a number they already know is wrong.
              onTap: () => setState(() => _step = step),
            ),
          ],
          const Spacer(),
          Flexible(
            child: Text(
              _step.caption,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Step one, the same for all four forms: who supplied it, the drawing,
  /// then its sizes and the operation beside it. The drawing takes the room
  /// rather than sitting in a band: it is the thing being reasoned about, and
  /// a plan you cannot see the shape of is just a column of numbers again.
  Widget _sheetStep(double panelWidth) {
    const controlsWidth = 392.0;
    final vendor = _vendors == null
        ? const <Widget>[]
        : <Widget>[_vendorRow(), const SizedBox(height: 12)];
    final band = _form.isBand;
    if (panelWidth < _sideBySideWidth) {
      return ListView(
        children: [
          // Who it came from first, then the stock itself.
          ...vendor,
          if (band)
            _bandDrawing()
          else
            SizedBox(height: 320, child: _sheetPanel()),
          const SizedBox(height: 12),
          _dimensionFields(),
          const SizedBox(height: 12),
          _cutOperationBar(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...vendor,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: band
                    ? ListView(
                        padding: EdgeInsets.zero,
                        children: [_bandDrawing()],
                      )
                    : _sheetPanel(),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: controlsWidth,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _dimensionFields(),
                    const SizedBox(height: 12),
                    _cutOperationBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- the form of stock: sheet, strip, coil, roll ------------------------

  String _stepTitle(_MasterStep step) =>
      step == _MasterStep.sheet ? '${_form.label} planning' : step.title;

  /// Vendor and grade are the current form's own: the sheet's are the
  /// record's fields, the others' sit on their form.
  int? get _vendorId =>
      _form.isBand ? _baseline.formOf(_form).vendorId : _baseline.vendorId;

  String get _vendorName =>
      _form.isBand ? _baseline.formOf(_form).vendorName : _baseline.vendorName;

  String get _grade =>
      widget.grade?.trim() ??
      (_form.isBand ? _baseline.formOf(_form).grade : _baseline.materialGrade);

  void _setVendor(int? id, String name) {
    _baseline = _form.isBand
        ? _baseline.withForm(
            _form,
            _baseline.formOf(_form).copyWith(vendorId: id, vendorName: name),
          )
        : _baseline.copyWith(vendorId: id, vendorName: name);
  }

  void _setGrade(String grade) {
    _baseline = _form.isBand
        ? _baseline.withForm(_form, _baseline.formOf(_form).copyWith(grade: grade))
        : _baseline.copyWith(materialGrade: grade);
  }

  void _updateBand(RawStockForm Function(RawStockForm plan) change) {
    setState(() {
      _baseline = _baseline.withForm(_form, change(_baseline.formOf(_form)));
    });
  }

  void _switchForm(RawForm form) {
    if (form == _form) return;
    setState(() {
      _form = form;
      _bandErrors.clear();
      // Recorded, so the panel reopens here — none of the four is a default.
      _baseline = _baseline.copyWith(lastForm: form);
      _writeBandFields();
    });
  }

  void _writeBandFields() {
    if (!_form.isBand) return;
    final plan = _baseline.formOf(_form);
    _bandWidthController.text =
        formatLengthFromNanometres(plan.widthNm, plan.widthUnit);
    _bandLengthController.text =
        formatLengthFromNanometres(plan.lengthNm, plan.lengthUnit);
    _bandPitchController.text =
        formatLengthFromNanometres(plan.pitchNm, plan.pitchUnit);
  }

  /// A measurement typed into a band field: stored exactly, or refused with
  /// the reason beside the field rather than rounded.
  void _onBandLength(
    String field,
    TextEditingController controller,
    String unit,
    RawStockForm Function(RawStockForm plan, int? nanometres) apply,
  ) {
    final parsed = parseLengthToNanometres(controller.text, unit);
    if (parsed.isFailure) {
      setState(() => _bandErrors[field] = parsed.error!);
      return;
    }
    _bandErrors.remove(field);
    _updateBand((plan) => apply(plan, parsed.nanometres));
  }

  /// The four forms, side by side and equal. A dot marks the ones that hold
  /// something; none is marked as the default.
  Widget _formBar(double width) {
    final compact = width < _compactStepBarWidth;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(compact ? 12 : 22, 10, compact ? 12 : 22, 10),
      decoration: const BoxDecoration(
        color: SoftErpTheme.shellSurface,
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: [
          for (final (index, form) in RawForm.values.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: _FormTile(
                key: ValueKey<String>('raw-form-${form.name}'),
                form: form,
                selected: form == _form,
                hasData: _baseline.hasForm(form),
                onTap: () => _switchForm(form),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _nmLabel(int? nm, String unit) =>
      nm == null ? '' : '${formatLengthFromNanometres(nm, unit)} $unit';

  static double? _mmOf(int? nm) =>
      nm == null ? null : nm / nanometresPerMillimetre;

  /// The strip, coil or roll, drawn as its own stock — never as cut from the
  /// sheet — with its measurements on it. Keyed by form, so a switch plays
  /// the new one; typing only redraws it.
  Widget _bandDrawing() {
    final plan = _baseline.formOf(_form);
    return BandFormAnimation(
      key: ValueKey<String>('band-animation-${_form.name}'),
      form: _form,
      widthMm: _mmOf(plan.widthNm),
      thicknessMm: _baseline.sheetThicknessMm > 0
          ? _baseline.sheetThicknessMm
          : null,
      lengthMm: plan.lengthKnown ? _mmOf(plan.lengthNm) : null,
      pitchMm: _mmOf(plan.pitchNm),
      widthLabel: _nmLabel(plan.widthNm, plan.widthUnit),
      thicknessLabel: _thicknessShown,
      lengthLabel: _nmLabel(plan.lengthNm, plan.lengthUnit),
      pitchLabel: _nmLabel(plan.pitchNm, plan.pitchUnit),
    );
  }

  /// The thickness as the fields show it — "1.2 mm", "23 ga" — or empty.
  String get _thicknessShown {
    final text = _thicknessController.text.trim();
    if (text.isEmpty) return '';
    return '$text ${lengthUnitBySymbol(_baseline.gaugeUnit).symbol}';
  }

  /// A band's width, laid out like the sheet's so the four forms read alike.
  Widget _bandWidthField() {
    final plan = _baseline.formOf(_form);
    return _DimensionField(
      key: ValueKey<String>('${_form.name}-width'),
      controller: _bandWidthController,
      label: 'Width',
      unit: plan.widthUnit,
      readOnly: widget.readOnly,
      errorText: _bandErrors['width'],
      onChanged: () => _onBandLength(
        'width',
        _bandWidthController,
        plan.widthUnit,
        (p, nm) => p.copyWith(widthNm: nm),
      ),
      unitWidget: _UnitPicker(
        symbol: plan.widthUnit,
        options: faceLengthUnits,
        onChanged: widget.readOnly
            ? null
            : (unit) {
                _updateBand((p) => p.copyWith(widthUnit: unit.symbol));
                _bandWidthController.text =
                    formatLengthFromNanometres(plan.widthNm, unit.symbol);
              },
      ),
    );
  }

  /// A band's length: Undefined, which it usually is — nobody knows when a
  /// coil's length comes down — or a length, once somebody does.
  Widget _bandLengthField() {
    final plan = _baseline.formOf(_form);
    final known = plan.lengthKnown || _lengthOpen.contains(_form);
    final enabled = !widget.readOnly;
    final choice = Builder(
      builder: (anchor) => Tooltip(
        message: known ? 'Back to undefined' : 'Undefined, or a known length',
        child: InkWell(
          key: ValueKey<String>('${_form.name}-length'),
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
          onTap: enabled ? () => _pickLength(anchor) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(
              Icons.arrow_drop_down_rounded,
              size: 22,
              color: enabled
                  ? SoftErpTheme.textPrimary
                  : SoftErpTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
    if (!known) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LENGTH', style: _fieldLabel),
          const SizedBox(height: 5),
          Container(
            key: ValueKey<String>('${_form.name}-length-undefined'),
            height: 44,
            padding: const EdgeInsets.only(left: 10, right: 2),
            decoration: BoxDecoration(
              color: SoftErpTheme.shellSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Undefined',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                choice,
              ],
            ),
          ),
        ],
      );
    }
    return _DimensionField(
      key: ValueKey<String>('${_form.name}-length-value'),
      controller: _bandLengthController,
      label: 'Length',
      unit: plan.lengthUnit,
      readOnly: widget.readOnly,
      errorText: _bandErrors['length'],
      onChanged: () => _onBandLength(
        'length',
        _bandLengthController,
        plan.lengthUnit,
        (p, nm) => p.copyWith(lengthNm: nm),
      ),
      unitWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UnitPicker(
            symbol: plan.lengthUnit,
            options: faceLengthUnits,
            onChanged: widget.readOnly
                ? null
                : (unit) {
                    _updateBand((p) => p.copyWith(lengthUnit: unit.symbol));
                    _bandLengthController.text =
                        formatLengthFromNanometres(plan.lengthNm, unit.symbol);
                  },
          ),
          choice,
        ],
      ),
    );
  }

  Future<void> _pickLength(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<bool>(
      context: anchor,
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy + box.size.height,
        overlay.size.width - at.dx - box.size.width,
        0,
      ),
      items: const [
        PopupMenuItem<bool>(
          value: false,
          child: Text('Undefined', style: TextStyle(fontSize: 14)),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: Text('Known length', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _bandErrors.remove('length');
      if (picked) {
        _lengthOpen.add(_form);
      } else {
        _lengthOpen.remove(_form);
        _bandLengthController.clear();
        _baseline = _baseline.withForm(
          _form,
          _baseline.formOf(_form).copyWith(lengthNm: null),
        );
      }
    });
  }

  static const TextStyle _fieldLabel = SheetStyle.label;

  /// The press's advance per part, for this form.
  Widget _bandPitchRow() {
    final plan = _baseline.formOf(_form);
    return _DimensionField(
      key: ValueKey<String>('${_form.name}-pitch'),
      controller: _bandPitchController,
      label: 'Pitch — one part every',
      unit: plan.pitchUnit,
      readOnly: widget.readOnly,
      errorText: _bandErrors['pitch'],
      onChanged: () => _onBandLength(
        'pitch',
        _bandPitchController,
        plan.pitchUnit,
        (p, nm) => p.copyWith(pitchNm: nm),
      ),
      unitWidget: _UnitPicker(
        symbol: plan.pitchUnit,
        options: faceLengthUnits,
        onChanged: widget.readOnly
            ? null
            : (unit) {
                _updateBand((p) => p.copyWith(pitchUnit: unit.symbol));
                _bandPitchController.text =
                    formatLengthFromNanometres(plan.pitchNm, unit.symbol);
              },
      ),
    );
  }

  /// What a band yields: a rate while its length is undefined, a count once
  /// it is known. One part across — a band is fed, not nested.
  Widget _bandYield() {
    final plan = _baseline.formOf(_form);
    final noun = _form.label.toLowerCase();
    final pitch = _nmLabel(plan.pitchNm, plan.pitchUnit);
    final parts = plan.partsFromLength();
    final String line;
    if ((plan.pitchNm ?? 0) <= 0) {
      line = 'Set the pitch to say how often a part comes off the $noun.';
    } else if (parts == null) {
      line = 'One part every $pitch of $noun.';
    } else {
      line = '≈ $parts parts from '
          '${_nmLabel(plan.lengthNm, plan.lengthUnit)} of $noun — '
          'one every $pitch.';
    }
    return Text(
      key: ValueKey<String>('${_form.name}-yield'),
      line,
      style: const TextStyle(
        color: SoftErpTheme.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// What a strip, coil or roll is called on the Input row.
  String get _bandLabel {
    final plan = _baseline.formOf(_form);
    final grade = _grade;
    final thickness = _thicknessShown;
    final bits = <String>[
      if (_alloy.isNotEmpty) _alloy,
      if (grade.isNotEmpty) '$grade grade',
      if (plan.widthNm != null) '${_nmLabel(plan.widthNm, plan.widthUnit)} wide',
      if (thickness.isNotEmpty) thickness,
    ];
    final noun = _form.label.toLowerCase();
    return bits.isEmpty ? noun : '$noun · ${bits.join(' · ')}';
  }

  /// Step two for a strip, coil or roll: one row, weight in and pieces out,
  /// both typed — there is no plan to fill them from and no density.
  Widget _bandMaterialStep() {
    final plan = _baseline.formOf(_form);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dataHeading(),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: SingleChildScrollView(
              child: PenPaperBaselineWidget(
                key: ValueKey<String>('material-${_form.name}'),
                baseline: PenPaperBaseline(
                  stageReconciliations: plan.hasData
                      ? [plan.reconciliation]
                      : const <PenPaperStageReconciliation>[],
                  notes: '',
                ),
                readOnly: widget.readOnly,
                showChrome: false,
                pipelineId: widget.pipelineId,
                pipelineName: widget.pipelineName,
                unattachedHint: widget.unattachedHint,
                itemName: widget.itemName,
                sheetLabel: _bandLabel,
                countFamily: _countFamily,
                stockNoun: _form.label.toLowerCase(),
                allowStageByStage: false,
                onChanged: (updated) {
                  final row = updated.stageReconciliations.firstOrNull;
                  if (row == null) return;
                  _updateBand((p) => p.copyWith(reconciliation: row));
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _materialStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dataHeading(),
        const SizedBox(height: 8),
        Expanded(child: _dataPanel()),
      ],
    );
  }

  /// The record as it will be saved: without the blank rows the editor keeps
  /// for typing into, and — while Material data still follows the plan — with
  /// the plan's figures in it, whether or not that step was ever opened. Save
  /// from step 1 used to store the generic 100 kg defaults behind it.
  PenPaperBaseline get _recorded {
    // The part's alloy is stamped on, so the record says what it was cut from
    // even after the part's Alloy is changed.
    // So are its grade and thickness, onto every form it holds.
    var baseline = _baseline.withoutEmptyBands.copyWith(materialName: _alloy);
    final partGrade = widget.grade?.trim();
    if (partGrade != null) {
      baseline = baseline.copyWith(materialGrade: partGrade);
    }
    final thicknessMm = baseline.sheetThicknessMm;
    final gauge = lengthUnitBySymbol(baseline.gaugeUnit);
    for (final entry in baseline.forms.entries) {
      baseline = baseline.withForm(
        entry.key,
        entry.value.copyWith(
          grade: partGrade ?? entry.value.grade,
          thicknessNm: thicknessMm > 0
              ? (thicknessMm * nanometresPerMillimetre).round()
              : null,
          // A gauge is a lookup, not a length; the band keeps millimetres.
          thicknessUnit: gauge.isGauge ? 'mm' : gauge.symbol,
        ),
      );
    }
    if (!baseline.materialFromPlan || baseline.isGranular) return baseline;
    return baseline.copyWith(
      stageReconciliations: [
        baseline.reconciliationFromPlan(
          sheetLabel: _sheetLabel,
          partName: widget.itemName.trim(),
          keepFrom: baseline.stageReconciliations.firstOrNull,
        ),
      ],
    );
  }

  List<RawSheetReviewSection> _reviewSections(PenPaperBaseline recorded) =>
      rawSheetReviewSections(
        baseline: recorded,
        partName: widget.itemName,
        sheetLabel: _sheetLabel,
        countFamily: _countFamily,
      );

  /// What will be recorded, on one page — and the same page printed.
  Widget _reviewStep() {
    final recorded = _recorded;
    final sections = _reviewSections(recorded);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'AS IT WILL BE RECORDED',
                style: SheetStyle.eyebrow,
              ),
            ),
            TextButton.icon(
              key: const ValueKey<String>('raw-review-print'),
              onPressed: () => showRawSheetReviewPrint(
                context,
                baseline: recorded,
                sections: sections,
                partName: widget.itemName,
              ),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text(
                'Print / PDF',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: SingleChildScrollView(
              child: RawSheetReviewCard(
                key: const ValueKey<String>('raw-review-card'),
                sections: sections,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final on = widget.pipelineName.trim().isEmpty
        ? 'no pipeline'
        : widget.pipelineName.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 14, 14),
      decoration: const BoxDecoration(
        color: SoftErpTheme.shellSurface,
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Master Data',
                  style: TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.itemName.trim().isEmpty
                      ? 'Recorded on $on'
                      : '${widget.itemName.trim()} · on $on',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onCancel != null)
            IconButton(
              tooltip: 'Close',
              onPressed: widget.onCancel,
              style: IconButton.styleFrom(
                backgroundColor: SoftErpTheme.shellSurface,
                foregroundColor: SoftErpTheme.textPrimary,
                side: const BorderSide(color: SoftErpTheme.borderStrong),
              ),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }

  Widget _sheetPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        // White, not the section wash: the drawing is ink on paper and the
        // hairlines only read that way against it.
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THE SHEET',
            style: SheetStyle.eyebrow,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SheetDimensionFigure(
              widthInches: _baseline.sheetWidthInches,
              heightInches: _baseline.sheetHeightInches,
              thicknessMm: _baseline.sheetThicknessMm,
              materialLabel: _materialLabel,
              trimXInches: _baseline.sizeInInches(
                _baseline.trimMm(SheetCutAxis.columns),
              ),
              trimYInches: _baseline.sizeInInches(
                _baseline.trimMm(SheetCutAxis.rows),
              ),
              columnBands: _baseline.primaryAxis == SheetCutAxis.columns
                  ? _primaryFigureBands()
                  : const <SheetFigureBand>[],
              rowBands: _baseline.primaryAxis == SheetCutAxis.rows
                  ? _primaryFigureBands()
                  : const <SheetFigureBand>[],
              columnPlanEndInches: _baseline.sizeInInches(
                _baseline.planEndMm(SheetCutAxis.columns),
              ),
              rowPlanEndInches: _baseline.sizeInInches(
                _baseline.planEndMm(SheetCutAxis.rows),
              ),
              primaryIsColumns: _baseline.primaryAxis == SheetCutAxis.columns,
              regionCuts: _allRegionCuts(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _summaryLine(),
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// The derived reading — area once both sides are in, volume once it has a
  /// gauge. Stays quiet rather than printing zeros for what has not been typed.
  String _summaryLine() {
    final area = _baseline.sheetAreaSqInches;
    if (area <= 0) return 'Enter width and length to draw the sheet.';
    final volume = _baseline.sheetVolumeCc;
    final areaText = '${_trim(area)} in²';
    if (volume <= 0) return '$areaText · add a thickness for volume';
    return '$areaText · ${_trim(volume)} cm³ per sheet';
  }

  static String _trim(double value) {
    if (value >= 1000) return value.toStringAsFixed(0);
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    // Trailing zeros read as false precision on a shop figure: 19.2 mm, not
    // 19.20 mm.
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  Widget _dimensionFields() {
    final face = lengthUnitBySymbol(_baseline.faceUnit, fallback: 'in');
    final gauge = lengthUnitBySymbol(_baseline.gaugeUnit);
    Widget facePicker() => _UnitPicker(
      symbol: face.symbol,
      // Everything but gauge: a gauge is a thickness, never a length across.
      options: faceLengthUnits,
      onChanged: widget.readOnly ? null : _onFaceUnitChanged,
    );
    final fromPart = widget.thickness != null;
    // Width, length, thickness — the same three, in the same places, for all
    // four forms. A band's length is usually undefined.
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _form.isBand
              ? _bandWidthField()
              : _DimensionField(
                  key: const ValueKey<String>('sheet-width'),
                  controller: _widthController,
                  label: 'Width',
                  // The face is one measurement in two directions, so both
                  // sides read in the same unit — a sheet quoted 96 in by
                  // 1219 mm is a mistake waiting to be made.
                  unit: face.symbol,
                  readOnly: widget.readOnly,
                  onChanged: _onDimensionChanged,
                  unitWidget: facePicker(),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _form.isBand
              ? _bandLengthField()
              : _DimensionField(
                  key: const ValueKey<String>('sheet-length'),
                  // The record's height is the sheet's length.
                  controller: _heightController,
                  label: 'Length',
                  unit: face.symbol,
                  readOnly: widget.readOnly,
                  onChanged: _onDimensionChanged,
                  unitWidget: facePicker(),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: fromPart
                ? 'The part’s Thickness — a change here changes it there'
                : '',
            child: _DimensionField(
              key: const ValueKey<String>('raw-thickness'),
              controller: _thicknessController,
              focusNode: _thicknessFocus,
              label: 'Thickness',
              unit: gauge.symbol,
              readOnly: widget.readOnly,
              onChanged: _onThicknessTyped,
              // Gauge belongs here and nowhere else, so this picker keeps the
              // whole catalogue.
              unitWidget: _UnitPicker(
                symbol: gauge.symbol,
                onChanged: widget.readOnly ? null : _onGaugeUnitChanged,
              ),
            ),
          ),
        ),
      ],
    );
    final unreadable = _thicknessUnreadable;
    if (unreadable == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        const SizedBox(height: 6),
        Text(
          '“$unreadable” in the Thickness column is not a measurement.',
          style: const TextStyle(
            color: SoftErpTheme.warningText,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _cutOperationBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'OPERATION',
                style: SheetStyle.eyebrow,
              ),
              const SizedBox(width: 6),
              // The definitions live under a hover rather than on the panel:
              // they are read once and then never again, and left inline they
              // cost every later glance the space they took.
              // A WidgetSpan, because Tooltip has no width of its own: left
              // to a bare TextSpan it grows to whatever the dialog is wide and
              // lands on top of the header.
              Tooltip(
                richMessage: WidgetSpan(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _form.isBand ? 'Pitch' : 'Edge trim',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _form.isBand
                              ? 'How far the ${_form.label.toLowerCase()} '
                                  'advances for each part — one part comes '
                                  'off every pitch, the blank and the web '
                                  'left between blanks together.'
                              : 'The strip nobody cuts into — the damaged '
                                  'mill edge, the machine clamp, the straight '
                                  'edge you gauge from. Comes off one pair of '
                                  'sides only: left & right (across the '
                                  'width) or top & bottom (along the length).',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                preferBelow: true,
                child: const Icon(
                  Icons.help_outline_rounded,
                  size: 15,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.parts.isNotEmpty) ...[
            _partPicker(),
            const SizedBox(height: 10),
          ],
          if (widget.alloy != null ||
              widget.grade != null ||
              widget.materials.isNotEmpty) ...[
            _alloyRow(),
            const SizedBox(height: 10),
          ],
          // The sheet is sheared into strips and blanks; a strip, coil or
          // roll is fed through the press, one part every pitch.
          if (_form.isBand) ...[
            _bandPitchRow(),
            const SizedBox(height: 10),
            _bandYield(),
          ] else ...[
            _machineRow(),
            const SizedBox(height: 10),
            _primaryBlock(),
            _regionBlocks(),
            _yieldBlock(),
          ],
        ],
      ),
    );
  }

  /// The part being cut, from the catalogue rather than from typed sizes.
  ///
  /// The client's whole complaint about paper is re-deriving what the system
  /// already holds. If a part carries a blank size, planning it should be one
  /// choice, not four numbers copied off a drawing.
  Widget _partPicker() {
    final planned = _baseline.plannedPartName.trim();
    return Row(
      children: [
        const SizedBox(
          width: _labelWidth,
          child: Text(
            'PART',
            style: _rowLabel,
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 32,
            child: DropdownButtonFormField<int>(
              key: const ValueKey<String>('sheet-part'),
              initialValue:
                  widget.parts.any((part) => part.id == _baseline.plannedPartId)
                  ? _baseline.plannedPartId
                  : null,
              isDense: true,
              isExpanded: true,
              hint: Text(
                planned.isEmpty ? 'Typed by hand' : planned,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                filled: true,
                fillColor: SoftErpTheme.cardSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
              ),
              items: <DropdownMenuItem<int>>[
                for (final part in widget.parts)
                  DropdownMenuItem<int>(
                    value: part.id,
                    child: Text(
                      '${part.name}  ·  ${part.sizeLabel}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: widget.readOnly
                  ? null
                  : (id) {
                      final part = widget.parts
                          .where((candidate) => candidate.id == id)
                          .firstOrNull;
                      if (part != null) _applyPart(part);
                    },
            ),
          ),
        ),
      ],
    );
  }

  /// The material the sheet is, from the master.
  ///
  /// One choice, and every figure on this screen gains a weight — which is the
  /// only reason the shop can price a plan without putting anything on a scale.
  /// The alloy the sheet is: the part's own when the host has an Alloy
  /// column, else whatever this record was given.
  String get _alloy => (widget.alloy ?? _baseline.materialName).trim();

  static const TextStyle _rowLabel = SheetStyle.label;

  /// The label column beside a value — wide enough for TRIM SIDES at 13px,
  /// which the old 74 (and one stray 78) wrapped.
  static const double _labelWidth = 96;

  /// Alloy and its grade. The alloy is the part's (changed in its Alloy
  /// column, never here) when the host gives one; the grade is the sheet's.
  /// No density and no weight: what an alloy weighs depends on its grade, so
  /// the weights in Material data are what went on the scale.
  /// A value the part owns, shown here and changed in its own column.
  static Widget _partValueBox({
    required Key key,
    required String value,
    required String column,
    required String unset,
  }) {
    return Tooltip(
      message: 'Change it in the $column column of the part',
      child: Container(
        key: key,
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: SoftErpTheme.sectionSurface,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Text(
          value.isEmpty ? unset : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: value.isEmpty
                ? SoftErpTheme.textSecondary
                : SoftErpTheme.textPrimary,
            fontSize: 14,
            fontWeight: value.isEmpty ? FontWeight.w600 : FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _alloyRow() {
    final alloy = _alloy;
    final fromPart = widget.alloy != null;
    final enabled = !widget.readOnly;
    final Widget alloyField = fromPart
        ? _partValueBox(
            key: const ValueKey<String>('sheet-alloy'),
            value: alloy,
            column: 'Alloy',
            unset: 'Not set — pick it in the Alloy column',
          )
        : _MaterialPickerField(
            key: const ValueKey<String>('sheet-material'),
            label: alloy,
            trailing: '',
            hint: 'Not set',
            enabled: enabled && widget.materials.isNotEmpty,
            onPressed: enabled && widget.materials.isNotEmpty
                ? (anchorContext) async {
                    final picked = await _showMaterialMenu(anchorContext);
                    if (picked == null || !mounted) return;
                    setState(() {
                      _baseline = _baseline.copyWith(materialName: picked);
                    });
                  }
                : null,
          );
    final grade = _grade;
    final Widget gradeField = widget.grade != null
        ? _partValueBox(
            key: const ValueKey<String>('part-grade'),
            value: grade,
            column: 'Grade',
            unset: 'Not set — add a Grade column in Properties',
          )
        : DropdownButtonFormField<String>(
      // Per form, so switching forms shows that form's grade.
      key: ValueKey<String>('${_form.name}-grade'),
      initialValue: PenPaperBaseline.grades.contains(grade) ? grade : '',
      isDense: true,
      isExpanded: true,
      style: const TextStyle(
        color: SoftErpTheme.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl)),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Not set')),
        for (final g in PenPaperBaseline.grades)
          DropdownMenuItem(value: g, child: Text('$g grade')),
      ],
      onChanged: enabled
          ? (value) => setState(() => _setGrade(value ?? ''))
          : null,
    );
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: _labelWidth, child: Text('ALLOY', style: _rowLabel)),
            Expanded(child: alloyField),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: _labelWidth, child: Text('GRADE', style: _rowLabel)),
            Expanded(child: gradeField),
          ],
        ),
      ],
    );
  }

  /// Who supplied the sheet, from the Vendors master. A name typed that is
  /// not there yet is added to it, so the next sheet offers it.
  Widget _vendorRow() {
    final vendors = _vendors;
    if (vendors == null) return const SizedBox.shrink();
    final listed = [
      for (final vendor in vendors.vendors)
        if (!vendor.isArchived || vendor.id == _vendorId) vendor,
    ];
    final current = _vendorId;
    final enabled = !widget.readOnly;
    return Row(
      children: [
        const SizedBox(width: _labelWidth, child: Text('VENDOR', style: _rowLabel)),
        Expanded(
          child: SearchableSelectField<int>(
            key: ValueKey<String>('${_form.name}-vendor'),
            value: listed.any((v) => v.id == current) ? current : null,
            fieldEnabled: enabled,
            dialogTitle: 'Vendor',
            searchHintText: 'Search or add a vendor',
            emptyText: 'No vendors yet — type a name to add one',
            options: [
              for (final vendor in listed)
                SearchableSelectOption<int>(
                  value: vendor.id,
                  label: vendor.displayLabel,
                  searchText: '${vendor.name} ${vendor.alias}',
                ),
            ],
            decoration: InputDecoration(
              isDense: true,
              hintText: _vendorName.isNotEmpty
                  ? _vendorName
                  : 'Who supplied the ${_form.label.toLowerCase()}',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
              ),
            ),
            canCreateOption: (query, options) =>
                enabled &&
                query.trim().isNotEmpty &&
                !options.any(
                  (o) => o.label.toLowerCase() == query.trim().toLowerCase(),
                ),
            createOptionLabelBuilder: (query) => 'Add vendor "${query.trim()}"',
            onCreateOption: (query) async {
              final created = await vendors.createVendor(
                CreateVendorInput(name: query.trim()),
              );
              if (created == null) return null;
              if (mounted) setState(() => _setVendor(created.id, created.name));
              return SearchableSelectOption<int>(
                value: created.id,
                label: created.displayLabel,
              );
            },
            onChanged: (id) {
              final vendor = vendors.findById(id);
              setState(() => _setVendor(id, vendor?.name ?? ''));
            },
          ),
        ),
      ],
    );
  }

  /// Opened under the field, capped in height and kept on screen.
  ///
  /// A plain dropdown menu of thirty-six materials is taller than the window
  /// and opens over the controls it belongs to, which is how it stopped being
  /// usable. This is the same list the unit chips use: anchored, bounded, and
  /// searched rather than scrolled.
  Future<String?> _showMaterialMenu(BuildContext anchorContext) {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return Future<String?>.value();
    return showDialog<String>(
      context: anchorContext,
      barrierColor: Colors.transparent,
      builder: (context) => _MaterialMenu(
        materials: widget.materials,
        currentName: _baseline.materialName,
        anchor: box.localToGlobal(Offset.zero, ancestor: overlay),
        anchorWidth: box.size.width,
        anchorHeight: box.size.height,
        overlaySize: overlay.size,
      ),
    );
  }

  /// What the sheet costs before any part is planned: the edge nobody will
  /// cut into, and which pair of sides it comes off. Above both axes, because
  /// it belongs to the stock, not to a band — and it is the figure a paper
  /// plan leaves out, which is much of why one comes up short on the floor.
  Widget _machineRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: _labelWidth,
              child: Text(
                'EDGE TRIM',
                style: _rowLabel,
              ),
            ),
            Expanded(
              child: _PlainNumberField(
                fieldKey: const ValueKey<String>('sheet-trim'),
                controller: _trimController,
                hint: '0',
                readOnly: widget.readOnly,
                onChanged: _onMachineChanged,
              ),
            ),
            const SizedBox(width: 6),
            const SizedBox(
              width: 28,
              child: Text(
                'mm',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // The trim comes off one pair of edges, not all four — so say which.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            const SizedBox(
              width: _labelWidth,
              child: Text(
                'TRIM SIDES',
                style: _rowLabel,
              ),
            ),
            _AxisChoice(
              axis: _baseline.edgeTrimAxis,
              keyPrefix: 'sheet-trim-axis',
              labelOf: (axis) => axis == SheetCutAxis.columns
                  ? 'left & right'
                  : 'top & bottom',
              onChanged: widget.readOnly
                  ? null
                  : (axis) => setState(() {
                      _baseline = _baseline.copyWith(edgeTrimAxis: axis);
                    }),
            ),
          ],
        ),
      ],
    );
  }

  /// One axis: the stepper that adds and removes bands, then a row per band.
  /// The sheet-wide split: which way the sheet is sheared, and into what.
  Widget _primaryBlock() {
    final bands =
        _bandControllers[_primaryRegion] ?? const <_BandControllers>[];
    final axis = _baseline.primaryAxis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'SHEAR INTO',
              style: SheetStyle.subHeading,
            ),
            const Spacer(),
            _UnitPicker(
              symbol: _unitFor(_primaryRegion).symbol,
              onChanged: widget.readOnly
                  ? null
                  : (unit) => _onRegionUnitChanged(_primaryRegion, unit),
            ),
          ],
        ),
        // Which way the first cut runs. On its own line: with the title and the
        // unit switch, the header has no room for it.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              const Text(
                'into',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              _AxisChoice(
                axis: axis,
                onChanged: widget.readOnly ? null : _onPrimaryAxisChanged,
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 28),
          child: _BandHeader(),
        ),
        for (var i = 0; i < bands.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _bandRow(_primaryRegion, i),
          ),
        if (_baseline.bands.any((group) => group.isComplete)) ...[
          const SizedBox(height: 6),
          Text(
            _baseline.usableSpanMm(axis) <= 0
                ? 'Measure ${axis == SheetCutAxis.columns ? 'the width' : 'the height'} first — there is nothing to divide yet.'
                : _primarySentence(),
            style: TextStyle(
              color:
                  _baseline.usableSpanMm(axis) <= 0 || _baseline.overruns(axis)
                  ? SoftErpTheme.warningText
                  : SoftErpTheme.textSecondary,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  /// Every region the plan made, each openable to be cut its own way.
  ///
  /// This is the answer to "where does this cut go?": a cut lands in a region,
  /// and the regions are the strips the shear produced plus whatever is left.
  Widget _regionBlocks() {
    if (!_baseline.bands.any((group) => group.isComplete)) {
      return const SizedBox.shrink();
    }
    final regions = _baseline.regions;
    if (regions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1, color: SoftErpTheme.border),
        const SizedBox(height: 10),
        const Text(
          'THEN CUT A REGION',
          style: SheetStyle.eyebrow,
        ),
        const SizedBox(height: 8),
        for (final region in regions) _regionRow(region),
      ],
    );
  }

  Widget _regionRow(SheetRegion region) {
    final open = _openRegion == region.index;
    final subs = _bandControllers[region.index] ?? const <_BandControllers>[];
    final planned = _baseline.subCutsFor(region.index);
    final made = planned.where((group) => group.isComplete).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: open ? SoftErpTheme.cardSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(
          color: open ? SoftErpTheme.accent : SoftErpTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey<String>('region-${region.index}'),
            onTap: () => setState(() {
              _openRegion = open ? null : region.index;
              // Opening a region gives it the blank row to type into, the same
              // way every region gets one as soon as it can be cut.
              if (!open) _ensureTrailingBlank(region.index);
            }),
            child: Row(
              children: [
                _BandSwatch(
                  colour: region.isOffcut
                      ? SoftErpTheme.warningText
                      : sheetBandColour(region.index),
                  label: region.label,
                  live: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_trim(region.widthMm)} × ${_trim(region.heightMm)} mm'
                    '${region.copies > 1 ? '  ·  ${region.copies}×' : ''}',
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (made > 0 && !open)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '$made cut${made == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: SoftErpTheme.successText,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: SoftErpTheme.textSecondary,
                ),
              ],
            ),
          ),
          if (open) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'CUT ALONG ${_baseline.secondaryAxis.letter.toUpperCase()}',
                  style: _rowLabel,
                ),
                const Spacer(),
                _UnitPicker(
                  symbol: _unitFor(region.index).symbol,
                  onChanged: widget.readOnly
                      ? null
                      : (unit) => _onRegionUnitChanged(region.index, unit),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 28),
              child: _BandHeader(),
            ),
            for (var i = 0; i < subs.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _bandRow(region.index, i),
              ),
          ],
        ],
      ),
    );
  }

  /// One band: its size, how many, and — beside the size, where the answer
  /// belongs — how many of that size the region could still take.
  Widget _bandRow(int region, int index) {
    final bands = _bandControllers[region] ?? const <_BandControllers>[];
    if (index >= bands.length) return const SizedBox.shrink();
    final band = bands[index];
    final primary = region == _primaryRegion;
    final axis = primary ? _baseline.primaryAxis : _baseline.secondaryAxis;
    final groups = primary ? _baseline.bands : _baseline.subCutsFor(region);
    final group = index < groups.length ? groups[index] : const SheetCutGroup();
    final fits = _baseline.fitsRemaining(
      axis,
      group.sizeMm,
      ignoreIndex: index,
      region: primary ? null : region,
    );
    final asks = group.count;
    final colour = primary
        ? sheetBandColour(index)
        : sheetBandColour(_baseline.bands.length + index);
    return Row(
      children: [
        _BandSwatch(
          colour: colour,
          label: '${axis.letter}${index + 1}',
          live: group.isComplete,
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: _PlainNumberField(
            fieldKey: ValueKey<String>('band-size-$region-$index'),
            controller: band.size,
            hint: 'size',
            readOnly: widget.readOnly,
            onChanged: _onBandsChanged,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '×',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _PlainNumberField(
            fieldKey: ValueKey<String>('band-count-$region-$index'),
            controller: band.count,
            hint: 'qty',
            integerOnly: true,
            readOnly: widget.readOnly,
            onChanged: _onBandsChanged,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: Text(
            group.sizeMm <= 0 ? '' : (asks > fits ? '≤$fits' : '$fits'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: group.sizeMm <= 0
                  ? SoftErpTheme.textSecondary
                  : (asks > fits
                        ? SoftErpTheme.dangerText
                        : SoftErpTheme.successText),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        // On the row it removes, rather than a shared − that takes the last
        // one: with several bands, "remove the last" is never what is meant.
        SizedBox(
          width: 22,
          child: group.sizeMm <= 0 && asks <= 0
              ? null
              : _RowRemove(
                  onTap: widget.readOnly
                      ? null
                      : () => _removeBandAt(region, index),
                ),
        ),
      ],
    );
  }

  /// Takes one band out, wherever it sits.
  void _removeBandAt(int region, int index) {
    final bands = _bandControllers[region];
    if (bands == null || index >= bands.length) return;
    setState(() {
      bands.removeAt(index).dispose();
      _baseline = _withFields(_baseline);
      _ensureTrailingBlank(region);
    });
  }

  /// What the shear takes off the sheet, and what it leaves.
  String _primarySentence() {
    final axis = _baseline.primaryAxis;
    final used = _baseline.plannedSpanMm(axis);
    final pieces = _baseline.plannedPieces(axis);
    if (used <= 0) {
      return 'Nothing claimed of ${_trim(_baseline.usableSpanMm(axis))} mm '
          'usable.';
    }
    if (_baseline.overruns(axis)) {
      return '$pieces strips need '
          '${_trim(_baseline.plannedConsumedMm(axis))} mm — '
          '${_trim(_baseline.overrunMm(axis))} mm more than the sheet has.';
    }
    final blade = _baseline.kerfLossMm(axis);
    final left = _baseline.remainderMm(axis);
    return <String>[
      '$pieces strips',
      '${_trim(used)} of ${_trim(_baseline.usableSpanMm(axis))} mm',
      if (blade > 0.05) '${_trim(blade)} mm gap',
      if (left >= 0.05) '${_trim(left)} mm left',
      '${_baseline.yieldPercent(axis).toStringAsFixed(0)}% yield',
    ].join(' · ');
  }

  /// What the plan actually produces — a list, because bands of different sizes
  /// make different parts and adding them into one number says nothing.
  Widget _yieldBlock() {
    final yields = _baseline.yields;
    if (yields.isEmpty) return const SizedBox.shrink();
    final parts = yields.where((entry) => !entry.isOffcut).toList();
    final waste = yields.where((entry) => entry.isOffcut).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const Divider(height: 1, color: SoftErpTheme.border),
        const SizedBox(height: 8),
        const Text(
          'THIS SHEET YIELDS',
          style: SheetStyle.eyebrow,
        ),
        const SizedBox(height: 6),
        for (final entry in parts) _yieldRow(entry),
        for (final entry in waste) _yieldRow(entry),
      ],
    );
  }

  Widget _yieldRow(SheetYield entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: entry.isOffcut
                  ? SoftErpTheme.warningText.withValues(alpha: 0.5)
                  : sheetBandColour(entry.colourIndex).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${entry.count}×',
            style: TextStyle(
              color: entry.isOffcut
                  ? SoftErpTheme.textSecondary
                  : SoftErpTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.sizeLabel,
              style: TextStyle(
                color: entry.isOffcut
                    ? SoftErpTheme.textSecondary
                    : SoftErpTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            entry.isOffcut ? 'offcut' : entry.label,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataHeading() {
    return const Text(
      'WHAT IT PRODUCED',
      style: SheetStyle.eyebrow,
    );
  }

  Widget _dataPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: SingleChildScrollView(
        child: PenPaperBaselineWidget(
          baseline: _baseline,
          readOnly: widget.readOnly,
          showChrome: false,
          pipelineId: widget.pipelineId,
          pipelineName: widget.pipelineName,
          unattachedHint: widget.unattachedHint,
          stageNodes: widget.stageNodes,
          itemName: widget.itemName,
          sheetLabel: _sheetLabel,
          countFamily: _countFamily,
          followsSheetPlan: true,
          // The widget edits a copy of this very record, so what comes back
          // is the whole of it — the sheet plan included.
          onChanged: (updated) => setState(() => _baseline = updated),
        ),
      ),
    );
  }

  Widget _footer(double width) {
    final buttons = <Widget>[
      if (widget.onCancel != null)
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: widget.onCancel,
        ),
      // Read only with somewhere to go, the footer offers the way in where
      // the Save would be: a greyed Save with "Read only." beside it was the
      // whole of the old answer to "how do I save this", and it read as broken.
      if (widget.readOnly && widget.onEdit != null)
        AppButton(
          key: const ValueKey<String>('master-data-edit'),
          label: 'Edit',
          icon: Icons.edit_outlined,
          onPressed: widget.onEdit,
        )
      else
        AppButton(
          key: const ValueKey<String>('master-data-save'),
          label: 'Save Master Data',
          icon: Icons.check_rounded,
          isLoading: widget.saving,
          onPressed: widget.readOnly || widget.saving
              ? null
              // Without the blank rows the editor keeps for typing into.
              : () => widget.onSave(_recorded),
        ),
    ];
    final note = !widget.readOnly
        ? 'The drawing follows what you type.'
        : widget.onEdit == null
        ? 'Read only.'
        : '';
    const decoration = BoxDecoration(
      color: SoftErpTheme.shellSurface,
      border: Border(top: BorderSide(color: SoftErpTheme.border)),
    );

    if (widget.embedded && width < _compactStepBarWidth) {
      // A side panel has no room for the hint beside two buttons, so it goes,
      // and the buttons wrap onto a second line rather than overflow when the
      // panel is narrower than both. Read only still says so: a disabled Save
      // with no reason beside it reads as broken.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: decoration,
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            if (widget.readOnly && note.isNotEmpty)
              Text(
                note,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ...buttons,
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            child: Text(
              note,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final (index, button) in buttons.indexed) ...[
            if (index > 0) const SizedBox(width: 10),
            button,
          ],
        ],
      ),
    );
  }
}

/// A measurement with its unit shown rather than hidden in a hint — the unit is
/// the difference between a 48 inch sheet and a 48 mm one. When [onUnitTap] is
/// given the unit is a control: tapping it switches what the number is read in.
class _DimensionField extends StatelessWidget {
  const _DimensionField({
    super.key,
    required this.controller,
    required this.label,
    required this.unit,
    required this.readOnly,
    required this.onChanged,
    this.unitWidget,
    this.integerOnly = false,
    this.hint = '0',
    this.focusNode,
    this.errorText,
  });

  final FocusNode? focusNode;

  /// Why what was typed cannot be stored, under the field.
  final String? errorText;

  final TextEditingController controller;
  final String label;
  final String unit;
  final bool readOnly;
  final VoidCallback onChanged;

  /// Shown in place of the plain unit text — a picker, where the unit can be
  /// changed rather than only read.
  final Widget? unitWidget;
  final bool integerOnly;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final suffix = unitWidget == null
        ? Padding(
            padding: const EdgeInsets.only(right: 10, left: 4),
            child: Text(
              unit,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(right: 5, left: 2),
            child: unitWidget,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: SheetStyle.label,
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 44,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            readOnly: readOnly,
            keyboardType: TextInputType.numberWithOptions(
              decimal: !integerOnly,
            ),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(
                integerOnly ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
              ),
            ],
            onChanged: (_) => onChanged(),
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              suffixIcon: suffix,
              suffixIconConstraints: const BoxConstraints(minWidth: 0),
              filled: true,
              fillColor: SoftErpTheme.cardSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
                borderSide: const BorderSide(color: SoftErpTheme.accent),
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: const TextStyle(
              color: SoftErpTheme.warningText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

/// Which way the sheet is sheared first.
///
/// It sits with the primary split because everything else hangs off it: change
/// the direction and the strips you had are not the strips you have.
class _AxisChoice extends StatelessWidget {
  const _AxisChoice({
    required this.axis,
    required this.onChanged,
    this.labelOf,
    this.keyPrefix,
  });

  final SheetCutAxis axis;
  final ValueChanged<SheetCutAxis>? onChanged;

  /// What each choice reads as; the axis's own [SheetCutAxis.yields] if unset.
  final String Function(SheetCutAxis axis)? labelOf;

  /// Keys each choice `<prefix>-<axis name>`, for finding it in a test.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final option in SheetCutAxis.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: keyPrefix == null
                    ? null
                    : ValueKey<String>('$keyPrefix-${option.name}'),
                onTap: onChanged == null ? null : () => onChanged!(option),
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: option == axis
                        ? SoftErpTheme.accentSurface
                        : SoftErpTheme.cardSurface,
                    borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                    border: Border.all(
                      color: option == axis
                          ? SoftErpTheme.accent
                          : SoftErpTheme.border,
                    ),
                  ),
                  child: Text(
                    labelOf?.call(option) ?? option.yields,
                    style: TextStyle(
                      color: option == axis
                          ? SoftErpTheme.accentDeeper
                          : SoftErpTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A band's colour, carrying its name. The same colour washes that band's
/// stretch of the sheet, so the two halves of the screen point at each other
/// without the reader translating.
class _BandSwatch extends StatelessWidget {
  const _BandSwatch({
    required this.colour,
    required this.label,
    required this.live,
  });

  final Color colour;
  final String label;

  /// A half-typed band claims no sheet yet, so its swatch is hollow — the
  /// colour is a promise about the drawing, and there is nothing there to
  /// promise about.
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: live ? colour.withValues(alpha: 0.85) : Colors.transparent,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
            border: Border.all(
              color: live ? colour : SoftErpTheme.border,
              width: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: live ? SoftErpTheme.textPrimary : SoftErpTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// One step in the workflow's bar.
/// One form of stock in the panel's switcher: its picture, its name, and a
/// dot when something is recorded for it.
class _FormTile extends StatelessWidget {
  const _FormTile({
    super.key,
    required this.form,
    required this.selected,
    required this.hasData,
    required this.onTap,
  });

  final RawForm form;
  final bool selected;
  final bool hasData;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = selected ? SoftErpTheme.accent : SoftErpTheme.textSecondary;
    return Tooltip(
      message: hasData
          ? '${form.label}: recorded'
          : '${form.label}: nothing recorded yet',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          child: Ink(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? SoftErpTheme.accentSurface : SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(
                color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 16,
                  child: CustomPaint(
                    painter: RawFormGlyphPainter(form, color: tone),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    form.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? SoftErpTheme.accentDeeper
                          : SoftErpTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasData) ...[
                  const SizedBox(width: 5),
                  Container(
                    key: ValueKey<String>('raw-form-dot-${form.name}'),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? SoftErpTheme.accentSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? SoftErpTheme.accent
                      : SoftErpTheme.cardSurfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: selected ? Colors.white : SoftErpTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? SoftErpTheme.accentDeeper
                      : SoftErpTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The controllers behind one band row.
class _BandControllers {
  _BandControllers({String size = '', String count = ''})
    : size = TextEditingController(text: size),
      count = TextEditingController(text: count);

  final TextEditingController size;
  final TextEditingController count;

  void dispose() {
    size.dispose();
    count.dispose();
  }
}

/// Says once what each column of the band rows is, so the rows themselves can
/// be bare numbers.
class _BandHeader extends StatelessWidget {
  const _BandHeader();

  @override
  Widget build(BuildContext context) {
    const style = SheetStyle.label;
    return const Row(
      children: [
        Expanded(flex: 4, child: Text('SIZE', style: style)),
        SizedBox(width: 26),
        Expanded(flex: 3, child: Text('HOW MANY', style: style)),
        SizedBox(width: 6),
        SizedBox(width: 44, child: Text('FIT', style: style)),
        SizedBox(width: 22),
      ],
    );
  }
}

/// The × that takes one band out, on the row it belongs to.
///
/// Quiet until the row is hovered: a plan with a dozen bands should not read as
/// a dozen delete buttons.
class _RowRemove extends StatefulWidget {
  const _RowRemove({required this.onTap});

  final VoidCallback? onTap;

  @override
  State<_RowRemove> createState() => _RowRemoveState();
}

class _RowRemoveState extends State<_RowRemove> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: 'Remove this band',
        child: IconButton(
          onPressed: widget.onTap,
          icon: Icon(
            Icons.close_rounded,
            size: 15,
            color: _hovered
                ? SoftErpTheme.dangerText
                : SoftErpTheme.textSecondary.withValues(alpha: 0.45),
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 22, height: 22),
        ),
      ),
    );
  }
}

/// The unit a measurement is read in: a slim chip with a chevron, opening a
/// searchable list of every length unit the system knows.
///
/// Searchable because the list is no longer four items — with thou and gauge in
/// it, and more to come, scanning is slower than typing. The search matches the
/// symbol, the name and what people actually type, so "swg" finds gauge and
/// "millimetre" finds mm.
/// The material field: reads like the part picker beside it, but opens a
/// bounded list rather than a menu as tall as the catalogue.
///
/// It hands its own context back to [onPressed] so the menu can anchor to this
/// field rather than to the dialog.
class _MaterialPickerField extends StatelessWidget {
  const _MaterialPickerField({
    super.key,
    required this.label,
    required this.trailing,
    required this.hint,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String trailing;
  final String hint;
  final bool enabled;
  final Future<void> Function(BuildContext anchorContext)? onPressed;

  @override
  Widget build(BuildContext context) {
    final chosen = label.trim().isNotEmpty;
    return SizedBox(
      height: 32,
      child: Material(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        child: InkWell(
          onTap: onPressed == null ? null : () => onPressed!(context),
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    chosen ? label : hint,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: chosen
                          ? SoftErpTheme.textPrimary
                          : SoftErpTheme.textSecondary,
                      fontSize: chosen ? 12.5 : 12,
                      fontWeight: chosen ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    trailing,
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: enabled
                      ? SoftErpTheme.textSecondary
                      : SoftErpTheme.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The material list: a search box and the materials that match it.
///
/// Returns the chosen name, or an empty string for "not set". Thirty-six rows
/// is past the point where scanning beats typing, which is why the search sits
/// above them and takes focus straight away.
class _MaterialMenu extends StatefulWidget {
  const _MaterialMenu({
    required this.materials,
    required this.currentName,
    required this.anchor,
    required this.anchorWidth,
    required this.anchorHeight,
    required this.overlaySize,
  });

  final List<MaterialDefinition> materials;
  final String currentName;
  final Offset anchor;
  final double anchorWidth;
  final double anchorHeight;
  final Size overlaySize;

  @override
  State<_MaterialMenu> createState() => _MaterialMenuState();
}

class _MaterialMenuState extends State<_MaterialMenu> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const maxHeight = 320.0;
    // As wide as the field it drops from, so it reads as that field's list.
    final width = math.max(240.0, widget.anchorWidth);
    final matches = widget.materials
        .where((material) => material.matches(_query.text))
        .toList(growable: false);

    // Kept on screen: a field near the right edge would otherwise open a list
    // that runs off it — which is exactly what the plain dropdown did.
    final left = widget.anchor.dx
        .clamp(8.0, math.max(8.0, widget.overlaySize.width - width - 8))
        .toDouble();
    final below = widget.anchor.dy + widget.anchorHeight + 4;
    final fitsBelow = below + maxHeight < widget.overlaySize.height - 8;
    final top = fitsBelow
        ? below
        : math.max(8.0, widget.anchor.dy - maxHeight - 4);

    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
            child: Container(
              width: width,
              constraints: const BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: SoftErpTheme.cardSurface,
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: TextField(
                      key: const ValueKey<String>('material-search'),
                      controller: _query,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search materials',
                        prefixIcon: const Icon(Icons.search_rounded, size: 16),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 30,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            SoftErpTheme.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: matches.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.fromLTRB(12, 6, 12, 14),
                            child: Text(
                              'No material by that name.',
                              style: TextStyle(
                                color: SoftErpTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 6),
                            // The clearing row only when there is something to
                            // clear, so it is not a permanent first option.
                            itemCount: matches.length + (_canClear ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_canClear && index == 0) return _clearRow();
                              return _row(matches[index - (_canClear ? 1 : 0)]);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool get _canClear =>
      widget.currentName.trim().isNotEmpty && _query.text.trim().isEmpty;

  Widget _clearRow() {
    return InkWell(
      key: const ValueKey<String>('material-option-none'),
      onTap: () => Navigator.of(context).pop(''),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: const Text(
          'Not set',
          style: TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _row(MaterialDefinition material) {
    final selected =
        material.name.toLowerCase() == widget.currentName.trim().toLowerCase();
    return InkWell(
      key: ValueKey<String>('material-option-${material.id}'),
      onTap: () => Navigator.of(context).pop(material.name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: selected ? SoftErpTheme.accentSurface : Colors.transparent,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                material.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? SoftErpTheme.accentDeeper
                      : SoftErpTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({
    required this.symbol,
    required this.onChanged,
    this.options,
  });

  final String symbol;
  final ValueChanged<GlobalLengthUnit>? onChanged;

  /// Defaults to every length unit; a face passes the ones that can measure
  /// one, which is everything but gauge.
  final List<GlobalLengthUnit>? options;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final unit = lengthUnitBySymbol(symbol);
    return Tooltip(
      message: 'Read this in another unit',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () async {
                  final picked = await _showUnitMenu(
                    context,
                    options ?? globalLengthUnits,
                    unit,
                  );
                  if (picked != null) onChanged!(picked);
                }
              : null,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: enabled ? SoftErpTheme.accentSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
              border: Border.all(
                color: enabled
                    ? SoftErpTheme.accent.withValues(alpha: 0.4)
                    : SoftErpTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  unit.symbol,
                  style: TextStyle(
                    color: enabled
                        ? SoftErpTheme.accentDeeper
                        : SoftErpTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 14,
                  color: enabled
                      ? SoftErpTheme.accentDeeper
                      : SoftErpTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opened under the chip it belongs to, so the list reads as that field's
  /// unit rather than as a dialog about units in general.
  Future<GlobalLengthUnit?> _showUnitMenu(
    BuildContext context,
    List<GlobalLengthUnit> units,
    GlobalLengthUnit current,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null)
      return Future<GlobalLengthUnit?>.value();
    final anchor = box.localToGlobal(Offset.zero, ancestor: overlay);
    return showDialog<GlobalLengthUnit>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => _UnitMenu(
        units: units,
        current: current,
        anchor: anchor,
        anchorHeight: box.size.height,
        overlaySize: overlay.size,
      ),
    );
  }
}

/// The list itself: a search box and the units that match it.
class _UnitMenu extends StatefulWidget {
  const _UnitMenu({
    required this.units,
    required this.current,
    required this.anchor,
    required this.anchorHeight,
    required this.overlaySize,
  });

  final List<GlobalLengthUnit> units;
  final GlobalLengthUnit current;
  final Offset anchor;
  final double anchorHeight;
  final Size overlaySize;

  @override
  State<_UnitMenu> createState() => _UnitMenuState();
}

class _UnitMenuState extends State<_UnitMenu> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const width = 218.0;
    const maxHeight = 290.0;
    final matches = widget.units
        .where((unit) => unit.matches(_query.text))
        .toList(growable: false);

    // Kept on screen: a chip near the right edge would otherwise open a list
    // that runs off it.
    final left = widget.anchor.dx
        .clamp(8.0, math.max(8.0, widget.overlaySize.width - width - 8))
        .toDouble();
    final below = widget.anchor.dy + widget.anchorHeight + 4;
    final fitsBelow = below + maxHeight < widget.overlaySize.height - 8;
    final top = fitsBelow
        ? below
        : math.max(8.0, widget.anchor.dy - maxHeight - 4);

    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
            child: Container(
              width: width,
              constraints: const BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: SoftErpTheme.cardSurface,
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: TextField(
                      key: const ValueKey<String>('unit-search'),
                      controller: _query,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search units',
                        prefixIcon: const Icon(Icons.search_rounded, size: 16),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 30,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            SoftErpTheme.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: matches.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.fromLTRB(12, 6, 12, 14),
                            child: Text(
                              'No unit by that name.',
                              style: TextStyle(
                                color: SoftErpTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 6),
                            itemCount: matches.length,
                            itemBuilder: (context, index) =>
                                _row(context, matches[index]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, GlobalLengthUnit unit) {
    final selected = unit.symbol == widget.current.symbol;
    return InkWell(
      key: ValueKey<String>('unit-option-${unit.symbol}'),
      onTap: () => Navigator.of(context).pop(unit),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: selected ? SoftErpTheme.accentSurface : Colors.transparent,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 34,
              child: Text(
                unit.symbol,
                style: TextStyle(
                  color: selected
                      ? SoftErpTheme.accentDeeper
                      : SoftErpTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                unit.name,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Said out loud, because a gauge is a lookup and behaves unlike
            // every other unit in the list.
            if (unit.isGauge)
              const Text(
                'SWG',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A bare number field for a band's size or count — no label above it, because
/// in a band row the axis letter and the × already say what each one is.
class _PlainNumberField extends StatelessWidget {
  const _PlainNumberField({
    required this.controller,
    required this.hint,
    required this.readOnly,
    required this.onChanged,
    this.integerOnly = false,
    this.fieldKey,
  });

  /// Put on the field itself rather than on this wrapper, so it can be found
  /// and typed into directly.
  final Key? fieldKey;
  final TextEditingController controller;
  final String hint;
  final bool readOnly;
  final VoidCallback onChanged;
  final bool integerOnly;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: TextField(
        key: fieldKey,
        controller: controller,
        readOnly: readOnly,
        keyboardType: TextInputType.numberWithOptions(decimal: !integerOnly),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(
            integerOnly ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
          ),
        ],
        onChanged: (_) => onChanged(),
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: SoftErpTheme.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          filled: true,
          fillColor: SoftErpTheme.cardSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
            borderSide: const BorderSide(color: SoftErpTheme.accent),
          ),
        ),
      ),
    );
  }
}
