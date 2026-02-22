import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import '../models/receipt_model.dart';
import 'ocr_screen.dart';


class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {

  final InAppPurchase _iap = InAppPurchase.instance;

  late final List<Plan> _plans;
  bool _purchaseHandled = false;
  static final Set<String> _productIds =
  Platform.isIOS
      ? {'pro_monthly', 'pro_yearly'}
      : {'refund_tracker_pro'};

  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _loading = true;
  bool _purchasing = false;

  // ---------------- INIT ----------------

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) {
      _plans = const [
        Plan(
          id: "pro_yearly",
          title: "Yearly Plan",
          displayPrice: "", // will come from App Store
        ),
        Plan(
          id: "pro_monthly",
          title: "Monthly Plan",
          displayPrice: "",
        ),
      ];
    } else {
      // ANDROID → manual display pricing
      _plans = const [
        Plan(
          id: "yearly",
          title: "Yearly Plan",
          displayPrice: "Rs 5,600 / year",
        ),
        Plan(
          id: "monthly",
          title: "Monthly Plan",
          displayPrice: "Rs 490 / month",
        ),
      ];
    }
    _initStore();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _initStore() async {
    final available = await _iap.isAvailable();
    // if (!available) return;
    if (!available) {
      setState(() => _loading = false);
      return;
    }

    final response = await _iap.queryProductDetails(_productIds);

    _products = response.productDetails;

    _subscription =
        _iap.purchaseStream.listen(_handlePurchaseUpdates);

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint("Products not found: ${response.notFoundIDs}");
    }

    setState(() => _loading = false);
  }

  void _buy(String productId) {
    if (_purchasing) return;
    final product = _findProduct(productId);
    if (product == null) return;

    setState(() => _purchasing = true);

    final param = PurchaseParam(productDetails: product);

    _iap.buyNonConsumable(
      purchaseParam: param,
    );
  }

  void _buyPlan(String planId) {
    if (_purchasing) return;

    if (Platform.isIOS) {
      _buy(planId); // real product id
    } else {
      // Android always buys same subscription
      _buy("refund_tracker_pro");
    }
  }


  ProductDetails? _findProduct(String id) {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  // Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
  //   for (final purchase in purchases) {
  //     if (purchase.status == PurchaseStatus.purchased ||
  //         purchase.status == PurchaseStatus.restored) {
  //
  //       // 1. Mark as Pro globally and locally
  //       final prefs = await SharedPreferences.getInstance();
  //       await prefs.setBool("isProUser", true);
  //       ProStatus.isPro = true;
  //
  //       // 2. Crucial: Complete the purchase to avoid "Already owned" errors
  //       if (purchase.pendingCompletePurchase) {
  //         await _iap.completePurchase(purchase);
  //       }
  //
  //       if (!mounted) return;
  //       setState(() => _purchasing = false);
  //
  //       // 3. Navigate immediately to the scanner (the "flow unlock")
  //       // Using pushReplacement so they can't go back to the sub screen
  //       Navigator.pushReplacement(
  //         context,
  //         MaterialPageRoute(builder: (_) => OcrScreen()), // FIXED
  //       );
  //     }
  //
  //     if (purchase.status == PurchaseStatus.error) {
  //       debugPrint("IAP Error: ${purchase.error}");
  //       setState(() => _purchasing = false);
  //     }
  //
  //     if (purchase.status == PurchaseStatus.canceled) {
  //       setState(() => _purchasing = false);
  //     }
  //   }
  // }


  // Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
  //   for (final purchase in purchases) {
  //     if (purchase.status == PurchaseStatus.purchased ||
  //         purchase.status == PurchaseStatus.restored) {
  //
  //       // 1. Sync to local memory immediately
  //       ProStatus.isPro = true;
  //
  //       // 2. AWAIT the disk write to ensure it's permanent before moving on
  //       final prefs = await SharedPreferences.getInstance();
  //       await prefs.setBool("isProUser", true);
  //
  //       debugPrint("✅ Pro Status synced to Disk and Global State");
  //
  //       // 3. Complete the transaction with the Store
  //       if (purchase.pendingCompletePurchase) {
  //         await _iap.completePurchase(purchase);
  //       }
  //
  //       if (!mounted) return;
  //       setState(() => _purchasing = false);
  //
  //       // 4. Navigate and clear the stack so they can't 'back' into the paywall
  //       Navigator.pushAndRemoveUntil(
  //         context,
  //         MaterialPageRoute(builder: (_) => const OcrScreen()),
  //             (route) => false,
  //       );
  //     }
  //
  //     if (purchase.status == PurchaseStatus.error) {
  //       debugPrint("IAP Error: ${purchase.error}");
  //       if (mounted) setState(() => _purchasing = false);
  //     }
  //   }
  // }



  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {

    // 🚨 HARD GUARD — prevents duplicate navigation
    if (_purchaseHandled) return;

    for (final purchase in purchases) {

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {

        _purchaseHandled = true;   // ✅ lock immediately

        ProStatus.isPro = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool("isProUser", true);

        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }

        if (!mounted) return;

        setState(() => _purchasing = false);

        // SINGLE navigation only
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const OcrScreen()),
              (route) => false,
        );

        return; // ✅ stop processing remaining events
      }

      if (purchase.status == PurchaseStatus.error) {
        debugPrint("IAP Error: ${purchase.error}");
        if (mounted) setState(() => _purchasing = false);
      }
    }
  }

  // inside SubscriptionScreen
  // Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
  //
  //   for (final purchase in purchases) {
  //     if (purchase.status == PurchaseStatus.purchased ||
  //         purchase.status == PurchaseStatus.restored) {
  //
  //       ProStatus.isPro = true;
  //       final prefs = await SharedPreferences.getInstance();
  //       await prefs.setBool("isProUser", true);
  //
  //       if (purchase.pendingCompletePurchase) {
  //         await _iap.completePurchase(purchase);
  //       }
  //
  //       if (!mounted) return;
  //       setState(() => _purchasing = false);
  //
  //       // CRITICAL: pushAndRemoveUntil ensures a total fresh load of OcrScreen
  //       Navigator.pushAndRemoveUntil(
  //         context,
  //         MaterialPageRoute(builder: (_) => const OcrScreen()),
  //             (route) => false,
  //       );
  //     }
  //     if (purchase.status == PurchaseStatus.error) {
  //       debugPrint("IAP Error: ${purchase.error}");
  //       if (mounted) setState(() => _purchasing = false);
  //     }
  //   }
  // }

  Future<void> _restorePurchases() async {
    // await _iap.restorePurchases();

    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint("Restore failed (safe to ignore): $e");
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Restoring purchases...")),
    );
  }

  // ---------------- LEGAL TEXT ----------------

  void _showLegal(BuildContext context, String title, String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(title,
            style: const TextStyle(color: Colors.blue)),
        content: SingleChildScrollView(
          child: Text(text,
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.blue),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [

            const Icon(Icons.stars_rounded,
                size: 80, color: Colors.blue),

            const SizedBox(height: 12),

            const Text(
              "Unlock Pro Scanner",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            _feature("Unlimited Receipt Scans"),
            _feature("Smart Deadline Reminders"),
            _feature("Automatic Calendar Sync"),
            _feature("Advanced Category Tracking"),
            _feature("Secure Local Storage"),

            const SizedBox(height: 16),

            const Text(
              "Never miss a refund deadline again — Pro pays for itself after one saved refund.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),

            const SizedBox(height: 24),

          Column(
            children: _plans.map((plan) {

              String price = plan.displayPrice;

              // iOS price comes from App Store
              if (Platform.isIOS) {
                final product = _findProduct(plan.id);
                price = product?.price ?? "";
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _planCard(
                  plan.title,
                  price,
                      () => _buyPlan(plan.id),
                  popular: plan.id.contains("yearly"),
                  badge: plan.id.contains("yearly") ? "SAVE 45%" : null,
                ),
              );
            }).toList(),
          ),
            const SizedBox(height: 30),

            if (Platform.isIOS)
              TextButton(
                onPressed: _restorePurchases,
                child: const Text(
                  "Restore Purchases",
                  style: TextStyle(color: Colors.blue),
                ),
              ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () =>
                      _showLegal(context,"Privacy Policy",_privacyText),
                  child: const Text(
                    "Privacy Policy",
                    style: TextStyle(
                        color: Colors.grey,
                        decoration: TextDecoration.underline,
                        fontSize: 12),
                  ),
                ),
                const Text(" | ",
                    style: TextStyle(color: Colors.grey)),
                GestureDetector(
                  onTap: () =>
                      _showLegal(context,"Terms of Service",_termsText),
                  child: const Text(
                    "Terms of Service",
                    style: TextStyle(
                        color: Colors.grey,
                        decoration: TextDecoration.underline,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              color: Colors.blue, size: 22),
          const SizedBox(width: 10),
          Text(text,
              style:
              const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _planCard(
      String title,
      String price,
      VoidCallback onTap, {
        bool popular = false,
        String? badge,
      }) {
    return GestureDetector(
      onTap: (_loading || _purchasing) ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: popular ? Colors.blue.withValues(alpha: .12) : Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: popular ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(price,
                    style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),

            if (badge != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -------- LEGAL TEXT --------

  final String _privacyText = """

Privacy Policy

Last updated: 2026

Refund Tracker (“the App”) respects your privacy. This Privacy Policy explains how information is handled when you use the application.

1. Information We Collect
The app processes receipt images and text that you choose to scan. This may include:
• Store name
• Purchase amount
• Purchase dates
• Notes you manually enter
• Receipt images

All receipt data is stored locally on your device.

2. Camera and Photos
The app requests camera and photo library access only to allow you to scan or import receipts. Images are never uploaded to external servers by the app.

3. Text Recognition (OCR)
Receipt images are processed using on-device text recognition technology. Text extraction happens locally on your device.

4. Calendar Access
If you enable calendar sync, the app creates reminder events for refund deadlines in your personal calendar. The app does not read or collect unrelated calendar data.

5. Notifications
The app schedules local notifications to remind you about refund deadlines. Notification data remains on your device.

6. Purchases and Subscriptions
Subscriptions are processed securely through Apple App Store or Google Play. The app does not collect or store your payment information.

7. Data Storage
All receipt data is stored locally on your device storage. The developer does not maintain remote databases containing your personal receipt information.

8. Data Sharing
The app does not sell, rent, or share your personal data with third parties.

9. Data Deletion
You may delete receipts at any time inside the app. Removing the app will delete locally stored data from your device.

10. Changes to This Policy
This policy may be updated when features change. Continued use of the app indicates acceptance of updates.

11. Contact
For questions regarding privacy, contact:
hasstech.dev@gmail.com

""";
  final String _termsText = """

Terms of Service

Last updated: 2026

By downloading or using Refund Tracker (“the App”), you agree to the following terms.

1. Use of the App
The app is designed to help users scan receipts, track refund deadlines, and receive reminder notifications. You agree to use the app only for lawful personal purposes.

2. Accuracy Disclaimer
The app uses automated text recognition (OCR) to extract receipt information. Accuracy is not guaranteed. Users are responsible for reviewing and correcting receipt details before relying on reminders.

3. Notifications and Reminders
Reminder notifications are provided as a convenience feature. The developer is not responsible for missed deadlines caused by device settings, disabled notifications, system restrictions, or incorrect user input.

4. Subscriptions
Some features require a paid subscription (“Pro”).

• Payment is charged through your Apple App Store or Google Play account.
• Subscriptions automatically renew unless cancelled at least 24 hours before the end of the billing period.
• You can manage or cancel subscriptions in your device account settings.
• Refunds are handled by Apple or Google according to their billing policies.

5. Free Features
Free usage may include limitations such as restricted scans or features. These limits may change in future versions.

6. Data Responsibility
All receipt information is stored locally on your device. You are responsible for maintaining backups and protecting access to your device.

7. Limitation of Liability
The app is provided “as is” without warranties of any kind. The developer is not liable for financial loss, missed refunds, or damages resulting from use of the app.

8. Termination
The developer may modify or discontinue features at any time without prior notice.

9. Changes to Terms
These terms may be updated periodically. Continued use of the app indicates acceptance of updated terms.

10. Contact
For support or questions:
hasstech.dev@gmail.com

""";
}