import 'pen_paper_baseline.dart';

/// The shapes raw stock arrives in. A part may be pressed from any of them,
/// and keeps a plan for each — none is the default.
enum RawForm {
  sheet('Sheet'),
  strip('Strip'),
  coil('Coil'),
  roll('Roll');

  const RawForm(this.label);

  final String label;

  /// A strip, coil or roll: a band of stock whose length is, usually, not
  /// known — it comes off the coil as it comes.
  bool get isBand => this != RawForm.sheet;

  static RawForm? fromName(String? name) {
    for (final form in RawForm.values) {
      if (form.name == name) return form;
    }
    return null;
  }
}

/// A strip, coil or roll, as one part is planned from it.
///
/// Width, and a length that is **undefined** until somebody knows it — nobody
/// knows when a coil's length comes down. The press takes one part every
/// [pitchNm]; with a known length that is a count, without one it is a rate.
/// Thickness, alloy and grade are the part's, stamped here when the plan is
/// saved so the record still says what it was. Nothing is weighed (no
/// density): what goes in and comes out is typed in [reconciliation].
///
/// Lengths are integer nanometres, the units contract's base for a length,
/// with the unit each was typed in kept beside it for showing it again.
class RawStockForm {
  const RawStockForm({
    this.widthNm,
    this.lengthNm,
    this.thicknessNm,
    this.pitchNm,
    this.widthUnit = 'mm',
    this.lengthUnit = 'mm',
    this.thicknessUnit = 'mm',
    this.pitchUnit = 'mm',
    this.vendorId,
    this.vendorName = '',
    this.grade = '',
    this.reconciliation = PenPaperStageReconciliation.empty,
  });

  static const RawStockForm empty = RawStockForm();

  final int? widthNm;

  /// Null is undefined — the normal case for a coil.
  final int? lengthNm;
  final int? thicknessNm;

  /// The press's advance per part: one part comes off every pitch.
  final int? pitchNm;
  final String widthUnit;
  final String lengthUnit;
  final String thicknessUnit;
  final String pitchUnit;

  /// Who supplied it, per form: a coil and a sheet of one part may come from
  /// different mills.
  final int? vendorId;
  final String vendorName;

  /// The part's grade, as it was when the plan was saved.
  final String grade;

  /// Weight in, pieces out — typed, never derived.
  final PenPaperStageReconciliation reconciliation;

  bool get lengthKnown => (lengthNm ?? 0) > 0;

  /// Whether anything has been recorded for this form. Thickness and grade
  /// are the part's, so they alone do not make a plan.
  bool get hasData =>
      (widthNm ?? 0) > 0 ||
      lengthKnown ||
      (pitchNm ?? 0) > 0 ||
      vendorId != null ||
      vendorName.trim().isNotEmpty ||
      reconciliation.inputKg > 0 ||
      reconciliation.outputKg > 0 ||
      reconciliation.piecesOut > 0;

  /// Parts from the whole length, one every pitch. Null while the length or
  /// the pitch is not known.
  int? partsFromLength() {
    final length = lengthNm;
    final pitch = pitchNm;
    if (length == null || length <= 0 || pitch == null || pitch <= 0) {
      return null;
    }
    return length ~/ pitch;
  }

  static const Object _keep = Object();

  RawStockForm copyWith({
    Object? widthNm = _keep,
    Object? lengthNm = _keep,
    Object? thicknessNm = _keep,
    Object? pitchNm = _keep,
    String? widthUnit,
    String? lengthUnit,
    String? thicknessUnit,
    String? pitchUnit,
    Object? vendorId = _keep,
    String? vendorName,
    String? grade,
    PenPaperStageReconciliation? reconciliation,
  }) =>
      RawStockForm(
        widthNm: identical(widthNm, _keep) ? this.widthNm : widthNm as int?,
        lengthNm: identical(lengthNm, _keep) ? this.lengthNm : lengthNm as int?,
        thicknessNm:
            identical(thicknessNm, _keep) ? this.thicknessNm : thicknessNm as int?,
        pitchNm: identical(pitchNm, _keep) ? this.pitchNm : pitchNm as int?,
        widthUnit: widthUnit ?? this.widthUnit,
        lengthUnit: lengthUnit ?? this.lengthUnit,
        thicknessUnit: thicknessUnit ?? this.thicknessUnit,
        pitchUnit: pitchUnit ?? this.pitchUnit,
        vendorId: identical(vendorId, _keep) ? this.vendorId : vendorId as int?,
        vendorName: vendorName ?? this.vendorName,
        grade: grade ?? this.grade,
        reconciliation: reconciliation ?? this.reconciliation,
      );

  Map<String, dynamic> toJson() => {
        if (widthNm != null) 'widthNm': widthNm,
        if (lengthNm != null) 'lengthNm': lengthNm,
        if (thicknessNm != null) 'thicknessNm': thicknessNm,
        if (pitchNm != null) 'pitchNm': pitchNm,
        'widthUnit': widthUnit,
        'lengthUnit': lengthUnit,
        'thicknessUnit': thicknessUnit,
        'pitchUnit': pitchUnit,
        if (vendorId != null) 'vendorId': vendorId,
        if (vendorName.isNotEmpty) 'vendorName': vendorName,
        if (grade.isNotEmpty) 'grade': grade,
        'reconciliation': reconciliation.toJson(),
      };

  /// [legacyPitchMm] is the sheet-wide pitch older plans kept, given to a
  /// band that has no pitch of its own.
  factory RawStockForm.fromJson(
    Map<String, dynamic> json, {
    double legacyPitchMm = 0,
  }) {
    int? whole(Object? value) => value is num ? value.round() : null;
    final recon = json['reconciliation'];
    final pitch = whole(json['pitchNm']) ??
        (legacyPitchMm > 0 ? (legacyPitchMm * 1000000).round() : null);
    return RawStockForm(
      widthNm: whole(json['widthNm']),
      lengthNm: whole(json['lengthNm']),
      thicknessNm: whole(json['thicknessNm']),
      pitchNm: pitch,
      widthUnit: '${json['widthUnit'] ?? 'mm'}',
      lengthUnit: '${json['lengthUnit'] ?? 'mm'}',
      thicknessUnit: '${json['thicknessUnit'] ?? 'mm'}',
      pitchUnit: '${json['pitchUnit'] ?? 'mm'}',
      vendorId: whole(json['vendorId']),
      vendorName: '${json['vendorName'] ?? ''}',
      grade: '${json['grade'] ?? ''}'.trim(),
      reconciliation: recon is Map<String, dynamic>
          ? PenPaperStageReconciliation.fromJson(recon)
          : PenPaperStageReconciliation.empty,
    );
  }
}
