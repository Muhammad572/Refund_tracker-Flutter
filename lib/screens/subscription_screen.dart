import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  final String _policyUrl = "https://sites.google.com/view/refundtracker-privacy";

  // --- NEW: Function to show Privacy/Terms in a professional dialog ---
  void _showTextDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(title, style: const TextStyle(color: Colors.blue)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              content,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.blue),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- TOP SECTION: UNLOCK FEATURES ---
              const Icon(Icons.stars_rounded, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                "Unlock Pro Scanner",
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _buildFeatureItem(Icons.check_circle, "Unlimited Receipt Scans"),
              _buildFeatureItem(Icons.check_circle, "Smart Deadline Reminders"),
              _buildFeatureItem(Icons.check_circle, "Auto Calendar Sync"),
              _buildFeatureItem(Icons.check_circle, "Advanced Category Tracking"),
              _buildFeatureItem(Icons.check_circle, "Secure Local Image Storage"),

              const SizedBox(height: 40),

              // --- MIDDLE SECTION: PACKAGES ---
              _buildPackageCard(
                title: "Monthly Plan",
                price: "\$2.99 / month",
                description: "Best for short-term tracking",
                onTap: () {
                  // TODO: Add IAP Monthly Logic
                },
              ),
              const SizedBox(height: 16),
              _buildPackageCard(
                title: "Yearly Plan",
                price: "\$19.99 / year",
                description: "Save 45% annually",
                isPopular: true,
                onTap: () {
                  // TODO: Add IAP Yearly Logic
                },
              ),

              const SizedBox(height: 40),

              // --- BOTTOM SECTION: POLICIES & RESTORE (LIFTED UP) ---
              Padding(
                padding: const EdgeInsets.only(bottom: 60.0),
                child: Column(
                  children: [
                    if (Platform.isIOS)
                      TextButton(
                        onPressed: () {
                          // TODO: Add Restore Purchases Logic
                        },
                        child: const Text("Restore Purchases", style: TextStyle(color: Colors.blue)),
                      ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => _showTextDialog(context, "Privacy Policy", _privacyText),
                          child: const Text("Privacy Policy", style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline, fontSize: 12)),
                        ),
                        const Text("  |  ", style: TextStyle(color: Colors.grey)),
                        GestureDetector(
                          onTap: () => _showTextDialog(context, "Terms of Service", _termsText),
                          child: const Text("Terms of Service", style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildPackageCard({
    required String title,
    required String price,
    required String description,
    required VoidCallback onTap,
    bool isPopular = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isPopular ? Colors.blue : Colors.transparent, width: 2),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(price, style: const TextStyle(color: Colors.blue, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
            if (isPopular)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(8)),
                  child: const Text("POPULAR", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- THE LEGAL TEXT STRINGS ---
  final String _privacyText = """
PRIVACY POLICY
Last Updated: 2026

1. Data Collection: We do not collect your personal receipt data. All OCR processing and storage happen locally on your device.
2. Information Usage: Any metadata provided is used solely for organizing your refund deadlines.
3. Third Parties: We do not sell or share your information with third-party advertisers.
4. Security: Data is stored in a local database protected by your device's security protocols.
5. Contact: For privacy concerns, please contact support through the app settings.
""";

  final String _termsText = """
TERMS OF SERVICE
Last Updated: 2026

1. Acceptance: By using Refund Tracker, you agree to these terms.
2. Subscriptions: Pro features are billed monthly or yearly. Payment is charged to your App Store/Play Store account.
3. Cancellation: You can cancel anytime through your store account settings.
4. Use License: You are granted a personal, non-exclusive license to use the app for personal refund tracking.
5. Disclaimer: While we strive for accuracy, the app is not responsible for missed refund windows due to OCR errors or device failure.
""";
}