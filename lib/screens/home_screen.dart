// import 'package:flutter/material.dart';
// import '../services/database_service.dart';
// import 'ocr_screen.dart';
// import 'receipt_detail_screen.dart'; // Added this import
// import '../services/notification_service.dart'; // Added for rescheduling logic
//
// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});
//
//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }
//
// class _HomeScreenState extends State<HomeScreen> {
//   List<Map<String, dynamic>> _receipts = [];
//
//   @override
//   void initState() {
//     super.initState();
//     _refreshReceipts(); // Load data when app opens
//   }
//
//   Future<void> _refreshReceipts() async {
//     final data = await DatabaseService().getReceipts();
//
//     // --- RULE: RESCHEDULE ALL NOTIFICATIONS ON APP LAUNCH ---
//     for (var r in data) {
//       NotificationService().scheduleNotification(
//         r['id'].hashCode,
//         r['storeName'],
//         r['amount'],
//         DateTime.parse(r['refundDeadline']),
//       );
//     }
//     // --- END OF RESCHEDULE RULE ---
//
//     setState(() {
//       _receipts = data;
//     });
//   }
//
//   String _getRemainingTime(String deadlineStr) {
//     final deadline = DateTime.parse(deadlineStr);
//     final now = DateTime.now();
//     final difference = deadline.difference(now);
//
//     if (difference.isNegative) {
//       return "Expired";
//     } else if (difference.inDays > 0) {
//       return "${difference.inDays} Days";
//     } else if (difference.inHours > 0) {
//       return "${difference.inHours} Hours";
//     } else {
//       return "${difference.inMinutes} Mins";
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("My Refund Tracker")),
//       body: _receipts.isEmpty
//           ? const Center(child: Text("No receipts saved yet!"))
//           : ListView.builder(
//         itemCount: _receipts.length,
//         itemBuilder: (context, index) {
//           final item = _receipts[index];
//           final timeLeft = _getRemainingTime(item['refundDeadline']);
//
//           return Card(
//             margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
//             child: ListTile(
//               // --- ADDED ONTAP HERE ---
//               onTap: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) => ReceiptDetailScreen(receipt: item),
//                   ),
//                 );
//               },
//               // --- END OF ADDITION ---
//               leading: const Icon(Icons.receipt_long, size: 40, color: Colors.blue),
//               title: Text(item['storeName'], style: const TextStyle(fontWeight: FontWeight.bold)),
//               subtitle: Text("Amount: \$${item['amount']}"),
//               // --- ONLY CHANGE IS HERE: Added Wrap to hold both Days and Delete ---
//               trailing: Wrap(
//                 spacing: 8,
//                 crossAxisAlignment: WrapCrossAlignment.center,
//                 children: [
//                   Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Text(
//                         "$timeLeft Days",
//                         style: TextStyle(
//                           color: timeLeft == "will Expire" ? Colors.orange : Colors.green,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       const Text("Left", style: TextStyle(fontSize: 10)),
//                     ],
//                   ),
//                   IconButton(
//                     icon: const Icon(Icons.delete, color: Colors.redAccent),
//                     onPressed: () {
//                       // Confirmation Box logic starts here
//                       showDialog(
//                         context: context,
//                         builder: (context) => AlertDialog(
//                           title: const Text("Delete Receipt?"),
//                           content: const Text("This will permanently remove this record."),
//                           actions: [
//                             TextButton(
//                               onPressed: () => Navigator.pop(context),
//                               child: const Text("CANCEL"),
//                             ),
//                             TextButton(
//                               onPressed: () async {
//                                 await DatabaseService().deleteReceipt(item['id']);
//                                 _refreshReceipts();
//                                 if (context.mounted) Navigator.pop(context);
//                               },
//                               child: const Text("DELETE", style: TextStyle(color: Colors.red)),
//                             ),
//                           ],
//                         ),
//                       );
//                     },
//                   ),
//                 ],
//               ),
//               // --- END OF CHANGE ---
//             ),
//           );
//         },
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () async {
//           // Go to Scanner and refresh list when coming back
//           await Navigator.push(
//             context,
//             MaterialPageRoute(builder: (context) => const OcrScreen()),
//           );
//           _refreshReceipts();
//         },
//         child: const Icon(Icons.add_a_photo),
//       ),
//     );
//   }
// }