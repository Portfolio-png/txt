class FreelancerJobBatch {
  const FreelancerJobBatch({
    required this.id,
    this.freelancerId,
    required this.batchNumber,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int? freelancerId;
  final String batchNumber;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory FreelancerJobBatch.fromJson(Map<String, dynamic> json) {
    return FreelancerJobBatch(
      id: json['id'] as int,
      freelancerId: json['freelancer_id'] as int?,
      batchNumber: json['batch_number'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class FreelancerJob {
  const FreelancerJob({
    required this.id,
    this.batchId,
    required this.itemId,
    required this.quantity,
    required this.status,
    required this.payoutBalance,
    required this.createdAt,
  });

  final int id;
  final int? batchId;
  final int itemId;
  final int quantity;
  final String status;
  final double payoutBalance;
  final DateTime createdAt;

  factory FreelancerJob.fromJson(Map<String, dynamic> json) {
    return FreelancerJob(
      id: json['id'] as int,
      batchId: json['batch_id'] as int?,
      itemId: json['item_id'] as int,
      quantity: json['quantity'] as int,
      status: json['status'] as String,
      payoutBalance: (json['payout_balance'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  FreelancerJob copyWith({
    int? id,
    int? batchId,
    int? itemId,
    int? quantity,
    String? status,
    double? payoutBalance,
    DateTime? createdAt,
  }) {
    return FreelancerJob(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      status: status ?? this.status,
      payoutBalance: payoutBalance ?? this.payoutBalance,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class FreelancerJobTask {
  const FreelancerJobTask({
    required this.id,
    required this.jobId,
    required this.itemId,
    required this.requiredQuantity,
    required this.status,
  });

  final int id;
  final int jobId;
  final int itemId;
  final double requiredQuantity;
  final String status;

  factory FreelancerJobTask.fromJson(Map<String, dynamic> json) {
    return FreelancerJobTask(
      id: json['id'] as int,
      jobId: json['job_id'] as int,
      itemId: json['item_id'] as int,
      requiredQuantity: (json['required_quantity'] as num).toDouble(),
      status: json['status'] as String,
    );
  }
}
