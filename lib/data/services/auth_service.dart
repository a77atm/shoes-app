import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';
import '../../core/constants/app_constants.dart';

/// Authentication + tenant membership.
///
/// Two distinct flows create accounts:
///
///  1. [signUp] — a store owner registers themselves. This creates a **new
///     tenant**: the user document is written with `ownerId == uid` and
///     `role == 'admin'`, and that store's data lives under `users/{uid}/...`.
///
///  2. [createEmployee] — an admin adds a member to their **existing** tenant.
///     The new user document inherits the admin's `ownerId`, so the employee
///     reads and writes exactly the same data as the admin.
///
/// Nothing else may set `ownerId`; the security rules reject any attempt to
/// change it after creation.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  // ─── Session ───────────────────────────────────────────────────────────────

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.usersCollection);

  /// Signs in and returns the membership document.
  ///
  /// Signs the user straight back out if their account has been deactivated, so
  /// a disabled employee never holds a usable session.
  Future<UserModel?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null) return null;

      final user = await getUserData(uid);
      if (user == null) {
        await _auth.signOut();
        throw 'لا يوجد ملف مستخدم مرتبط بهذا الحساب';
      }
      if (!user.isActive) {
        await _auth.signOut();
        throw AppStrings.accountDisabled;
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<void> signOut() => _auth.signOut();

  // ─── Tenant creation (self sign-up) ────────────────────────────────────────

  /// Registers a brand new store owner and, with them, a brand new tenant.
  ///
  /// The membership document is written by the newly-created user themselves
  /// (they are signed in at that point) — the one case the security rules allow
  /// a user to create their own `users/{uid}` document, and only with
  /// `ownerId == uid` and `role == 'admin'`.
  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
    String? storeName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      final trimmedStore = storeName?.trim();
      final owner = UserModel(
        id: uid,
        ownerId: uid, // <- the tenant root is the owner's own UID
        name: name.trim(),
        email: email.trim(),
        role: AppConstants.roleAdmin,
        isActive: true,
        storeName:
            (trimmedStore == null || trimmedStore.isEmpty) ? null : trimmedStore,
        createdAt: DateTime.now(),
      );

      await _users.doc(uid).set(owner.toMap());
      await credential.user!.updateDisplayName(owner.name);
      return owner;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  // ─── Membership management (admin only) ────────────────────────────────────

  /// Creates an employee (or a second admin) **inside the caller's tenant**.
  ///
  /// [FirebaseAuth.createUserWithEmailAndPassword] signs the newly created user
  /// in on whatever app instance it is called on — which, on the default
  /// instance, silently signs the admin out mid-session (a real bug in the
  /// single-tenant version). We therefore create the account on a *secondary*
  /// [FirebaseApp] that reuses the primary app's options, and sign that
  /// secondary instance out immediately afterwards. The admin's session is
  /// never touched.
  ///
  /// The Firestore document is written through the **primary** instance, so the
  /// security rules see the admin as the writer and can verify that
  /// `ownerId == the admin's own ownerId`.
  Future<UserModel> createEmployee({
    required String name,
    required String email,
    required String password,
    required String role,
    required String ownerId,
  }) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await _secondaryApp();
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      final member = UserModel(
        id: uid,
        ownerId: ownerId, // <- inherits the admin's tenant
        name: name.trim(),
        email: email.trim(),
        role: role,
        isActive: true,
        createdAt: DateTime.now(),
      );

      // Written as the admin, on the primary instance.
      await _users.doc(uid).set(member.toMap());

      // Drop the secondary session so nothing is left signed in.
      await secondaryAuth.signOut();
      return member;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } finally {
      // Deleting the app frees its resources; failures here are not fatal.
      try {
        await secondaryApp?.delete();
      } catch (_) {}
    }
  }

  /// Returns (creating if necessary) the secondary app used for provisioning.
  Future<FirebaseApp> _secondaryApp() async {
    try {
      return Firebase.app(AppConstants.secondaryAuthAppName);
    } catch (_) {
      return Firebase.initializeApp(
        name: AppConstants.secondaryAuthAppName,
        options: Firebase.app().options,
      );
    }
  }

  // ─── Reads ─────────────────────────────────────────────────────────────────

  /// One-shot read of a membership document.
  Future<UserModel?> getUserData(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromMap(doc.data()!, doc.id);
  }

  /// Live membership document. Used as the source of the tenant context so a
  /// role change or a deactivation propagates to the UI immediately.
  Stream<UserModel?> watchUserData(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromMap(doc.data()!, doc.id);
    });
  }

  /// All members of a single tenant. Requires the composite index
  /// `users: ownerId ASC, name ASC`.
  Stream<List<UserModel>> getTenantUsers(String ownerId) {
    return _users
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('name')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => UserModel.fromMap(d.data(), d.id)).toList());
  }

  // ─── Writes ────────────────────────────────────────────────────────────────

  /// Updates a member's editable fields. `ownerId` / `email` are never sent.
  Future<void> updateUser(UserModel user) async {
    await _users.doc(user.id).update(user.toEditableMap());
  }

  /// Enables/disables a member. The tenant owner can never be disabled.
  Future<void> toggleUserStatus(String userId, bool isActive) async {
    await _users.doc(userId).update({'isActive': isActive});
  }

  Future<void> changePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'المستخدم غير موجود';
      case 'wrong-password':
      case 'invalid-credential':
        return 'كلمة المرور غير صحيحة';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح';
      case 'user-disabled':
        return 'هذا الحساب معطل';
      case 'email-already-in-use':
        return 'البريد الإلكتروني مستخدم بالفعل';
      case 'weak-password':
        return 'كلمة المرور ضعيفة جداً';
      case 'too-many-requests':
        return 'محاولات كثيرة، حاول لاحقاً';
      case 'network-request-failed':
        return 'تعذر الاتصال بالشبكة';
      default:
        return 'حدث خطأ: ${e.message}';
    }
  }
}
