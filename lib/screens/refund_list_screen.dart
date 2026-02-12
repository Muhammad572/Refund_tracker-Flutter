import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import 'ocr_screen.dart';
import 'receipt_detail_screen.dart';
import '../models/receipt_model.dart';

class RefundListScreen extends StatefulWidget {
  const RefundListScreen({super.key});

  @override
  State<RefundListScreen> createState() => _RefundListScreenState();
}

class _RefundListScreenState extends State<RefundListScreen> {
  late Future<List<Map<String, dynamic>>> _receipts;

  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      NotificationService().flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _refresh();
  }

  void _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  void _initNotifications() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // This handles clicking the notification
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'refund_channel',
      'Refund Reminders',
      description: 'Critical refund deadline alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _refresh() {
    setState(() {
      _receipts = DatabaseService().getReceipts().then((list) {
        List<Map<String, dynamic>> sortedList = List.from(list);

        sortedList.sort((a, b) {
          DateTime dateA = DateTime.parse(a['refundDeadline']);
          DateTime dateB = DateTime.parse(b['refundDeadline']);
          DateTime now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          int getPriority(DateTime deadline) {
            final deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
            final diff = deadlineDate.difference(today).inDays;

            if (deadlineDate.isBefore(today) || deadlineDate.isAtSameMomentAs(today)) return 3;
            if (diff <= 7) return 1;
            return 2;
          }

          int priorityA = getPriority(dateA);
          int priorityB = getPriority(dateB);

          if (priorityA != priorityB) {
            return priorityA.compareTo(priorityB);
          } else {
            return dateA.compareTo(dateB);
          }
        });

        for (var receipt in sortedList) {
          _scheduleNotification(receipt);
        }

        setState(() {
          _allData = sortedList;
          _filteredData = sortedList;
        });

        return sortedList;
      });
    });
  }

  void _scheduleNotification(Map<String, dynamic> receipt) async {
    final deadline = DateTime.parse(receipt['refundDeadline']);
    final store = receipt['storeName'].toString();
    final amount = double.tryParse(receipt['amount'].toString()) ?? 0.0;
    final baseId = receipt['id'].hashCode.abs();

    // --- REPLACED OLD 7/2 DAY LOGIC WITH SMART REMINDERS ---
    await NotificationService().scheduleSmartReminders(
      receiptId: baseId,
      storeName: store,
      amount: amount,
      deadline: deadline,
    );
  }

  void _runFilter(String enteredKeyword) {
    setState(() {
      if (enteredKeyword.isEmpty) {
        _filteredData = _allData;
      } else {
        _filteredData = _allData
            .where((receipt) => receipt['storeName']
            .toString()
            .toLowerCase()
            .contains(enteredKeyword.toLowerCase()))
            .toList();
      }
    });
  }

  Color _getStatusColor(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
    final difference = deadlineDate.difference(today).inDays;

    if (deadlineDate.isBefore(today) || deadlineDate.isAtSameMomentAs(today)) {
      return Colors.red;
    } else if (difference <= 7) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  String _getStatusLabel(DateTime deadline) {
    final now = DateTime.now();
    final deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
    final difference = deadlineDate.difference(DateTime(now.year, now.month, now.day)).inDays;

    if (deadlineDate.isBefore(DateTime(now.year, now.month, now.day)) ||
        deadlineDate.isAtSameMomentAs(DateTime(now.year, now.month, now.day))) return "Expired";
    if (difference <= 7) return "Expiring Soon";
    return "Active";
  }

  String _getDaysText(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
    final difference = deadlineDate.difference(today).inDays;

    if (deadlineDate.isBefore(today)) return "Past";
    if (deadlineDate.isAtSameMomentAs(today)) return "Today";
    return "$difference Days";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search store name...',
              border: InputBorder.none,
            ),
            onChanged: (value) => _runFilter(value),
          )
              : const Text("My Refunds"),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _filteredData = _allData;
                  }
                });
              },
            )
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _receipts,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final displayList = _isSearching ? _filteredData : snapshot.data!;
            if (displayList.isEmpty) return const Center(child: Text("No receipts found."));

            return ListView.builder(
              itemCount: displayList.length,
              itemBuilder: (context, i) {
                final data = displayList[i];
                final deadline = DateTime.parse(data['refundDeadline']);
                final statusColor = _getStatusColor(deadline);
                final statusLabel = _getStatusLabel(deadline);
                final daysRemainingText = _getDaysText(deadline);

                return Dismissible(
                  key: Key(data['id']),
                  background: Container(
                    color: Colors.blue,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.edit, color: Colors.white),
                  ),
                  secondaryBackground: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OcrScreen(
                            existingReceipt: Receipt(
                              id: data['id'],
                              storeName: data['storeName'],
                              amount: data['amount'],
                              purchaseDate: DateTime.parse(data['purchaseDate']),
                              refundDeadline: DateTime.parse(data['refundDeadline']),
                              imagePath: data['imagePath'],
                              fullText: data['fullText'],
                              notes: data['notes'],
                              category: data['category'] ?? "General",
                            ),
                          ),
                        ),
                      ).then((_) => _refresh());
                      return false;
                    } else {
                      return await showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Confirm Delete"),
                          content: const Text("Delete this receipt permanently?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
                          ],
                        ),
                      );
                    }
                  },
                  onDismissed: (direction) async {
                    if (direction == DismissDirection.endToStart) {
                      await DatabaseService().deleteReceipt(data['id']);
                      _refresh();
                    }
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReceiptDetailScreen(receipt: data),
                          ),
                        ).then((_) => _refresh());
                      },
                      child: ListTile(
                        leading: data['imagePath'] != ""
                            ? Image.file(File(data['imagePath']), width: 50, height: 50, fit: BoxFit.cover)
                            : const Icon(Icons.receipt),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                data['storeName'],
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text("\$${data['amount']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: statusColor, width: 1),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              daysRemainingText,
                              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Confirm Delete"),
                                    content: const Text("Delete this receipt permanently?"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await DatabaseService().deleteReceipt(data['id']);
                                  _refresh();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: "addBtn",
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OcrScreen())
              ).then((_) => _refresh()),
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}