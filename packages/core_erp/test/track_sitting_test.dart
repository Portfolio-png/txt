import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/auth/domain/track_event.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/auth/presentation/widgets/track_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Reading a sitting: the model, and the tile that renders it.
///
/// The server grew two new `action` values and five new entity types when
/// sittings landed, and this side knew about neither — so a link read
/// "Updated" with a pencil and a set read `inventory_sets` out loud. A refused
/// fetch was worse: it arrived as an empty list and rendered as "No activity
/// tracked yet", telling somebody nothing had happened in a window they were
/// simply not allowed to see.

Map<String, dynamic> _json({
  String action = 'created',
  String entityType = 'items',
  Map<String, dynamic>? details,
  String? sittingId,
}) => {
  'id': 7,
  'entityType': entityType,
  'entityId': '42',
  'action': action,
  'actorName': 'Asha',
  'actorRole': 'user',
  'changes': const <Map<String, dynamic>>[],
  'details': details ?? {'label': 'Cone Top'},
  'createdAt': '2026-10-17T14:02:00.000Z',
  if (sittingId != null) 'sittingId': sittingId,
};

void main() {
  group('TrackEvent keeps what a sitting needs', () {
    test('the sitting id is no longer dropped', () {
      final event = TrackEvent.fromJson(_json(sittingId: 's123-abc'));
      expect(event.sittingId, 's123-abc');
    });

    test('a link carries the record at the other end', () {
      final event = TrackEvent.fromJson(
        _json(
          action: 'linked',
          details: {
            'label': 'Cone Top',
            'otherType': 'dies',
            'otherLabel': 'TD-12',
            'pairKey': 'dies:3|items:42',
          },
        ),
      );
      expect(event.isLink, isTrue);
      expect(event.otherType, 'dies');
      expect(event.otherLabel, 'TD-12');
      expect(event.otherNoun, 'Die');
    });

    test('a payload from an older server still decodes', () {
      // All three new fields are nullable precisely so this holds.
      final event = TrackEvent.fromJson(_json());
      expect(event.sittingId, isNull);
      expect(event.otherType, isNull);
      expect(event.isLink, isFalse);
      expect(event.label, 'Cone Top');
    });

    test('the five masters that started logging have words', () {
      // Without these the fallback prints the raw column value.
      const expected = {
        'departments': 'Department',
        'sub_contractors': 'Sub-contractor',
        'groups': 'Group',
        'inventory_sets': 'Set',
        'materials': 'Material',
      };
      expected.forEach((type, noun) {
        expect(trackEntityNoun(type), noun, reason: type);
      });
    });

    test('a type nobody has taught it still reads as itself', () {
      expect(trackEntityNoun('spaceships'), 'spaceships');
    });
  });

  group('the panel renders a sitting', () {
    // Driven through the real TrackPanel rather than its private tile: the
    // point is the whole path, provider included.
    Future<void> pump(
      WidgetTester tester, {
      List<TrackEvent> events = const [],
      Object? failure,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AuthProvider>(
              create: (_) => _StubAuth(events: events, failure: failure),
              child: SingleChildScrollView(
                child: TrackPanel.sitting(sittingId: 's1', showHeader: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a link names both sides, not just one', (tester) async {
      await pump(
        tester,
        events: [
          TrackEvent.fromJson(
            _json(
              action: 'linked',
              details: {
                'label': 'Cone Top',
                'otherType': 'dies',
                'otherLabel': 'TD-12',
              },
            ),
          ),
        ],
      );

      expect(find.textContaining('Linked'), findsOneWidget);
      expect(find.textContaining('Cone Top'), findsOneWidget);
      expect(
        find.textContaining('TD-12'),
        findsOneWidget,
        reason: 'naming one side says half of what happened',
      );
      expect(find.textContaining('Updated'), findsNothing);
    });

    testWidgets('an unlink says so, and leans on the noun', (tester) async {
      await pump(
        tester,
        events: [
          TrackEvent.fromJson(
            _json(
              action: 'unlinked',
              details: {'label': 'Cone Top', 'otherType': 'machines'},
            ),
          ),
        ],
      );
      expect(find.textContaining('Unlinked'), findsOneWidget);
      // No label for the other side — it may have been deleted since — so the
      // noun carries the line.
      expect(find.textContaining('Machine'), findsOneWidget);
    });

    testWidgets('an action nobody has seen still renders', (tester) async {
      await pump(
        tester,
        events: [TrackEvent.fromJson(_json(action: 'teleported'))],
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Updated'), findsOneWidget);
    });

    testWidgets('a sitting spanning masters names each record', (tester) async {
      await pump(
        tester,
        events: [
          TrackEvent.fromJson(
            _json(entityType: 'inventory_sets', details: {'label': 'Cone Kit'}),
          ),
        ],
      );
      // Words, not the raw column value.
      expect(find.textContaining('Set'), findsOneWidget);
      expect(find.textContaining('inventory_sets'), findsNothing);
    });

    testWidgets('a refusal is an error, NOT "no activity yet"', (tester) async {
      // The defect this suite exists for: a 404 or a 403 used to arrive as an
      // empty list and claim nothing had happened.
      await pump(tester, failure: Exception('No such sitting.'));

      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.textContaining('No activity tracked yet'), findsNothing);
    });

    testWidgets('an empty sitting still says it is empty', (tester) async {
      await pump(tester);
      expect(find.textContaining('No activity tracked yet'), findsOneWidget);
    });

    testWidgets('nothing in the panel is set below 13', (tester) async {
      await pump(
        tester,
        events: [TrackEvent.fromJson(_json(details: {'label': 'Cone Top'}))],
      );
      final texts = tester.widgetList<Text>(find.byType(Text));
      expect(texts, isNotEmpty);
      for (final text in texts) {
        final size = text.style?.fontSize;
        if (size != null) {
          expect(size, greaterThanOrEqualTo(13), reason: text.data);
        }
      }
    });
  });
}

/// Answers with fixed events, or throws — which is the half the real provider
/// deliberately does NOT swallow for a sitting.
class _StubAuth extends AuthProvider {
  _StubAuth({required this.events, this.failure}) : super(baseUrl: '');

  final List<TrackEvent> events;
  final Object? failure;

  @override
  Future<List<TrackEvent>> getSittingTrack(String sittingId) async {
    if (failure != null) throw failure!;
    return events;
  }
}
