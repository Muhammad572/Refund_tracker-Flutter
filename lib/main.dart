import 'package:flutter/material.dart';
import 'dart:io'; // Added for exit(0)
import 'dart:async';
import 'package:flutter/services.dart'; // Added for SystemNavigator
import 'package:refund_tracker/screens/main_tabs_screen.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/onboarding_screen.dart';
import 'services/database_service.dart'; // Added for rescheduling logic
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Added for permission check
import 'screens/receipt_detail_screen.dart'; // Required for navigation
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'screens/refund_list_screen.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../models/receipt_model.dart';
// --- 9.2: GLOBAL NAVIGATOR KEY ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Variable to track back button timing globally
DateTime? _lastPressedAt;

// ADDED: This tracks if we should show detail screen directly
Map<String, dynamic>? notificationReceipt;

bool _isProChecking = false; // Add this global variable

// Future<void> checkProStatus() async {
//   if (_isProChecking) return;
//   _isProChecking = true;
//
//   final iap = InAppPurchase.instance;
//   final prefs = await SharedPreferences.getInstance();
//
//   if (!await iap.isAvailable()) {
//     _isProChecking = false;
//     return;
//   }
//
//   // Initial Sync from local storage
//   ProStatus.isPro = prefs.getBool("isProUser") ?? false;
//   debugPrint("✅ ProStatus.isPro = ${ProStatus.isPro}");
//   iap.purchaseStream.listen((purchases) async {
//     // 1. Check if ANY valid purchase exists in the returned list
//     bool foundActiveSub = purchases.any((purchase) =>
//     (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) &&
//         (purchase.productID == "pro_monthly" || purchase.productID == "pro_yearly" || purchase.productID == "refund_tracker_pro"));
//
//     // 2. Update status based on the store result
//     if (foundActiveSub) {
//       if (!ProStatus.isPro) {
//         await prefs.setBool("isProUser", true);
//         ProStatus.isPro = true;
//         debugPrint("Pro Status: Active ✅");
//       }
//     } else {
//       // If we checked the store and found NOTHING, set to false
//       if (ProStatus.isPro) {
//         await prefs.setBool("isProUser", false);
//         ProStatus.isPro = false;
//         debugPrint("Pro Status: Expired/None found ❌");
//       }
//     }
//
//     for (final purchase in purchases) {
//       if (purchase.pendingCompletePurchase) {
//         await iap.completePurchase(purchase);
//       }
//     }
//   });
//
//   try {
//     await iap.restorePurchases();
//   } catch (_) {
//     _isProChecking = false;
//   }
// }

Future<void> checkProStatus() async {
  if (_isProChecking) return;
  _isProChecking = true;

  final iap = InAppPurchase.instance;
  final prefs = await SharedPreferences.getInstance();

  if (!await iap.isAvailable()) {
    _isProChecking = false;
    return;
  }

  // Initial Sync from local storage
  ProStatus.isPro = prefs.getBool("isProUser") ?? false;
  debugPrint("✅ ProStatus.isPro = ${ProStatus.isPro}");
  // await iap.restorePurchases();
  iap.purchaseStream.listen((purchases) async {
    // 1. FILTER: We only look for 'purchased' or 'restored' items that match our IDs
    bool hasActivePro = purchases.any((purchase) =>
    (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) &&
        (purchase.productID == "pro_monthly" ||
            purchase.productID == "pro_yearly" ||
            purchase.productID == "refund_tracker_pro"));

    // 2. HANDLE EXPIRATION / REVOCATION
    if (hasActivePro) {
      if (!ProStatus.isPro) {
        await prefs.setBool("isProUser", true);
        ProStatus.isPro = true;
        debugPrint("Subscription Verified: User is PRO ✅");
      }
    } else {
      // IF THE STORE RETURNS NOTHING: It means the sub is expired, cancelled, or refunded
      if (ProStatus.isPro) {
        await prefs.setBool("isProUser", false);
        ProStatus.isPro = false;
        debugPrint("Subscription Expired: Reverting to FREE ❌");
      }
    }

    for (final purchase in purchases) {
      if (purchase.pendingCompletePurchase) {
        await iap.completePurchase(purchase);
      }
    }
  });

  try {
    // This forces the App Store to tell us the CURRENT state of ownership
    await iap.restorePurchases();
  } catch (e) {
    debugPrint("Restore error: $e");
    _isProChecking = false;
  }
}

Future<void> debugHardReset() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear(); // Wipes EVERYTHING local
  ProStatus.isPro = false;
  debugPrint("🚨 APP HARD RESET: User is now FREE.");
}

