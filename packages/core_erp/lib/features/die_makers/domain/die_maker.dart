import 'package:flutter/foundation.dart';

/// Who made a die.
///
/// A fourth party master beside clients, vendors and sub-contractors, with the
/// client form's fields because that is what the shop asked to fill in. Only
/// [name] is required: an outside toolroom is a company you invoice and has a
/// GST number and an address, while a fitter on the floor has neither, and
/// both have to fit in here.
///
/// Migration 048 made `dies.made_by` free text and argued the master would be
/// "wrong half the time" for exactly that reason. The answer is not to refuse
/// the master but to let most of it go unanswered — and to keep the free text
/// beside the id, so a die that names a person who was never a record still
/// reads back as that name.
@immutable
class DieMaker {
  const DieMaker({
    required this.id,
    required this.name,
    this.alias = '',
    this.gstNumber = '',
    this.address = '',
    this.contactName = '',
    this.designation = '',
    this.phone = '',
    this.email = '',
    this.logoUrl = '',
    this.photoUrl = '',
    this.isArchived = false,
    this.usageCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String alias;
  final String gstNumber;
  final String address;
  final String contactName;
  final String designation;
  final String phone;
  final String email;
  final String logoUrl;
  final String photoUrl;
  final bool isArchived;

  /// How many dies name this maker. What makes a delete safe to offer: a maker
  /// nothing points at can go, one that is on forty dies is archived.
  final int usageCount;

  final String? createdAt;
  final String? updatedAt;

  bool get hasContact => contactName.trim().isNotEmpty;

  /// What a picker shows. The alias is how a shop actually refers to a
  /// toolroom, so it rides along when there is one.
  String get displayLabel =>
      alias.trim().isEmpty ? name : '$name (${alias.trim()})';

  /// The second line in a picker — whoever you ring, else where they are.
  String get pickerSubtitle {
    if (hasContact) {
      final role = designation.trim();
      return role.isEmpty ? contactName : '$contactName · $role';
    }
    if (address.trim().isNotEmpty) return address.trim();
    return '';
  }

  /// Everything a search should match, not just the name.
  String get searchText =>
      [name, alias, gstNumber, contactName, phone, email]
          .where((part) => part.trim().isNotEmpty)
          .join(' ');

  factory DieMaker.fromJson(Map<String, dynamic> json) => DieMaker(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        alias: json['alias'] as String? ?? '',
        gstNumber: json['gstNumber'] as String? ?? '',
        address: json['address'] as String? ?? '',
        contactName: json['contactName'] as String? ?? '',
        designation: json['designation'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        logoUrl: json['logoUrl'] as String? ?? '',
        photoUrl: json['photoUrl'] as String? ?? '',
        isArchived: json['isArchived'] == true,
        usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String?,
        updatedAt: json['updatedAt'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DieMaker && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// What a save sends.
///
/// Absent means leave alone and present-and-empty means clear, which is why
/// these are nullable rather than defaulted — the editor is opened pre-filled
/// from a picker and most fields are never touched.
@immutable
class DieMakerInput {
  const DieMakerInput({
    this.id,
    this.name,
    this.alias,
    this.gstNumber,
    this.address,
    this.contactName,
    this.designation,
    this.phone,
    this.email,
    this.logoUrl,
    this.photoUrl,
    this.isArchived,
  });

  final int? id;
  final String? name;
  final String? alias;
  final String? gstNumber;
  final String? address;
  final String? contactName;
  final String? designation;
  final String? phone;
  final String? email;
  final String? logoUrl;
  final String? photoUrl;

  /// Null leaves it as it is; false brings an archived maker back.
  final bool? isArchived;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (isArchived != null) 'isArchived': isArchived,
        if (name != null) 'name': name,
        if (alias != null) 'alias': alias,
        if (gstNumber != null) 'gstNumber': gstNumber,
        if (address != null) 'address': address,
        if (contactName != null) 'contactName': contactName,
        if (designation != null) 'designation': designation,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (photoUrl != null) 'photoUrl': photoUrl,
      };
}

/// A save the server refused, with the reason a screen can act on.
class DieMakerException implements Exception {
  DieMakerException(this.message, {this.code, this.existingId});

  final String message;
  final String? code;

  /// On `die_maker_duplicate`, who already holds the name — so a picker can
  /// select that one instead of making a second.
  final int? existingId;

  bool get isDuplicate => code == 'die_maker_duplicate';

  @override
  String toString() => message;
}
