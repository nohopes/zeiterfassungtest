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

  // GlobalKey statt const-Liste, damit wir den Monats-Screen von außen zum
  // Neuladen anstoßen können (siehe _onDestinationSelected).
  final _monthKey = GlobalKey<MonthOverviewScreenState>();

  late final List<Widget> _screens = [
    const HomeScreen(),
    MonthOverviewScreen(key: _monthKey),
    const SearchScreen(),
  ];

  void _onDestinationSelected(int i) {
    setState(() => _index = i);
    if (i == 1) {
      // Beim Wechsel auf "Monat" neu laden - IndexedStack hält den Screen
      // dauerhaft am Leben, er bekäme neue Einträge aus anderen Tabs sonst
      // erst nach einem App-Neustart mit.
      _monthKey.currentState?.reload();
    }
  }

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
        onDestinationSelected: _onDestinationSelected,
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
