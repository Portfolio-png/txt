class DepartmentDefinition {
  final int id;
  final String name;
  final String description;
  final String photoUrl;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  const DepartmentDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.photoUrl = '',
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DepartmentDefinition.fromJson(Map<String, dynamic> json) {
    return DepartmentDefinition(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      photoUrl: json['photoUrl'] as String? ?? '',
      isArchived: json['isArchived'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'photoUrl': photoUrl,
      'isArchived': isArchived,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  DepartmentDefinition copyWith({
    int? id,
    String? name,
    String? description,
    String? photoUrl,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return DepartmentDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      photoUrl: photoUrl ?? this.photoUrl,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
