import 'package:flutter/material.dart';

import '../core/router/app_router.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
  });

  final int currentIndex;

  static const List<String> _routes = <String>[
    AppRoutes.dashboard,
    AppRoutes.watch,
    AppRoutes.ema,
    AppRoutes.sleep,
    AppRoutes.history,
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      onDestinationSelected: (index) => _open(context, index),
      destinations: const <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.sensors_outlined),
          selectedIcon: Icon(Icons.sensors_rounded),
          label: 'Live',
        ),
        NavigationDestination(
          icon: Icon(Icons.add_circle_outline_rounded),
          selectedIcon: Icon(Icons.add_circle_rounded),
          label: 'Check-in',
        ),
        NavigationDestination(
          icon: Icon(Icons.bedtime_outlined),
          selectedIcon: Icon(Icons.bedtime_rounded),
          label: 'Sleep',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history_rounded),
          label: 'History',
        ),
      ],
    );
  }

  void _open(BuildContext context, int index) {
    if (index == currentIndex) return;
    final navigator = Navigator.of(context);
    final route = _routes[index];

    if (route == AppRoutes.dashboard) {
      navigator.pushNamedAndRemoveUntil(route, (candidate) => false);
      return;
    }

    navigator.pushNamedAndRemoveUntil(
      route,
      (candidate) => candidate.settings.name == AppRoutes.dashboard,
    );
  }
}
