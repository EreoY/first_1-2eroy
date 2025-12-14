import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat/chat_landing_screen.dart'; // Import ChatLandingScreen
import 'tabs/history_tab.dart';
import 'tabs/settings_tab.dart';
import '../providers/app_global_provider.dart';
import '../services/slip_scanner_service.dart';
import '../services/database_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();

    _tabs = [
      const ChatLandingScreen(),
      const HistoryTab(),
      const SettingsTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool showAppBar = _currentIndex == 2; // Only for Settings
    final appProvider = context.watch<AppGlobalProvider>();

    return Scaffold(
      appBar: showAppBar ? AppBar(
        title: const Text('AI Expense Tracker'),
        elevation: 0,
        centerTitle: true,
      ) : null,
      body: Column(
        children: [
          Expanded(child: _tabs[_currentIndex]),
          

        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart_outline),
            activeIcon: Icon(Icons.pie_chart),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _importSlips(List<SlipData> slips) async {
    final db = DatabaseService();
    int count = 0;
    
    for (final slip in slips) {
      await db.addTransaction(
        slip.bank, // Use bank name as item/note
        slip.amount,
        category: 'Transfer', // Default category
        qty: 1.0,
      );
      count++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Imported $count slips successfully!")),
      );
      setState(() {}); 
    }
  }
}
