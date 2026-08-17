import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/providers/providers.dart';
import '../../core/constants/app_constants.dart';

class MainScaffold extends ConsumerWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  static const _navItems = [
    _NavItem('/dashboard', Icons.dashboard_rounded, Icons.dashboard_outlined,
        AppStrings.dashboard),
    _NavItem('/inventory', Icons.inventory_2_rounded,
        Icons.inventory_2_outlined, AppStrings.inventory),
    _NavItem('/sales', Icons.point_of_sale_rounded,
        Icons.point_of_sale_outlined, AppStrings.sales),
    _NavItem('/customers', Icons.people_rounded, Icons.people_outline_rounded,
        AppStrings.customers),
    _NavItem('/reports', Icons.bar_chart_rounded, Icons.bar_chart_outlined,
        AppStrings.reports),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final userAsync = ref.watch(currentUserProvider);
    final isAdmin =
        userAsync.when(data: (u) => u?.isAdmin ?? false, loading: () => false, error: (_, __) => false);

    int currentIndex = _navItems.indexWhere(
        (item) => location.startsWith(item.path));
    if (currentIndex < 0) currentIndex = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          context.go(_navItems[index].path);
        },
        destinations: [
          ..._navItems.map((item) => NavigationDestination(
                icon: Icon(item.inactiveIcon),
                selectedIcon: Icon(item.activeIcon),
                label: item.label,
              )),
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings_rounded),
              label: AppStrings.users,
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String path;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  const _NavItem(this.path, this.activeIcon, this.inactiveIcon, this.label);
}
