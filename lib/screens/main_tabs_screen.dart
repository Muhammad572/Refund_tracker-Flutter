// import 'package:flutter/material.dart';
// import 'ocr_screen.dart';
// import 'refund_list_screen.dart';
//
// class MainTabsScreen extends StatefulWidget {
//   const MainTabsScreen({super.key});
//
//   @override
//   State<MainTabsScreen> createState() => _MainTabsScreenState();
// }
//
// class _MainTabsScreenState extends State<MainTabsScreen> {
//
//   int _currentIndex = 1;
//
//   final List<Widget> _pages = const [
//     OcrScreen(),
//     RefundListScreen(),
//   ];
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//
//       // ⭐ IMPORTANT
//       body: IndexedStack(
//         index: _currentIndex,
//         children: _pages,
//       ),
//
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: _currentIndex,
//         type: BottomNavigationBarType.fixed,
//         onTap: (index) {
//           setState(() {
//             _currentIndex = index;
//           });
//         },
//         items: const [
//           BottomNavigationBarItem(
//             icon: Icon(Icons.camera_alt),
//             label: "Scan",
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.receipt_long),
//             label: "List Refunds",
//           ),
//         ],
//       ),
//     );
//   }
// }