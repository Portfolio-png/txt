import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/pen_paper_baseline.dart';
import '../../domain/pipeline_stage_node.dart';
import '../../../units/domain/global_length_units.dart';
import '../../domain/sheet_part.dart';
import 'pen_paper_baseline_widget.dart';
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
  bool readOnly = false,
}) {
  return showDialog<PenPaperBaseline>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MasterDataDialog(
      baseline: baseline,
      pipelineId: pipelineId,
      pipelineName: pipelineName,
      itemName: itemName,
      stageNodes: stageNodes,
      parts: parts,
      readOnly: readOnly,
    ),
  );
}

class _MasterDataDialog extends StatefulWidget {
  const _MasterDataDialog({
    required this.baseline,
    required this.pipelineId,
    required this.pipelineName,
    required this.itemName,
    required this.stageNodes,
    required this.parts,
    required this.readOnly,
  });

  final PenPaperBaseline baseline;
  final String? pipelineId;
  final String pipelineName;
  final String itemName;
  final List<PipelineStageNode> stageNodes;

  /// Parts the catalogue already knows the blank size of. Empty when the caller
  /// has none, in which case the panel stays a place to type sizes by hand.
  final List<SheetPart> parts;
  final bool readOnly;

  @override
  State<_MasterDataDialog> createState() => _MasterDataDialogState();
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

class _MasterDataDialogState extends State<_MasterDataDialog> {
  late PenPaperBaseline _baseline;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _thicknessController;
  late final TextEditingController _kerfController;
  late final TextEditingController _trimController;

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

  /// The unit each axis is being typed in. Storage is always millimetres; this
  /// only decides what the fields show, because a 40 mm band and a 1.575 in
  /// band are the same cut and should not be two records.
  final Map<SheetCutAxis, bool> _axisInInches = <SheetCutAxis, bool>{
    SheetCutAxis.columns: false,
    SheetCutAxis.rows: false,
  };

  /// Below this the two halves stop being side by side and stack, so the sheet
  /// keeps a readable drawing area instead of being squeezed into a sliver.
  static const double _sideBySideWidth = 940;

  @override
  void initState() {
    super.initState();
    _baseline = widget.baseline;
    _widthController = TextEditingController(
      text: _faceText(_baseline.sheetWidthInches, _baseline.faceUnit),
    );
    _heightController = TextEditingController(
      text: _faceText(_baseline.sheetHeightInches, _baseline.faceUnit),
    );
    _thicknessController = TextEditingController(
      text: _showUnit(
        _baseline.sheetThicknessMm,
        lengthUnitBySymbol(_baseline.gaugeUnit),
      ),
    );
    _kerfController = TextEditingController(text: _initial(_baseline.kerfMm));
    _trimController = TextEditingController(
      text: _initial(_baseline.edgeTrimMm),
    );
    _seedControllers();
    _ensureTrailingBlank(_primaryRegion);
  }

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
    _widthController.dispose();
    _heightController.dispose();
    _thicknessController.dispose();
    _kerfController.dispose();
    _trimController.dispose();
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

  /// What the sheet is, from the variant's own name — a variant of a sheet is a
  /// sheet, the same rule the Master Data table reads its material type by.
  String get _materialLabel {
    final name = widget.itemName.toLowerCase();
    for (final noun in const <String>[
      'sheet',
      'coil',
      'strip',
      'plate',
      'patti',
      'rod',
      'bar',
      'wire',
      'pipe',
      'tube',
    ]) {
      if (name.contains(noun)) return noun;
    }
    return 'sheet';
  }

