/// Who a part was developed for, when, and what was quoted.
///
/// One value object rather than nine loose fields, because nine would have to
/// cross [ItemDefinition], two inputs, four request/DTO classes and three
/// screens — which is exactly how the single `developedForClientId` it replaces
/// reached twelve call sites and still showed up nowhere but one chip.
///
/// The split between what the PART stores and what is READ FROM THE PARTY is
/// the point of the design:
///
/// * the part stores [kind], the party ids, [at] and [quotationAmount];
/// * [companyName], [contactName], [designation], [phone] and [email] are
///   resolved server-side from the client (or the contractor) on every read.
///
/// So correcting a phone number is one edit in the client editor, not an edit
/// per part — and a part developed for a contractor still names the company,
/// because the backend derives the contractor's parent client.
library;

/// Who the part was made for. [none] is not [self]: "developed in-house" is a
/// fact someone recorded, and "nobody has said yet" is the absence of one. No
/// combination of party ids can tell those apart, which is why the backend
/// stores the kind as its own column.
enum DevelopedForKind {
  none(''),
  self('self'),
  client('client'),
  contractor('contractor');

  const DevelopedForKind(this.wire);

  /// The string the `items.developed_for_kind` column holds.
  final String wire;

  static DevelopedForKind fromWire(String? value) {
    final raw = (value ?? '').trim();
    for (final kind in DevelopedForKind.values) {
      if (kind.wire == raw) return kind;
    }
    // An unknown kind reads as "nobody has said" rather than throwing: a client
    // one version behind the server must still be able to open the part.
    return DevelopedForKind.none;
  }

  String get label => switch (this) {
        DevelopedForKind.none => 'Not recorded',
        DevelopedForKind.self => 'Self (in-house)',
        DevelopedForKind.client => 'Client',
        DevelopedForKind.contractor => 'Contractor',
      };
}

class DevelopedFor {
  const DevelopedFor({
    this.kind = DevelopedForKind.none,
    this.clientId,
    this.clientName = '',
    this.subContractorId,
    this.subContractorName = '',
    this.companyName = '',
    this.contactName = '',
    this.designation = '',
    this.phone = '',
    this.email = '',
    this.at,
    this.quotationAmount,
  });

  static const DevelopedFor empty = DevelopedFor();

  final DevelopedForKind kind;

  /// The company. Set for [DevelopedForKind.contractor] too — the backend
  /// derives the contractor's parent client, so "parts for this client"
  /// includes work routed through their contractors.
  final int? clientId;
  final String clientName;

  final int? subContractorId;
  final String subContractorName;

  // --- read-only, resolved from the party on every read ---------------------
  final String companyName;
  final String contactName;
  final String designation;
  final String phone;
  final String email;

  /// When the part was developed for them — the occurrence time, as against
  /// `createdAt`, which is when the row was typed in. Parsed from a full ISO
  /// instant; always render it through `partStamp`, never by reading `.day`.
  final DateTime? at;

  /// Rupees. Null means never quoted, which is not the same as quoted at zero.
  final double? quotationAmount;

  /// Nothing has been recorded. A block with only a date in it is not empty:
  /// someone opened the form and put something in.
  bool get isEmpty =>
      kind == DevelopedForKind.none &&
      clientId == null &&
      subContractorId == null &&
      at == null &&
      quotationAmount == null;

  bool get isNotEmpty => !isEmpty;

  /// Whether a party still has to be picked for the kind that is selected.
  /// The form refuses to save while this is true, and so does the backend.
  bool get needsParty =>
      (kind == DevelopedForKind.client && clientId == null) ||
      (kind == DevelopedForKind.contractor && subContractorId == null);

  /// Who you actually deal with, for a one-line summary. Empty for self.
  String get partyName => switch (kind) {
        DevelopedForKind.contractor =>
          subContractorName.isNotEmpty ? subContractorName : companyName,
        DevelopedForKind.client => companyName.isNotEmpty ? companyName : clientName,
        _ => '',
      };

