class FreelancerJob {
  const FreelancerJob({
    required this.id,
    required this.freelancerId,
    required this.itemId,
    required this.count,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int freelancerId;
  final int itemId;
  final int count;
  final String status;
  final DateTime createdAt;

  factory FreelancerJob.fromJson(Map<String, dynamic> json) {
    return FreelancerJob(
      id: json['id'] as int,
      freelancerId: json['freelancer_id'] as int,
      itemId: json['item_id'] as int,
      count: json['count'] as int,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'freelancer_id': freelancerId,
      'item_id': itemId,
      'count': count,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  FreelancerJob copyWith({
    int? id,
    int? freelancerId,
    int? itemId,
    int? count,
    String? status,
    DateTime? createdAt,
  }) {
    return FreelancerJob(
      id: id ?? this.id,
      freelancerId: freelancerId ?? this.freelancerId,
      itemId: itemId ?? this.itemId,
      count: count ?? this.count,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
