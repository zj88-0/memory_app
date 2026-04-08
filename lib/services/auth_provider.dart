import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../services/data_service.dart';

class AuthProvider extends ChangeNotifier {
  final DataService _db = DataService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  UserModel? _currentUser;
  CareGroup? _currentGroup;

  UserModel? get currentUser => _currentUser;
  CareGroup? get currentGroup => _currentGroup;
  bool get isLoggedIn => _currentUser != null;
  bool get isCaregiver => _currentUser?.role == UserRole.caregiver;
  bool get isElderly => _currentUser?.role == UserRole.elderly;

  /// True when the group has at least one caregiver joined
  bool get groupHasCaregivers =>
      (_currentGroup?.memberIds.isNotEmpty) ?? false;

  // ── Init ──────────────────────────────────────────────────────────────────
  // DataService.init() is already called in main.dart before runApp.
  // Firebase Auth persists the session automatically — no SharedPrefs needed.
  Future<void> init() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      _currentUser = await _db.getUserById(firebaseUser.uid);
      if (_currentUser != null) {
        await _loadGroup();
      }
    }
  }

  Future<void> _loadGroup() async {
    if (_currentUser == null) return;
    final gid = _currentUser!.groupId;
    if (gid != null && gid.isNotEmpty) {
      // Fast path: 1 point-read instead of 2 where-queries.
      _currentGroup = await _db.getGroupById(gid);
    } else {
      // Fallback for users whose groupId field is not yet populated.
      _currentGroup = await _db.getGroupForUser(_currentUser!.id);
    }
    notifyListeners();
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  Future<String?> login(String email, String password) async {
    try {
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      _currentUser = await _db.getUserById(cred.user!.uid);
      if (_currentUser == null) {
        // Firebase Auth account exists but no Firestore profile (edge case).
        await _firebaseAuth.signOut();
        return 'invalidCredentials';
      }
      await _loadGroup();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] login error: ${e.code}');
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-email') {
        return 'invalidCredentials';
      }
      return e.message ?? 'error';
    } catch (e) {
      debugPrint('[Auth] login unexpected error: $e');
      return 'error';
    }
  }

  // ── Sign up ───────────────────────────────────────────────────────────────
  Future<String?> signup({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      // Use Firebase Auth UID as the Firestore document ID so that
      // request.auth.uid == userId in the security rules.
      final user = UserModel(
        id: cred.user!.uid,
        name: name.trim(),
        email: email.trim().toLowerCase(),
        password: '', // Password is managed entirely by Firebase Auth.
        role: role,
        createdAt: DateTime.now(),
      );
      await _db.createUser(user);
      _currentUser = user;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] signup error: ${e.code}');
      if (e.code == 'email-already-in-use') return 'emailInUse';
      return e.message ?? 'error';
    } catch (e) {
      debugPrint('[Auth] signup unexpected error: $e');
      return 'error';
    }
  }

  // ── Reset password (forgot password flow) ─────────────────────────────────
  // Firebase sends a reset link to the user's email.
  // The `newPassword` parameter from the old custom-auth flow is no longer
  // used — the user sets their password via the Firebase email link instead.
  Future<String?> resetPassword(String email, String newPassword) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      );
      return null; // null = success
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] resetPassword error: ${e.code}');
      if (e.code == 'user-not-found') return 'invalidCredentials';
      return e.message ?? 'error';
    } catch (e) {
      debugPrint('[Auth] resetPassword unexpected error: $e');
      return 'error';
    }
  }

  // ── Update language ───────────────────────────────────────────────────────
  Future<void> updateLanguage(String lang) async {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(preferredLanguage: lang);
    await _db.updateUser(updated);
    _currentUser = updated;
    notifyListeners();
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    await _firebaseAuth.signOut();
    await _db.clearCurrentUser(); // clears any legacy SharedPrefs session
    _currentUser = null;
    _currentGroup = null;
    notifyListeners();
  }

  // ── Group management ──────────────────────────────────────────────────────
  Future<String?> createGroup(String groupName) async {
    if (_currentUser == null) return 'error';
    if (_currentGroup != null) return 'alreadyInGroup';
    final group = CareGroup(
      id: const Uuid().v4(),
      name: groupName,
      adminId: _currentUser!.id,
      memberIds: isCaregiver ? [_currentUser!.id] : [],
      elderlyId: isElderly ? _currentUser!.id : '',
      createdAt: DateTime.now(),
    );
    await _db.createGroup(group);
    final updated = _currentUser!.copyWith(groupId: group.id);
    await _db.updateUser(updated);
    _currentUser = updated;
    _currentGroup = group;
    notifyListeners();
    return null;
  }

  Future<String?> joinGroup(String inviteCode) async {
    if (_currentUser == null) return 'error';
    if (_currentGroup != null) return 'alreadyInGroup';
    final group = await _db.getGroupByInviteCode(inviteCode);
    if (group == null) return 'invalidCode';
    if (group.isFull) return 'groupFull';

    final success = await _db.joinGroup(group.id, _currentUser!.id);
    if (!success) return 'groupFull';

    final updated = _currentUser!.copyWith(groupId: group.id);
    await _db.updateUser(updated);
    _currentUser = updated;
    _currentGroup = await _db.getGroupById(group.id);
    notifyListeners();
    return null;
  }

  Future<void> leaveGroup() async {
    if (_currentUser == null || _currentGroup == null) return;
    await _db.leaveGroup(_currentGroup!.id, _currentUser!.id);
    final updated = _currentUser!.copyWith(groupId: null);
    await _db.updateUser(updated);
    _currentUser = updated;
    _currentGroup = null;
    notifyListeners();
  }

  Future<void> refreshGroup() async => _loadGroup();

  Future<void> removeMember(String memberId) async {
    if (_currentGroup == null) return;
    await _db.leaveGroup(_currentGroup!.id, memberId);
    final memberUser = await _db.getUserById(memberId);
    if (memberUser != null) {
      await _db.updateUser(memberUser.copyWith(groupId: null));
    }
    await _loadGroup();
  }

  Future<void> transferAdmin(String newAdminId) async {
    if (_currentGroup == null) return;
    final updated = _currentGroup!.copyWith(adminId: newAdminId);
    await _db.updateGroup(updated);
    _currentGroup = updated;
    notifyListeners();
  }

  // ── Update display name ───────────────────────────────────────────────────
  Future<void> updateUserName(String name) async {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(name: name);
    await _db.updateUser(updated);
    _currentUser = updated;
    notifyListeners();
  }

  // ── Change password ───────────────────────────────────────────────────────
  // Re-authenticates the Firebase Auth user before updating the password.
  // The old password is passed in via [hashForCompare] from the Settings screen.
  // We store it temporarily so updatePassword can use it for re-auth.
  String _pendingOldPassword = '';

  /// Called from Settings screen to verify the old password before changing.
  /// Returns the old password as-is so the Settings screen comparison works.
  /// Also caches it for use in [updatePassword].
  String hashForCompare(String input) {
    _pendingOldPassword = input; // cache for re-authentication
    return input; // return plain text; comparison is done by Firebase Auth
  }

  Future<void> updatePassword(String newPassword) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || _currentUser == null) return;
    try {
      // Re-authenticate first (Firebase requires this before sensitive ops).
      final credential = EmailAuthProvider.credential(
        email: _currentUser!.email,
        password: _pendingOldPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      _pendingOldPassword = '';
      // password field is empty in Firestore — nothing to update there.
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] updatePassword error: ${e.code}');
      // Propagate so the UI can show the error.
      rethrow;
    }
  }
}
