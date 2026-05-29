class Factory {
  const Factory({
    required this.id,
    required this.name,
    required this.code,
    required this.location,
    this.createdAt,
  });

  final String id;
  final String name;
  final String code;
  final String location;
  final DateTime? createdAt;

  factory Factory.fromJson(Map<String, dynamic> json) {
    return Factory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      location: json['location'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'location': location,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  Factory copyWith({
    String? id,
    String? name,
    String? code,
    String? location,
    DateTime? createdAt,
  }) {
    return Factory(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
