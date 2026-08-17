import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../../core/constants/app_constants.dart';
import 'inventory_service.dart';
import 'customer_service.dart';

class SalesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final InventoryService _inventoryService = InventoryService();
  final CustomerService _customerService = CustomerService();

  // Get sales stream with optional filters
  Stream<List<SaleModel>> getSalesStream([SaleFilters? filters]) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(AppConstants.salesCollection)
        .orderBy('saleDate', descending: true);

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
      var sales =
          snap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();

      if (filters != null) {
        if (filters.minAmount != null) {
          sales =
              sales.where((s) => s.totalAmount >= filters.minAmount!).toList();
        }
        if (filters.maxAmount != null) {
          sales =
              sales.where((s) => s.totalAmount <= filters.maxAmount!).toList();
        }
        if (filters.searchQuery != null &&
            filters.searchQuery!.isNotEmpty) {
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

  // Add a new sale (with transaction)
  Future<SaleModel> addSale(SaleModel sale) async {
    return await _firestore.runTransaction((transaction) async {
      final docRef =
          _firestore.collection(AppConstants.salesCollection).doc();

      final finalSale = SaleModel(
        id: docRef.id,
        customerId: sale.customerId,
        customerName: sale.customerName,
        items: sale.items,
        totalAmount: sale.totalAmount,
        status: sale.status,
        saleType: sale.saleType,
        notes: sale.notes,
        createdById: sale.createdById,
        createdByName: sale.createdByName,
        saleDate: sale.saleDate,
        createdAt: DateTime.now(),
      );

      transaction.set(docRef, finalSale.toMap());

      // Update inventory sold quantities
      for (final item in sale.items) {
        final invRef = _firestore
            .collection(AppConstants.inventoryCollection)
            .doc(item.inventoryId);
        transaction.update(invRef, {
          'soldQuantity': FieldValue.increment(item.quantity),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      // Update customer totals
      final customerRef = _firestore
          .collection(AppConstants.customersCollection)
          .doc(sale.customerId);

      if (sale.status == AppConstants.statusPaid) {
        transaction.update(customerRef, {
          'totalPurchases': FieldValue.increment(sale.totalAmount),
        });
      } else if (sale.status == AppConstants.statusPending) {
        transaction.update(customerRef, {
          'totalPurchases': FieldValue.increment(sale.totalAmount),
          'pendingAmount': FieldValue.increment(sale.totalAmount),
        });
      }

      return finalSale;
    });
  }

  // Update sale status
  Future<void> updateSaleStatus(String saleId, String newStatus,
      String oldStatus, double amount, String customerId) async {
    await _firestore.runTransaction((transaction) async {
      final saleRef =
          _firestore.collection(AppConstants.salesCollection).doc(saleId);
      final customerRef = _firestore
          .collection(AppConstants.customersCollection)
          .doc(customerId);

      transaction.update(saleRef, {'status': newStatus});

      // Update customer pending amount
      if (oldStatus == AppConstants.statusPending &&
          newStatus == AppConstants.statusPaid) {
        transaction.update(customerRef, {
          'pendingAmount': FieldValue.increment(-amount),
        });
      } else if (newStatus == AppConstants.statusReturned) {
        // Reverse the sale effect
        transaction.update(customerRef, {
          'totalPurchases': FieldValue.increment(-amount),
          if (oldStatus == AppConstants.statusPending)
            'pendingAmount': FieldValue.increment(-amount),
        });
      }
    });

    // Revert inventory if returned
    if (newStatus == AppConstants.statusReturned) {
      final sale = await _getSaleById(saleId);
      if (sale != null) {
        for (final item in sale.items) {
          await _inventoryService.revertSoldQuantity(
              item.inventoryId, item.quantity);
        }
      }
    }
  }

  Future<SaleModel?> _getSaleById(String saleId) async {
    final doc = await _firestore
        .collection(AppConstants.salesCollection)
        .doc(saleId)
        .get();
    if (doc.exists) return SaleModel.fromMap(doc.data()!, doc.id);
    return null;
  }

  // Delete sale
  Future<void> deleteSale(SaleModel sale) async {
    await _firestore
        .collection(AppConstants.salesCollection)
        .doc(sale.id)
        .delete();
  }

  // Get sales report
  Future<SalesReport> getSalesReport(DateTime start, DateTime end) async {
    final snap = await _firestore
        .collection(AppConstants.salesCollection)
        .where('saleDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            isLessThanOrEqualTo: Timestamp.fromDate(end))
        .where('status', isNotEqualTo: AppConstants.statusReturned)
        .get();

    final sales =
        snap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();

    // Calculate totals
    double totalRevenue = 0;
    int totalItems = 0;
    final productSales = <String, Map<String, dynamic>>{};
    final customerSales = <String, Map<String, dynamic>>{};

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;
      for (final item in sale.items) {
        totalItems += item.quantity;

        // Product stats
        final key = '${item.brand}-${item.productName}-${item.size}';
        productSales[key] = {
          'name': '${item.brand} ${item.productName} (${item.size})',
          'quantity': (productSales[key]?['quantity'] ?? 0) + item.quantity,
          'revenue': (productSales[key]?['revenue'] ?? 0.0) + item.totalPrice,
        };

        // Customer stats
        customerSales[sale.customerId] = {
          'name': sale.customerName,
          'count': (customerSales[sale.customerId]?['count'] ?? 0) + 1,
          'revenue':
              (customerSales[sale.customerId]?['revenue'] ?? 0.0) + sale.totalAmount,
        };
      }
    }

    // Sort by revenue
    final sortedProducts = productSales.values.toList()
      ..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
    final sortedCustomers = customerSales.values.toList()
      ..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));

    return SalesReport(
      startDate: start,
      endDate: end,
      totalSales: sales.length,
      totalRevenue: totalRevenue,
      totalItemsSold: totalItems,
      topProducts: sortedProducts.take(10).toList(),
      topCustomers: sortedCustomers.take(10).toList(),
      dailyRevenue: _getDailyRevenue(sales, start, end),
    );
  }

  // Get daily revenue for chart
  Map<DateTime, double> _getDailyRevenue(
      List<SaleModel> sales, DateTime start, DateTime end) {
    final map = <DateTime, double>{};
    for (final sale in sales) {
      final day = DateTime(
          sale.saleDate.year, sale.saleDate.month, sale.saleDate.day);
      map[day] = (map[day] ?? 0) + sale.totalAmount;
    }
    return map;
  }

  // Get dashboard stats
  Future<DashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);

    final todaySnap = await _firestore
        .collection(AppConstants.salesCollection)
        .where('saleDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('status', isNotEqualTo: AppConstants.statusReturned)
        .get();

    final monthSnap = await _firestore
        .collection(AppConstants.salesCollection)
        .where('saleDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('status', isNotEqualTo: AppConstants.statusReturned)
        .get();

    final pendingSnap = await _firestore
        .collection(AppConstants.salesCollection)
        .where('status', isEqualTo: AppConstants.statusPending)
        .get();

    final todaySales =
        todaySnap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();
    final monthSales =
        monthSnap.docs.map((d) => SaleModel.fromMap(d.data(), d.id)).toList();

    double todayRevenue =
        todaySales.fold(0, (sum, s) => sum + s.totalAmount);
    double monthRevenue =
        monthSales.fold(0, (sum, s) => sum + s.totalAmount);
    double pendingAmount = pendingSnap.docs
        .map((d) => SaleModel.fromMap(d.data(), d.id))
        .fold(0.0, (sum, s) => sum + s.totalAmount);

    return DashboardStats(
      todaySalesCount: todaySales.length,
      todayRevenue: todayRevenue,
      monthSalesCount: monthSales.length,
      monthRevenue: monthRevenue,
      pendingSalesCount: pendingSnap.docs.length,
      pendingAmount: pendingAmount,
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
