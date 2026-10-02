import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing saved in the creation window, remembered so the sitting it
/// belonged to can be picked out of the recents list later.
class CreationSessionRecord {
  const CreationSessionRecord({
    required this.kind,
    required this.id,
    required this.title,
  });

  /// A [CreationKinds] key.
  final String kind;
  final String id;
  final String title;

  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'title': title};

  static CreationSessionRecord? fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    final id = json['id'] as String?;
    if (kind == null || id == null) return null;
    return CreationSessionRecord(
      kind: kind,
      id: id,
      title: (json['title'] as String?) ?? '',
    );
  }
}

/// One sitting at the creation window: everything saved in it, together.
///
/// A die is usually made for an item, and the machine that runs it in the same
/// breath; those belong together afterwards too, so they are remembered as one
/// entry rather than as three unrelated records.
class CreationSession {
  const CreationSession({
    required this.id,
    required this.savedAt,
    required this.records,
  });

  final String id;
  final DateTime savedAt;
  final List<CreationSessionRecord> records;

  /// What the recents list shows: the names, in the order they were saved.
  String get label => records.map((record) => record.title).join(' · ');

  bool matches(String query) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();
    return records.any(
      (record) =>
          record.title.toLowerCase().contains(needle) ||
          record.kind.toLowerCase().contains(needle),
    );
  }

  CreationSession plus(CreationSessionRecord record) => CreationSession(
    id: id,
    savedAt: DateTime.now(),
    records: [
      // A record saved twice (edited, then saved again) keeps its first place.
      ...records.where(
        (existing) =>
            !(existing.kind == record.kind && existing.id == record.id),
      ),
      record,
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'savedAt': savedAt.toIso8601String(),
    'records': [for (final record in records) record.toJson()],
  };

  static CreationSession? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null) return null;
    final records = <CreationSessionRecord>[
      for (final raw in (json['records'] as List?) ?? const [])
        if (raw is Map<String, dynamic>)
          if (CreationSessionRecord.fromJson(raw) case final record?) record,
    ];
    if (records.isEmpty) return null;
    return CreationSession(
      id: id,
      savedAt:
          DateTime.tryParse((json['savedAt'] as String?) ?? '') ??
          DateTime.now(),
      records: records,
    );
  }
}

/// The recents list behind the creation window's search bar, and the way back
/// into one. Held by the dialog, filled by the workspace.
///
/// Sessions live in [SharedPreferences]: they are a convenience for whoever is
/// sitting at this machine entering data, not shared state.
class CreationSessionController extends ChangeNotifier {
  CreationSessionController({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String prefsKey = 'creation_recent_sessions';

  /// How many sittings are kept. Enough to reach back through a morning's
  /// work, few enough that the list stays readable.
  static const int keep = 12;

  final SharedPreferences? _preferences;

  List<CreationSession> _recent = const [];
  List<CreationSession> get recent => _recent;

  /// Set by the workspace: puts a remembered sitting back on screen.
  ValueChanged<CreationSession>? onRestore;

  Future<SharedPreferences?> _prefs() async {
    if (_preferences != null) return _preferences;
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      // No store (a test, a platform without one): recents simply stay empty.
      return null;
    }
  }

  Future<void> load() async {
    final prefs = await _prefs();
    final raw = prefs?.getStringList(prefsKey) ?? const <String>[];
    final sessions = <CreationSession>[];
    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) {
          final session = CreationSession.fromJson(decoded);
          if (session != null) sessions.add(session);
        }
      } catch (_) {
        // A single unreadable entry must not cost the whole list.
      }
    }
    _recent = sessions;
    notifyListeners();
  }

  /// Files [session] at the top, replacing an earlier write of the same one.
  Future<void> remember(CreationSession session) async {
    if (session.records.isEmpty) return;
    _recent = [
      session,
      ..._recent.where((existing) => existing.id != session.id),
    ].take(keep).toList(growable: false);
    notifyListeners();
    final prefs = await _prefs();
    await prefs?.setStringList(prefsKey, [
      for (final entry in _recent) jsonEncode(entry.toJson()),
    ]);
  }

  void restore(CreationSession session) => onRestore?.call(session);
}
