import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init(Function(String?) onSelectNotification) async {
    tz_data.initializeTimeZones();

    // Setup local timezone for background survival
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.cancelAll();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        onSelectNotification(response.payload);
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'refund_channel',
      'Refund Reminders',
      description: 'Reminders for refund deadlines',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> scheduleSmartReminders({
    required int receiptId,
    required String storeName,
    required double amount,
    required DateTime deadline,
  }) async {
    final now = DateTime.now();

    // 1. RULE: DEADLINE TOMORROW (24 hours before)
    final date1DayBefore = deadline.subtract(const Duration(days: 1));
    if (date1DayBefore.isAfter(now)) {
      await scheduleNotification(
          receiptId + 1000,
          "Deadline Tomorrow!",
          "Last chance for $storeName • \$${amount.toStringAsFixed(2)}",
          date1DayBefore,
          payload: receiptId.toString() // ADDED PAYLOAD
      );
    }

    // 2. RULE: 1 HOUR BEFORE EXPIRE
    final oneHourBefore = deadline.subtract(const Duration(hours: 1));
    if (oneHourBefore.isAfter(now)) {
      await scheduleNotification(
          receiptId + 500, // Unique ID for 1 hour warning
          "Expires in 1 Hour!",
          "Your return for $storeName expires very soon.",
          oneHourBefore,
          payload: receiptId.toString() // ADDED PAYLOAD
      );
    }

    // Always schedule a notification for the exact deadline time if it is in the future
    if (deadline.isAfter(now)) {
      await scheduleNotification(
          receiptId,
          "Refund Deadline: EXPIRED",
          "The deadline for $storeName has reached.",
          deadline,
          payload: receiptId.toString() // ADDED PAYLOAD
      );
    }
  }

  Future<void> scheduleNotification(int id, String title, String bodyText, DateTime fireDate, {String? payload}) async {

    // REMOVED 9:00 AM RULE - Uses exact time now
    final scheduledTime = tz.TZDateTime.from(fireDate, tz.local);

    if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) return;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      bodyText,
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'refund_channel',
          'Refund Reminders',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          // --- FIXED: Removed non-existent presentAlert/Sound/Badge ---
          // Android handles these via the "Importance" level set above
        ),
      ),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload ?? id.toString(),
    );
  }

  // --- ADDED THIS METHOD TO SOLVE YOUR ERROR ---
  Future<void> scheduleSingleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    // Only schedule if the date is in the future
    if (scheduledDate.isBefore(DateTime.now())) return;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'refund_channel', // Changed to match your existing channel ID
          'Refund Reminders',
          importance: Importance.max,
          priority: Priority.high,
          // --- FIXED: Removed non-existent presentAlert ---
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false, // This is still correct for iOS
          presentSound: true,
          presentBadge: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      payload: id.toString(), // ADDED: Required to open the specific receipt on click
    );
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    await flutterLocalNotificationsPlugin.cancel(id + 7000);
    await flutterLocalNotificationsPlugin.cancel(id + 2000);
    await flutterLocalNotificationsPlugin.cancel(id + 1000);
    await flutterLocalNotificationsPlugin.cancel(id + 500); // Cancel the 1-hour warning too
  }
}