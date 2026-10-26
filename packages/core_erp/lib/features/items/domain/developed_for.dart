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
///
/// Since migration 056 a company holds many people and the part ticks which of
/// them the deal involved: [contactIds] is stored by the part, [contacts] is
/// those people as read back.
library;

import '../../clients/domain/party_contact.dart';

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
    this.contactIds,
    this.contacts = const [],
    this.companyName = '',
    this.contactName = '',
    this.designation = '',
    this.phone = '',
    this.email = '',
    this.at,
    this.quotationAmount,
    this.costAmount,
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

  /// WHICH of the company's people this deal was done with — any number.
  ///
  /// A deal happens with whoever picks up the phone, and more than one person
  /// may have been involved, so the part ticks them. **Null says nothing**:
  /// the save leaves whatever is ticked alone (the wizard and item editor,
  /// which never show people, rely on that). An empty list clears.
  ///
  /// Always empty for a contractor or self — a sub-contractor IS the person,
  /// and in-house work had no customer to speak to. The backend refuses a
  /// tick on either.
  ///
  /// The quotation is NOT per contact. A part is quoted once however many
  /// people were spoken to.
  final List<int>? contactIds;

  /// The ticked people as read back, primary first. Read-only, like the
  /// resolved fields below — writing goes through [contactIds].
  final List<PartyContact> contacts;

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
  ///
  /// What was quoted for MAKING THIS PART'S DIES — the development job, not a
  /// price per piece and not the value of a production run.
  final double? quotationAmount;

  /// Rupees. What that die making cost us — the counterpart to
  /// [quotationAmount], and the other half of the only question anybody asks
  /// of a quotation.
  ///
  /// Null means never costed. That is emphatically not zero: a margin reading
  /// zero cost would show 100% on every part nobody has priced yet, which is
  /// the most dangerous possible default for a figure somebody might quote
  /// against. [hasMargin] is the guard.
  final double? costAmount;

  /// Whether a margin can honestly be shown: both halves present, and a
  /// quotation above zero to divide by.
  bool get hasMargin =>
      quotationAmount != null && costAmount != null && quotationAmount! > 0;

  /// The development margin as a percentage, or null when it cannot be known.
  ///
  /// Null rather than 0 on purpose — "we do not know" and "we broke even" are
  /// different answers and must not render alike.
  double? get marginPercent => hasMargin
      ? ((quotationAmount! - costAmount!) / quotationAmount!) * 100
      : null;

  /// Nothing has been recorded. A block with only a date in it is not empty:
  /// someone opened the form and put something in.
  bool get isEmpty =>
      kind == DevelopedForKind.none &&
      clientId == null &&
      subContractorId == null &&
      at == null &&
      quotationAmount == null &&
      costAmount == null;

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
    double? costAmount,
    bool clearCostAmount = false,
    List<int>? contactIds,
    bool clearContactIds = false,
  }) {
    // Moving the part to another company retires the old company's people:
    // they would be strangers at the new one, and the backend refuses that.
    final clientMoved =
        clearClientId || (clientId != null && clientId != this.clientId);
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
      costAmount: clearCostAmount ? null : (costAmount ?? this.costAmount),
      contactIds: clearContactIds
          ? null
          : contactIds ?? (clientMoved ? null : this.contactIds),
      contacts: clientMoved && contactIds == null ? const [] : this.contacts,
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
          contactIds: const [],
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
        // The contractor is the person; nobody at the company is ticked.
        return copyWith(kind: next, contactIds: const []);
    }
  }

  factory DevelopedFor.fromJson(Map<String, dynamic> json) {
    final rawAt = json['at'] as String?;
    final rawQuotation = json['quotationAmount'];
    final rawCost = json['costAmount'];
    return DevelopedFor(
      kind: DevelopedForKind.fromWire(json['kind'] as String?),
      clientId: json['clientId'] as int?,
      // Absent stays null — "unknown", which a save turns into "say nothing".
      // Reading it as [] would let a reply from an older server clear every
      // tick on the next save.
      contactIds: json['contactIds'] is List
          ? [
              for (final id in json['contactIds'] as List)
                (id as num).toInt(),
            ]
          : null,
      contacts: [
        for (final row in (json['contacts'] as List? ?? const []))
          PartyContact.fromJson(row as Map<String, dynamic>),
      ],
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
      costAmount: rawCost == null ? null : (rawCost as num).toDouble(),
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
        // Absent when null, so a save that never showed people keeps them.
        if (contactIds != null) 'contactIds': contactIds,
        'subContractorId': subContractorId,
        'at': at?.toUtc().toIso8601String(),
        'quotationAmount': quotationAmount,
        'costAmount': costAmount,
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
      other.quotationAmount == quotationAmount &&
      other.costAmount == costAmount &&
      _sameIds(other.contactIds, contactIds) &&
      _sameContacts(other.contacts, contacts);

  static bool _sameIds(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameContacts(List<PartyContact> a, List<PartyContact> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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
        costAmount,
        contactIds == null ? null : Object.hashAll(contactIds!),
        Object.hashAll(contacts),
      );
}
