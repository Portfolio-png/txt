import 'package:core_erp/features/items/domain/part_code.dart';
import 'column_def.dart';
import 'column_option.dart';
import 'sheet_def.dart';
import 'sheet_draft.dart';
import 'sheet_binding.dart';

class ValidationError {
  const ValidationError({
    required this.columnId,
    required this.code,
    required this.message,
  });

  final int columnId;
  final String code;
  final String message;

  @override
  String toString() => 'ValidationError($columnId, $code): $message';
}

abstract final class SheetEngine {
  /// "12.50", "₹ 1,250", "85,000" → rupees; null when it is not an amount.
  ///
  /// Commas, spaces and the rupee sign are dropped and the decimal point is
  /// KEPT. Stripping everything but digits read 12.50 as 1250.
  static double? parseMoney(String? text) {
    final cleaned = (text ?? '').replaceAll(RegExp(r'[,\s₹]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// A whole number as typed — commas and spaces allowed, a sign kept, a
  /// decimal point refused (null) rather than silently dropped.
  static int? parseWhole(String? text) {
    final cleaned = (text ?? '').replaceAll(RegExp(r'[,\s]'), '');
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }

  /// The option id [columnId]'s choices hang off on this row: the nearest
  /// ancestor that holds one.
  ///
  /// Not just the parent. A part filed straight under a Group has an empty
  /// Type, and looking only one level up offered it no part names at all —
  /// and refused the names a loaded row already had.
  static int? parentOptionIdFor(
    SheetDef sheet,
    SheetDraft draft,
    int columnId,
  ) {
    var parentId = sheet.getColumn(columnId)?.parentId;
    while (parentId != null) {
      final value = draft.get(parentId);
      if (value != null && value.isNotEmpty) return value.optionId;
      parentId = sheet.getColumn(parentId)?.parentId;
    }
    return null;
  }

  /// Clears descendant answers that no longer exist under the new answer.
  /// Rule 8: Changing an answer clears every descendant answer that does not
  /// exist under the new answer. Nothing else is cleared.
  static void cascade(
    SheetDef sheet,
    SheetDraft draft,
    int changedColumnId,
    List<ColumnOption> allOptions,
  ) {
    final changedVal = draft.get(changedColumnId);
    final changedOptId = changedVal?.optionId;

    final children = sheet.columns
        .where((c) => c.parentId == changedColumnId)
        .toList();
    for (final child in children) {
      final childVal = draft.get(child.id);
      if (childVal == null || childVal.isEmpty) continue;

      if (changedOptId == null) {
        draft.clear(child.id);
        cascade(sheet, draft, child.id, allOptions);
        continue;
      }

      final validOption = allOptions.any(
        (opt) =>
            opt.columnId == child.id &&
            opt.parentOptionId == changedOptId &&
            opt.id == childVal.optionId,
      );

      final matchingOptionUnderNewParent = allOptions
          .where(
            (opt) =>
                opt.columnId == child.id &&
                opt.parentOptionId == changedOptId &&
                opt.label.toLowerCase() ==
                    (childVal.optionLabel ?? '').toLowerCase(),
          )
          .firstOrNull;

      if (matchingOptionUnderNewParent != null) {
        draft.set(
          child.id,
          childVal.copyWith(
            optionId: matchingOptionUnderNewParent.id,
            optionLabel: matchingOptionUnderNewParent.label,
          ),
        );
        cascade(sheet, draft, child.id, allOptions);
        continue;
      }

      final isNewValid =
          childVal.isNew &&
          draft.newOptions.any(
            (opt) =>
                opt.columnId == child.id &&
                opt.parentOptionId == changedOptId &&
                opt.label.toLowerCase() ==
                    (childVal.optionLabel ?? '').toLowerCase(),
          );

      if (!validOption && !isNewValid) {
        draft.clear(child.id);
        cascade(sheet, draft, child.id, allOptions);
      }
    }
  }

  /// Calculates the group path string leading up to this column
  static String groupPathString(
    SheetDef sheet,
    SheetDraft draft,
    int columnId,
  ) {
    final ancestors = sheet.ancestors(columnId);
    final segments = <String>[];
    for (final anc in ancestors) {
      final val = draft.get(anc.id);
      final label = val?.optionLabel ?? val?.textValue;
      if (label != null && label.isNotEmpty) {
        segments.add(label);
      }
    }
    return segments.join(' › ');
  }

  /// Generates the derived sequence running number and code for Auto columns.
  static void derive(
    SheetDef sheet,
    SheetDraft draft, {
    Map<String, int> counters = const {},
  }) {
    // A saved row is never re-derived. Its running number and code are what the
    // server stored, not a suggestion.
    //
    // This matters the moment rows commit one at a time: committing row 1 moves
    // the counters, every row is re-derived, and a row already in the database
    // would silently take a NEW code on screen — which a later edit would then
    // push back over the stored one.
    if (draft.entityId != null) return;

    int? currentSeq;

    for (final col in sheet.columns) {
      final cellVal = draft.get(col.id);

      if (col.kind == ColumnKind.seq) {
        final mode = cellVal?.mode ?? ValueMode.auto;
        if (mode == ValueMode.auto) {
          final scope = groupPathString(sheet, draft, col.id);
          final last = counters[scope] ?? 0;
          final nextVal = last + 1;
          currentSeq = nextVal;
          draft.set(
            col.id,
            (cellVal ?? CellValue(columnId: col.id)).copyWith(
              intValue: nextVal,
              mode: ValueMode.auto,
            ),
          );
        } else if (cellVal?.intValue != null) {
          currentSeq = cellVal!.intValue;
        }
      }

      if (col.kind == ColumnKind.code) {
        final mode = cellVal?.mode ?? ValueMode.auto;
        if (mode == ValueMode.auto) {
          // The trunk is the identity chain — the group levels and the part
          // name — read off the sheet rather than by column kind and position.
          // Position was never the right test: the code column moved to the
          // end of Properties, which put every property column "before" it and
          // would have folded Finish's full initials into the trunk while a
          // Material or Gauge column contributed nothing at all.
          final nameColumn =
              sheet.columnBoundTo(SheetBindsTo.name) ?? sheet.itemColumn;
          final chain = <ColumnDef>[
            if (nameColumn != null) ...sheet.ancestors(nameColumn.id),
            if (nameColumn != null) nameColumn,
          ];

          final buffer = StringBuffer();
          for (final link in chain) {
            final value = draft.get(link.id);
            final label = value?.optionLabel ?? value?.textValue;
            if (label != null && label.isNotEmpty) {
              buffer.write(partCodeInitials(label));
            }
          }

          // Then one code per top-level property, in column order: numbers
          // whole, letters first, so 22 Gauge and 24 Gauge stay apart.
          final values = StringBuffer();
          for (final property in sheet.variationColumns) {
            final value = draft.get(property.id);
            final label = value?.optionLabel ?? value?.textValue;
            if (label != null && label.isNotEmpty) {
              values.write(partPropertyCode(label));
            }
          }

          // The same 12-letter cap the server applies to the trunk, so the
          // preview cannot claim a code the server would shorten. The value
          // codes are deliberately NOT capped — clipping one makes two parts
          // that differ only by a property share a code.
          final rawTrunk = buffer.toString();
          final prefix = rawTrunk.length <= kMaxPartCodeLetters
              ? rawTrunk
              : rawTrunk.substring(0, kMaxPartCodeLetters);
          // No prefix means nothing on the group path is filled in, and a bare
          // running number is not a part code — an untouched sheet derived the
          // code "1" and offered it as one. A code needs a path to come from.
          final fullCode = prefix.isEmpty
              ? ''
              : '$prefix$values${currentSeq ?? ''}';

          draft.set(
            col.id,
            (cellVal ?? CellValue(columnId: col.id)).copyWith(
              textValue: fullCode,
              mode: ValueMode.auto,
            ),
          );
        }
      }
    }
  }

  /// Validates a draft against all business rules.
  static Map<int, ValidationError> validate(
    SheetDef sheet,
    SheetDraft draft, {
    List<ColumnOption> allOptions = const [],
    List<Party> parties = const [],
    List<Contact> contacts = const [],
    Map<String, int> counters = const {},
    Set<String> existingCodes = const {},
    Set<String> existingPaths = const {},
    OptionIndex? optionIndex,
  }) {
    final errors = <int, ValidationError>{};

    for (final col in sheet.columns) {
      final val = draft.get(col.id);

      // Rule 1: Default columns required — except the stamps, which the
      // SERVER sets on save and nobody can fill beforehand. Marking them
      // required made the sheet unsatisfiable: Date and Time were empty on
      // every new part, so "2 cells need attention" was permanent and the
      // save could never go through. The prototype hid it by seeding the
      // literal text "Set on save" into those cells, which made them look
      // filled.
      if (col.isDefault && !col.isStamp && (val == null || val.isEmpty)) {
        errors[col.id] = ValidationError(
          columnId: col.id,
          code: 'required',
          message: '${col.label} is required.',
        );
        continue;
      }

      if (val == null || val.isEmpty) {
        if (col.kind == ColumnKind.seq && val?.mode == ValueMode.edit) {
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'edit_empty',
            message:
                'Type a value for ${col.label}, or switch it back to Auto.',
          );
        }
        continue;
      }

      // Rule 2 & parent_first: Parent must be answered first — but only when
      // there is something to answer it with.
      //
      // A level with no options under the level above is a level that cannot
      // be filled, and blocking the cell below it then makes the sheet
      // unsaveable. That is not hypothetical: a workspace whose item groups
      // are flat has no Types at all, so "Pick Type first" sat permanently on
      // Part Name and no part could be named, let alone saved. The binding
      // already files a part under the deepest level actually named, so the
      // model allowed what this rule forbade.
      if (col.parentId != null) {
        final parent = sheet.getColumn(col.parentId!);
        final parentVal = parent != null ? draft.get(parent.id) : null;
        if (parent != null && (parentVal == null || parentVal.isEmpty)) {
          final grandparent = parent.parentId != null
              ? draft.get(parent.parentId!)
              : null;
          final parentHasChoices = allOptions.any(
            (opt) =>
                opt.columnId == parent.id &&
                opt.parentOptionId == grandparent?.optionId,
          );
          // A value that IS an option under the level above the empty one is
          // a part filed there on purpose — a part straight under a Group
          // that also has Types. Refusing it made such a part unsaveable
          // from the sheet once loaded.
          final label = (val.optionLabel ?? val.textValue ?? '').toLowerCase();
          final ancestorOptId = parentOptionIdFor(sheet, draft, col.id);
          final filedAbove =
              ancestorOptId != null &&
              allOptions.any(
                (opt) =>
                    opt.columnId == col.id &&
                    opt.parentOptionId == ancestorOptId &&
                    opt.label.toLowerCase() == label,
              );
          if (parentHasChoices && !filedAbove) {
            errors[col.id] = ValidationError(
              columnId: col.id,
              code: 'parent_first',
              message: 'Pick ${parent.label} first.',
            );
            continue;
          }
        }
      }

      // Rule 7 & not_in_list
      if (col.kind == ColumnKind.list && col.source == ColumnSource.options) {
        final optLabel = val.optionLabel ?? val.textValue ?? '';
        final parentOptId = parentOptionIdFor(sheet, draft, col.id);
        final wanted = optLabel.toLowerCase();

        final exists = optionIndex != null
            ? optionIndex.contains(col.id, parentOptId, wanted)
            : allOptions.any(
                (opt) =>
                    opt.columnId == col.id &&
                    opt.parentOptionId == parentOptId &&
                    opt.label.toLowerCase() == wanted,
              );

        final isNew =
            val.isNew ||
            draft.newOptions.any(
              (opt) =>
                  opt.columnId == col.id &&
                  opt.parentOptionId == parentOptId &&
                  opt.label.toLowerCase() == optLabel.toLowerCase(),
            );

        if (!exists && !isNew && optLabel.isNotEmpty) {
          // A property column's list is its own, not a level of the group
          // path — "not a part name under Switch Action" was wrong for one.
          final message = SheetBindsTo.isVariation(col.bindsTo)
              ? '“$optLabel” is not in ${col.label}\'s list. Pick one, or choose Add new.'
              : '“$optLabel” is not a part name under '
                    '${groupPathString(sheet, draft, col.id)}. Pick one, or choose Add new.';
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'not_in_list',
            message: message,
          );
          continue;
        }
      }

      // Rule 9 & duplicate_item
      if (col.isItem) {
        final path = groupPathString(sheet, draft, col.id);
        final itemLabel = val.optionLabel ?? val.textValue ?? '';
        final fullPath = path.isNotEmpty ? '$path › $itemLabel' : itemLabel;
        if (existingPaths.contains(fullPath.toLowerCase())) {
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'duplicate_item',
            message: '$itemLabel already exists under $path.',
          );
          continue;
        }
      }

      // Rule 10 & seq_used
      if (col.kind == ColumnKind.seq &&
          val.mode == ValueMode.edit &&
          val.intValue != null) {
        final scope = groupPathString(sheet, draft, col.id);
        final last = counters[scope] ?? 0;
        if (val.intValue! <= last) {
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'seq_used',
            message:
                '${col.label} ${val.intValue} is already used within $scope. The last one is $last.',
          );
          continue;
        }
      }

      // Rule 11 & code_used — only for a code somebody TYPED.
      //
      // A derived code is a preview of what the server will stamp, not a claim
      // on it. Refusing the sheet over one made bulk entry impossible: every
      // row under a group derives the same preview, so every row after the
      // first was flagged for a value the user never entered and could not
      // change without switching the cell to manual.
      if (col.kind == ColumnKind.code && val.mode == ValueMode.edit) {
        final code = val.textValue ?? '';
        if (existingCodes.contains(code.toUpperCase())) {
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'code_used',
            message: '$code is already used by another item.',
          );
          continue;
        }
      }

