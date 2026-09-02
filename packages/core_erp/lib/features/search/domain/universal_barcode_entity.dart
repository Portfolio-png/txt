import 'package:flutter/foundation.dart';

/// How a scanned code was resolved — and how much the answer can be trusted.
///
/// Not decoration. A code found by falling back to a column printed before the
/// scheme existed is a weaker answer than one that decoded and verified, and a
/// screen that cannot tell them apart will present a guess as a fact.
@immutable
class BarcodeResolution {
  const BarcodeResolution({
    this.via,
    this.looksLikeOurs = false,
    this.hasCheck = false,
    this.checkValid = true,
    this.canonical,
  });

  factory BarcodeResolution.fromJson(Map<String, dynamic> json) {
    return BarcodeResolution(
      via: json['via']?.toString(),
      looksLikeOurs: json['looksLikeOurs'] == true,
      hasCheck: json['hasCheck'] == true,
      checkValid: json['checkValid'] != false,
      canonical: json['canonical']?.toString(),
    );
  }

  /// `structured` — decoded from the scheme. `legacy-code` — matched a column
  /// that predates it. Null when nothing resolved.
  final String? via;

  /// Whether the string was shaped like one of ours. A code of ours naming
  /// nothing is a different problem from a code that was never ours: the first
  /// may be a deleted record or another workspace, the second is a foreign
  /// label. They deserve different words on screen.
  final bool looksLikeOurs;

  /// Whether a check character was present at all. Absent on a hand-typed code
  /// or an older label — such a code still resolves, just unverified.
  final bool hasCheck;

  /// False only when a check character was present and did not match. That is a
  /// misread, and the safe reading is "you may be holding something else".
  final bool checkValid;

  /// What the label ought to say, so a legacy code can be offered a reprint
  /// rather than left outside the scheme forever.
  final String? canonical;

  bool get isVerified => hasCheck && checkValid;
  bool get isMisread => hasCheck && !checkValid;
  bool get isLegacy => via == 'legacy-code';
}

/// The identity of whatever was scanned.
@immutable
class BarcodeEntity {
  const BarcodeEntity({
    required this.type,
    required this.typeLabel,
    required this.id,
    required this.title,
    this.subtitle = '',
  });

  factory BarcodeEntity.fromJson(Map<String, dynamic> json) {
    return BarcodeEntity(
      type: json['type']?.toString() ?? '',
      typeLabel: json['typeLabel']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
    );
  }

  /// The three-letter code — MAT, DC, RUN, EMP. What the resolver dispatched on.
  final String type;
  final String typeLabel;
  final String id;
  final String title;
  final String subtitle;
}

/// One entry in the chain of custody: something that happened to this thing.
@immutable
class CustodyEvent {
  const CustodyEvent({
    required this.eventId,
    required this.eventType,
    required this.at,
    this.actor = '',
    this.actorBarcode,
    this.locationBarcode,
    this.machineBarcode,
    this.dieBarcode,
    this.parents = const <String>[],
    this.children = const <String>[],
    this.orderBarcode,
    this.documentBarcode,
    this.metrics = const <String, dynamic>{},
    this.notes = '',
  });

  factory CustodyEvent.fromJson(Map<String, dynamic> json) {
    List<String> codes(Object? value) => value is List
        ? value.map((entry) => entry.toString()).toList(growable: false)
        : const <String>[];

    return CustodyEvent(
      eventId: json['eventId']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? '',
      at: json['at']?.toString() ?? '',
      actor: json['actor']?.toString() ?? '',
      actorBarcode: json['actorBarcode']?.toString(),
      locationBarcode: json['locationBarcode']?.toString(),
      machineBarcode: json['machineBarcode']?.toString(),
      dieBarcode: json['dieBarcode']?.toString(),
      parents: codes(json['parents']),
      children: codes(json['children']),
      orderBarcode: json['orderBarcode']?.toString(),
      documentBarcode: json['documentBarcode']?.toString(),
      metrics: json['metrics'] is Map
          ? Map<String, dynamic>.from(json['metrics'] as Map)
          : const <String, dynamic>{},
      notes: json['notes']?.toString() ?? '',
    );
  }

  final String eventId;

  /// INWARD_RECEIVED, ISSUED_TO_PIPELINE, DISPATCH_PACKED and the rest. Kept as
  /// the raw string rather than an enum: a workshop will record an event this
  /// build has never heard of, and showing it verbatim is better than dropping
  /// it because it did not parse.
  final String eventType;
  final String at;
  final String actor;
  final String? actorBarcode;
  final String? locationBarcode;
  final String? machineBarcode;
  final String? dieBarcode;