  DevelopedFor copyWith({
    DevelopedForKind? kind,
    int? clientId,
    bool clearClientId = false,
    String? clientName,
    int? subContractorId,
    bool clearSubContractorId = false,
    String? subContractorName,
    String? companyName,
    String? contactName,
    String? designation,
    String? phone,
    String? email,
    DateTime? at,
    bool clearAt = false,
    double? quotationAmount,
    bool clearQuotationAmount = false,
  }) {
    return DevelopedFor(
      kind: kind ?? this.kind,
      // Explicit clear flags, because every nullable field here has a null that
      // means something — `copyWith(clientId: null)` cannot say "remove it".
      clientId: clearClientId ? null : (clientId ?? this.clientId),
      clientName: clientName ?? this.clientName,
      subContractorId:
          clearSubContractorId ? null : (subContractorId ?? this.subContractorId),
      subContractorName: subContractorName ?? this.subContractorName,
      companyName: companyName ?? this.companyName,
      contactName: contactName ?? this.contactName,
      designation: designation ?? this.designation,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      at: clearAt ? null : (at ?? this.at),
      quotationAmount:
          clearQuotationAmount ? null : (quotationAmount ?? this.quotationAmount),
    );
  }

  /// The kind switched, with the party that no longer applies dropped.
  ///
  /// Selecting Self must not leave a client id behind for the save to send:
  /// the backend would null it anyway, and a form that disagrees with what it
  /// is about to write is a form that lies to the person filling it in.
  DevelopedFor withKind(DevelopedForKind next) {
    switch (next) {
      case DevelopedForKind.none:
      case DevelopedForKind.self:
        return copyWith(
          kind: next,
          clearClientId: true,
          clientName: '',
          clearSubContractorId: true,
          subContractorName: '',
          companyName: '',
          contactName: '',
          designation: '',
          phone: '',
          email: '',
        );
      case DevelopedForKind.client:
        // A contractor's parent client is a real answer to "which company", so
        // switching from contractor to client keeps it and only drops the
        // person.
        return copyWith(
          kind: next,
          clearSubContractorId: true,
          subContractorName: '',
        );
      case DevelopedForKind.contractor:
        return copyWith(kind: next);
    }
  }

  factory DevelopedFor.fromJson(Map<String, dynamic> json) {
    final rawAt = json['at'] as String?;
    final rawQuotation = json['quotationAmount'];
    return DevelopedFor(
      kind: DevelopedForKind.fromWire(json['kind'] as String?),
      clientId: json['clientId'] as int?,
      clientName: json['clientName'] as String? ?? '',
      subContractorId: json['subContractorId'] as int?,
      subContractorName: json['subContractorName'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      contactName: json['contactName'] as String? ?? '',
      designation: json['designation'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      // Left null when unparseable rather than defaulted to now(): a fabricated
      // timestamp would be printed as if someone had entered it.
      at: (rawAt == null || rawAt.isEmpty) ? null : DateTime.tryParse(rawAt),
      quotationAmount: rawQuotation == null ? null : (rawQuotation as num).toDouble(),
    );
  }

  /// Only what the part stores. The resolved person is read-only — sending it
  /// back would invite the border to write a client's phone number from an
  /// item save.
  ///
  /// `at` goes out in UTC: the server stores a full ISO instant and the client
  /// is the only thing that knows the local offset.
  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'clientId': clientId,
        'subContractorId': subContractorId,
        'at': at?.toUtc().toIso8601String(),
        'quotationAmount': quotationAmount,
      };

  @override
  bool operator ==(Object other) =>
      other is DevelopedFor &&
      other.kind == kind &&
      other.clientId == clientId &&
      other.clientName == clientName &&
      other.subContractorId == subContractorId &&
      other.subContractorName == subContractorName &&
      other.companyName == companyName &&
      other.contactName == contactName &&
      other.designation == designation &&
      other.phone == phone &&
      other.email == email &&
      other.at == at &&
      other.quotationAmount == quotationAmount;

  @override
  int get hashCode => Object.hash(
        kind,
        clientId,
        clientName,
        subContractorId,
        subContractorName,
        companyName,
        contactName,
        designation,
        phone,
        email,
        at,
        quotationAmount,
      );
}
