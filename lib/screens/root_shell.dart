import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'month_overview_screen.dart';
import 'search_screen.dart';

/// Äußerer App-Rahmen mit Bottom-Navigation für schnellen Wechsel
/// zwischen Tagesansicht, Monatsübersicht und Suche.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    MonthOverviewScreen(),
    SearchScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack hält alle drei Screens "am Leben" - beim Wechseln
      // gehen z. B. Sucheingabe oder das gewählte Datum nicht verloren.
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Tag',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Monat',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Suche',
          ),
        ],
      ),
    );
  }
}
