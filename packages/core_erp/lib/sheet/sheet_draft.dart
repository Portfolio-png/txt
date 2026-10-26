import 'package:flutter/foundation.dart';
import 'column_def.dart';
import 'column_option.dart';

@immutable
class CellValue {
  const CellValue({
    required this.columnId,
    this.optionId,
    this.optionTmp,
    this.optionLabel,
    this.refId,
    this.textValue,
    this.intValue,
    this.mode = ValueMode.auto,
    this.isNew = false,
  });

  final int columnId;
  final int? optionId;
  final String? optionTmp;
  final String? optionLabel;
  final int? refId;
  final String? textValue;
  final int? intValue;
  final ValueMode mode;
  final bool isNew;

  bool get isEmpty =>
      optionId == null &&
      optionTmp == null &&
      (optionLabel == null || optionLabel!.isEmpty) &&
      refId == null &&
      (textValue == null || textValue!.isEmpty) &&
      intValue == null;

  bool get isNotEmpty => !isEmpty;

  CellValue copyWith({
    int? columnId,
    int? optionId,
    bool clearOptionId = false,
    String? optionTmp,
    bool clearOptionTmp = false,
    String? optionLabel,
    bool clearOptionLabel = false,
    int? refId,
    bool clearRefId = false,
    String? textValue,
    bool clearTextValue = false,
    int? intValue,
    bool clearIntValue = false,
    ValueMode? mode,
    bool? isNew,
  }) {
    return CellValue(
      columnId: columnId ?? this.columnId,
      optionId: clearOptionId ? null : (optionId ?? this.optionId),
      optionTmp: clearOptionTmp ? null : (optionTmp ?? this.optionTmp),
      optionLabel: clearOptionLabel ? null : (optionLabel ?? this.optionLabel),
      refId: clearRefId ? null : (refId ?? this.refId),
      textValue: clearTextValue ? null : (textValue ?? this.textValue),
      intValue: clearIntValue ? null : (intValue ?? this.intValue),
      mode: mode ?? this.mode,
      isNew: isNew ?? this.isNew,
    );
  }
}

class SheetDraft {
  SheetDraft({
    required this.sheetKey,
    this.entityId,
    Map<int, CellValue>? values,
    List<ColumnOption>? newOptions,
  })  : _values = Map<int, CellValue>.from(values ?? {}),
        _newOptions = List<ColumnOption>.from(newOptions ?? []);

  final String sheetKey;

  /// The record this row came from, or null for a row being entered.
  ///
  /// Without it a loaded row has nothing to say it is an edit, so saving a
  /// sheet that was opened for editing would file a second part with the same
  /// name and code — and the code is unique, so the server would refuse the
  /// save rather than obviously duplicating. A row knows what it is.
  final int? entityId;
  final Map<int, CellValue> _values;
  final List<ColumnOption> _newOptions;

  Map<int, CellValue> get values => Map.unmodifiable(_values);
  List<ColumnOption> get newOptions => List.unmodifiable(_newOptions);

  /// Whether anything has changed since this row was last written.
  ///
  /// A sheet re-committed after fixing one bad row would otherwise push an
  /// update for every row that already landed — pointless traffic, and with a
  /// full-replace update it is traffic that can only lose information.
  bool _dirtySinceSave = false;
  bool get isDirtySinceSave => _dirtySinceSave;
  void markClean() => _dirtySinceSave = false;

  /// For a row that took its saved id while holding an edit the save did not
  /// carry: it is a record now, and it still has something to write.
  void markDirty() => _dirtySinceSave = true;

  CellValue? get(int columnId) => _values[columnId];

  void set(int columnId, CellValue value) {
    _values[columnId] = value;
    _dirtySinceSave = true;
  }

  void clear(int columnId) {
    _values.remove(columnId);
    _dirtySinceSave = true;
  }

  void addNewOption(ColumnOption option) {
    _newOptions.removeWhere(
      (opt) => opt.columnId == option.columnId && opt.label.toLowerCase() == option.label.toLowerCase(),
    );
    _newOptions.add(option);
  }

  SheetDraft clone() {
    return SheetDraft(
      sheetKey: sheetKey,
      entityId: entityId,
      values: _values,
      newOptions: _newOptions,
    );
  }
}
