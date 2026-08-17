import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/models/models.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/inventory_service.dart';
import '../../data/services/sales_service.dart';
import '../../data/services/customer_service.dart';

// ─── Services ────────────────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final inventoryServiceProvider =
    Provider<InventoryService>((ref) => InventoryService());
final salesServiceProvider =
    Provider<SalesService>((ref) => SalesService());
final customerServiceProvider =
    Provider<CustomerService>((ref) => CustomerService());

// ─── Auth State ──────────────────────────────────────────────────────────────

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.when(
    data: (u) => u,
    loading: () => null,
    error: (_, __) => null,
  );
  if (user == null) return null;
  return ref.watch(authServiceProvider).getUserData(user.uid);
});

// ─── Inventory ───────────────────────────────────────────────────────────────

final inventorySearchProvider = StateProvider<String>((ref) => '');

final inventoryStreamProvider = StreamProvider<List<InventoryModel>>((ref) {
  final search = ref.watch(inventorySearchProvider);
  return ref
      .watch(inventoryServiceProvider)
      .getInventoryStream(searchQuery: search.isEmpty ? null : search);
});

final lowStockStreamProvider = StreamProvider<List<InventoryModel>>((ref) {
  return ref.watch(inventoryServiceProvider).getLowStockStream();
});

final inventoryStatsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  return ref.watch(inventoryServiceProvider).getInventoryStats();
});

// ─── Sales ───────────────────────────────────────────────────────────────────

final saleFiltersProvider =
    StateProvider<SaleFilters>((ref) => const SaleFilters());

final salesStreamProvider = StreamProvider<List<SaleModel>>((ref) {
  final filters = ref.watch(saleFiltersProvider);
  return ref
      .watch(salesServiceProvider)
      .getSalesStream(filters.hasFilters ? filters : null);
});

final dashboardStatsProvider =
    FutureProvider<DashboardStats>((ref) async {
  return ref.watch(salesServiceProvider).getDashboardStats();
});

// ─── Customers ───────────────────────────────────────────────────────────────

final customerSearchProvider = StateProvider<String>((ref) => '');

final customersStreamProvider = StreamProvider<List<CustomerModel>>((ref) {
  final search = ref.watch(customerSearchProvider);
  return ref
      .watch(customerServiceProvider)
      .getCustomersStream(searchQuery: search.isEmpty ? null : search);
});

final pendingCustomersProvider = StreamProvider<List<CustomerModel>>((ref) {
  return ref.watch(customerServiceProvider).getPendingCustomersStream();
});

final allCustomersProvider =
    FutureProvider<List<CustomerModel>>((ref) async {
  return ref.watch(customerServiceProvider).getAllCustomers();
});

// ─── Users ───────────────────────────────────────────────────────────────────

final usersStreamProvider = StreamProvider<List<UserModel>>((ref) {
  return ref.watch(authServiceProvider).getAllUsers();
});

// ─── Reports ─────────────────────────────────────────────────────────────────

final reportPeriodProvider = StateProvider<ReportPeriod>(
    (ref) => ReportPeriod.monthly);

final reportDateRangeProvider = StateProvider<DateRange>((ref) {
  final now = DateTime.now();
  return DateRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
});

final salesReportProvider =
    FutureProvider.autoDispose<SalesReport>((ref) async {
  final range = ref.watch(reportDateRangeProvider);
  return ref
      .watch(salesServiceProvider)
      .getSalesReport(range.start, range.end);
});

// ─── Theme ───────────────────────────────────────────────────────────────────

final themeProvider = StateProvider<bool>((ref) => false); // false = light

// ─── Cart (for new sale) ─────────────────────────────────────────────────────

final cartProvider =
    StateNotifierProvider<CartNotifier, List<SaleItemModel>>(
        (ref) => CartNotifier());

class CartNotifier extends StateNotifier<List<SaleItemModel>> {
  CartNotifier() : super([]);

  void addItem(SaleItemModel item) {
    // Check if same item already in cart
    final index = state.indexWhere(
        (i) => i.inventoryId == item.inventoryId);
    if (index >= 0) {
      final updated = List<SaleItemModel>.from(state);
      final existing = updated[index];
      updated[index] = SaleItemModel(
        inventoryId: existing.inventoryId,
        brand: existing.brand,
        productName: existing.productName,
        size: existing.size,
        quantity: existing.quantity + item.quantity,
        priceAtSale: item.priceAtSale,
      );
      state = updated;
    } else {
      state = [...state, item];
    }
  }

  void removeItem(String inventoryId) {
    state = state.where((i) => i.inventoryId != inventoryId).toList();
  }

  void updateQuantity(String inventoryId, int quantity) {
    state = state.map((i) {
      if (i.inventoryId == inventoryId) {
        return SaleItemModel(
          inventoryId: i.inventoryId,
          brand: i.brand,
          productName: i.productName,
          size: i.size,
          quantity: quantity,
          priceAtSale: i.priceAtSale,
        );
      }
      return i;
    }).toList();
  }

  void updatePrice(String inventoryId, double price) {
    state = state.map((i) {
      if (i.inventoryId == inventoryId) {
        return SaleItemModel(
          inventoryId: i.inventoryId,
          brand: i.brand,
          productName: i.productName,
          size: i.size,
          quantity: i.quantity,
          priceAtSale: price,
        );
      }
      return i;
    }).toList();
  }

  void clear() => state = [];

  double get total =>
      state.fold(0, (sum, item) => sum + item.totalPrice);
}

// ─── Helper Models ───────────────────────────────────────────────────────────

enum ReportPeriod { daily, weekly, monthly, custom }

class DateRange {
  final DateTime start;
  final DateTime end;
  DateRange({required this.start, required this.end});
}
