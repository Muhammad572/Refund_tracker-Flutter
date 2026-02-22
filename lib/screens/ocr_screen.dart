import 'dart:io';
import 'dart:async'; // Added for StreamSubscription
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import 'package:device_calendar/device_calendar.dart';// Added for 10.1
import 'package:path_provider/path_provider.dart'; // Added for Step 7
import 'package:path/path.dart' as p; // Added for Step 7
import 'package:in_app_purchase/in_app_purchase.dart'; // Added for IAP
import 'package:shared_preferences/shared_preferences.dart'; // Added for Free Trial check
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/database_service.dart';
import '../models/receipt_model.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import 'onboarding_screen.dart'; // Added import to allow navigation back
import 'receipt_detail_screen.dart'; // Added for direct navigation
import 'refund_list_screen.dart'; // Added to ensure correct navigation after update
import 'package:timezone/timezone.dart' as tz;
import 'subscription_screen.dart';

class ParsedValue<T> {
  final T value;
  final double confidence;
  ParsedValue({required this.value, required this.confidence});
}

class OcrScreen extends StatefulWidget {
  final Receipt? existingReceipt;
  const OcrScreen({super.key, this.existingReceipt});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  File? _pickedImage;

  String _extractedText = "Scan a receipt to begin";
  bool _isDisposed = false;
  bool _hasOpenedCamera = false;

