// import 'package:flutter/material.dart';
// import 'home_screen.dart';
// import 'ocr_screen.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';
// import 'refund_list_screen.dart';
//
// class MainWrapper extends StatefulWidget {
//   const MainWrapper({super.key});
//
//   @override
//   State<MainWrapper> createState() => _MainWrapperState();
// }
//
// class _MainWrapperState extends State<MainWrapper> {
//   // --- ADDED: HIDE SPLASH SCREEN ON LOAD ---
//   @override
//   void initState() {
//     super.initState();
//     FlutterNativeSplash.remove();
//   }
//
//   int _selectedIndex = 0;
//
//   // The two tabs: My Refunds and Scan
//   final List<Widget> _pages = [
//     const OcrScreen(),
//     const RefundListScreen(),
//   ];
//
//   void _onItemTapped(int index) {
//     setState(() {
//       _selectedIndex = index;
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: IndexedStack(
//         index: _selectedIndex,
//         children: _pages,
//       ),
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: _selectedIndex,
//         onTap: _onItemTapped,
//         selectedItemColor: Colors.blue,
//         unselectedItemColor: Colors.grey,
//         items: const [
//           BottomNavigationBarItem(
//             icon: Icon(Icons.receipt_long),
//             label: 'My Refunds',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.camera_alt),
//             label: 'Scan',
//           ),
//         ],
//       ),
//     );
//   }
// }