import 'dart:io';
import 'package:flutter/material.dart';
import '../services/database_service.dart'; // Needed for Delete
import 'ocr_screen.dart'; // Needed for Edit
import '../models/receipt_model.dart'; // Needed for Edit
import '../services/notification_service.dart'; // Added to handle cancellation

class ReceiptDetailScreen extends StatelessWidget {
  final Map<String, dynamic> receipt;

  ReceiptDetailScreen({super.key, required dynamic receipt})
      : receipt = receipt is Receipt ? receipt.toMap() : receipt;

  // --- NEW: STEP 7.7 COLORED BADGE LOGIC ---
  Color _getStatusColor(DateTime deadline) {
    final now = DateTime.now();
    if (deadline.isBefore(now)) return Colors.red;
    if (deadline.difference(now).inDays <= 7) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    // Parsing dates for the logic
    final deadlineDate = DateTime.parse(receipt['refundDeadline'] ?? DateTime.now().toIso8601String());
    final statusColor = _getStatusColor(deadlineDate);

    // FIXED: Intercept back button to return to Home Screen safely
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Forces the app to go to the Home list screen
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(receipt['storeName'] ?? "Receipt"),
          // --- NEW: STEP 7.7 EDIT BUTTON ---
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OcrScreen(
                      existingReceipt: Receipt(
                        id: receipt['id'],
                        storeName: receipt['storeName'],
                        amount: receipt['amount'],
                        purchaseDate: DateTime.parse(receipt['purchaseDate']),
                        refundDeadline: deadlineDate,
                        imagePath: receipt['imagePath'],
                        // --- FIXED: PASSING NOTES AND TEXT TO EDIT SCREEN ---
                        fullText: receipt['fullText'] ?? "",
                        notes: receipt['notes'] ?? "",
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Display the scanned image
              // --- NEW: STEP 7.7 TAP -> FULLSCREEN ---
              GestureDetector(
                onTap: () {
                  if (receipt['imagePath'] != null && receipt['imagePath'] != "") {
                    Navigator.push(context, MaterialPageRoute(builder: (_) =>
                        Scaffold(
                          backgroundColor: Colors.black,
                          appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
                          body: Center(child: InteractiveViewer(child: Image.file(File(receipt['imagePath'])))),
                        )
                    ));
                  }
                },
                child: Container(
                  height: 300,
                  width: double.infinity,
                  color: Colors.black12,
                  // LOOPHOLE FIX: Added null check and existence check
                  child: (receipt['imagePath'] != null && receipt['imagePath'] != "" && File(receipt['imagePath']).existsSync())
                      ? Image.file(File(receipt['imagePath']), fit: BoxFit.cover)
                      : const Icon(Icons.image_not_supported, size: 100),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Amount: \$${receipt['amount'] ?? '0.00'}",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // --- NEW: STEP 7.7 COLORED STATUS BADGE ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        "Deadline: ${receipt['refundDeadline'] ?? 'N/A'}",
                        style: TextStyle(fontSize: 16, color: statusColor, fontWeight: FontWeight.bold),
                      ),
                    ),

                    const SizedBox(height: 20),
                    // Added Purchase Date display
                    Text("Purchase Date: ${receipt['purchaseDate'] ?? 'N/A'}",
                        style: const TextStyle(fontSize: 16, color: Colors.grey)),

                    const Divider(height: 40),
                    const Text("Notes:", style: TextStyle(fontWeight: FontWeight.bold)),
                    // --- FIXED: ENSURING NOTES SHOW FROM DATABASE KEY ---
                    Text(receipt['notes'] != null && receipt['notes'].toString().isNotEmpty
                        ? receipt['notes']
                        : "No notes added"),

                    const SizedBox(height: 20),
                    const Text("Full Scanned Text:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(receipt['fullText'] ?? "No text extracted"),

                    const SizedBox(height: 40),
                    // --- NEW: STEP 7.7 DELETE BUTTON ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () async {
                          final confirm = await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Delete Receipt?"),
                              content: const Text("This action cannot be undone."),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            // Rule: Cancel notification when receipt deleted
                            await NotificationService().cancelNotification(receipt['id'].hashCode);
                            await DatabaseService().deleteReceipt(receipt['id']);
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.delete),
                        label: const Text("DELETE RECORD"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}