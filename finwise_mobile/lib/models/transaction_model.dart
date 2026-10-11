class TransactionModel {
  final String id;
  final double amount;
  final String type; // 'expense' hoặc 'income'
  final String categoryCode;
  final String? categoryName;
  final String note;
  final DateTime transactionDate;
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
      aiPredicted: json['ai_predicted'] == true,
      aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
    );
  }
}
