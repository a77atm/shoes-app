import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

// ─── UserModel ───────────────────────────────────────────────────────────────

/// Identity + tenant-membership document stored at `users/{id}`.
///
/// [ownerId] is the UID of the tenant this user belongs to:
///  * a store owner who signs up        -> `ownerId == id` (role `admin`)
///  * an employee created by that owner -> `ownerId == owner's UID`
///
/// All tenant data lives under `users/{ownerId}/...`, so [ownerId] is the only
/// piece of state the app needs in order to scope every read and write.
class UserModel extends Equatable {
  final String id;
  final String ownerId;
  final String name;
  final String email;
  final String role; // 'admin' | 'employee'
  final bool isActive;
  final String? storeName;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.email,
    required this.role,
    this.isActive = true,
    this.storeName,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';

  /// True for the user who created the tenant. The owner document can never be
  /// deactivated or demoted by anyone else.
  bool get isOwner => id == ownerId;

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    final rawOwnerId = map['ownerId'] as String?;
    return UserModel(
      id: id,
      // Documents written before multi-tenancy have no `ownerId`; treating them
      // as their own tenant keeps legacy admin accounts able to sign in.
      ownerId:
          (rawOwnerId != null && rawOwnerId.isNotEmpty) ? rawOwnerId : id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'employee',
      isActive: map['isActive'] ?? true,
      storeName: map['storeName'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'name': name,
        'email': email,
        'role': role,
        'isActive': isActive,
        'storeName': storeName,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  /// Fields an admin may change on a member of their own tenant. Deliberately
  /// excludes `ownerId` and `email` — moving a user between tenants is never an
  /// in-app edit, and the security rules reject it.
  Map<String, dynamic> toEditableMap() => {
        'name': name,
        'role': role,
        'isActive': isActive,
        'storeName': storeName,
      };

  UserModel copyWith({
    String? name,
    String? email,
    String? role,
    bool? isActive,
    String? storeName,
  }) =>
      UserModel(
        id: id,
        ownerId: ownerId,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role ?? this.role,
        isActive: isActive ?? this.isActive,
        storeName: storeName ?? this.storeName,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, ownerId, name, email, role, isActive];
}

// ─── CustomerModel ───────────────────────────────────────────────────────────

class CustomerModel extends Equatable {
  final String id;
  final String name;
  final String phone;
  final String? address;
  final String? notes;
  final double totalPurchases;
  final double pendingAmount;
  final DateTime createdAt;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    this.notes,
    this.totalPurchases = 0,
    this.pendingAmount = 0,
    required this.createdAt,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map, String id) {
    return CustomerModel(
      id: id,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      address: map['address'],
      notes: map['notes'],
      totalPurchases: (map['totalPurchases'] ?? 0).toDouble(),
      pendingAmount: (map['pendingAmount'] ?? 0).toDouble(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'address': address,
        'notes': notes,
        'totalPurchases': totalPurchases,
        'pendingAmount': pendingAmount,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  CustomerModel copyWith({
    String? name,
    String? phone,
    String? address,
    String? notes,
    double? totalPurchases,
    double? pendingAmount,
  }) =>
      CustomerModel(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        totalPurchases: totalPurchases ?? this.totalPurchases,
        pendingAmount: pendingAmount ?? this.pendingAmount,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, name, phone, totalPurchases, pendingAmount];
}

// ─── InventoryModel ──────────────────────────────────────────────────────────

class InventoryModel extends Equatable {
  final String id;
  final String brand;
  final String productName;
  final String size;
  final int openingBalance;
  final int soldQuantity;
  final double currentPrice;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryModel({
    required this.id,
    required this.brand,
    required this.productName,
    required this.size,
    required this.openingBalance,
    this.soldQuantity = 0,
    required this.currentPrice,
    required this.createdAt,
    required this.updatedAt,
  });

  int get currentBalance => openingBalance - soldQuantity;
  bool get isLowStock => currentBalance <= 5;

  String get fullName => '$brand - $productName - $size';

  factory InventoryModel.fromMap(Map<String, dynamic> map, String id) {
    return InventoryModel(
      id: id,
      brand: map['brand'] ?? '',
      productName: map['productName'] ?? '',
      size: map['size'] ?? '',
      openingBalance: (map['openingBalance'] ?? 0).toInt(),
      soldQuantity: (map['soldQuantity'] ?? 0).toInt(),
      currentPrice: (map['currentPrice'] ?? 0).toDouble(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'brand': brand,
        'productName': productName,
        'size': size,
        'openingBalance': openingBalance,
        'soldQuantity': soldQuantity,
        'currentPrice': currentPrice,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  InventoryModel copyWith({
    String? brand,
    String? productName,
    String? size,
    int? openingBalance,
    int? soldQuantity,
    double? currentPrice,
  }) =>
      InventoryModel(
        id: id,
        brand: brand ?? this.brand,
        productName: productName ?? this.productName,
        size: size ?? this.size,
        openingBalance: openingBalance ?? this.openingBalance,
        soldQuantity: soldQuantity ?? this.soldQuantity,
        currentPrice: currentPrice ?? this.currentPrice,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  @override
  List<Object?> get props =>
      [id, brand, productName, size, openingBalance, soldQuantity, currentPrice];
}

// ─── SaleItemModel ───────────────────────────────────────────────────────────

class SaleItemModel extends Equatable {
  final String inventoryId;
  final String brand;
  final String productName;
  final String size;
  final int quantity;
  final double priceAtSale; // السعر وقت البيع

  const SaleItemModel({
    required this.inventoryId,
    required this.brand,
    required this.productName,
    required this.size,
    required this.quantity,
    required this.priceAtSale,
  });

  double get totalPrice => quantity * priceAtSale;

  factory SaleItemModel.fromMap(Map<String, dynamic> map) {
    return SaleItemModel(
      inventoryId: map['inventoryId'] ?? '',
      brand: map['brand'] ?? '',
      productName: map['productName'] ?? '',
      size: map['size'] ?? '',
      quantity: (map['quantity'] ?? 1).toInt(),
      priceAtSale: (map['priceAtSale'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'inventoryId': inventoryId,
        'brand': brand,
        'productName': productName,
        'size': size,
        'quantity': quantity,
        'priceAtSale': priceAtSale,
      };

  @override
  List<Object?> get props =>
      [inventoryId, quantity, priceAtSale];
}

// ─── SaleModel ───────────────────────────────────────────────────────────────

class SaleModel extends Equatable {
  final String id;
  final String customerId;
  final String customerName;
  final List<SaleItemModel> items;
  final double totalAmount;
  final String status; // 'paid' | 'pending' | 'returned'
  final String saleType; // 'normal' | 'bulk'
  final String? notes;
  final String createdById;
  final String createdByName;
  final DateTime saleDate;
  final DateTime createdAt;

  const SaleModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.saleType,
    this.notes,
    required this.createdById,
    required this.createdByName,
    required this.saleDate,
    required this.createdAt,
  });

  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';
  bool get isReturned => status == 'returned';
  bool get isBulk => saleType == 'bulk';

  factory SaleModel.fromMap(Map<String, dynamic> map, String id) {
    return SaleModel(
      id: id,
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      items: (map['items'] as List<dynamic>?)
              ?.map((e) => SaleItemModel.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalAmount: (map['totalAmount'] ?? 0).toDouble(),
      status: map['status'] ?? 'paid',
      saleType: map['saleType'] ?? 'normal',
      notes: map['notes'],
      createdById: map['createdById'] ?? '',
      createdByName: map['createdByName'] ?? '',
      saleDate: (map['saleDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'customerId': customerId,
        'customerName': customerName,
        'items': items.map((e) => e.toMap()).toList(),
        'totalAmount': totalAmount,
        'status': status,
        'saleType': saleType,
        'notes': notes,
        'createdById': createdById,
        'createdByName': createdByName,
        'saleDate': Timestamp.fromDate(saleDate),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  SaleModel copyWith({String? status, String? notes}) => SaleModel(
        id: id,
        customerId: customerId,
        customerName: customerName,
        items: items,
        totalAmount: totalAmount,
        status: status ?? this.status,
        saleType: saleType,
        notes: notes ?? this.notes,
        createdById: createdById,
        createdByName: createdByName,
        saleDate: saleDate,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, customerId, totalAmount, status];
}

// ─── SaleFilters ─────────────────────────────────────────────────────────────

class SaleFilters {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? status;
  final String? customerId;
  final String? inventoryId;
  final String? saleType;
  final double? minAmount;
  final double? maxAmount;
  final String? searchQuery;

  const SaleFilters({
    this.startDate,
    this.endDate,
    this.status,
    this.customerId,
    this.inventoryId,
    this.saleType,
    this.minAmount,
    this.maxAmount,
    this.searchQuery,
  });

  bool get hasFilters =>
      startDate != null ||
      endDate != null ||
      status != null ||
      customerId != null ||
      inventoryId != null ||
      saleType != null ||
      minAmount != null ||
      maxAmount != null ||
      (searchQuery != null && searchQuery!.isNotEmpty);

  SaleFilters copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? customerId,
    String? inventoryId,
    String? saleType,
    double? minAmount,
    double? maxAmount,
    String? searchQuery,
  }) =>
      SaleFilters(
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        status: status ?? this.status,
        customerId: customerId ?? this.customerId,
        inventoryId: inventoryId ?? this.inventoryId,
        saleType: saleType ?? this.saleType,
        minAmount: minAmount ?? this.minAmount,
        maxAmount: maxAmount ?? this.maxAmount,
        searchQuery: searchQuery ?? this.searchQuery,
      );

  SaleFilters clear() => const SaleFilters();
}
