/// One person at a company — a client today; the backend table is generic
/// over vendors and die makers too (migrations/056-party-contacts.sql).
///
/// A company has as many of these as it has people, and a part's deal may
/// name any number of them. One may be [isPrimary], the person to ring first;
/// the client's flat contact fields mirror that one.
class PartyContact {
  const PartyContact({
    this.id,
    this.partyType = 'client',
    this.partyId,
    required this.name,
    this.designation = '',
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.isPrimary = false,
    this.isArchived = false,
  });

  /// Null until saved.
  final int? id;
  final String partyType;
  final int? partyId;
  final String name;
  final String designation;
  final String phone;
  final String email;
  final String notes;
  final bool isPrimary;

  /// Archived, not deleted: a part dealt with someone who has since left
  /// still records who it was.
  final bool isArchived;

  factory PartyContact.fromJson(Map<String, dynamic> json) {
    return PartyContact(
      id: (json['id'] as num?)?.toInt(),
      partyType: json['partyType'] as String? ?? 'client',
      partyId: (json['partyId'] as num?)?.toInt(),
      name: json['name'] as String? ?? '',
      designation: json['designation'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      isPrimary: json['isPrimary'] == true,
      isArchived: json['isArchived'] == true,
    );
  }

  /// What a create or an update sends. Identity and flags travel separately
  /// (the URL, and an explicit `isPrimary`/`isArchived` when meant).
  Map<String, dynamic> toJson() => {
        'name': name,
        'designation': designation,
        'phone': phone,
        'email': email,
        'notes': notes,
      };

  PartyContact copyWith({
    int? id,
    String? partyType,
    int? partyId,
    String? name,
    String? designation,
    String? phone,
    String? email,
    String? notes,
    bool? isPrimary,
    bool? isArchived,
  }) {
    return PartyContact(
      id: id ?? this.id,
      partyType: partyType ?? this.partyType,
      partyId: partyId ?? this.partyId,
      name: name ?? this.name,
      designation: designation ?? this.designation,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      isPrimary: isPrimary ?? this.isPrimary,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PartyContact &&
      other.id == id &&
      other.partyType == partyType &&
      other.partyId == partyId &&
      other.name == name &&
      other.designation == designation &&
      other.phone == phone &&
      other.email == email &&
      other.notes == notes &&
      other.isPrimary == isPrimary &&
      other.isArchived == isArchived;

  @override
  int get hashCode => Object.hash(id, partyType, partyId, name, designation,
      phone, email, notes, isPrimary, isArchived);
}
