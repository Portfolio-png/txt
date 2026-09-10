import 'item_expression.dart';

/// The two writes an expression can make, narrowed to an interface so the
/// ordering logic can be tested without a provider, a repository or a server.
abstract class ItemExpressionSink {
  /// The id of a top-level property already called [name], or null.
  ///
  /// A plan is a snapshot of the item as it read when the line was typed. By
  /// the time it is applied the item may have moved on — most obviously
  /// because an earlier click already made this very property. Resolving
  /// against the item as it *is* keeps applying twice from failing.
  Future<int?> findProperty({required int itemId, required String name});

  /// Creates the property and, where the type stores values, its first value —
  /// in one write. As two writes the property's id could go stale between
  /// them. Returns the new property's node id, or null if it could not be made.
  Future<int?> appendPropertyWithValue({
    required int itemId,
    required String name,
    required String inputType,
    required String value,
  });

  /// True when the type is answered per use (Numeric, Gauge) and so holds no
  /// stored values to append to.
  bool isDataEntry(String inputType);

  Future<bool> appendValue({
    required int itemId,
    required int propertyNodeId,
    required String value,
  });

  /// Why the last call failed, if it said. Surfaced so a refusal reaches the
  /// person who caused it rather than dying in a boolean.
  String? get lastError;
}

class ItemExpressionOutcome {
  const ItemExpressionOutcome({
    required this.reused,
    required this.valuesAdded,
    required this.propertiesAdded,
    required this.failures,
  });

  /// Values that already existed and were selected rather than written.
  final int reused;
  final int valuesAdded;
  final int propertiesAdded;

  /// Segments that could not be written, in the order they were attempted.
  final List<String> failures;

  bool get isClean => failures.isEmpty;
  bool get wroteNothing => valuesAdded == 0 && propertiesAdded == 0;

  String get summary {
    if (wroteNothing && isClean) {
      return reused == 0 ? 'Nothing to add.' : '$reused already on the item.';
    }
    final parts = <String>[
      if (propertiesAdded > 0)
        '$propertiesAdded propert${propertiesAdded == 1 ? 'y' : 'ies'}',
      if (valuesAdded > 0) '$valuesAdded value${valuesAdded == 1 ? '' : 's'}',
    ];
    return 'Added ${parts.join(' and ')}.';
  }
}

/// Turns a parsed expression into writes, against an item that already exists.
///
/// Creating the *item* is deliberately not here: that is the item editor's job,
/// and the picker already routes to it. This handles the case the expression
/// exists for — adding to something already in the master.
///
/// An invented property and its first value go in as **one** write, because a
/// property id read back between two writes can be stale by the time it is
/// used. A property the item already has is reused rather than remade, so
/// applying the same line twice adds nothing the second time instead of
/// failing. A segment that failed does not stop the rest: the half that can
/// land should land, and the caller is told what did not.
class ItemExpressionExecutor {
  const ItemExpressionExecutor._();

  /// Pairs what was being attempted with whatever the sink said went wrong.
  static String _describe(String attempt, ItemExpressionSink sink) {
    final reason = sink.lastError?.trim() ?? '';
    return reason.isEmpty ? '$attempt.' : '$attempt — $reason';
  }

  static Future<ItemExpressionOutcome> apply(
    ItemExpressionPlan plan,
    ItemExpressionSink sink,
  ) async {
    final itemId = plan.itemId;
    if (itemId == null) {
      return const ItemExpressionOutcome(
        reused: 0,
        valuesAdded: 0,
        propertiesAdded: 0,
        failures: ['This line names an item that does not exist yet.'],
      );
    }

    var reused = 0;
    var valuesAdded = 0;
    var propertiesAdded = 0;
    final failures = <String>[];

    for (final segment in plan.valueSegments) {
      switch (segment.kind) {
        case SegmentKind.item:
        case SegmentKind.pending:
          break;

        case SegmentKind.existingValue:
          // Already there. The whole point of naming this case is that it
          // writes nothing.
          reused++;

        case SegmentKind.boundValue:
          // Resolve the property live, the same way the invented case does.
          // The id on the segment came from the snapshot the line was typed
          // against, and node ids are reassigned when a used item's tree is
          // rewritten — so the snapshot's id can point at nothing.
          final propertyId =
              await sink.findProperty(
                itemId: itemId,
                name: segment.propertyName,
              ) ??
              segment.propertyId;
          if (propertyId == null) {
            failures.add('${segment.value} — no property to put it on.');
            break;
          }
          final ok = await sink.appendValue(
            itemId: itemId,
            propertyNodeId: propertyId,
            value: segment.value,
          );
          if (ok) {
            valuesAdded++;
          } else {
            failures.add(
              _describe('${segment.value} on ${segment.propertyName}', sink),
            );
          }

        case SegmentKind.typeOnly:
          // Declared but never filled in — the values dialog should have
          // caught this, so treat it as a caller error rather than writing an
          // empty property.
          failures.add('${segment.propertyName} has no value yet.');

        case SegmentKind.newProperty:
          final existing = await sink.findProperty(
            itemId: itemId,
            name: segment.propertyName,
          );
          if (existing != null) {
            // A second run over the same line: the property landed the first
            // time, so only its value is still outstanding.
            if (sink.isDataEntry(segment.inputType)) break;
            // Named `added`, not `reused`: that would shadow the counter.
            final added = await sink.appendValue(
              itemId: itemId,
              propertyNodeId: existing,
              value: segment.value,
            );
            if (added) {
              valuesAdded++;
            } else {
              failures.add(
                _describe('${segment.value} on ${segment.propertyName}', sink),
              );
            }
            break;
          }
          final created = await sink.appendPropertyWithValue(
            itemId: itemId,
            name: segment.propertyName,
            inputType: segment.inputType,
            value: segment.value,
          );
          if (created == null) {
            failures.add(
              _describe('Could not add ${segment.propertyName}', sink),
            );
            break;
          }
          propertiesAdded++;
          // A Numeric or Gauge property stores no values — the number is given
          // each time it is used — so the property alone is the write.
          if (!sink.isDataEntry(segment.inputType)) valuesAdded++;
      }
    }

    return ItemExpressionOutcome(
      reused: reused,
      valuesAdded: valuesAdded,
      propertiesAdded: propertiesAdded,
      failures: failures,
    );
  }
}
