import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/models/models.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/inventory_service.dart';
import '../../data/services/sales_service.dart';
import '../../data/services/customer_service.dart';
import '../../data/services/tenant_context.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Provider graph (multi-tenant)
//
//    authStateProvider          Firebase Auth user (or null)
//          │
//    currentUserProvider        live users/{uid} membership document
//          │
//    tenantProvider             TenantContext  { uid, ownerId, role }
//          │
//    ┌─────┴───────────────┬──────────────────────┐
//    inventoryService   salesService        customerService
//          │                  │                    │
//     data providers ────────────────────────────────
//
//  Everything below `tenantProvider` is rebuilt whenever the signed-in user,
//  their role or their tenant changes, so switching accounts tears down and
//  rebuilds every stream — no stale data from the previous store can survive.
// ═════════════════════════════════════════════════════════════════════════════

// ─── Auth ────────────────────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Live membership document for the signed-in user.
///
/// This is a *stream* (it used to be a one-shot future) so that a role change
/// or a deactivation performed by an admin takes effect immediately, without
/// requiring the employee to restart the app.
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final firebaseUser = ref.watch(authStateProvider).valueOrNull;
  if (firebaseUser == null) return Stream.value(null);
  return ref.watch(authServiceProvider).watchUserData(firebaseUser.uid);
});

// ─── Tenant context ──────────────────────────────────────────────────────────

/// The tenant the signed-in user is acting on behalf of, or `null` while the
/// membership document is still loading / after sign-out / when the account has
/// been deactivated.
///
/// Reactive data providers watch this one so they can stay in the *loading*
/// state instead of flashing an error during start-up.
final tenantOrNullProvider = Provider<TenantContext?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || !user.isActive) return null;
  return TenantContext.fromUser(user);
});

/// Same thing, but throws instead of returning null.
///
/// Used to build the services: a service must never exist without a tenant,
/// because an unscoped service would query across stores. Imperative call sites
/// (button handlers) already run inside a try/catch and show the Arabic message.
final tenantProvider = Provider<TenantContext>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) throw const TenantNotReadyException();
  if (!user.isActive) throw const TenantAccessDeniedException();
  return TenantContext.fromUser(user);
});

/// A future that never completes — keeps a [FutureProvider] in its `loading`
/// state while the tenant context is still resolving.
Future<T> _pending<T>() => Completer<T>().future;

/// Convenience accessors used by the UI. Null-safe, never throw.
final currentOwnerIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.ownerId;
});

final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.isAdmin ?? false;
});

// ─── Tenant-scoped services ──────────────────────────────────────────────────

final inventoryServiceProvider = Provider<InventoryService>(
    (ref) => InventoryService(ref.watch(tenantProvider)));

final salesServiceProvider =
    Provider<SalesService>((ref) => SalesService(ref.watch(tenantProvider)));

final customerServiceProvider = Provider<CustomerService>(
    (ref) => CustomerService(ref.watch(tenantProvider)));

// ─── Inventory ───────────────────────────────────────────────────────────────

final inventorySearchProvider = StateProvider<String>((ref) => '');

final inventoryStreamProvider = StreamProvider<List<InventoryModel>>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return const Stream.empty();
  final search = ref.watch(inventorySearchProvider);
  return ref
      .watch(inventoryServiceProvider)
      .getInventoryStream(searchQuery: search.isEmpty ? null : search);
});

final lowStockStreamProvider = StreamProvider<List<InventoryModel>>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return const Stream.empty();
  return ref.watch(inventoryServiceProvider).getLowStockStream();
});

final inventoryStatsProvider = FutureProvider<Map<String, int>>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return _pending();
  return ref.watch(inventoryServiceProvider).getInventoryStats();
});

// ─── Sales ───────────────────────────────────────────────────────────────────

final saleFiltersProvider =
    StateProvider<SaleFilters>((ref) => const SaleFilters());

final salesStreamProvider = StreamProvider<List<SaleModel>>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return const Stream.empty();
  final filters = ref.watch(saleFiltersProvider);
  return ref
      .watch(salesServiceProvider)
      .getSalesStream(filters.hasFilters ? filters : null);
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return _pending();
  return ref.watch(salesServiceProvider).getDashboardStats();
});

// ─── Customers ───────────────────────────────────────────────────────────────

final customerSearchProvider = StateProvider<String>((ref) => '');

final customersStreamProvider = StreamProvider<List<CustomerModel>>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return const Stream.empty();
  final search = ref.watch(customerSearchProvider);
  return ref
      .watch(customerServiceProvider)
      .getCustomersStream(searchQuery: search.isEmpty ? null : search);
});

final pendingCustomersProvider = StreamProvider<List<CustomerModel>>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return const Stream.empty();
  return ref.watch(customerServiceProvider).getPendingCustomersStream();
});

final allCustomersProvider = FutureProvider<List<CustomerModel>>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return _pending();
  return ref.watch(customerServiceProvider).getAllCustomers();
});

// ─── Users ───────────────────────────────────────────────────────────────────

/// Members of the current tenant only — never every user in the database.
/// Requires the composite index `users: ownerId ASC, name ASC`.
final usersStreamProvider = StreamProvider<List<UserModel>>((ref) {
  final tenant = ref.watch(tenantOrNullProvider);
  if (tenant == null) return const Stream.empty();
  return ref.watch(authServiceProvider).getTenantUsers(tenant.ownerId);
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

final salesReportProvider = FutureProvider.autoDispose<SalesReport>((ref) {
  if (ref.watch(tenantOrNullProvider) == null) return _pending();
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
