import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';
import 'tenant_context.dart';

/// Customers, scoped to a single tenant (`users/{ownerId}/customers`).
class CustomerService {
  final TenantContext _tenant;

  CustomerService(this._tenant);

  CollectionReference<Map<String, dynamic>> get _col => _tenant.customers;

  // ─── Reads ─────────────────────────────────────────────────────────────────

  Stream<List<CustomerModel>> getCustomersStream({String? searchQuery}) {
    return _col.orderBy('name').snapshots().map((snap) {
      var customers =
          snap.docs.map((d) => CustomerModel.fromMap(d.data(), d.id)).toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        customers = customers
            .where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q))
            .toList();
      }
      return customers;
    });
  }

  /// Customers who still owe money. Single-field index only — the filter and
  /// the ordering are on the same field.
  Stream<List<CustomerModel>> getPendingCustomersStream() {
    return _col
        .where('pendingAmount', isGreaterThan: 0)
        .orderBy('pendingAmount', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => CustomerModel.fromMap(d.data(), d.id))
            .toList());
  }

  Future<CustomerModel?> getCustomer(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return CustomerModel.fromMap(doc.data()!, doc.id);
  }

  Future<List<CustomerModel>> getAllCustomers() async {
    final snap = await _col.orderBy('name').get();
    return snap.docs.map((d) => CustomerModel.fromMap(d.data(), d.id)).toList();
  }

  // ─── Writes ────────────────────────────────────────────────────────────────

  /// Any active member may add a customer (employees register walk-ins).
  Future<CustomerModel> addCustomer(CustomerModel customer) async {
    final docRef = _col.doc();
    final newCustomer = CustomerModel(
      id: docRef.id,
      name: customer.name,
      phone: customer.phone,
      address: customer.address,
      notes: customer.notes,
      createdAt: DateTime.now(),
    );
    await docRef.set(newCustomer.toMap());
    return newCustomer;
  }

  /// Updates the descriptive fields only. `totalPurchases` / `pendingAmount`
  /// are money fields and are mutated exclusively inside the sales transaction.
  Future<void> updateCustomer(CustomerModel customer) async {
    await _col.doc(customer.id).update({
      'name': customer.name,
      'phone': customer.phone,
      'address': customer.address,
      'notes': customer.notes,
    });
  }

  Future<void> deleteCustomer(String id) async {
    _tenant.requireAdmin();
    await _col.doc(id).delete();
  }
}
