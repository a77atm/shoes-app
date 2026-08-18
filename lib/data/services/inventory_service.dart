import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';
import 'tenant_context.dart';

/// Inventory, scoped to a single tenant.
///
/// The service holds a [TenantContext] and never builds a Firestore reference
/// by hand — every query starts from `tenant.inventory`, which is
/// `users/{ownerId}/inventory`. There is no code path that can read or write
/// another store's stock.
class InventoryService {
  final TenantContext _tenant;

  InventoryService(this._tenant);

  CollectionReference<Map<String, dynamic>> get _col => _tenant.inventory;

  // ─── Reads ─────────────────────────────────────────────────────────────────

  /// All items in this store, ordered by brand then product name.
  ///
  /// Requires the composite index `inventory: brand ASC, productName ASC`.
  /// Search is applied client-side, exactly as before — the collection is
  /// per-store now, so it is small.
  Stream<List<InventoryModel>> getInventoryStream({String? searchQuery}) {
    return _col
        .orderBy('brand')
        .orderBy('productName')
        .snapshots()
        .map((snap) {
      var items =
          snap.docs.map((d) => InventoryModel.fromMap(d.data(), d.id)).toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        items = items
            .where((item) =>
                item.brand.toLowerCase().contains(q) ||
                item.productName.toLowerCase().contains(q) ||
                item.size.toLowerCase().contains(q))
            .toList();
      }
      return items;
    });
  }

  /// Items at or below the low-stock threshold.
  Stream<List<InventoryModel>> getLowStockStream() {
    return _col.snapshots().map((snap) => snap.docs
        .map((d) => InventoryModel.fromMap(d.data(), d.id))
        .where((item) => item.isLowStock)
        .toList());
  }

  Future<InventoryModel?> getInventoryItem(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return InventoryModel.fromMap(doc.data()!, doc.id);
  }

  // ─── Writes (admin only) ───────────────────────────────────────────────────

  Future<InventoryModel> addItem(InventoryModel item) async {
    _tenant.requireAdmin();

    final docRef = _col.doc();
    final now = DateTime.now();
    final finalItem = InventoryModel(
      id: docRef.id,
      brand: item.brand,
      productName: item.productName,
      size: item.size,
      openingBalance: item.openingBalance,
      soldQuantity: item.soldQuantity,
      currentPrice: item.currentPrice,
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set(finalItem.toMap());
    return finalItem;
  }

  Future<void> updateItem(InventoryModel item) async {
    _tenant.requireAdmin();
    await _col.doc(item.id).update(item.toMap());
  }

  Future<void> deleteItem(String id) async {
    _tenant.requireAdmin();
    await _col.doc(id).delete();
  }

  // ─── Stock movement (any active member) ────────────────────────────────────
  //
  // Employees are not allowed to edit inventory, but they must be able to move
  // stock when they record a sale. Both methods touch only `soldQuantity` and
  // `updatedAt`, which is precisely the exception the security rules carve out.

  Future<void> updateSoldQuantity(String inventoryId, int quantitySold) async {
    await _col.doc(inventoryId).update({
      'soldQuantity': FieldValue.increment(quantitySold),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> revertSoldQuantity(
      String inventoryId, int quantityReturned) async {
    await _col.doc(inventoryId).update({
      'soldQuantity': FieldValue.increment(-quantityReturned),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ─── Dashboard ─────────────────────────────────────────────────────────────

  Future<Map<String, int>> getInventoryStats() async {
    final snap = await _col.get();
    final items =
        snap.docs.map((d) => InventoryModel.fromMap(d.data(), d.id)).toList();

    return {
      'total': items.length,
      'lowStock': items.where((i) => i.isLowStock).length,
      'outOfStock': items.where((i) => i.currentBalance <= 0).length,
    };
  }
}