void main() async {
  // --- NATIVE SPLASH: PRESERVE LOGIC START ---

  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // --- NATIVE SPLASH: PRESERVE LOGIC END ---

  // --- ADDED: REQUIRED FOR NOTIFICATIONS TO WORK ---

  tz.initializeTimeZones();
  debugHardReset();
  final prefs = await SharedPreferences.getInstance();
  ProStatus.isPro = prefs.getBool("isProUser") ?? false;

  checkProStatus();

  // --- 9.2 RULE: NAVIGATE DIRECTLY TO RECEIPT DETAIL SCREEN ON TAP ---
  await NotificationService().init((String? payload) async {
    if (payload != null) {
      final dbReceipts = await DatabaseService().getReceipts();
      final receiptData = dbReceipts.firstWhere(
            (r) => r['id'].hashCode.toString() == payload || r['id'].toString() == payload,
        orElse: () => {},
      );

      if (receiptData.isNotEmpty) {
        // Wait 1.2s to ensure the engine is ready
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (navigatorKey.currentState != null) {
            // YE FIX HAI: Pehle HomeScreen load hogi, phir uske upar Detail aayegi
            // Is se back button list par wapas le jayega
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const RefundListScreen()),
                  (route) => false,
            );
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (context) => ReceiptDetailScreen(receipt: receiptData)),
            );
          }
        });
      }
    }
  });
  // --- FIX: CHECK IF APP WAS OPENED FROM KILL STATE BY NOTIFICATION ---
  final NotificationAppLaunchDetails? launchDetails =
  await NotificationService().flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

  if (launchDetails?.didNotificationLaunchApp ?? false) {
    String? payload = launchDetails?.notificationResponse?.payload;
    if (payload != null) {
      final dbReceipts = await DatabaseService().getReceipts();
      final receiptData = dbReceipts.firstWhere(
            (r) => r['id'].hashCode.toString() == payload || r['id'].toString() == payload,
        orElse: () => {},
      );
      if (receiptData.isNotEmpty) {
        notificationReceipt = receiptData;
      }
    }
  }

  // --- 8.3 ANDROID PERMISSION REQUEST (Android 13, 14+) ---
  final dynamic androidPlugin = NotificationService()
      .flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  // 1. Request Normal Notification Permission
  await androidPlugin?.requestNotificationsPermission();

  // 2. SPECIAL FIX FOR SAMSUNG/PIXEL: Exact Alarm Check
  if (Platform.isAndroid) {
    // Check if the permission is available for this version of the plugin
    try {
      final bool isAllowed = await androidPlugin?.canScheduleExactAlarms() ?? true;

      if (!isAllowed) {
        // User ko settings screen par le jayega
        await androidPlugin?.requestExactAlarmsPermission();
      }
    } catch (e) {
      // Agar purana version hai aur method nahi mil raha, toh safe exit
      debugPrint("Exact Alarms not supported or already handled: $e");
    }
  }

  // --- 8.2 RULE: RESCHEDULE ALL NOTIFICATIONS ON APP LAUNCH ---
  // FIXED: Added a 2-second delay to ensure DB and Permissions are ready
  Future.delayed(const Duration(seconds: 2), () async {
    // Kill existing notifications to avoid duplicates and fix background sync
    await NotificationService().flutterLocalNotificationsPlugin.cancelAll();

    final dbReceipts = await DatabaseService().getReceipts();

    for (var r in dbReceipts) {
      final deadline = DateTime.parse(r['refundDeadline']);
      final store = r['storeName'].toString();
      final amount = double.tryParse(r['amount'].toString()) ?? 0.0;
      final baseId = r['id'].hashCode.abs();

      // Ensure notification is only scheduled for future dates
      if (deadline.isAfter(DateTime.now())) {
        await NotificationService().scheduleSmartReminders(
          receiptId: baseId,
          storeName: store,
          amount: amount,
          deadline: deadline,
        );
      }
    }
  });
  // Check if user has seen onboarding
  // final prefs = await SharedPreferences.getInstance();
  final bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

  // Native Splash removal happens here if needed, or inside screens
  FlutterNativeSplash.remove();
  runApp(MyApp(showOnboarding: !hasSeenOnboarding));
}

class MyApp extends StatelessWidget {
  final bool showOnboarding;

  const MyApp({super.key, required this.showOnboarding});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // --- 9.2: ATTACHED KEY FOR DEEP LINKING ---
      debugShowCheckedModeBanner: false,
      title: 'OCR APP',
      // --- UPDATED: GLOBAL BLACK AND BLUE THEME ---
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.blue),
          titleTextStyle: TextStyle(color: Colors.blue, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blue,
          onPrimary: Colors.white,
          secondary: Colors.blueAccent,
          surface: Colors.black,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        useMaterial3: true,
      ),
      // --- UPDATED FIX FOR CRASH: Handles back button correctly for OCR ---
      builder: (context, child) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            final NavigatorState? nav = navigatorKey.currentState;

            // FIX: If there is a screen to go back to, go back.
            // This prevents the "null" crash on the OCR screen.
            if (nav != null && nav.canPop()) {
              nav.maybePop();
            } else {
              final now = DateTime.now();
              if (_lastPressedAt == null ||
                  now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
                _lastPressedAt = now;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Press back again to exit"),
                    backgroundColor: Colors.white,
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                SystemNavigator.pop();
              }
            }
          },
          child: child!,
        );
      },
      // --- IF/ELSE LOGIC ADDED HERE AS REQUESTED ---
    //   home: notificationReceipt != null
    //       ? ReceiptDetailScreen(receipt: notificationReceipt!)
    //       : (showOnboarding ? const OnboardingScreen() : const OnboardingScreen()),
    // );
        home: notificationReceipt != null
            ? ReceiptDetailScreen(receipt: notificationReceipt!)
            : (showOnboarding
            ? const OnboardingScreen()
            : const RefundListScreen()),);
  }
}