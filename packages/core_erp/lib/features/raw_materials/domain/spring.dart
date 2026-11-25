/// A spring — the second raw-material form (Docs/architecture/13-raw-material-forms.md).
///
/// The owner, 2026-11-25: a spring is of a KIND — Double Hook (an extension
/// spring, the first drawing), Conical (the second picture), Iron Connector —
/// and of a TYPE (1.5 Cell, 5 A Steel, 15 A Steel, 16 A Iron Connector …).
/// Each kind has its own sizes. Everything measured tells two springs apart;
/// the NAME is arranged by the user from blocks joined by a space, X, + or -:
///
///   Double Hook Spring 114 X 6           (the default)
///   Double Hook Spring 114 X 6 - 22 SWG  (Wire Gauge added)
///
/// [springName] builds it the way the backend does, for the live preview.
library;

import 'rivet.dart' show RivetVendorPrice, isValidMillimetres;

/// The system key of the default Springs group (backend system-groups.js).
const String springsGroupSystemKey = 'raw_materials.springs';

enum SpringKind {
  doubleHook('Double Hook'),
  conical('Conical'),
  ironConnector('Iron Connector');

  const SpringKind(this.label);

  final String label;

  static SpringKind fromLabel(String? label) {
    for (final kind in values) {
      if (kind.label.toLowerCase() == (label ?? '').trim().toLowerCase()) {
        return kind;
      }
    }
    return SpringKind.doubleHook;
  }
}

/// Types offered as one tap; another can be typed.
const List<String> springTypeChoices = <String>[
  '1.5 Cell',
  '5 A Steel',
  '15 A Steel',
  '16 A Iron Connector',
];

/// A spring's sizes. [count] ones are how many coils; the rest millimetres.
enum SpringSize {
  coilLength('coilLength', 'Coil Length', required: true),
  coilNumber('coilNumber', 'Coil Number', required: true, count: true),
  coilOd('coilOd', 'Coil OD'),
  coilId('coilId', 'Coil ID'),
  freeLength('freeLength', 'Free Length', required: true),
  totalCoils('totalCoils', 'Total Coils', required: true, count: true),
  smallOd('smallOd', 'Small OD'),
  largeOd('largeOd', 'Large OD'),
  wireDiameter('wireDiameter', 'Wire Diameter');

  const SpringSize(
    this.key,
    this.label, {
    this.required = false,
    this.count = false,
  });

  final String key;
  final String label;
  final bool required;
  final bool count;
}

/// The sizes a kind has, in the order the form asks for them.
List<SpringSize> springSizesFor(SpringKind kind) => kind == SpringKind.conical
    ? const <SpringSize>[
        SpringSize.freeLength,
        SpringSize.totalCoils,
        SpringSize.smallOd,
        SpringSize.largeOd,
        SpringSize.wireDiameter,
      ]
    : const <SpringSize>[
        SpringSize.coilLength,
        SpringSize.coilNumber,
        SpringSize.coilOd,
        SpringSize.coilId,
      ];

/// Whether a kind's wire is given as a gauge (the extension kinds) — a
/// conical spring's is its Wire Diameter.
bool springHasGauge(SpringKind kind) => kind != SpringKind.conical;

/// How two blocks of a name are joined.
enum NameSeparator {
  space(' ', ' ', 'Space'),
  times('x', ' X ', 'X'),
  plus('+', ' + ', '+'),
  minus('-', ' - ', '-');

  const NameSeparator(this.wire, this.text, this.label);

  /// What is stored and sent.
  final String wire;

  /// What it puts between the blocks.
  final String text;
  final String label;

  static NameSeparator fromWire(String? wire) {
    for (final sep in values) {
      if (sep.wire == (wire ?? '').toLowerCase()) return sep;
    }
    return NameSeparator.space;
  }
}

/// One block of a name, and what joins it to the block before.
class NameToken {
  const NameToken(this.block, [this.sep = NameSeparator.space]);

  final String block;
  final NameSeparator sep;

  NameToken withSep(NameSeparator next) => NameToken(block, next);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'block': block,
    'sep': sep.wire,
  };

  static NameToken fromJson(Map<String, dynamic> json) => NameToken(
    json['block']?.toString() ?? '',
    NameSeparator.fromWire(json['sep']?.toString()),
  );

  @override
  bool operator ==(Object other) =>
      other is NameToken && other.block == block && other.sep == sep;

  @override
  int get hashCode => Object.hash(block, sep);
}

/// The blocks a kind's name can be made of (the backend's blocksFor).
List<String> springNameBlocks(SpringKind kind) => <String>[
  'kind',
  'spring',
  'springType',
  for (final size in springSizesFor(kind)) size.key,
  if (springHasGauge(kind)) 'wireGauge',
  'wireGrade',
];

/// What a block is called in the naming-format editor.
String springBlockLabel(String block) => switch (block) {
  'kind' => 'Kind',
  'spring' => '"Spring"',
  'springType' => 'Type',
  'wireGauge' => 'Wire Gauge',
  'wireGrade' => 'Wire Grade',
  _ =>
    SpringSize.values.where((s) => s.key == block).firstOrNull?.label ?? block,
};

/// "Double Hook Spring 114 X 6", "Conical Spring 20 X 5".
List<NameToken> defaultSpringNameFormat(SpringKind kind) {
  final conical = kind == SpringKind.conical;
  return <NameToken>[
    const NameToken('kind'),
    const NameToken('spring'),
    NameToken(conical ? 'freeLength' : 'coilLength'),
    NameToken(conical ? 'totalCoils' : 'coilNumber', NameSeparator.times),
  ];
}

