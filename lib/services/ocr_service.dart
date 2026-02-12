import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  Future<Map<String, dynamic>> parseReceipt(InputImage inputImage) async {
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    String extractedMerchant = "";
    double highestAmount = 0.0;
    double totalConfidence = 0.0;
    int lineCount = 0;

    if (recognizedText.blocks.isNotEmpty) {
      extractedMerchant = recognizedText.blocks.first.text.split('\n').first;
    }

    RegExp priceRegex = RegExp(r"(\d+[\.,]\d{2})");

    // Improved Date Regex to handle spaces often added by OCR
    RegExp dateRegex = RegExp(r"(\d{1,2}\s?[/\-.]\s?\d{1,2}\s?[/\-.]\s?\d{2,4})");

    DateTime? receiptDate;
    DateTime? dueDate;

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        String lineText = line.text.toUpperCase();

        totalConfidence += line.confidence ?? 0.0;
        lineCount++;

        // --- NEW KEYWORD LOGIC FOR EXACT DATES ---
        if (lineText.contains("RECEIPT DATE") || lineText.contains("DATE")) {
          receiptDate = _extractDateFromString(lineText, dateRegex);
        } else if (lineText.contains("DUE DATE") || lineText.contains("DUE")) {
          dueDate = _extractDateFromString(lineText, dateRegex);
        }

        Iterable<RegExpMatch> priceMatches = priceRegex.allMatches(lineText);
        for (var match in priceMatches) {
          double? val = double.tryParse(match.group(0)!.replaceAll(',', '.'));
          if (val != null && val > highestAmount) {
            highestAmount = val;
          }
        }
      }
    }

    // Fallback if keywords weren't on the same line as the date
    if (receiptDate == null || dueDate == null) {
      List<DateTime> allDates = _extractAllDates(recognizedText.text, dateRegex);
      if (receiptDate == null && allDates.isNotEmpty) receiptDate = allDates[0];
      if (dueDate == null && allDates.length > 1) dueDate = allDates[1];
    }

    return {
      'merchant': extractedMerchant,
      'amount': highestAmount,
      'fullText': recognizedText.text,
      'extractedDate': receiptDate, // Purchase Date
      'dueDate': dueDate,           // Due Date
      'isReliable': lineCount > 0 && (totalConfidence / lineCount) > 0.7,
    };
  }

  // Helper to parse date from a specific line of text
  DateTime? _extractDateFromString(String text, RegExp reg) {
    final match = reg.firstMatch(text.replaceAll(' ', ''));
    if (match != null) {
      return _parseDateString(match.group(0)!);
    }
    return null;
  }

  // Helper to find all dates in the whole receipt
  List<DateTime> _extractAllDates(String text, RegExp reg) {
    String cleanText = text.replaceAll(' ', '');
    return reg.allMatches(cleanText)
        .map((m) => _parseDateString(m.group(0)!))
        .whereType<DateTime>()
        .toList();
  }

  DateTime? _parseDateString(String dateStr) {
    try {
      String clean = dateStr.replaceAll('.', '/').replaceAll('-', '/');
      List<String> parts = clean.split('/');
      int day = int.parse(parts[0]);
      int month = int.parse(parts[1]);
      int year = int.parse(parts[2]);
      if (year < 100) year += 2000;
      return DateTime(year, month, day);
    } catch (_) { return null; }
  }

  // --- KEPT WORD FOR WORD FROM YOUR ORIGINAL CODE ---
  DateTime? extractBestDate(String text) {
    RegExp dateRegex = RegExp(r"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})");
    Iterable<RegExpMatch> matches = dateRegex.allMatches(text);
    for (var match in matches) {
      String dateStr = match.group(0)!;
      try {
        dateStr = dateStr.replaceAll('-', '/');
        List<String> parts = dateStr.split('/');
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      } catch (_) { continue; }
    }
    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }
}