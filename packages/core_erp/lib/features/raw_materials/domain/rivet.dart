/// A rivet — the first raw-material form (Docs/architecture/13-raw-material-forms.md).
///
/// A rivet is an ordinary item in the default Rivets group; what makes it a
/// rivet is its spec. Its name is built from the spec — the backend builds the
/// stored one, [rivetName] builds the same thing for the live preview:
///
///   Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)
library;

/// The system key of the default Rivets group (backend system-groups.js).
const String rivetsGroupSystemKey = 'raw_materials.rivets';

/// The three kinds of rivet the shop uses — the backend accepts these and
/// nothing else (owner, 2026-11-25).
const List<String> rivetTypes = <String>['Bimetal', 'Copper', 'Aluminium'];

/// Only a bimetal rivet has a silver layer: it is the silver on the copper.
/// Required there; on Copper and Aluminium it stays blank and out of the name.
bool rivetHasSilverLayer(String rivetType) =>
    rivetType.trim().toLowerCase() == 'bimetal';

enum RivetHeadType {
  flat('F', 'Flat'),
  round('R', 'Round');

  const RivetHeadType(this.code, this.label);

  /// What is stored and sent: F or R.
  final String code;
  final String label;

  static RivetHeadType? fromCode(String? code) {
    for (final type in values) {
      if (type.code == code?.toUpperCase()) return type;
    }
    return null;
  }
}

/// The five dimensions, in the order the name prints them.
enum RivetDimension {
  headOd('headOd', 'Head OD', required: true),
  headDia('headDia', 'Head Diameter', required: true),
  shankDia('shankDia', 'Shank Diameter', required: true),
  shankLength('shankLength', 'Shank Length', required: true),
  silverLayer('silverLayer', 'Silver Layer', required: false);

  const RivetDimension(this.key, this.label, {required this.required});

  final String key;
  final String label;

  /// Silver Layer may be blank (a plain copper rivet has none).
  final bool required;
}

/// How a vendor's price is quoted.
enum RivetPriceBasis {
  piece('piece', 'per piece'),
  hundred('hundred', 'per 100 pcs'),
  thousand('thousand', 'per 1000 pcs'),
  kg('kg', 'per kg');

  const RivetPriceBasis(this.key, this.label);

  final String key;
  final String label;

  static RivetPriceBasis fromKey(String? key) {
    for (final basis in values) {
      if (basis.key == key) return basis;
    }
    return RivetPriceBasis.piece;
  }
}

/// A millimetre value as typed ("2.0"), and the exact nanometres it is.
class RivetLength {
  const RivetLength({required this.mm, required this.nm});

  final String mm;
  final int nm;

  static RivetLength? fromJson(Object? json) {
    if (json is! Map) return null;
    return RivetLength(
      mm: json['mm']?.toString() ?? '',
      nm: (json['nm'] as num?)?.toInt() ?? 0,
    );
  }
}

class RivetVendorPrice {
  const RivetVendorPrice({
    required this.vendorId,
    required this.price,
    required this.basis,
    this.vendorName,
  });

  final int vendorId;
  final String? vendorName;

  /// Rupees as text, exact ("0.035", "32.50").
  final String price;
  final RivetPriceBasis basis;

  factory RivetVendorPrice.fromJson(Map<String, dynamic> json) {
    return RivetVendorPrice(
      vendorId: (json['vendorId'] as num).toInt(),
      vendorName: json['vendorName'] as String?,
      price: json['price']?.toString() ?? '',
      basis: RivetPriceBasis.fromKey(json['basis'] as String?),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'vendorId': vendorId,
    'price': price,
    'basis': basis.key,
  };
}

class RivetDefinition {
  const RivetDefinition({
    required this.itemId,
    required this.name,
    required this.code,
    required this.rivetType,
    required this.headType,
    required this.dimensions,
    required this.vendors,
    this.isArchived = false,
  });

  /// The item's id: a rivet is an item.
  final int itemId;
  final String name;
  final String code;
  final String rivetType;
  final RivetHeadType headType;
  final Map<RivetDimension, RivetLength?> dimensions;
  final List<RivetVendorPrice> vendors;
  final bool isArchived;

  factory RivetDefinition.fromJson(Map<String, dynamic> json) {
    return RivetDefinition(
      itemId: (json['itemId'] as num).toInt(),
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      rivetType: json['rivetType'] as String? ?? '',
      headType:
          RivetHeadType.fromCode(json['headType'] as String?) ??
          RivetHeadType.flat,
      dimensions: <RivetDimension, RivetLength?>{
        for (final dim in RivetDimension.values)
          dim: RivetLength.fromJson(json[dim.key]),
      },
      vendors: (json['vendors'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((row) => RivetVendorPrice.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
      isArchived: json['isArchived'] as bool? ?? false,
    );
  }
}

/// What the form sends: the spec as typed, the code, and the whole vendor list.
class RivetInput {
  const RivetInput({
    required this.rivetType,
    required this.headType,
    required this.dimensions,
    required this.code,
    required this.vendors,
  });

  final String rivetType;
  final RivetHeadType headType;

  /// Millimetres as typed; blank is "not given".
  final Map<RivetDimension, String> dimensions;
  final String code;
  final List<RivetVendorPrice> vendors;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'rivetType': rivetType.trim(),
    'headType': headType.code,
    for (final dim in RivetDimension.values)
      dim.key: (dimensions[dim] ?? '').trim(),
    'code': code.trim(),
    'vendors': vendors.map((v) => v.toJson()).toList(growable: false),
  };
}

/// A millimetre value the backend will take: digits, an optional point and
/// up to six decimals, more than zero.
bool isValidMillimetres(String text) {
  final match = RegExp(r'^(\d{1,4})(?:\.(\d{1,6}))?$').firstMatch(text.trim());
  if (match == null) return false;
  return RegExp(r'[1-9]').hasMatch(text);
}

/// A price the backend will take: rupees with up to six decimals.
bool isValidPrice(String text) => RegExp(
  r'^\d{1,9}(?:\.\d{1,6})?$',
).hasMatch(text.trim().replaceFirst('₹', '').trim());

/// "02.0" → "2.0", as the backend stores it.
String _normalizeMm(String text) {
  final match = RegExp(r'^(\d+)(\.\d*)?$').firstMatch(text.trim());
  if (match == null) return text.trim();
  final whole = int.tryParse(match.group(1)!) ?? 0;
  return '$whole${match.group(2) ?? ''}';
}

/// The rivet's name, the same rule as the backend's rivetName. Blank values
/// show as … so the preview reads while it is being filled.
String rivetName({
  required String rivetType,
  required RivetHeadType? headType,
  required Map<RivetDimension, String> dimensions,
}) {
  String d(RivetDimension dim) {
    final text = (dimensions[dim] ?? '').trim();
    return text.isEmpty ? '…' : _normalizeMm(text);
  }

  final type = rivetType.trim().isEmpty ? '…' : rivetType.trim();
  final head = headType?.label ?? '…';
  final base =
      '$type Rivet ${d(RivetDimension.headOd)} X ${d(RivetDimension.headDia)}'
      ' / ${d(RivetDimension.shankDia)} X ${d(RivetDimension.shankLength)} $head';
  final silver = (dimensions[RivetDimension.silverLayer] ?? '').trim();
  return silver.isEmpty ? base : '$base (${_normalizeMm(silver)})';
}
