/// One stage a part can pass through on the floor.
///
/// A row in the factory's stage master, not a constant. Two hardcoded lists of
/// process types exist elsewhere in this codebase and disagree with each other;
/// a route reads only from here.
class ProcessStage {
  const ProcessStage({
    required this.id,
    required this.code,
    required this.name,
    this.position = 0,
    this.repeatable = false,
    this.active = true,
    this.uses = 0,
  });

  final int id;
  final String code;
  final String name;
  final int position;

  /// Whether this stage may appear more than once in one route. The backend
  /// enforces it; this is here so a view can stop offering it a second time
  /// rather than letting someone pick it and be refused.
  final bool repeatable;

  final bool active;

  /// Draft and active routes standing on this stage. While any do, it cannot
  /// be deleted from the master.
  final int uses;

  static ProcessStage? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    if (id == null) return null;
    return ProcessStage(
      id: id,
      code: (json['code'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      position: (json['position'] as num?)?.toInt() ?? 0,
      repeatable: _flag(json['repeatable']),
      active: _flag(json['active'], fallback: true),
      uses: (json['uses'] as num?)?.toInt() ?? 0,
    );
  }

  /// SQLite has no boolean, so these arrive as 0/1 — but a mock or a future
  /// JSON source may send a real bool. Both read the same way.
  static bool _flag(Object? value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return fallback;
    return text == '1' || text == 'true';
  }

  @override
  String toString() => 'ProcessStage($code)';
}
