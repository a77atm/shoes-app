import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';
import '../../core/constants/app_constants.dart';
import 'tenant_context.dart';

/// Sales, reports and dashboard stats — scoped to a single tenant
/// (`users/{ownerId}/sales`).
///
/// Every money-moving operation runs in a single Firestore transaction that
/// touches the sale, the affected inventory items and the customer totals
/// together, so those three can never drift apart.
class SalesService {
  final TenantContext _tenant;

  SalesService(this._tenant);

  CollectionReference<Map<String, dynamic>> get _sales => _tenant.sales;
  CollectionReference<Map<String, dynamic>> get _inventory => _tenant.inventory;
  CollectionReference<Map<String, dynamic>> get _customers => _tenant.customers;

  /// Statuses that count towards revenue. Used instead of
  /// `isNotEqualTo: 'returned'`, which forces Firestore to order by `status`
  /// first and cannot be combined cleanly with a `saleDate` range.
  static const List<String> _revenueStatuses = [
    AppConstants.statusPaid,
    AppConstants.statusPending,
  ];

  // ─── Reads ─────────────────────────────────────────────────────────────────

  /// Sales for this store, newest first, with optional server-side filters.
  ///
  /// Amount and free-text filters stay client-side (Firestore cannot range on
  /// two fields plus a text match), exactly as in the original implementation.
  Stream<List<SaleModel>> getSalesStream([SaleFilters? filters]) {
    Query<Map<String, dynamic>> query =
        _sales.orderBy('saleDate', descending: true);

    if (filters != null) {
      if (filters.status != null) {
        query = query.where('status', isEqualTo: filters.status);
      }
      if (filters.customerId != null) {
        query = query.where('customerId', isEqualTo: filters.customerId);
      }
      if (filters.saleType != null) {
        query = query.where('saleType', isEqualTo: filters.saleType);
      }
      if (filters.startDate != null) {
        query = query.where('saleDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(filters.startDate!));
      }
      if (filters.endDate != null) {
        final endOfDay = DateTime(filters.endDate!.year, filters.endDate!.month,
            filters.endDate!.day, 23, 59, 59);
        query = query.where('saleDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
      }
    }

    return query.snapshots().map((snap) {
      var sales = snap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();

      if (filters != null) {
        if (filters.minAmount != null) {
          sales = sales.where((s) => s.totalAmount >= filters.minAmount!).toList();
        }
        if (filters.maxAmount != null) {
          sales = sales.where((s) => s.totalAmount <= filters.maxAmount!).toList();
        }
        if (filters.searchQuery != null && filters.searchQuery!.isNotEmpty) {
          final q = filters.searchQuery!.toLowerCase();
          sales = sales
              .where((s) =>
                  s.customerName.toLowerCase().contains(q) ||
                  s.items.any((item) =>
                      item.brand.toLowerCase().contains(q) ||
                      item.productName.toLowerCase().contains(q)))
              .toList();
        }
      }

      return sales;
    });
  }

  Future<SaleModel?> getSale(String saleId) async {
    final doc = await _sales.doc(saleId).get();
    if (!doc.exists || doc.data() == null) return null;
    return SaleModel.fromMap(doc.data()!, doc.id);
  }

  // ─── Create ────────────────────────────────────────────────────────────────

  /// Records a sale.
  ///
  /// In one transaction we:
  ///   1. read every referenced inventory item and the customer,
  ///   2. validate that the item exists and that there is enough stock,
  ///   3. write the sale, increment `soldQuantity`, and update customer totals.
  ///
  /// Reads happen before writes because Firestore requires it; doing the stock
  /// check inside the transaction is what makes concurrent sales of the last
  /// pair of shoes safe.
  Future<SaleModel> addSale(SaleModel sale) async {
    if (sale.items.isEmpty) {
      throw 'لا يمكن تسجيل فاتورة بدون منتجات';
    }
    if (sale.customerId.isEmpty) {
      throw 'الرجاء اختيار العميل';
    }

    return _tenant.firestore.runTransaction<SaleModel>((transaction) async {
      // ── 1. Reads ────────────────────────────────────────────────────────
      final customerRef = _customers.doc(sale.customerId);
      final customerSnap = await transaction.get(customerRef);
      if (!customerSnap.exists) {
        throw 'العميل غير موجود في هذا المتجر';
      }

      // Merge duplicate lines so a repeated product is validated as one total.
      final quantities = <String, int>{};
      for (final item in sale.items) {
        quantities[item.inventoryId] =
            (quantities[item.inventoryId] ?? 0) + item.quantity;
      }

      final inventorySnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final inventoryId in quantities.keys) {
        final snap = await transaction.get(_inventory.doc(inventoryId));
        if (!snap.exists) {
          throw 'أحد المنتجات لم يعد موجوداً في المخزون';
        }
        inventorySnaps[inventoryId] = snap;
      }

      // ── 2. Validate ─────────────────────────────────────────────────────
      for (final entry in quantities.entries) {
        final item =
            InventoryModel.fromMap(inventorySnaps[entry.key]!.data()!, entry.key);
        if (item.currentBalance < entry.value) {
          throw 'الكمية المطلوبة من "${item.fullName}" غير متوفرة '
              '(المتاح: ${item.currentBalance})';
        }
      }

      // ── 3. Writes ───────────────────────────────────────────────────────
      final docRef = _sales.doc();
      final finalSale = SaleModel(
        id: docRef.id,
        customerId: sale.customerId,
        customerName: sale.customerName,
        items: sale.items,
        totalAmount: sale.totalAmount,
        status: sale.status,
        saleType: sale.saleType,
        notes: sale.notes,
        // Always stamped from the tenant context, never from the caller —
        // the security rules require createdById == request.auth.uid.
        createdById: _tenant.uid,
        createdByName: _tenant.displayName,
        saleDate: sale.saleDate,
        createdAt: DateTime.now(),
      );
      transaction.set(docRef, finalSale.toMap());

      final now = Timestamp.fromDate(DateTime.now());
      for (final entry in quantities.entries) {
        transaction.update(_inventory.doc(entry.key), {
          'soldQuantity': FieldValue.increment(entry.value),
          'updatedAt': now,
        });
      }

      if (finalSale.status == AppConstants.statusPaid) {
        transaction.update(customerRef, {
          'totalPurchases': FieldValue.increment(finalSale.totalAmount),
        });
      } else if (finalSale.status == AppConstants.statusPending) {
        transaction.update(customerRef, {
          'totalPurchases': FieldValue.increment(finalSale.totalAmount),
          'pendingAmount': FieldValue.increment(finalSale.totalAmount),
        });
      }

      return finalSale;
    });
  }

  // ─── Status changes ────────────────────────────────────────────────────────

  /// Changes a sale's status and applies every side effect atomically.
  ///
  /// `pending -> paid`      : clear the customer's outstanding balance.
  /// `* -> returned`        : reverse revenue, reverse the outstanding balance
  ///                          if it was pending, and put the stock back.
  ///
  /// The original implementation reverted stock in a *separate* pass after the
  /// transaction committed, which could leave the books and the stock out of
  /// sync if the app died in between. Everything now happens in one commit.
  Future<void> updateSaleStatus(SaleModel sale, String newStatus) async {
    if (sale.status == newStatus) return;

    await _tenant.firestore.runTransaction<void>((transaction) async {
      final saleRef = _sales.doc(sale.id);

      // ── Reads first ─────────────────────────────────────────────────────
      final saleSnap = await transaction.get(saleRef);
      if (!saleSnap.exists) throw 'الفاتورة غير موجودة';

      final current = SaleModel.fromMap(saleSnap.data()!, saleSnap.id);
      // Re-read the stored status: another device may have changed it.
      if (current.status == newStatus) return;

      final customerRef = current.customerId.isEmpty
          ? null
          : _customers.doc(current.customerId);
      final customerExists = customerRef != null &&
          (await transaction.get(customerRef)).exists;

      // Stock direction: give it back on a return, take it again if a return
      // is undone. Nothing to do for a pending -> paid change.
      final wasReturned = current.status == AppConstants.statusReturned;
      final willBeReturned = newStatus == AppConstants.statusReturned;
      final stockDelta = (!wasReturned && willBeReturned)
          ? -1
          : (wasReturned && !willBeReturned)
              ? 1
              : 0;

      // Pre-read the inventory documents so a product that was deleted since
      // the sale was rung up is skipped instead of failing the whole
      // transaction (Firestore rejects an update to a missing document).
      final liveInventoryIds = <String>{};
      if (stockDelta != 0) {
        for (final id in current.items.map((i) => i.inventoryId).toSet()) {
          if (id.isEmpty) continue;
          final snap = await transaction.get(_inventory.doc(id));
          if (snap.exists) liveInventoryIds.add(id);
        }
      }

      // ── Writes ──────────────────────────────────────────────────────────
      transaction.update(saleRef, {'status': newStatus});

      if (customerExists && customerRef != null) {
        if (current.status == AppConstants.statusPending &&
            newStatus == AppConstants.statusPaid) {
          transaction.update(customerRef, {
            'pendingAmount': FieldValue.increment(-current.totalAmount),
          });
        } else if (newStatus == AppConstants.statusReturned) {
          transaction.update(customerRef, {
            'totalPurchases': FieldValue.increment(-current.totalAmount),
            if (current.status == AppConstants.statusPending)
              'pendingAmount': FieldValue.increment(-current.totalAmount),
          });
        } else if (current.status == AppConstants.statusReturned &&
            newStatus == AppConstants.statusPaid) {
          // Un-returning a sale re-applies the revenue.
          transaction.update(customerRef, {
            'totalPurchases': FieldValue.increment(current.totalAmount),
          });
        }
      }

      if (stockDelta != 0) {
        final now = Timestamp.fromDate(DateTime.now());
        for (final item in current.items) {
          if (!liveInventoryIds.contains(item.inventoryId)) continue;
          transaction.update(_inventory.doc(item.inventoryId), {
            'soldQuantity': FieldValue.increment(stockDelta * item.quantity),
            'updatedAt': now,
          });
        }
      }
    });
  }

  // ─── Delete (admin only) ───────────────────────────────────────────────────

  /// Deletes a sale and undoes its effect on stock and customer totals, so a
  /// deletion can never leave the dashboard reporting phantom revenue.
  Future<void> deleteSale(SaleModel sale) async {
    _tenant.requireAdmin();

    await _tenant.firestore.runTransaction<void>((transaction) async {
      final saleRef = _sales.doc(sale.id);
      final saleSnap = await transaction.get(saleRef);
      if (!saleSnap.exists) return;

      final current = SaleModel.fromMap(saleSnap.data()!, saleSnap.id);

      // Only a sale that still counts needs unwinding; a returned sale was
      // already reversed when its status changed.
      final stillCounts = current.status != AppConstants.statusReturned;

      // ── Reads ───────────────────────────────────────────────────────────
      final customerRef = current.customerId.isEmpty
          ? null
          : _customers.doc(current.customerId);
      final customerSnap =
          customerRef == null ? null : await transaction.get(customerRef);

      final liveInventoryIds = <String>{};
      if (stillCounts) {
        for (final id in current.items.map((i) => i.inventoryId).toSet()) {
          if (id.isEmpty) continue;
          final snap = await transaction.get(_inventory.doc(id));
          if (snap.exists) liveInventoryIds.add(id);
        }
      }

      // ── Writes ──────────────────────────────────────────────────────────
      if (stillCounts && customerRef != null && customerSnap!.exists) {
        transaction.update(customerRef, {
          'totalPurchases': FieldValue.increment(-current.totalAmount),
          if (current.status == AppConstants.statusPending)
            'pendingAmount': FieldValue.increment(-current.totalAmount),
        });
      }

      if (stillCounts) {
        final now = Timestamp.fromDate(DateTime.now());
        for (final item in current.items) {
          if (!liveInventoryIds.contains(item.inventoryId)) continue;
          transaction.update(_inventory.doc(item.inventoryId), {
            'soldQuantity': FieldValue.increment(-item.quantity),
            'updatedAt': now,
          });
        }
      }

      transaction.delete(saleRef);
    });
  }

  // ─── Reports ───────────────────────────────────────────────────────────────

  /// Aggregated report for a date range, for this store only.
  ///
  /// Requires the composite index `sales: status ASC, saleDate ASC`.
  Future<SalesReport> getSalesReport(DateTime start, DateTime end) async {
    final snap = await _sales
        .where('status', whereIn: _revenueStatuses)
        .where('saleDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('saleDate')
        .get();

    final sales = snap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();

    double totalRevenue = 0;
    int totalItems = 0;
    final productSales = <String, Map<String, dynamic>>{};
    final customerSales = <String, Map<String, dynamic>>{};

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;

      for (final item in sale.items) {
        totalItems += item.quantity;
        final key = '${item.brand}-${item.productName}-${item.size}';
        productSales[key] = {
          'name': '${item.brand} ${item.productName} (${item.size})',
          'quantity': (productSales[key]?['quantity'] ?? 0) + item.quantity,
          'revenue': (productSales[key]?['revenue'] ?? 0.0) + item.totalPrice,
        };
      }

      // Aggregated per sale, not per line item — the previous version counted
      // a sale once for every product on the invoice.
      customerSales[sale.customerId] = {
        'name': sale.customerName,
        'count': (customerSales[sale.customerId]?['count'] ?? 0) + 1,
        'revenue': (customerSales[sale.customerId]?['revenue'] ?? 0.0) +
            sale.totalAmount,
      };
    }

    final sortedProducts = productSales.values.toList()
      ..sort((a, b) =>
          (b['revenue'] as double).compareTo(a['revenue'] as double));
    final sortedCustomers = customerSales.values.toList()
      ..sort((a, b) =>
          (b['revenue'] as double).compareTo(a['revenue'] as double));

    return SalesReport(
      startDate: start,
      endDate: end,
      totalSales: sales.length,
      totalRevenue: totalRevenue,
      totalItemsSold: totalItems,
      topProducts: sortedProducts.take(10).toList(),
      topCustomers: sortedCustomers.take(10).toList(),
      dailyRevenue: _getDailyRevenue(sales),
    );
  }

  Map<DateTime, double> _getDailyRevenue(List<SaleModel> sales) {
    final map = <DateTime, double>{};
    for (final sale in sales) {
      final day =
          DateTime(sale.saleDate.year, sale.saleDate.month, sale.saleDate.day);
      map[day] = (map[day] ?? 0) + sale.totalAmount;
    }
    return map;
  }

  // ─── Dashboard ─────────────────────────────────────────────────────────────

  Future<DashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);