class SpringDefinition {
  const SpringDefinition({
    required this.itemId,
    required this.name,
    required this.code,
    required this.kind,
    required this.springType,
    required this.sizes,
    required this.wireGauge,
    required this.wireGrade,
    required this.nameFormat,
    required this.vendors,
    this.isArchived = false,
  });

  /// The item's id: a spring is an item.
  final int itemId;
  final String name;
  final String code;
  final SpringKind kind;
  final String springType;

  /// Each size as typed: millimetres ("114") or a count ("6").
  final Map<SpringSize, String> sizes;

  /// As the vendor writes it ("22 SWG") — kept verbatim.
  final String wireGauge;
  final String wireGrade;
  final List<NameToken> nameFormat;
  final List<RivetVendorPrice> vendors;
  final bool isArchived;

  factory SpringDefinition.fromJson(Map<String, dynamic> json) {
    final kind = SpringKind.fromLabel(
      json['kind'] as String? ?? json['coilHook'] as String?,
    );
    final sizes = <SpringSize, String>{};
    for (final size in SpringSize.values) {
      final raw = json[size.key];
      if (raw is Map) {
        final mm = raw['mm']?.toString() ?? '';
        if (mm.isNotEmpty) sizes[size] = mm;
      } else if (raw is num) {
        sizes[size] = raw.toInt().toString();
      }
    }
    final format = (json['nameFormat'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((t) => NameToken.fromJson(t.cast<String, dynamic>()))
        .toList(growable: false);
    return SpringDefinition(
      itemId: (json['itemId'] as num).toInt(),
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      kind: kind,
      springType: json['springType'] as String? ?? '',
      sizes: sizes,
      wireGauge: json['wireGauge'] as String? ?? '',
      wireGrade: json['wireGrade'] as String? ?? '',
      nameFormat: format.isEmpty ? defaultSpringNameFormat(kind) : format,
      vendors: (json['vendors'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((row) => RivetVendorPrice.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
      isArchived: json['isArchived'] as bool? ?? false,
    );
  }

  /// "6 coils" — whichever count the kind has.
  String? get coilCount =>
      sizes[SpringSize.coilNumber] ?? sizes[SpringSize.totalCoils];
}

/// What the spring form sends.
class SpringInput {
  const SpringInput({
    required this.kind,
    required this.springType,
    required this.sizes,
    required this.wireGauge,
    required this.wireGrade,
    required this.code,
    required this.nameFormat,
    required this.vendors,
  });

  final SpringKind kind;
  final String springType;
  final Map<SpringSize, String> sizes;
  final String wireGauge;
  final String wireGrade;
  final String code;
  final List<NameToken> nameFormat;
  final List<RivetVendorPrice> vendors;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.label,
    'springType': springType.trim(),
    // Only the kind's own sizes: another kind's left-overs are not sent.
    for (final size in springSizesFor(kind))
      size.key: (sizes[size] ?? '').trim(),
    if (springHasGauge(kind)) 'wireGauge': wireGauge.trim(),
    'wireGrade': wireGrade.trim(),
    'code': code.trim(),
    'nameFormat': nameFormat.map((t) => t.toJson()).toList(growable: false),
    'vendors': vendors.map((v) => v.toJson()).toList(growable: false),
  };
}

/// How many coils: a whole number above 0.
bool isValidCoilNumber(String text) {
  final value = int.tryParse(text.trim());
  return value != null &&
      value > 0 &&
      RegExp(r'^\d{1,4}$').hasMatch(text.trim());
}

/// The inner size must be under the outer, when both are given.
bool coilIdUnderOd(String od, String id) {
  if (!isValidMillimetres(od) || !isValidMillimetres(id)) return true;
  return double.parse(id.trim()) < double.parse(od.trim());
}

/// "double  hook" → "Double Hook", as the backend stores text it names by.
String springTitleCase(String text) => text
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _normalizeMm(String text) {
  final match = RegExp(r'^(\d+)(\.\d*)?$').firstMatch(text.trim());
  if (match == null) return text.trim();
  final whole = int.tryParse(match.group(1)!) ?? 0;
  return '$whole${match.group(2) ?? ''}';
}

/// The spring's name from its blocks and format — the backend's springName.
/// A block with nothing in it is left out with its separator; a required size
/// not typed yet shows as … so the preview reads while it is filled.
String springName({
  required SpringKind kind,
  required String springType,
  required Map<SpringSize, String> sizes,
  required String wireGauge,
  required String wireGrade,
  required List<NameToken> format,
}) {
  String text(String block) {
    switch (block) {
      case 'kind':
        return kind.label;
      case 'spring':
        return 'Spring';
      case 'springType':
        return springType.trim().isEmpty ? '' : springTitleCase(springType);
      case 'wireGauge':
        return wireGauge.trim();
      case 'wireGrade':
        return wireGrade.trim();
    }
    final size = SpringSize.values.where((s) => s.key == block).firstOrNull;
    if (size == null) return '';
    final typed = (sizes[size] ?? '').trim();
    if (typed.isEmpty) return size.required ? '…' : '';
    return size.count
        ? (int.tryParse(typed)?.toString() ?? typed)
        : _normalizeMm(typed);
  }

  var name = '';
  for (final token in format) {
    final words = text(token.block);
    if (words.isEmpty) continue;
    name = name.isEmpty ? words : '$name${token.sep.text}$words';
  }
  return name.isEmpty ? '${kind.label} Spring' : name;
}
