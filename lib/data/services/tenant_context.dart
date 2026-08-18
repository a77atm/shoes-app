import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../models/models.dart';

/// Thrown when a tenant-scoped service is used before the signed-in user's
/// membership document has been resolved (or after the user signed out).
///
/// Fail-closed by design: it is better to surface an error than to silently
/// fall back to an unscoped, cross-tenant query.
class TenantNotReadyException implements Exception {
  const TenantNotReadyException();

  @override
  String toString() => AppStrings.tenantLoading;
}

/// Thrown when the signed-in user's account has been deactivated by an admin.
class TenantAccessDeniedException implements Exception {
  final String message;
  const TenantAccessDeniedException([this.message = AppStrings.accountDisabled]);

  @override
  String toString() => message;
}

/// Everything a service needs to know about "who is asking, on behalf of which
/// store". Immutable, cheap to build, and rebuilt whenever the user document
/// changes (role change, deactivation, sign-out).
class TenantContext {
  /// UID of the signed-in Firebase Auth user.
  final String uid;

  /// UID of the tenant owner. Equal to [uid] for a store owner.
  final String ownerId;

  /// 'admin' | 'employee'
  final String role;

  /// Display name of the signed-in user, denormalised onto sales.
  final String displayName;

  final FirebaseFirestore _firestore;

  TenantContext({
    required this.uid,
    required this.ownerId,
    required this.role,
    required this.displayName,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  factory TenantContext.fromUser(UserModel user,
          {FirebaseFirestore? firestore}) =>
      TenantContext(
        uid: user.id,
        ownerId: user.ownerId,
        role: user.role,
        displayName: user.name,
        firestore: firestore,
      );

  bool get isAdmin => role == AppConstants.roleAdmin;
  bool get isOwner => uid == ownerId;

  // ─── Scoped references ─────────────────────────────────────────────────────
  //
  // Services must *only* ever reach Firestore through these getters. Because
  // every reference is rooted at users/{ownerId}, it is structurally impossible
  // for a query built from them to touch another tenant's documents.

  /// `users/{ownerId}` — the tenant root document.
  DocumentReference<Map<String, dynamic>> get tenantDoc =>
      _firestore.collection(AppConstants.usersCollection).doc(ownerId);

  /// `users/{ownerId}/inventory`
  CollectionReference<Map<String, dynamic>> get inventory =>
      tenantDoc.collection(AppConstants.inventoryCollection);

  /// `users/{ownerId}/customers`
  CollectionReference<Map<String, dynamic>> get customers =>
      tenantDoc.collection(AppConstants.customersCollection);

  /// `users/{ownerId}/sales`
  CollectionReference<Map<String, dynamic>> get sales =>
      tenantDoc.collection(AppConstants.salesCollection);

  /// Root `users` collection — used only for membership management.
  CollectionReference<Map<String, dynamic>> get members =>
      _firestore.collection(AppConstants.usersCollection);

  FirebaseFirestore get firestore => _firestore;

  /// Guard for client-side admin-only operations. The security rules enforce
  /// the same thing server-side; this just gives a nicer Arabic error and
  /// avoids a pointless round trip.
  void requireAdmin() {
    if (!isAdmin) throw const TenantAccessDeniedException(AppStrings.noPermission);
  }

  // Value equality matters here: the tenant context is rebuilt on every
  // snapshot of the membership document, and Riverpod only notifies listeners
  // when a provider's value actually changes. Without `==`, every no-op
  // snapshot would tear down and re-subscribe every Firestore stream.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TenantContext &&
          other.uid == uid &&
          other.ownerId == ownerId &&
          other.role == role &&
          other.displayName == displayName);

  @override
  int get hashCode => Object.hash(uid, ownerId, role, displayName);

  @override
  String toString() => 'TenantContext(uid: $uid, ownerId: $ownerId, role: $role)';
}
