import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/models.dart';
import '../../presentation/providers/providers.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/inventory/inventory_screen.dart';
import '../../presentation/screens/inventory/add_edit_inventory_screen.dart';
import '../../presentation/screens/sales/sales_screen.dart';
import '../../presentation/screens/sales/add_sale_screen.dart';
import '../../presentation/screens/sales/sale_detail_screen.dart';
import '../../presentation/screens/customers/customers_screen.dart';
import '../../presentation/screens/customers/customer_detail_screen.dart';
import '../../presentation/screens/reports/reports_screen.dart';
import '../../presentation/screens/users/users_screen.dart';
import '../widgets/main_scaffold.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isLoggedIn = authState.when(
        data: (user) => user != null,
        loading: () => false,
        error: (_, __) => false,
      );

      final isAuthRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const InventoryScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) =>
                    const AddEditInventoryScreen(),
              ),
              GoRoute(
                path: 'edit/:id',
                builder: (context, state) => AddEditInventoryScreen(
                  inventoryId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) => const SalesScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) => const AddSaleScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => SaleDetailScreen(
                  saleId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomersScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => CustomerDetailScreen(
                  customerId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/users',
            builder: (context, state) => const UsersScreen(),
          ),
        ],
      ),
    ],
  );
});

// ─── Main Scaffold ────────────────────────────────────────────────────────────

// ignore: library_private_types_in_public_api
class MainScaffoldWidget extends ConsumerStatefulWidget {
  final Widget child;
  const MainScaffoldWidget({super.key, required this.child});
  @override
  _MainScaffoldWidgetState createState() => _MainScaffoldWidgetState();
}

class _MainScaffoldWidgetState extends ConsumerState<MainScaffoldWidget> {
  @override
  Widget build(BuildContext context) => widget.child;
}