      // Phone check
      if (col.kind == ColumnKind.phone) {
        final digits = (val.textValue ?? '').replaceAll(RegExp(r'\D'), '');
        if (digits.isNotEmpty && digits.length != 10) {
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'phone_digits',
            message: '${col.label} should have 10 digits.',
          );
          continue;
        }
      }

      // Email check
      if (col.kind == ColumnKind.email) {
        final email = (val.textValue ?? '').trim();
        if (email.isNotEmpty &&
            (!email.contains('@') || !email.split('@').last.contains('.'))) {
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'email_format',
            message:
                'Check ${col.label}. It should look like name@company.com.',
          );
          continue;
        }
      }

      // Number check
      if (col.kind == ColumnKind.number) {
        if (val.textValue != null &&
            val.textValue!.isNotEmpty &&
            val.intValue == null) {
          errors[col.id] = ValidationError(
            columnId: col.id,
            code: 'not_number',
            message: '${col.label} takes a whole number.',
          );
          continue;
        }
      }

      // Money check — paise allowed, a negative amount is not.
      if (col.kind == ColumnKind.money) {
        final text = val.textValue;
        if (text != null && text.trim().isNotEmpty) {
          final amount = parseMoney(text);
          if (amount == null || amount < 0) {
            errors[col.id] = ValidationError(
              columnId: col.id,
              code: 'not_number',
              message:
                  '${col.label} takes an amount of zero or more, like 1250 or 12.50.',
            );
            continue;
          }
        }
      }
    }

    return errors;
  }

  /// Contextual hint message for a cell
  static String hintFor(
    SheetDef sheet,
    SheetDraft draft,
    int columnId, {
    Map<String, int> counters = const {},
  }) {
    final col = sheet.getColumn(columnId);
    if (col == null) return '';

    if (col.role == ColumnRole.stamp) {
      return 'Paper stamps the date when this is saved. It cannot be typed or changed.';
    }

    if (col.kind == ColumnKind.seq) {
      final scope = groupPathString(sheet, draft, columnId);
      final last = counters[scope] ?? 0;
      return 'Next after $last within $scope.';
    }

    if (col.kind == ColumnKind.code) {
      return 'First letters of each group column on its left, then the running number.';
    }

    if (col.parentId != null) {
      final scope = groupPathString(sheet, draft, columnId);
      return 'Values listed under $scope.';
    }

    // Before the primary-group case, which is merely "has no parent" and so is
    // true of every property too — Alloy explained itself as a primary group.
    if (SheetBindsTo.isVariation(col.bindsTo)) {
      return 'A property of the part. Its value shows in the part code.';
    }

    if (col.isPrimaryGroup) {
      return 'Primary group: Same list for every item.';
    }

    if (col.source == ColumnSource.contact) {
      final clientVal = draft.get(columnId);
      if (clientVal?.optionLabel != null) {
        return 'Filled from ${clientVal!.optionLabel}’s record. You can change it.';
      }
    }

    return 'Enter value for ${col.label}.';
  }
}

/// Options looked up by (column, parent, lower-cased label) in one step.
///
/// Validation asked "is this label an option here?" by scanning every option
/// for every list cell of every row, on every keystroke. Built once when the
/// options change instead.
class OptionIndex {
  OptionIndex(Iterable<ColumnOption> options) {
    for (final option in options) {
      _keys.add(
        _key(
          option.columnId,
          option.parentOptionId,
          option.label.toLowerCase(),
        ),
      );
    }
  }

  final Set<String> _keys = <String>{};

  static String _key(int columnId, int? parentOptionId, String lowerLabel) =>
      '$columnId|${parentOptionId ?? ''}|$lowerLabel';

  bool contains(int columnId, int? parentOptionId, String lowerLabel) =>
      _keys.contains(_key(columnId, parentOptionId, lowerLabel));
}