  /// What was consumed, and what came out. This is the genealogy: following
  /// parents walks back towards the vendor, children forward towards a client.
  final List<String> parents;
  final List<String> children;

  final String? orderBarcode;
  final String? documentBarcode;
  final Map<String, dynamic> metrics;
  final String notes;

  /// The event name in words, for a screen. Unknown types fall back to a
  /// readable form of the raw string rather than to "Unknown".
  String get label => switch (eventType) {
    'GENESIS_PURCHASE' => 'Purchased',
    'INWARD_RECEIVED' => 'Received',
    'LOCATION_MOVED' => 'Moved',
    'ISSUED_TO_PIPELINE' => 'Issued to production',
    'STAGE_PROCESSED' => 'Processed',
    'OUTPUT_MINTED' => 'Output produced',
    'DISPATCH_PACKED' => 'Packed for dispatch',
    'CLIENT_DELIVERED' => 'Delivered',
    'CUSTOMER_RETURN' => 'Returned by client',
    'INVOICED' => 'Invoiced',
    _ => eventType
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase()),
  };

  /// Every other barcode this event mentions — what the trail can be walked to
  /// from here.
  List<String> get relatedBarcodes => <String>[
    ...parents,
    ...children,
    if (orderBarcode != null) orderBarcode!,
    if (documentBarcode != null) documentBarcode!,
    if (machineBarcode != null) machineBarcode!,
    if (dieBarcode != null) dieBarcode!,
    if (actorBarcode != null) actorBarcode!,
  ];
}

/// A labelled value on the entity's summary.
@immutable
class BarcodeFact {
  const BarcodeFact({required this.label, required this.value});

  factory BarcodeFact.fromJson(Map<String, dynamic> json) => BarcodeFact(
    label: json['label']?.toString() ?? '',
    value: json['value']?.toString() ?? '',
  );

  final String label;
  final String value;
}

/// Everything one scan yields.
///
/// One shape whatever was scanned — a sheet, a challan, a machine, a person —
/// so a single screen renders all of them and a scanner gun does not have to
/// know what it is pointed at.
@immutable
class UniversalBarcodeEntity {
  const UniversalBarcodeEntity({
    required this.code,
    required this.found,
    required this.resolution,
    this.entity,
    this.facts = const <BarcodeFact>[],
    this.custody = const <CustodyEvent>[],
  });

  factory UniversalBarcodeEntity.fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) build) {
      final raw = json[key];
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((row) => build(row.cast<String, dynamic>()))
          .toList(growable: false);
    }

    return UniversalBarcodeEntity(
      code: json['code']?.toString() ?? '',
      found: json['found'] == true,
      resolution: BarcodeResolution.fromJson(
        (json['resolution'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      entity: json['entity'] is Map
          ? BarcodeEntity.fromJson(
              (json['entity'] as Map).cast<String, dynamic>(),
            )
          : null,
      facts: listOf('facts', BarcodeFact.fromJson),
      custody: listOf('custody', CustodyEvent.fromJson),
    );
  }

  final String code;
  final bool found;
  final BarcodeResolution resolution;
  final BarcodeEntity? entity;
  final List<BarcodeFact> facts;

  /// Oldest first. A custody trail read out of order is not a trail.
  final List<CustodyEvent> custody;

  /// What went into this, gathered from the whole trail.
  List<String> get upstream => <String>{
    for (final event in custody) ...event.parents,
  }.toList(growable: false);

  /// What came out of it.
  List<String> get downstream => <String>{
    for (final event in custody) ...event.children,
  }.toList(growable: false);

  /// What to tell someone when nothing resolved.
  ///
  /// The distinction the old lookup could not draw. "Not found" for a code of
  /// ours means a deleted record or another workspace; for a foreign label it
  /// means this is not our sticker at all. Same words for both is what made
  /// scanning a sheet you were holding indistinguishable from scanning
  /// gibberish.
  String get notFoundMessage {
    if (resolution.looksLikeOurs) {
      return 'This is one of ours, but nothing here carries it. '
          'It may belong to another workspace, or the record may have been '
          'deleted.';
    }
    return 'No record carries this code. It may be a supplier\'s own label '
        'rather than one of ours.';
  }
}