  void _onMachineChanged() {
    setState(() {
      _baseline = _baseline.copyWith(
        kerfMm: double.tryParse(_kerfController.text.trim()) ?? 0,
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
      _baseline.edgeTrimMm + _baseline.usableSpanMm(_baseline.primaryAxis),
    );
    return out;
  }

  /// One region's cuts walked into bands, in the inches the sheet is drawn in.
  List<SheetFigureBand> _regionBands(int region, List<SheetCutGroup> groups) {
    final gap = _baseline.kerfMm;
    final limit =
        _baseline.edgeTrimMm +
        _baseline.regionExtentMm(region, _baseline.secondaryAxis);
    final out = <SheetFigureBand>[];
    var at = _baseline.edgeTrimMm;
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
    final media = MediaQuery.of(context);
    final width = (media.size.width * 0.94).clamp(360.0, 1440.0);
    final height = (media.size.height * 0.92).clamp(420.0, 980.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SoftErpTheme.border),
          boxShadow: SoftErpTheme.raisedShadow,
        ),
        child: Column(
          children: [
            _header(),
            _stepBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: switch (_step) {
                  _MasterStep.sheet => _sheetStep(width),
                  _MasterStep.material => _materialStep(),
                  _MasterStep.review => _reviewStep(),
                },
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _stepBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFDFDFD),
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
              label: step.title,
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
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Step one. The drawing takes the room now rather than sitting in a band:
  /// it is the thing being reasoned about, and a plan you cannot see the shape
  /// of is just a column of numbers again.
  Widget _sheetStep(double dialogWidth) {
    const controlsWidth = 392.0;
    if (dialogWidth < 900) {
      return ListView(
        children: [
          SizedBox(height: 320, child: _sheetPanel()),
          const SizedBox(height: 12),
          _dimensionFields(),
          const SizedBox(height: 12),
          _cutOperationBar(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _sheetPanel()),
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

  Widget _reviewStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.fact_check_outlined,
              size: 30,
              color: SoftErpTheme.textSecondary,
            ),
            const SizedBox(height: 10),
            const Text(
              'Review comes next',
              style: TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _baseline.hasCutPlan
                  ? 'The plan so far: ${_planSummary()}.'
                  : 'Nothing planned on the sheet yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
        color: Color(0xFFFBFBFB),
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
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF8FAFC),
              foregroundColor: const Color(0xFF334155),
              side: const BorderSide(color: Color(0xFFD9E2F2)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THE SHEET',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SheetDimensionFigure(
              widthInches: _baseline.sheetWidthInches,
              heightInches: _baseline.sheetHeightInches,
              thicknessMm: _baseline.sheetThicknessMm,
              materialLabel: _materialLabel,
              trimInches: _baseline.sizeInInches(_baseline.edgeTrimMm),
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
              fontSize: 11,
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
    if (area <= 0) return 'Enter width and height to draw the sheet.';
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
    return Row(
      children: [
        Expanded(
          child: _DimensionField(
            controller: _widthController,
            label: 'Width',
            unit: face.symbol,
            readOnly: widget.readOnly,
            onChanged: _onDimensionChanged,
            unitWidget: facePicker(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DimensionField(
            controller: _heightController,
            label: 'Height',
            // The face is one measurement in two directions, so both sides read
            // in the same unit — a sheet quoted 48 in by 1219 mm is a mistake
            // waiting to be made.
            unit: face.symbol,
            readOnly: widget.readOnly,
            onChanged: _onDimensionChanged,
            unitWidget: facePicker(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DimensionField(
            controller: _thicknessController,
            label: 'Thickness',
            unit: gauge.symbol,
            readOnly: widget.readOnly,
            onChanged: _onDimensionChanged,
            // Gauge belongs here and nowhere else, so this picker keeps the
            // whole catalogue.
            unitWidget: _UnitPicker(
              symbol: gauge.symbol,
              onChanged: widget.readOnly ? null : _onGaugeUnitChanged,
            ),
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
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
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
                      children: const <Widget>[
                        Text(
                          'Part gap',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'The web left between blanks so the strip does not '
                          'tear under the punch — or the kerf, if the cut '
                          'removes material. A shear removes none, so leave it '
                          'at zero for shearing.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Edge trim',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'The band around the sheet nobody cuts into — the '
                          'damaged mill edge, the machine clamp, and the '
                          'straight edge you gauge from. Comes off both ends '
                          'of each axis before anything is planned.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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
          _machineRow(),
          const SizedBox(height: 10),
          _primaryBlock(),
          _regionBlocks(),
          _yieldBlock(),
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
          width: 74,
          child: Text(
            'PART',
            style: TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
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
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
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

  /// What the machine costs before any part is planned: the blade, and the
  /// edge nobody will cut into.
  ///
  /// These sit above both axes because they are properties of the shear and the
  /// stock, not of a band — and they are the two figures a paper plan leaves
  /// out, which is most of why a paper plan comes up short on the floor.
  Widget _machineRow() {
    final kerf = _baseline.kerfMm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 78,
              child: Text(
                'PART GAP',
                style: TextStyle(
                  color: kerf > 0
                      ? SoftErpTheme.textPrimary
                      : SoftErpTheme.warningText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: _PlainNumberField(
                fieldKey: const ValueKey<String>('sheet-kerf'),
                controller: _kerfController,
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
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const SizedBox(
              width: 74,
              child: Text(
                'EDGE TRIM',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
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
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (kerf <= 0 && _baseline.hasCutPlan) ...[
          const SizedBox(height: 6),
          const Text(
            'No gap set — counts assume blanks touching edge to edge.',
            style: TextStyle(
              color: SoftErpTheme.warningText,
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
              style: TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
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
                  fontSize: 12,
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
              fontSize: 12,
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
          style: TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
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
        color: open ? Colors.white : Colors.transparent,
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
                      fontSize: 12,
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
                        fontSize: 11.5,
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
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
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
              fontSize: 12.5,
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

  /// The plan in one line, for the places a list will not fit.
  String _planSummary() {
    final parts = _baseline.yields.where((entry) => !entry.isOffcut).toList();
    if (parts.isEmpty) return 'nothing yet';
    if (parts.length == 1) {
      return '${parts.single.count} × ${parts.single.sizeLabel}';
    }
    return '${_baseline.pieceCount} pieces in ${parts.length} sizes';
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
          style: TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
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
              borderRadius: BorderRadius.circular(3),
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
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            entry.isOffcut ? 'offcut' : entry.label,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 11.5,
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
      style: TextStyle(
        color: SoftErpTheme.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
      ),
    );
  }

  Widget _dataPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
          stageNodes: widget.stageNodes,
          itemName: widget.itemName,
          onChanged: (updated) {
            setState(() {
              // The widget rebuilds the baseline wholesale, so the dimensions
              // are carried across rather than dropped by an edit to the table.
              _baseline = updated.copyWith(
                sheetWidthInches: _baseline.sheetWidthInches,
                sheetHeightInches: _baseline.sheetHeightInches,
                sheetThicknessMm: _baseline.sheetThicknessMm,
              );
            });
          },
        ),
      ),
    );
  }

  Widget _footer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(top: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.readOnly
                  ? 'Read only.'
                  : 'The drawing follows what you type.',
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          AppButton(
            label: 'Save Master Data',
            icon: Icons.check_rounded,
            onPressed: widget.readOnly
                ? null
                // Without the blank rows the editor keeps for typing into.
                : () => Navigator.of(context).pop(_baseline.withoutEmptyBands),
          ),
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
    required this.controller,
    required this.label,
    required this.unit,
    required this.readOnly,
    required this.onChanged,
    this.unitWidget,
    this.integerOnly = false,
    this.hint = '0',
  });

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
          style: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 44,
          child: TextField(
            controller: controller,
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
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                borderSide: const BorderSide(color: SoftErpTheme.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which way the sheet is sheared first.
///
/// It sits with the primary split because everything else hangs off it: change
/// the direction and the strips you had are not the strips you have.
class _AxisChoice extends StatelessWidget {
  const _AxisChoice({required this.axis, required this.onChanged});

  final SheetCutAxis axis;
  final ValueChanged<SheetCutAxis>? onChanged;

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
                onTap: onChanged == null ? null : () => onChanged!(option),
                borderRadius: BorderRadius.circular(5),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: option == axis
                        ? SoftErpTheme.accentSurface
                        : Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: option == axis
                          ? SoftErpTheme.accent
                          : SoftErpTheme.border,
                    ),
                  ),
                  child: Text(
                    option.yields,
                    style: TextStyle(
                      color: option == axis
                          ? SoftErpTheme.accentDeeper
                          : SoftErpTheme.textSecondary,
                      fontSize: 12,
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
            borderRadius: BorderRadius.circular(3),
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
                width: 17,
                height: 17,
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
                    fontSize: 10,
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
                  fontSize: 12.5,
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
    const style = TextStyle(
      color: SoftErpTheme.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    );
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
          borderRadius: BorderRadius.circular(5),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: enabled ? SoftErpTheme.accentSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
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
                    fontSize: 12.5,
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
                color: Colors.white,
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
                                fontSize: 12.5,
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
                  fontSize: 12,
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
                  fontSize: 10,
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
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            borderSide: const BorderSide(color: SoftErpTheme.accent),
          ),
        ),
      ),
    );
  }
}
