import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for SystemNavigator
import 'package:shared_preferences/shared_preferences.dart';
import 'main_wrapper.dart';
import 'ocr_screen.dart'; // Needed for the camera button
import 'refund_list_screen.dart'; // Needed for the list button
import 'package:flutter_native_splash/flutter_native_splash.dart';

// Changed to StatefulWidget to track the exit timer
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  DateTime? _lastPressedAt; // Track time for double-back exit

  // --- ADDED: HIDE SPLASH SCREEN ON LOAD ---
  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
  }

  // Save the flag so user never sees this again
  Future<void> _completeOnboarding(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    // --- THIS IS THE CRITICAL FIX ---
    await prefs.setBool('hasSeenOnboarding', true);

    if (context.mounted) {
      // CHANGE: Instead of going to MainWrapper, we go direct to OCR/Camera
      // This will trigger the auto-camera logic we added to OcrScreen's initState
      Navigator.pushReplacement( // Changed to pushReplacement so user can't go back to onboarding
        context,
        MaterialPageRoute(builder: (context) => const OcrScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent immediate exit
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final now = DateTime.now();
        // If first click OR click was more than 2 seconds ago
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Press back again to exit"),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // Second click within 2 seconds
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        // Added Stack to place the "My Refunds" and "Scan" buttons at the bottom
        body: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_balance_wallet, size: 100, color: Colors.blue),
                  const SizedBox(height: 30),
                  const Text(
                    "Stop Losing Money!",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  _buildFeatureRow(Icons.document_scanner, "Scan your paper receipts instantly."),
                  _buildFeatureRow(Icons.timer, "Track refund deadlines automatically."),
                  _buildFeatureRow(Icons.notifications_active, "Get reminders before it's too late."),
                  const SizedBox(height: 50),

                  // Keeping your original button as well
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _completeOnboarding(context),
                    child: const Text("SCAN RECEIPT"),
                  ),
                ],
              ),
            ),

            // --- UPDATED: SIMPLE BUTTONS AT THE BOTTOM (Left: Scan, Right: My Refunds) ---
            Positioned(
              bottom: 30,
              left: 30,
              right: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // LEFT SIDE: SIMPLE SCAN BUTTON
                  InkWell(
                    onTap: () async {
                      // Also save status here so the app knows the user is "active"
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hasSeenOnboarding', true);

                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const OcrScreen()),
                        );
                      }
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt, color: Colors.blue),
                        Text("Scan", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),

                  // RIGHT SIDE: SIMPLE MY REFUNDS BUTTON
                  InkWell(
                    onTap: () async {
                      // Also save status here
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hasSeenOnboarding', true);

                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RefundListScreen()),
                        );
                      }
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long, color: Colors.blue),
                        Text("List Refunds", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 15),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}