import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_bottom_navigation.dart';

class ClientBottomNavigation extends StatelessWidget {
  const ClientBottomNavigation({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return AppBottomNavigation(
      currentIndex: currentIndex,
      onTap: (index) {
        if (index == currentIndex) return;
        switch (index) {
          case 0: context.go('/harita');
          case 1: context.go('/kesfet');
          case 2: context.go('/taleplerim');
          case 3: context.go('/profil');
        }
      },
      items: const [
        AppBottomNavigationItem(label: 'Ana Sayfa', icon: Icons.home_outlined, selectedIcon: Icons.home),
        AppBottomNavigationItem(label: 'Keşfet', icon: Icons.explore_outlined, selectedIcon: Icons.explore),
        AppBottomNavigationItem(label: 'Randevular', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month),
        AppBottomNavigationItem(label: 'Profil', icon: Icons.person_outlined, selectedIcon: Icons.person),
      ],
    );
  }
}
