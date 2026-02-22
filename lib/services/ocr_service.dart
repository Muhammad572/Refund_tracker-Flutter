// import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
//
// class OcrService {
//   final TextRecognizer _textRecognizer = TextRecognizer();
//
//   Future<Map<String, dynamic>> parseReceipt(InputImage inputImage) async {
//     final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
//
//     String extractedMerchant = "";
//     double highestAmount = 0.0;
//     double totalConfidence = 0.0;
//     int lineCount = 0;
//
//     if (recognizedText.blocks.isNotEmpty) {
//       extractedMerchant = recognizedText.blocks.first.text.split('\n').first;
//     }
//
//     RegExp priceRegex = RegExp(r"(\d+[\.,]\d{2})");
//
//     // Improved Date Regex to handle spaces often added by OCR
//     RegExp dateRegex = RegExp(r"(\d{1,2}\s?[/\-.]\s?\d{1,2}\s?[/\-.]\s?\d{2,4})");
//
//     DateTime? receiptDate;
//     DateTime? dueDate;
//
//     for (TextBlock block in recognizedText.blocks) {
//       for (TextLine line in block.lines) {
//         String lineText = line.text.toUpperCase();
//
//         totalConfidence += line.confidence ?? 0.0;
//         lineCount++;
//
//         // --- NEW KEYWORD LOGIC FOR EXACT DATES ---
//         if (lineText.contains("RECEIPT DATE") || lineText.contains("DATE")) {
//           receiptDate = _extractDateFromString(lineText, dateRegex);
//         } else if (lineText.contains("DUE DATE") || lineText.contains("DUE")) {
//           dueDate = _extractDateFromString(lineText, dateRegex);
//         }
//
//         Iterable<RegExpMatch> priceMatches = priceRegex.allMatches(lineText);
//         for (var match in priceMatches) {
//           double? val = double.tryParse(match.group(0)!.replaceAll(',', '.'));
//           if (val != null && val > highestAmount) {
//             highestAmount = val;
//           }
//         }
//       }
//     }
//
//     // Fallback if keywords weren't on the same line as the date
//     if (receiptDate == null || dueDate == null) {
//       List<DateTime> allDates = _extractAllDates(recognizedText.text, dateRegex);
//       if (receiptDate == null && allDates.isNotEmpty) receiptDate = allDates[0];
//       if (dueDate == null && allDates.length > 1) dueDate = allDates[1];
//     }
//
//     return {
//       'merchant': extractedMerchant,
//       'amount': highestAmount,
//       'fullText': recognizedText.text,
//       'extractedDate': receiptDate, // Purchase Date
//       'dueDate': dueDate,           // Due Date
//       'isReliable': lineCount > 0 && (totalConfidence / lineCount) > 0.7,
//     };
//   }
//
//   // Helper to parse date from a specific line of text
//   DateTime? _extractDateFromString(String text, RegExp reg) {
//     final match = reg.firstMatch(text.replaceAll(' ', ''));
//     if (match != null) {
//       return _parseDateString(match.group(0)!);
//     }
//     return null;
//   }
//
//   // Helper to find all dates in the whole receipt
//   List<DateTime> _extractAllDates(String text, RegExp reg) {
//     String cleanText = text.replaceAll(' ', '');
//     return reg.allMatches(cleanText)
//         .map((m) => _parseDateString(m.group(0)!))
//         .whereType<DateTime>()
//         .toList();
//   }
//
//   DateTime? _parseDateString(String dateStr) {
//     try {
//       String clean = dateStr.replaceAll('.', '/').replaceAll('-', '/');
//       List<String> parts = clean.split('/');
//       int day = int.parse(parts[0]);
//       int month = int.parse(parts[1]);
//       int year = int.parse(parts[2]);
//       if (year < 100) year += 2000;
//       return DateTime(year, month, day);
//     } catch (_) { return null; }
//   }
//
//   // --- KEPT WORD FOR WORD FROM YOUR ORIGINAL CODE ---
//   DateTime? extractBestDate(String text) {
//     RegExp dateRegex = RegExp(r"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})");
//     Iterable<RegExpMatch> matches = dateRegex.allMatches(text);
//     for (var match in matches) {
//       String dateStr = match.group(0)!;
//       try {
//         dateStr = dateStr.replaceAll('-', '/');
//         List<String> parts = dateStr.split('/');
//         int day = int.parse(parts[0]);
//         int month = int.parse(parts[1]);
//         int year = int.parse(parts[2]);
//         if (year < 100) year += 2000;
//         return DateTime(year, month, day);
//       } catch (_) { continue; }
//     }
//     return null;
//   }
//
//   void dispose() {
//     _textRecognizer.close();
//   }
// }


