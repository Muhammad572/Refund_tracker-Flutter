class Receipt {
  final String id;
  final String storeName;
  final double amount;
  final DateTime purchaseDate;
  final DateTime refundDeadline;
  final String imagePath;
  final String fullText;
  // --- NEW PHASE-2 FIELDS ---
  final String category;
  final String currency;
  final String? notes; // ADDED: To match your OCR screen logic

  Receipt({
    required this.id,
    required this.storeName,
    required this.amount,
    required this.purchaseDate,
    required this.refundDeadline,
    required this.imagePath,
    required this.fullText,
    this.category = "General",
    this.currency = "\$",
    this.notes, // ADDED: To store your notes
  });
  int get daysRemaining {
    final now = DateTime.now();
    final difference = refundDeadline.difference(DateTime(now.year, now.month, now.day));
    return difference.inDays;
  }
  // FIX: Added toMap to ensure notes and other fields are saved to the Database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeName': storeName,
      'amount': amount,
      'purchaseDate': purchaseDate.toIso8601String(),
      'refundDeadline': refundDeadline.toIso8601String(),
      'imagePath': imagePath,
      'fullText': fullText,
      'category': category,
      'currency': currency,
      'notes': notes,
    };
  }

  // FIX: Added fromMap to ensure notes are loaded back from the Database
  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      id: map['id'],
      storeName: map['storeName'],
      amount: map['amount'],
      purchaseDate: DateTime.parse(map['purchaseDate']),
      refundDeadline: DateTime.parse(map['refundDeadline']),
      imagePath: map['imagePath'],
      fullText: map['fullText'],
      category: map['category'] ?? "General",
      currency: map['currency'] ?? "\$",
      notes: map['notes'],
    );
  }
}

class Refund {
  final String id;
  String merchant;
  DateTime purchaseDate;
  DateTime returnDeadline;
  double amount;
  String? notes;
  String imagePath; // Local file path
  DateTime createdAt;
  // --- NEW PHASE-2 FIELDS ---
  String category;
  String currency;

  Refund({
    required this.id,
    required this.merchant,
    required this.purchaseDate,
    required this.returnDeadline,
    required this.amount,
    this.notes,
    required this.imagePath,
    required this.createdAt,
    this.category = "General",
    this.currency = "\$",
  });

  // Convert a Refund object into a Map for the Database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'merchant': merchant,
      'purchaseDate': purchaseDate.toIso8601String(),
      'returnDeadline': returnDeadline.toIso8601String(),
      'amount': amount,
      'notes': notes,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
      'category': category, // Added for Phase 2
      'currency': currency, // Added for Phase 2
    };
  }

  // Convert a Map from the Database back into a Refund object
  factory Refund.fromMap(Map<String, dynamic> map) {
    return Refund(
      id: map['id'],
      merchant: map['merchant'],
      purchaseDate: DateTime.parse(map['purchaseDate']),
      returnDeadline: DateTime.parse(map['returnDeadline']),
      amount: map['amount'],
      notes: map['notes'],
      imagePath: map['imagePath'],
      createdAt: DateTime.parse(map['createdAt']),
      category: map['category'] ?? "General", // Added for Phase 2
      currency: map['currency'] ?? "\$", // Added for Phase 2
    );
  }
}

class ProStatus {
  static bool isPro = false;
}

class Plan {
  final String id;
  final String title;
  final String displayPrice;

  const Plan({
    required this.id,
    required this.title,
    required this.displayPrice,
  });
}
