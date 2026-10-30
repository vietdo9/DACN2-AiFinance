class TransactionModel {
  final String id;
  final double amount;
  final String type; // 'expense' hoặc 'income'
  final String categoryCode;
  final String? categoryName;
  final String note;
  final DateTime transactionDate;
  final DateTime? createdAt;
  final bool aiPredicted;
  final double? aiConfidence;

  TransactionModel({
    required this.id,
    required this.amount,
    required this.type,
    required this.categoryCode,
    this.categoryName,
    required this.note,
    required this.transactionDate,
    this.createdAt,
    this.aiPredicted = false,
    this.aiConfidence,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] ?? 'expense',
      categoryCode: json['category_code'] ?? 'AN_UONG',
      categoryName: json['category_name'] ?? json['categories']?['name'],
      note: json['note'] ?? '',
      transactionDate: DateTime.tryParse(json['transaction_date']?.toString() ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      aiPredicted: json['ai_predicted'] == true,
      aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
    );
  }

  /// So sánh theo thứ tự thời gian chuẩn (Mới nhất lên đầu)
  int compareToTime(TransactionModel other) {
    // 1. So sánh ngày giao dịch (ngày mới hơn đứng trước)
    final cmpDate = other.transactionDate.compareTo(transactionDate);
    if (cmpDate != 0) return cmpDate;

    // 2. Nếu cùng ngày, so sánh giờ tạo (created_at mới hơn đứng trước)
    if (createdAt != null && other.createdAt != null) {
      final cmpTime = other.createdAt!.compareTo(createdAt!);
      if (cmpTime != 0) return cmpTime;
    }

    // 3. Fallback theo id
    return other.id.compareTo(id);
  }
}
