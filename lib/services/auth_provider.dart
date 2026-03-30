import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../services/data_service.dart';

class AuthProvider extends ChangeNotifier {
  final DataService _db = DataService();
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

  Future<void> init() async {
    await _db.init();
    final id = _db.getCurrentUserId();
    if (id != null) {
      _currentUser = await _db.getUserById(id);
      if (_currentUser != null) {
        await _loadGroup();
      }
    }
  }

  Future<void> _loadGroup() async {
    if (_currentUser == null) return;
    _currentGroup = await _db.getGroupForUser(_currentUser!.id);
    notifyListeners();
  }

  Future<String?> login(String email, String password) async {
    final user = await _db.getUserByEmail(email);
    if (user == null || user.password != _hash(password)) {
      return 'invalidCredentials';
    }
    _currentUser = user;
    await _db.setCurrentUserId(user.id);
    await _loadGroup();
    notifyListeners();
    return null;
  }

  Future<String?> signup({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final existing = await _db.getUserByEmail(email);
    if (existing != null) return 'emailInUse';

    final user = UserModel(
      id: const Uuid().v4(),
      name: name,
      email: email,
      password: _hash(password),
      role: role,
      createdAt: DateTime.now(),
    );
    await _db.createUser(user);
    _currentUser = user;
    await _db.setCurrentUserId(user.id);
    notifyListeners();
    return null;
  }

  Future<String?> resetPassword(String email, String newPassword) async {
    final user = await _db.getUserByEmail(email);
    if (user == null) return 'invalidCredentials';
    final updated = user.copyWith(password: _hash(newPassword));
    await _db.updateUser(updated);
    return null;
  }

  Future<void> updateLanguage(String lang) async {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(preferredLanguage: lang);
    await _db.updateUser(updated);
    _currentUser = updated;
    notifyListeners();
  }

  Future<void> logout() async {
    await _db.clearCurrentUser();
    _currentUser = null;
    _currentGroup = null;
    notifyListeners();
  }

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

  // Simple hash — replace with bcrypt/SHA in production
  String _hash(String input) {
    var hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = (hash << 5) - hash + input.codeUnitAt(i);
      hash &= hash;
    }
    return hash.toRadixString(16);
  }

  Future<void> updateUserName(String name) async {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(name: name);
    await _db.updateUser(updated);
    _currentUser = updated;
    notifyListeners();
  }

  Future<void> updatePassword(String newPassword) async {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(password: _hash(newPassword));
    await _db.updateUser(updated);
    _currentUser = updated;
    notifyListeners();
  }

  String hashForCompare(String input) => _hash(input);
}
