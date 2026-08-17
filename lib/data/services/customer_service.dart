import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../../core/constants/app_constants.dart';

class CustomerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream all customers
  Stream<List<CustomerModel>> getCustomersStream({String? searchQuery}) {
    return _firestore
        .collection(AppConstants.customersCollection)
        .orderBy('name')
        .snapshots()
        .map((snap) {
      var customers = snap.docs
          .map((d) => CustomerModel.fromMap(d.data(), d.id))
          .toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        customers = customers
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.phone.contains(q))
            .toList();
      }
      return customers;
    });
  }

  // Get customers with pending amounts
  Stream<List<CustomerModel>> getPendingCustomersStream() {
    return _firestore
        .collection(AppConstants.customersCollection)
        .where('pendingAmount', isGreaterThan: 0)
        .orderBy('pendingAmount', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CustomerModel.fromMap(d.data(), d.id)).toList());
  }

  // Get single customer
  Future<CustomerModel?> getCustomer(String id) async {
    final doc = await _firestore
        .collection(AppConstants.customersCollection)
        .doc(id)
        .get();
    if (doc.exists) return CustomerModel.fromMap(doc.data()!, doc.id);
    return null;
  }

  // Add customer
  Future<CustomerModel> addCustomer(CustomerModel customer) async {
    final docRef =
        _firestore.collection(AppConstants.customersCollection).doc();
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

  // Update customer
  Future<void> updateCustomer(CustomerModel customer) async {
    await _firestore
        .collection(AppConstants.customersCollection)
        .doc(customer.id)
        .update({
      'name': customer.name,
      'phone': customer.phone,
      'address': customer.address,
      'notes': customer.notes,
    });
  }

  // Delete customer
  Future<void> deleteCustomer(String id) async {
    await _firestore
        .collection(AppConstants.customersCollection)
        .doc(id)
        .delete();
  }

  // Get all customers as list (for dropdowns)
  Future<List<CustomerModel>> getAllCustomers() async {
    final snap = await _firestore
        .collection(AppConstants.customersCollection)
        .orderBy('name')
        .get();
    return snap.docs
        .map((d) => CustomerModel.fromMap(d.data(), d.id))
        .toList();
  }
}
