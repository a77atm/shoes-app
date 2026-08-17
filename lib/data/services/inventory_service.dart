import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../../core/constants/app_constants.dart';

class InventoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();

  // Stream of all inventory items
  Stream<List<InventoryModel>> getInventoryStream({String? searchQuery}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(AppConstants.inventoryCollection)
        .orderBy('brand')
        .orderBy('productName');

    return query.snapshots().map((snap) {
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

  // Get low stock items
  Stream<List<InventoryModel>> getLowStockStream() {
    return _firestore
        .collection(AppConstants.inventoryCollection)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => InventoryModel.fromMap(d.data(), d.id))
          .where((item) => item.isLowStock)
          .toList();
    });
  }

  // Get single inventory item
  Future<InventoryModel?> getInventoryItem(String id) async {
    final doc = await _firestore
        .collection(AppConstants.inventoryCollection)
        .doc(id)
        .get();
    if (doc.exists) {
      return InventoryModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  // Add inventory item
  Future<InventoryModel> addItem(InventoryModel item, {File? imageFile}) async {
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await _uploadImage(imageFile, item.id);
    }

    final newItem = item.copyWith(imageUrl: imageUrl ?? item.imageUrl);
    final docRef = _firestore.collection(AppConstants.inventoryCollection).doc();

    final finalItem = InventoryModel(
      id: docRef.id,
      brand: newItem.brand,
      productName: newItem.productName,
      size: newItem.size,
      openingBalance: newItem.openingBalance,
      soldQuantity: newItem.soldQuantity,
      currentPrice: newItem.currentPrice,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await docRef.set(finalItem.toMap());
    return finalItem;
  }

  // Update inventory item
  Future<void> updateItem(InventoryModel item, {File? imageFile}) async {
    String? imageUrl = item.imageUrl;
    if (imageFile != null) {
      imageUrl = await _uploadImage(imageFile, item.id);
    }

    final updated = item.copyWith(imageUrl: imageUrl);
    await _firestore
        .collection(AppConstants.inventoryCollection)
        .doc(item.id)
        .update(updated.toMap());
  }

  // Delete inventory item
  Future<void> deleteItem(String id) async {
    // Delete image from storage if exists
    try {
      await _storage.ref('${AppConstants.productImagesPath}/$id').delete();
    } catch (_) {}

    await _firestore
        .collection(AppConstants.inventoryCollection)
        .doc(id)
        .delete();
  }

  // Update sold quantity (called when a sale is recorded)
  Future<void> updateSoldQuantity(String inventoryId, int quantitySold) async {
    await _firestore
        .collection(AppConstants.inventoryCollection)
        .doc(inventoryId)
        .update({
      'soldQuantity': FieldValue.increment(quantitySold),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // Revert sold quantity (called on sale return)
  Future<void> revertSoldQuantity(
      String inventoryId, int quantityReturned) async {
    await _firestore
        .collection(AppConstants.inventoryCollection)
        .doc(inventoryId)
        .update({
      'soldQuantity': FieldValue.increment(-quantityReturned),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // Upload image to Firebase Storage
  Future<String> _uploadImage(File imageFile, String itemId) async {
    final ref = _storage.ref(
        '${AppConstants.productImagesPath}/$itemId.jpg');
    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
  }

  // Get inventory stats for dashboard
  Future<Map<String, int>> getInventoryStats() async {
    final snap = await _firestore
        .collection(AppConstants.inventoryCollection)
        .get();

    final items =
        snap.docs.map((d) => InventoryModel.fromMap(d.data(), d.id)).toList();
    final lowStock = items.where((i) => i.isLowStock).length;
    final outOfStock = items.where((i) => i.currentBalance <= 0).length;

    return {
      'total': items.length,
      'lowStock': lowStock,
      'outOfStock': outOfStock,
    };
  }
}
