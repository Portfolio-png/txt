import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/dxf_blank.dart';

/// What the user chose out of a drawing: the profile, and the file it came from
/// so the size can be traced back to its source months later.
class DxfBlankChoice {
  const DxfBlankChoice({required this.profile, required this.fileName});

  final DxfProfile profile;
  final String fileName;

  /// Stamped on the part, so "where did 60 × 40 come from?" has an answer.
  String get provenance =>
      '$fileName · ${profile.kindLabel}'
      '${profile.layer.isEmpty || profile.layer == '0' ? '' : ' on ${profile.layer}'}';
}

/// Asks which shape in the drawing is the blank.
///
/// The whole reason this is a dialog rather than an automatic read: a die
/// drawing holds the plate, the punch, dimension lines, a title block and often
/// several views. Picking the biggest, or trusting the file's own extents,
/// gives a confident wrong answer — usually the size of the paper. One click
/// from someone who can read the drawing settles it for good.
Future<DxfBlankChoice?> showDxfBlankPicker(
  BuildContext context, {
  required DxfBlankCandidates candidates,
  required String fileName,
}) {
  return showDialog<DxfBlankChoice>(
    context: context,
    builder: (context) =>
        _DxfBlankPicker(candidates: candidates, fileName: fileName),
  );
}

class _DxfBlankPicker extends StatefulWidget {
  const _DxfBlankPicker({required this.candidates, required this.fileName});

  final DxfBlankCandidates candidates;
  final String fileName;

  @override
  State<_DxfBlankPicker> createState() => _DxfBlankPickerState();
}

class _DxfBlankPickerState extends State<_DxfBlankPicker> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final profiles = widget.candidates.profiles;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 620),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            if (widget.candidates.unitsAssumed) _unitsWarning(),
            Flexible(
              child: profiles.isEmpty
                  ? _empty()
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: profiles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _row(index),
                    ),
            ),
            _footer(profiles),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final units = widget.candidates.units;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Which shape is the blank?',
            style: TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${widget.fileName} · ${widget.candidates.entitiesRead} shapes read '
            '· drawn in ${units.label}',
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// A drawing that never said what its units were is the one way this can be
  /// quietly and badly wrong, so it is said out loud rather than inferred.
  Widget _unitsWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.straighten_rounded,
            size: 16,
            color: SoftErpTheme.warningText,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'This drawing does not say what its units are, so these sizes '
              'read one drawing unit as one millimetre. If it was drawn in '
              'inches every size here is 25.4× too small — check one against '
              'the part before you trust it.',
              style: TextStyle(
                color: SoftErpTheme.warningText,
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.layers_clear_outlined,
            size: 30,
            color: SoftErpTheme.textSecondary,
          ),
          SizedBox(height: 10),
          Text(
            'No shapes found',
            style: TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'This may be a DWG or a binary DXF rather than an ASCII one. Ask '
            'for a plain DXF export — it is one dialog in any CAD package.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int index) {
    final profile = widget.candidates.profiles[index];
    final selected = index == _selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selected = index),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected ? SoftErpTheme.accentSurface : Colors.white,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 17,
                color: selected
                    ? SoftErpTheme.accent
                    : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.sizeLabel,
                      style: TextStyle(
                        color: selected
                            ? SoftErpTheme.accentDeeper
                            : SoftErpTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.kindLabel} · layer ${profile.layer}'
                      '${profile.kind == DxfProfileKind.layer ? ' · ${profile.entityCount} shapes' : ''}',
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(List<DxfProfile> profiles) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(top: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Smallest first — the blank is usually smaller than the plate.',
              style: TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 11.5,
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
            label: 'Use this size',
            icon: Icons.check_rounded,
            onPressed: profiles.isEmpty
                ? null
                : () => Navigator.of(context).pop(
                    DxfBlankChoice(
                      profile: profiles[_selected],
                      fileName: widget.fileName,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
