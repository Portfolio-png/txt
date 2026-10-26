import 'package:flutter/foundation.dart';

@immutable
class ColumnOption {
  const ColumnOption({
    required this.id,
    required this.columnId,
    this.parentOptionId,
    required this.label,
    this.isNew = false,
    this.createdAt,
    this.createdBy,
  });

  final int id;
  final int columnId;
  final int? parentOptionId;
  final String label;
  final bool isNew;
  final String? createdAt;
  final int? createdBy;

  ColumnOption copyWith({
    int? id,
    int? columnId,
    int? parentOptionId,
    String? label,
    bool? isNew,
    String? createdAt,
    int? createdBy,
  }) {
    return ColumnOption(
      id: id ?? this.id,
      columnId: columnId ?? this.columnId,
      parentOptionId: parentOptionId ?? this.parentOptionId,
      label: label ?? this.label,
      isNew: isNew ?? this.isNew,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColumnOption &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          columnId == other.columnId &&
          parentOptionId == other.parentOptionId &&
          label.toLowerCase() == other.label.toLowerCase();

  @override
  int get hashCode => Object.hash(id, columnId, parentOptionId, label.toLowerCase());
}

@immutable
class Party {
  const Party({
    required this.id,
    required this.name,
    required this.type,
    this.gstin,
  });

  final int id;
  final String name;
  final String type; // 'client', 'vendor', 'contractor'
  final String? gstin;
}

@immutable
class Contact {
  const Contact({
    required this.id,
    required this.partyId,
    required this.name,
    this.designationOptionId,
    this.designation,
    this.phone,
    this.email,
  });

  final int id;
  final int partyId;
  final String name;
  final int? designationOptionId;
  final String? designation;
  final String? phone;
  final String? email;
}
