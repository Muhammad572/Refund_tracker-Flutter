import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import 'package:device_calendar/device_calendar.dart'; // Added for 10.1
import 'package:timezone/timezone.dart' as tz; // Added for 10.1
import 'package:path_provider/path_provider.dart'; // Added for Step 7
import 'package:path/path.dart' as p; // Added for Step 7
import '../services/database_service.dart';
import '../models/receipt_model.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import 'onboarding_screen.dart'; // Added import to allow navigation back
import 'receipt_detail_screen.dart'; // Added for direct navigation

class OcrScreen extends StatefulWidget {
  final Receipt? existingReceipt;
  const OcrScreen({super.key, this.existingReceipt});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  File? _pickedImage;

  String _extractedText = "Scan a receipt to begin";

  DateTime? _lastPressedAt;
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

  // --- 10.1: CALENDAR SYNC LOGIC ---
  final DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();

  Future<void> _syncToCalendar({required String storeName, required double amount, required DateTime deadline}) async {
    try {
      var permissions = await _calendarPlugin.requestPermissions();
      if (permissions.isSuccess && permissions.data!) {
        final calendars = await _calendarPlugin.retrieveCalendars();
        if (calendars.isSuccess && calendars.data!.isNotEmpty) {
          Calendar defaultCal = calendars.data!.first;

          Event event = Event(defaultCal.id);
          event.title = "Refund Deadline: $storeName";
          event.description = "Category: $_selectedCategory. Amount: \$${amount.toStringAsFixed(2)}. Notes: ${_notesController.text}";

          event.start = tz.TZDateTime.from(deadline, tz.local);
          event.end = tz.TZDateTime.from(deadline.add(const Duration(hours: 1)), tz.local);

          await _calendarPlugin.createOrUpdateEvent(event);
        }
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

  @override
  void initState() {
    super.initState();
    if (widget.existingReceipt != null) {
      _storeController.text = widget.existingReceipt!.storeName;
      _amountController.text = widget.existingReceipt!.amount.toString();
      _selectedDate = widget.existingReceipt!.refundDeadline;
      _purchaseDate = widget.existingReceipt!.purchaseDate;
      _notesController.text = widget.existingReceipt!.notes ?? "";
      _extractedText = widget.existingReceipt!.fullText;
      _selectedCategory = widget.existingReceipt!.category; // Load Category
      _isDateManuallySet = true;
      if (widget.existingReceipt!.imagePath.isNotEmpty) {
        _pickedImage = File(widget.existingReceipt!.imagePath);
      }
    } else {  //line 97 remeber where to cut if put back right there till line 101
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickImage(ImageSource.camera);
      });
    }
  }
  @override
  void dispose() {
    _ocrService.dispose();
    _storeController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
  Future<void> _pickImage(ImageSource source) async {
    try {
      XFile? image;

      if (source == ImageSource.camera) {
        image = await Navigator.push<XFile?>(
          context,
          MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
        );
      } else {
        // High quality setting preserved
        image = await _picker.pickImage(source: source, imageQuality: 90);
      }

      if (image == null) {
        if (widget.existingReceipt == null && mounted) {
          // --- CHANGE HERE: Back to Onboarding if image canceled ---
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
        _isDateManuallySet = false; // Reset on new scan
      });

      _readTextFromImage();
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  // Helper for Exact Date Parsing
  DateTime? _parseExactDate(String input) {
    try {
      // Standardize separators
      String clean = input.replaceAll(RegExp(r'[^0-9]'), '/');
      List<String> parts = clean.split('/').where((s) => s.isNotEmpty).toList();

      if (parts.length >= 3) {
        int d = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        int y = int.parse(parts[2]);
        if (y < 100) y += 2000;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime(y, m, d);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _readTextFromImage() async {
    if (_pickedImage == null) return;
    setState(() => _isOcrRunning = true);
    try {
      final inputImage = InputImage.fromFile(_pickedImage!);
      final result = await _ocrService.parseReceipt(inputImage);
      String fullText = result['fullText'];

      DateTime? detectedPurchaseDate;
      DateTime? detectedDeadline;

      RegExp datePattern = RegExp(r"(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4})");

      List<String> lines = fullText.split('\n');
      for (var line in lines) {
        String upperLine = line.toUpperCase();
        var match = datePattern.firstMatch(line.replaceAll(' ', ''));

        if (match != null) {
          DateTime? parsed = _parseExactDate(match.group(0)!);
          if (parsed != null) {
            // --- ENHANCED SCAN: More keywords for deadline ---
            if (upperLine.contains("DUE") ||
                upperLine.contains("EXP") ||
                upperLine.contains("UNTIL") ||
                upperLine.contains("BEFORE") ||
                upperLine.contains("DEADLINE") ||
                upperLine.contains("RETURN BY")) {
              detectedDeadline = parsed;
            } else if (detectedPurchaseDate == null) {
              detectedPurchaseDate = parsed;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _isOcrRunning = false;
          _storeController.text = result['merchant'];
          _amountController.text = result['amount'] > 0 ? result['amount'].toStringAsFixed(2) : "";
          _extractedText = fullText;

          if (detectedPurchaseDate != null) {
            _purchaseDate = detectedPurchaseDate;
          }

          if (!_isDateManuallySet) {
            if (detectedDeadline != null) {
              _selectedDate = detectedDeadline;
            } else {
              // If no clear deadline found, stick to 30 days but don't "force" it if user is typing
              _selectedDate = _purchaseDate.add(const Duration(days: 30));
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _extractedText = "Error: $e"; _isOcrRunning = false; });
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
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo),
                      label: const Text("Gallery"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
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
                  // --- VISUAL FIX: Use bold color for manual dates ---
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

                    // Line 396 updated:
                    if (pickedDate != null && mounted) {
                      setState(() {
                        _selectedDate = pickedDate; // No time picker here anymore
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

                    // --- MANUAL TIME PICKER ---
                    TimeOfDay? pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_selectedDate),
                      builder: (context, child) => Theme(
                        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.blue)),
                        child: child!,
                      ),
                    );

                    if (pickedTime != null) {
                      setState(() {
                        _selectedDate = DateTime(
                          _selectedDate.year,
                          _selectedDate.month,
                          _selectedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    } else {
                      return;
                    }

                    String finalImagePath = _pickedImage?.path ?? "";
                    if (_pickedImage != null && widget.existingReceipt == null) {
                      finalImagePath = await _saveImagePermanently(_pickedImage!.path);
                    }

                    final receipt = Receipt(
                      id: widget.existingReceipt?.id ?? DateTime.now().toString(),
                      storeName: _storeController.text,
                      amount: double.tryParse(_amountController.text) ?? 0.0,
                      purchaseDate: _purchaseDate,
                      refundDeadline: _selectedDate,
                      imagePath: finalImagePath,
                      fullText: _extractedText,
                      notes: _notesController.text,
                      category: _selectedCategory,
                    );

                    await DatabaseService().insertReceipt(receipt.toMap());
                    await _syncToCalendar(
                      storeName: receipt.storeName,
                      amount: receipt.amount,
                      deadline: receipt.refundDeadline,
                    );

                    // --- UPDATED NOTIFICATION LOGIC ---
                    // This calls the smart reminders (1 Day and 1 Hour) synchronized in NotificationService
                    await NotificationService().scheduleSmartReminders(
                      receiptId: receipt.id.hashCode.abs(),
                      storeName: receipt.storeName,
                      amount: receipt.amount,
                      deadline: receipt.refundDeadline,
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Receipt Saved & Smart Reminder Set!"), backgroundColor: Colors.blue),
                      );

                      // --- UPDATED NAVIGATION: Go directly to ReceiptDetailScreen using toMap() ---
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReceiptDetailScreen(receipt: receipt.toMap()),
                        ),
                      );
                    }
                  },
                  child: Text(widget.existingReceipt == null ? "SAVE RECEIPT & SET REMINDER" : "UPDATE RECEIPT"),
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

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    controller = CameraController(cameras.first, ResolutionPreset.high);
    await controller!.initialize();
    if (mounted) setState(() {});
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
                  final file = await controller!.takePicture();
                  if (mounted) Navigator.pop(context, XFile(file.path));
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