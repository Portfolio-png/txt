class ScanEventModel {
  const ScanEventModel({
    this.id,
    required this.barcode,
    required this.scannedAt,
  });

  final int? id;
  final String barcode;
  final DateTime scannedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'scanned_at': scannedAt.toIso8601String(),
    };
  }
}