  // DateTime? _lastPressedAt;
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  DateTime _purchaseDate = DateTime.now();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 30));

  // --- FLAGS FOR MANUAL OVERRIDE ---
  bool _isDateManuallySet = false;
  bool _isOcrRunning = false;

  final ImagePicker _picker = ImagePicker();
  final OcrService _ocrService = OcrService();
  // --- 10.2 CATEGORY VARIABLES ---
  String _selectedCategory = "General";
  final List<String> _categories = ["General", "Electronics", "Clothing", "Groceries", "Dining", "Others"];

  final DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();

  // --- IAP VARIABLES ---
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;


  Future<void> _syncToCalendar({
    required String storeName,
    required double amount,
    required DateTime deadline,
  }) async {
    try {
      // Request permission
      final permissions = await _calendarPlugin.requestPermissions();

      if (!(permissions.isSuccess && permissions.data == true)) {
        debugPrint("Calendar permission denied");
        return;
      }

      // Get calendars
      final calendarsResult = await _calendarPlugin.retrieveCalendars();

      if (!calendarsResult.isSuccess ||
          calendarsResult.data == null ||
          calendarsResult.data!.isEmpty) {
        debugPrint("No calendar found");
        return;
      }

      // Use default calendar
      final Calendar calendar = calendarsResult.data!.first;

      final location = tz.local;
      final Event event = Event(
        calendar.id,
        title: "Refund Deadline: $storeName",
        description:
        "Category: $_selectedCategory\n"
            "Amount: \$${amount.toStringAsFixed(2)}\n"
            "Notes: ${_notesController.text}",
        start: tz.TZDateTime.from(deadline, location),
        end: tz.TZDateTime.from(
          deadline.add(const Duration(hours: 1)),
          location,
        ),
      );

      final createResult =
      await _calendarPlugin.createOrUpdateEvent(event);

      if (createResult?.isSuccess ?? false) {
        debugPrint("Calendar event added silently ✅");
      }
    } catch (e) {
      debugPrint("Calendar Sync Error: $e");
    }
  }

  // --- ADDED FOR STEP 7: PERMANENT STORAGE LOGIC ---
  Future<String> _saveImagePermanently(String temporaryPath) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = p.basename(temporaryPath);
    final permanentFile = await File(temporaryPath).copy('${directory.path}/$fileName');
    return permanentFile.path;
  }

  // --- IAP LOGIC: Payment Dialog ---
  void _showPaymentDialog(ImageSource source) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Scan Limit Reached", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        content: const Text(
          "You can have one active receipt for free. Please view our plans to unlock unlimited scans.",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
              );
            },
            child: const Text("View Plans", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- IAP LOGIC: Handle Purchase ---
  Future<void> _initiatePurchase(ImageSource source) async {
    final bool available = await _inAppPurchase.isAvailable();
    if (!available) return;

    const Set<String> _kIds = <String>{'next_scan_299'};
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_kIds);

    if (response.productDetails.isNotEmpty) {
      final PurchaseParam purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
      _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList, ImageSource source) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {

        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }

        ProStatus.isPro = true;

        // Small delay to prevent camera hardware race condition
        if (mounted) {
            if (mounted) _pickImage(source);
        }
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        debugPrint("Purchase Error: ${purchaseDetails.error}");
      }
    }
  }



  @override
  void initState() {
    super.initState();

    // _subscription = _inAppPurchase.purchaseStream.listen((purchases) {
    //   // 1. HARD GUARD: Only act if not disposed AND not already initialized
    //   if (!_isDisposed && mounted && !_hasOpenedCamera) {
    //     _listenToPurchaseUpdated(purchases, ImageSource.camera);
    //   }
    // });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 2. HARD GUARD: Check disposal after the frame is rendered
      if (_isDisposed || !mounted || _hasOpenedCamera) return;

      final prefs = await SharedPreferences.getInstance();

      // 3. RE-CHECK: Disposal can happen during the async 'await' above
      if (_isDisposed || !mounted) return;

      ProStatus.isPro = prefs.getBool("isProUser") ?? false;

      if (widget.existingReceipt != null) {
        _hasOpenedCamera = true;
        _loadExistingReceipt();
      } else {
        final receipts = await DatabaseService().getReceipts();

        // 4. RE-CHECK: Database call is async
        if (_isDisposed || !mounted) return;

        if (!_hasOpenedCamera) {
          if (ProStatus.isPro || receipts.isEmpty) {
            _hasOpenedCamera = true;
            _pickImage(ImageSource.camera);
          } else {
            _showPaymentDialog(ImageSource.camera);
          }
        }
      }
    });
  }

  // Add this method to handle loading data when editing an existing receipt
  void _loadExistingReceipt() {
    setState(() {
      _storeController.text = widget.existingReceipt!.storeName;
      _amountController.text = widget.existingReceipt!.amount.toString();
      _selectedDate = widget.existingReceipt!.refundDeadline;
      _purchaseDate = widget.existingReceipt!.purchaseDate;
      _notesController.text = widget.existingReceipt!.notes ?? "";
      _extractedText = widget.existingReceipt!.fullText;
      _selectedCategory = widget.existingReceipt!.category;
      _isDateManuallySet = true; // Since it's existing, we treat it as set
      if (widget.existingReceipt!.imagePath.isNotEmpty) {
        _pickedImage = File(widget.existingReceipt!.imagePath);
      }
    });
  }

  // inside OcrScreen class

  Future<void> _checkLimitAndOpenScanner() async {
    final List<Map<String, dynamic>> receipts = await DatabaseService().getReceipts();

    // LIVE RE-VERIFY: Check storage for immediate purchase updates
    final prefs = await SharedPreferences.getInstance();
    final isProUser = prefs.getBool("isProUser") ?? false;
    ProStatus.isPro = isProUser;

    if (isProUser || receipts.length < 1) {
      _pickImage(ImageSource.camera);
    } else {
      _showPaymentDialog(ImageSource.camera);
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // Mark as dead first

    _storeController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _ocrService.dispose();

    super.dispose();
  }

  Future<void> _handleScanAction(ImageSource source) async {
    // 1. If editing, always allow
    if (widget.existingReceipt != null) {
      _pickImage(source);
      return;
    }

    // 2. CHECK GLOBAL VARIABLE FIRST (Instant)
    if (ProStatus.isPro) {
      _pickImage(source);
      return;
    }

    // 3. Fallback to Database check for free users
    final List<Map<String, dynamic>> receipts = await DatabaseService().getReceipts();
    if (receipts.isEmpty) {
      _pickImage(source);
    } else {
      _showPaymentDialog(source);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!mounted) return;
    if (!ModalRoute.of(context)!.isCurrent) return;
    if (_isDisposed) return;
    try {
      XFile? image;

      if (source == ImageSource.camera) {
        image = await Navigator.push<XFile?>(
          context,
          MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
        );
      } else {
        image = await _picker.pickImage(source: source, imageQuality: 90);
      }

      if (image == null) {
        if (widget.existingReceipt == null && mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const OnboardingScreen()),
                (route) => false,
          );
        }
        return;
      }

      if (mounted) {
        bool? usePhoto = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                title: const Text("Preview Receipt", style: TextStyle(color: Colors.blue)),
                automaticallyImplyLeading: false,
              ),
              body: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Image.file(File(image!.path), fit: BoxFit.contain),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      children: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text("USE PHOTO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 15),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.blue),
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text("RETAKE", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (usePhoto == false) {
          await File(image.path).delete();
          _pickImage(ImageSource.camera);
          return;
        }
      }

      setState(() {
        _pickedImage = File(image!.path);
        _extractedText = "Reading receipt...";
        _isDateManuallySet = false;
      });

      _readTextFromImage();
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  // DateTime? _parseExactDate(String input) {
  //   try {
  //     String clean = input.replaceAll(RegExp(r'[^0-9]'), '/');
  //     List<String> parts = clean.split('/').where((s) => s.isNotEmpty).toList();
  //
  //     if (parts.length >= 3) {
  //       int d = int.parse(parts[0]);
  //       int m = int.parse(parts[1]);
  //       int y = int.parse(parts[2]);
  //       if (y < 100) y += 2000;
  //       if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
  //         return DateTime(y, m, d);
  //       }
  //     }
  //   } catch (_) {}
  //   return null;
  // }

  DateTime? _parseExactDate(String input) {
    try {
      // Standardize separators to '/'
      String clean = input.replaceAll(RegExp(r'[.\-\s]'), '/');

      // Extract numbers only
      List<String> parts = clean.split('/').where((s) => RegExp(r'^\d+$').hasMatch(s)).toList();

      if (parts.length >= 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);

        // Handle 2-digit years (24 -> 2024)
        if (year < 100) year += 2000;

        // Validate date ranges to prevent "31/31/2024" errors
        if (month < 1 || month > 12) return null;
        if (day < 1 || day > 31) return null;

        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  // Future<void> _readTextFromImage() async {
  //   if (_pickedImage == null || !mounted) return;
  //
  //   setState(() => _isOcrRunning = true);
  //
  //   try {
  //     final inputImage = InputImage.fromFile(_pickedImage!);
  //     // Heavy processing starts here
  //     final result = await _ocrService.parseReceipt(inputImage);
  //
  //     // GUARD: Check if user left during OCR
  //     if (!mounted) return;
  //
  //     String fullText = result['fullText'];
  //     DateTime purchaseDate = DateTime.now();
  //     DateTime selectedDate = purchaseDate.add(const Duration(days: 30));
  //
  //     RegExp datePattern = RegExp(r"(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4})");
  //     List<String> lines = fullText.split('\n');
  //
  //     for (var line in lines) {
  //       String upperLine = line.toUpperCase();
  //       var match = datePattern.firstMatch(line.replaceAll(' ', ''));
  //       if (match != null) {
  //         DateTime? parsed = _parseExactDate(match.group(0)!);
  //         if (parsed != null) {
  //           if (upperLine.contains("DUE") || upperLine.contains("EXP") ||
  //               upperLine.contains("RETURN BY") || upperLine.contains("DEADLINE")) {
  //             selectedDate = parsed;
  //           } else {
  //             purchaseDate = parsed;
  //           }
  //         }
  //       }
  //     }
  //
  //     // FINAL GUARD: Update UI only if still mounted
  //     setState(() {
  //       _isOcrRunning = false;
  //       _storeController.text = result['merchant'];
  //       _amountController.text = result['amount'] > 0 ? result['amount'].toStringAsFixed(2) : "";
  //       _extractedText = fullText;
  //       _purchaseDate = purchaseDate;
  //       if (!_isDateManuallySet) {
  //         _selectedDate = selectedDate;
  //       }
  //     });
  //   } catch (e) {
  //     debugPrint("OCR Error: $e");
  //     if (mounted) {
  //       setState(() {
  //         _extractedText = "Error reading receipt";
  //         _isOcrRunning = false;
  //       });
  //     }
  //   }
  // }

  Future<void> _readTextFromImage() async {
    if (_pickedImage == null || !mounted) return;
    setState(() => _isOcrRunning = true);

    try {
      final inputImage = InputImage.fromFile(_pickedImage!);
      final result = await _ocrService.parseReceipt(inputImage);
      if (!mounted) return;

      String fullText = result['fullText'];
      List<String> lines = fullText.split('\n');

      DateTime? detectedPurchaseDate;
      DateTime? detectedDeadline;

      // Improved Regex: Handles spaces like "12 / 05 / 2024"
      RegExp datePattern = RegExp(r"(\d{1,2}[\s/\-.]+\d{1,2}[\s/\-.]+\d{2,4})");

      // Keywords to look for
      List<String> deadlineKeywords = ["RETURN", "DUE", "EXP", "VALID", "UNTIL", "BEFORE", "DEADLINE"];
      List<String> purchaseKeywords = ["DATE", "SALE", "TRANS", "TIME", "ISSUED"];

      for (var line in lines) {
        String upperLine = line.toUpperCase();
        var match = datePattern.firstMatch(line);

        if (match != null) {
          DateTime? parsed = _parseExactDate(match.group(0)!);
          if (parsed != null) {
            // Check if this specific line contains deadline intent
            bool isDeadlineLine = deadlineKeywords.any((k) => upperLine.contains(k));
            bool isPurchaseLine = purchaseKeywords.any((k) => upperLine.contains(k));

            if (isDeadlineLine) {
              detectedDeadline = parsed;
            } else if (isPurchaseLine && detectedPurchaseDate == null) {
              detectedPurchaseDate = parsed;
            } else if (detectedPurchaseDate == null) {
              // Fallback: first generic date found is usually the purchase date
              detectedPurchaseDate = parsed;
            }
          }
        }
      }

      setState(() {
        _isOcrRunning = false;
        _storeController.text = result['merchant'];
        _amountController.text = result['amount'] > 0 ? result['amount'].toStringAsFixed(2) : "";
        _extractedText = fullText;

        // Logic: If we found a purchase date but no deadline, default to +30 days
        if (detectedPurchaseDate != null) {
          _purchaseDate = detectedPurchaseDate;
        }

        if (!_isDateManuallySet) {
          if (detectedDeadline != null) {
            _selectedDate = detectedDeadline;
          } else {
            // Auto-calculate 30 days from detected purchase date
            _selectedDate = _purchaseDate.add(const Duration(days: 30));
          }
        }
      });
    } catch (e) {
      debugPrint("OCR Error: $e");
      if (mounted) setState(() => _isOcrRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
              (route) => false,
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.blue),
          title: Text(
            widget.existingReceipt == null ? 'Refund Tracker Scanner' : 'Edit Receipt',
            style: const TextStyle(color: Colors.blue),
          ),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_pickedImage != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) =>
                          Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.blue)), body: Center(child: Image.file(_pickedImage!)))));
                    }
                  },
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _pickedImage != null
                        ? Image.file(_pickedImage!, fit: BoxFit.contain)
                        : const Center(child: Text("No Receipt Selected", style: TextStyle(color: Colors.blue))),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _handleScanAction(ImageSource.gallery),
                      icon: const Icon(Icons.photo),
                      label: const Text("Gallery"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _handleScanAction(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text("Camera"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                  ],
                ),
                const Divider(height: 40, color: Colors.blue),
                TextField(
                  controller: _storeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Store Name",
                    labelStyle: TextStyle(color: Colors.blue),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue, width: 2)),
                  ),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Category",
                    labelStyle: TextStyle(color: Colors.blue),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue, width: 2)),
                  ),
                  items: _categories.map((String category) {
                    return DropdownMenuItem(value: category, child: Text(category));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _amountController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Total Amount",
                    labelStyle: TextStyle(color: Colors.blue),
                    prefixText: "\$ ",
                    prefixStyle: TextStyle(color: Colors.blue),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue, width: 2)),
                  ),
                ),
                const SizedBox(height: 15),
                ListTile(
                  title: Text("Purchase Date: ${_purchaseDate.day}/${_purchaseDate.month}/${_purchaseDate.year}", style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.calendar_today, color: Colors.blue),
                  tileColor: Colors.blue.withOpacity(0.1),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _purchaseDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      builder: (context, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.blue)), child: child!),
                    );
                    if (picked != null) {
                      setState(() {
                        _purchaseDate = picked;
                        _isDateManuallySet = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: Text(
                    "Deadline: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                    style: TextStyle(color: _isDateManuallySet ? Colors.greenAccent : Colors.white),
                  ),
                  subtitle: _isDateManuallySet
                      ? const Text("Set Manually", style: TextStyle(color: Colors.greenAccent, fontSize: 10))
                      : (_isOcrRunning ? const Text("Scanning...", style: TextStyle(color: Colors.blue, fontSize: 10)) : const Text("Tap to change", style: TextStyle(color: Colors.grey, fontSize: 10))),
                  trailing: const Icon(Icons.edit_calendar, color: Colors.blue),
                  tileColor: Colors.blue.withOpacity(0.1),
                  onTap: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      builder: (context, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.blue)), child: child!),
                    );

                    if (pickedDate != null && mounted) {
                      setState(() {
                        _selectedDate = pickedDate;
                        _isDateManuallySet = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _notesController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: "Notes (Optional)",
                    labelStyle: TextStyle(color: Colors.blue),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue, width: 2)),
                  ),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (_storeController.text.isEmpty || _amountController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please fill in all details"), backgroundColor: Colors.blue),
                      );
                      return;
                    }

                    // --- RESTORED TIME PICKER ---
                    // This allows the user to set the exact time for the notification
                    TimeOfDay? pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_selectedDate),
                      builder: (context, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(primary: Colors.blue),
                        ),
                        child: child!,
                      ),
                    );

                    // If user cancels the time picker, we stop the save process
                    if (pickedTime == null) return;

                    // Update the deadline with the selected time
                    setState(() {
                      _selectedDate = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });

                    // 1. Image logic
                    String finalImagePath = _pickedImage?.path ?? "";
                    if (_pickedImage != null && widget.existingReceipt == null) {
                      finalImagePath = await _saveImagePermanently(_pickedImage!.path);
                    }

                    // 2. Create the receipt object
                    final receipt = Receipt(
                      id: widget.existingReceipt?.id ?? DateTime.now().toString(),
                      storeName: _storeController.text,
                      amount: double.tryParse(_amountController.text) ?? 0.0,
                      purchaseDate: _purchaseDate,
                      refundDeadline: _selectedDate, // Now contains the picked time
                      imagePath: finalImagePath,
                      fullText: _extractedText,
                      notes: _notesController.text,
                      category: _selectedCategory,
                    );

                    // 3. Database operation
                    await DatabaseService().insertReceipt(receipt.toMap());

                    // 4. Calendar & Notifications
                    if (mounted) {
                      await _syncToCalendar(
                        storeName: receipt.storeName,
                        amount: receipt.amount,
                        deadline: receipt.refundDeadline,
                      );

                      if (!mounted) return;

                      await NotificationService().scheduleSmartReminders(
                        receiptId: receipt.id.hashCode.abs(),
                        storeName: receipt.storeName,
                        amount: receipt.amount,
                        deadline: receipt.refundDeadline,
                      );
                    }

                    // 5. Final Navigation
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Receipt Saved & Reminder Set!"), backgroundColor: Colors.blue),
                      );

                      if (widget.existingReceipt != null) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const RefundListScreen()),
                        );
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => ReceiptDetailScreen(receipt: receipt.toMap())),
                        );
                      }
                    }
                  },
                  child: Text(widget.existingReceipt == null ? "SAVE RECEIPT & SET REMINDER" : "UPDATE AND SET REMINDER"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const OnboardingScreen()),
                          (route) => false,
                    );
                  },
                  child: const Text("Cancel", style: TextStyle(color: Colors.blue)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? controller;
  bool _isCapturing = false;
  @override
  void initState() {
    super.initState();
    initCamera();
  }

  @override
  void dispose() {
    // This shuts down the camera hardware and turns off the light
    controller?.dispose();
    super.dispose();
  }

  Future<void> initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Create a local temporary controller first
      final CameraController tempController = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false, // Setting to false prevents many background crashes
      );

      // Safety Check: If user left the screen while getting cameras
      if (!mounted) return;

      await tempController.initialize();

      // Safety Check: If user left the screen while initializing
      if (!mounted) {
        await tempController.dispose();
        return;
      }

      setState(() {
        controller = tempController;
      });
    } catch (e) {
      debugPrint("Camera Initialization Error: $e");
      // Handle specific error: if it fails, pop back so the app doesn't freeze
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox(
            width: size.width,
            height: size.height,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.width,
                height: size.width * controller!.value.aspectRatio,
                child: CameraPreview(controller!),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                backgroundColor: Colors.blue,
                onPressed: () async {
                  if (_isCapturing) return; // Ignore if already taking a photo

                  setState(() => _isCapturing = true);
                  try {
                    final file = await controller!.takePicture();
                    if (mounted) Navigator.pop(context, XFile(file.path));
                  } catch (e) {
                    debugPrint("Capture Error: $e");
                  } finally {
                    if (mounted) setState(() => _isCapturing = false);
                  }
                },
                child: const Icon(Icons.camera_alt, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
