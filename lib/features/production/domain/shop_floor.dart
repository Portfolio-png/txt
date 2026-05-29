class ShopFloor {
  const ShopFloor({
    required this.id,
    required this.factoryId,
    required this.name,
    required this.code,
    this.createdAt,
  });

  final String id;
  final String factoryId;
  final String name;
  final String code;
  final DateTime? createdAt;

  factory ShopFloor.fromJson(Map<String, dynamic> json) {
    return ShopFloor(
      id: json['id'] as String? ?? '',
      factoryId: json['factory_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'factory_id': factoryId,
      'name': name,
      'code': code,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  ShopFloor copyWith({
    String? id,
    String? factoryId,
    String? name,
    String? code,
    DateTime? createdAt,
  }) {
    return ShopFloor(
      id: id ?? this.id,
      factoryId: factoryId ?? this.factoryId,
      name: name ?? this.name,
      code: code ?? this.code,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
