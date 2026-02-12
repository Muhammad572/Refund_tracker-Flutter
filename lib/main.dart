import 'package:flutter/material.dart';
import 'dart:io'; // Added for exit(0)
import 'package:flutter/services.dart'; // Added for SystemNavigator
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_wrapper.dart';
import 'services/database_service.dart'; // Added for rescheduling logic
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Added for permission check
import 'screens/receipt_detail_screen.dart'; // Required for navigation
import 'package:timezone/timezone.dart' as tz; // Added for timezone support
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_native_splash/flutter_native_splash.dart';

// --- 9.2: GLOBAL NAVIGATOR KEY ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Variable to track back button timing globally
DateTime? _lastPressedAt;

// ADDED: This tracks if we should show detail screen directly
Map<String, dynamic>? notificationReceipt;

void main() async {
  // --- NATIVE SPLASH: PRESERVE LOGIC START ---
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // --- NATIVE SPLASH: PRESERVE LOGIC END ---

  // --- ADDED: REQUIRED FOR NOTIFICATIONS TO WORK ---
  tz.initializeTimeZones();

  // --- 9.2 RULE: NAVIGATE DIRECTLY TO RECEIPT DETAIL SCREEN ON TAP ---
  await NotificationService().init((String? payload) async {
    if (payload != null) {
      final dbReceipts = await DatabaseService().getReceipts();
      // Find the specific receipt using the ID from the payload
      final receiptData = dbReceipts.firstWhere(
            (r) => r['id'].hashCode.toString() == payload || r['id'].toString() == payload,
        orElse: () => {},
      );

      if (receiptData.isNotEmpty) {
        // Store for if/else logic
        notificationReceipt = receiptData;

        // Push logic for background state
        Future.delayed(const Duration(milliseconds: 1200), () async {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => ReceiptDetailScreen(receipt: receiptData),
            ),
          );
        });
      }
    }
  });

  // --- 8.3 ANDROID PERMISSION REQUEST (Android 13+) ---
  await NotificationService()
      .flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  // --- 8.2 RULE: RESCHEDULE ALL NOTIFICATIONS ON APP LAUNCH ---
  // FIXED: Added a 2-second delay and a cancelAll() to stop duplicate spam and Realme crashes
  Future.delayed(const Duration(seconds: 2), () async {
    await NotificationService().flutterLocalNotificationsPlugin.cancelAll();

    final dbReceipts = await DatabaseService().getReceipts();
    final now = DateTime.now();

    for (var r in dbReceipts) {
      final deadline = DateTime.parse(r['refundDeadline']);
      final store = r['storeName'].toString();
      final amount = double.tryParse(r['amount'].toString()) ?? 0.0; // Keep as double for smart service
      final baseId = r['id'].hashCode.abs();

      // --- FIXED: Replaced manual 7/2 day scheduling with the Smart Reminder Call ---
      await NotificationService().scheduleSmartReminders(
        receiptId: baseId,
        storeName: store,
        amount: amount,
        deadline: deadline,
      );
    }
  });

  // Check if user has seen onboarding
  final prefs = await SharedPreferences.getInstance();
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
      home: notificationReceipt != null
          ? ReceiptDetailScreen(receipt: notificationReceipt!)
          : (showOnboarding ? const OnboardingScreen() : const MainWrapper()),
    );
  }
}