import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  // Keyword constants from your Swift code
  static const merchantBlacklist = ["receipt", "bill to", "ship to", "total", "amount", "tax", "qty", "description"];
  static const purchaseKeywords = ["receipt date", "order date", "purchase date", "purchased on", "order placed", "date"];
  static const dueKeywords = ["due date", "return by", "return until", "refund by", "return before"];
  static const totalKeywords = ["total", "amount due", "balance due", "grand total", "total charged"];
  static const ignoreAmountKeywords = ["tax", "%", "tip", "subtotal"];

  Future<Map<String, dynamic>> parseReceipt(InputImage inputImage) async {
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    // Convert ML Kit blocks into a flat list of lines (like Swift's observations mapping)
    List<String> lines = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        lines.add(line.text);
      }
    }

    // 1. Detect Merchant (Prefix 6 lines logic)
    String merchant = _detectMerchant(lines);

    // 2. Detect Dates (Contextual logic)
    final dateResult = _detectDates(lines);

    // 3. Detect Amount
    double amount = _detectAmount(lines);

    // 4. Calculate Deadline
    DateTime? purchaseDate = dateResult['purchase'];
    DateTime? deadline = dateResult['due'] ?? (purchaseDate != null ? purchaseDate.add(const Duration(days: 30)) : null);

    return {
      'merchant': merchant,
      'amount': amount,
      'purchaseDate': purchaseDate ?? DateTime.now(),
      'deadline': deadline ?? DateTime.now().add(const Duration(days: 30)),
      'fullText': recognizedText.text,
    };
  }

  String _detectMerchant(List<String> lines) {
    // lines.prefix(6) logic from Swift
    int limit = lines.length < 6 ? lines.length : 6;
    for (int i = 0; i < limit; i++) {
      String line = lines[i];
      String lower = line.toLowerCase();

      bool isBlacklisted = merchantBlacklist.any((k) => lower.contains(k));
      if (isBlacklisted) continue;

      if (line.length >= 4) return line;
    }
    return "Unknown Store";
  }

  Map<String, DateTime?> _detectDates(List<String> lines) {
    DateTime? purchase;
    DateTime? due;

    // Regex for finding dates within strings
    RegExp dateRegExp = RegExp(r"(\d{1,2}[\s/\-.]+\d{1,2}[\s/\-.]+\d{2,4})");

    List<Map<String, dynamic>> foundDates = [];

    // 1️⃣ Collect all dates and their line indices
    for (int i = 0; i < lines.length; i++) {
      var match = dateRegExp.firstMatch(lines[i]);
      if (match != null) {
        DateTime? parsed = _parseDate(match.group(0)!);
        if (parsed != null) {
          foundDates.add({'index': i, 'date': parsed});
        }
      }
    }

    // 2️⃣ Backward context scan (The Swift "Stride" logic)
    for (var item in foundDates) {
      int dateIndex = item['index'];

      // Look back up to 3 lines for keywords
      int startLookback = dateIndex - 1;
      int endLookback = (dateIndex - 3) < 0 ? 0 : (dateIndex - 3);

      for (int b = startLookback; b >= endLookback; b--) {
        String context = lines[b].toLowerCase();

        if (purchase == null && purchaseKeywords.any((k) => context.contains(k))) {
          purchase = item['date'];
          break;
        }
        if (due == null && dueKeywords.any((k) => context.contains(k))) {
          due = item['date'];
          break;
        }
      }
    }

    // 3️⃣ Fallbacks
    if (purchase == null && foundDates.isNotEmpty) {
      purchase = foundDates.first['date'];
    }
    if (due == null && foundDates.length >= 2) {
      due = foundDates.last['date'];
    }

    return {'purchase': purchase, 'due': due};
  }

  double _detectAmount(List<String> lines) {
    RegExp moneyRegExp = RegExp(r"([0-9]+(\.[0-9]{2}))");

    // 1️⃣ Strong signal: TOTAL keywords
    for (String line in lines) {
      String lower = line.toLowerCase();
      if (totalKeywords.any((k) => lower.contains(k)) &&
          !ignoreAmountKeywords.any((k) => lower.contains(k))) {

        var match = moneyRegExp.firstMatch(line);
        if (match != null) {
          return double.tryParse(match.group(1)!) ?? 0.0;
        }
      }
    }

    // 2️⃣ Fallback: Largest monetary value
    List<double> values = [];
    for (String line in lines) {
      var match = moneyRegExp.firstMatch(line);
      if (match != null) {
        values.add(double.tryParse(match.group(1)!) ?? 0.0);
      }
    }

    return values.isNotEmpty ? values.reduce((a, b) => a > b ? a : b) : 0.0;
  }

  DateTime? _parseDate(String input) {
    try {
      String clean = input.replaceAll(RegExp(r'[.\-\s]'), '/');
      List<String> parts = clean.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 3) {
        int d = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        int y = int.parse(parts[2]);
        if (y < 100) y += 2000;
        return DateTime(y, m, d);
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }
}