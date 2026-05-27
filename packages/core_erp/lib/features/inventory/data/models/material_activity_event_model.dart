import '../../domain/material_activity_event.dart';

class MaterialActivityEventModel {
  const MaterialActivityEventModel({
    required this.id,
    required this.barcode,
    required this.type,
    required this.label,
    required this.description,
    required this.actor,
    required this.createdAt,
  });

  final int? id;
  final String barcode;
  final String type;
  final String label;
  final String description;
  final String actor;
  final DateTime createdAt;

  factory MaterialActivityEventModel.fromMap(Map<String, Object?> map) {
    return MaterialActivityEventModel(
      id: map['id'] as int?,
      barcode: map['barcode'] as String? ?? '',
      type: map['event_type'] as String? ?? '',
      label: map['event_label'] as String? ?? '',
      description: map['event_description'] as String? ?? '',
      actor: map['actor'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'event_type': type,
      'event_label': label,
      'event_description': description,
      'actor': actor,
      'created_at': createdAt.toIso8601String(),
    };
  }

  MaterialActivityEvent toEvent() {
    return MaterialActivityEvent(
      id: id,
      barcode: barcode,
      type: type,
      label: label,
      description: description,
      actor: actor,
      createdAt: createdAt,
    );
  }
}
