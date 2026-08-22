import 'package:flutter/foundation.dart';

/// A part the planner can nest onto a sheet: what it is, and how big its blank
/// is in millimetres.
///
/// Deliberately not an [ItemDefinition]. The planner needs four fields, and
/// taking the whole item would tie the sheet drawing to the catalogue — which
/// would mean the dialog could not be opened, or tested, without the items
/// feature standing behind it. The caller maps its own records into this.
@immutable
class SheetPart {
  const SheetPart({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
  });

  final int id;
  final String name;
  final double widthMm;
  final double heightMm;

  bool get isPlannable => widthMm > 0 && heightMm > 0;

  /// The blank as it reads on a drawing.
  String get sizeLabel => '${_trim(widthMm)} × ${_trim(heightMm)} mm';

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  @override
  bool operator ==(Object other) =>
      other is SheetPart &&
      other.id == id &&
      other.name == name &&
      other.widthMm == widthMm &&
      other.heightMm == heightMm;

  @override
  int get hashCode => Object.hash(id, name, widthMm, heightMm);
}