    // Fetch the month once and derive "today" from it — one query instead of
    // two, and today is always inside the current month.
    final monthSnap = await _sales
        .where('status', whereIn: _revenueStatuses)
        .where('saleDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .orderBy('saleDate')
        .get();

    final pendingSnap =
        await _sales.where('status', isEqualTo: AppConstants.statusPending).get();

    final monthSales =
        monthSnap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();
    final todaySales =
        monthSales.where((s) => !s.saleDate.isBefore(todayStart)).toList();
    final pendingSales =
        pendingSnap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();

    return DashboardStats(
      todaySalesCount: todaySales.length,
      todayRevenue: todaySales.fold(0.0, (sum, s) => sum + s.totalAmount),
      monthSalesCount: monthSales.length,
      monthRevenue: monthSales.fold(0.0, (sum, s) => sum + s.totalAmount),
      pendingSalesCount: pendingSales.length,
      pendingAmount: pendingSales.fold(0.0, (sum, s) => sum + s.totalAmount),
    );
  }
}

// ─── Report Models ───────────────────────────────────────────────────────────

class SalesReport {
  final DateTime startDate;
  final DateTime endDate;
  final int totalSales;
  final double totalRevenue;
  final int totalItemsSold;
  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> topCustomers;
  final Map<DateTime, double> dailyRevenue;

  const SalesReport({
    required this.startDate,
    required this.endDate,
    required this.totalSales,
    required this.totalRevenue,
    required this.totalItemsSold,
    required this.topProducts,
    required this.topCustomers,
    required this.dailyRevenue,
  });
}

class DashboardStats {
  final int todaySalesCount;
  final double todayRevenue;
  final int monthSalesCount;
  final double monthRevenue;
  final int pendingSalesCount;
  final double pendingAmount;

  const DashboardStats({
    required this.todaySalesCount,
    required this.todayRevenue,
    required this.monthSalesCount,
    required this.monthRevenue,
    required this.pendingSalesCount,
    required this.pendingAmount,
  });
}
