import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/schedule_model.dart';
import '../models/quick_action_model.dart';
import '../models/group_model.dart';
import '../models/request_model.dart';
import '../models/moment_model.dart';

/// ---------------------------------------------------------------------------
/// DataService — CRUD layer backed by SharedPreferences.
/// To migrate to Firebase: replace each method body with Firestore calls.
/// Keys are isolated per collection for easy replacement.
/// ---------------------------------------------------------------------------
class DataService {
  static const String _usersKey = 'ec_users';
  static const String _schedulesKey = 'ec_schedules';
  static const String _quickActionsKey = 'ec_quick_actions';
  static const String _groupsKey = 'ec_groups';
  static const String _currentUserKey = 'ec_current_user_id';
  static const String _requestsKey = 'ec_requests';
  static const String _momentsKey = 'ec_moments';

  // ─── Singleton ──────────────────────────────────────────────────────────────
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────
  String? getRawString(String key) {
    return _prefs.getString(key);
  }

  Future<void> setRawString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  List<Map<String, dynamic>> _readCollection(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> _writeCollection(String key, List<Map<String, dynamic>> data) async {
    await _prefs.setString(key, jsonEncode(data));
  }

  // ─── USERS ──────────────────────────────────────────────────────────────────
  Future<List<UserModel>> getAllUsers() async {
    return _readCollection(_usersKey).map(UserModel.fromJson).toList();
  }

  Future<UserModel?> getUserById(String id) async {
    final all = await getAllUsers();
    try {
      return all.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final all = await getAllUsers();
    try {
      return all.firstWhere((u) => u.email.toLowerCase() == email.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  Future<void> createUser(UserModel user) async {
    final list = _readCollection(_usersKey);
    list.add(user.toJson());
    await _writeCollection(_usersKey, list);
  }

  Future<void> updateUser(UserModel user) async {
    final list = _readCollection(_usersKey);
    final idx = list.indexWhere((u) => u['id'] == user.id);
    if (idx >= 0) list[idx] = user.toJson();
    await _writeCollection(_usersKey, list);
  }

  Future<void> deleteUser(String id) async {
    final list = _readCollection(_usersKey);
    list.removeWhere((u) => u['id'] == id);
    await _writeCollection(_usersKey, list);
  }

  // ─── AUTH SESSION ────────────────────────────────────────────────────────────
  Future<void> setCurrentUserId(String id) async {
    await _prefs.setString(_currentUserKey, id);
  }

  String? getCurrentUserId() => _prefs.getString(_currentUserKey);

  Future<void> clearCurrentUser() async {
    await _prefs.remove(_currentUserKey);
  }

  // ─── SCHEDULES ───────────────────────────────────────────────────────────────
  Future<List<ScheduleItem>> getSchedulesByGroup(String groupId) async {
    return _readCollection(_schedulesKey)
        .map(ScheduleItem.fromJson)
        .where((s) => s.groupId == groupId)
        .toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  Future<void> createSchedule(ScheduleItem item) async {
    final list = _readCollection(_schedulesKey);
    list.add(item.toJson());
    await _writeCollection(_schedulesKey, list);
  }

  Future<void> updateSchedule(ScheduleItem item) async {
    final list = _readCollection(_schedulesKey);
    final idx = list.indexWhere((s) => s['id'] == item.id);
    if (idx >= 0) list[idx] = item.toJson();
    await _writeCollection(_schedulesKey, list);
  }

  Future<void> deleteSchedule(String id) async {
    final list = _readCollection(_schedulesKey);
    list.removeWhere((s) => s['id'] == id);
    await _writeCollection(_schedulesKey, list);
  }

  // ─── QUICK ACTIONS ───────────────────────────────────────────────────────────
  Future<List<QuickActionButton>> getQuickActionsByGroup(String groupId) async {
    return _readCollection(_quickActionsKey)
        .map(QuickActionButton.fromJson)
        .where((q) => q.groupId == groupId)
        .toList();
  }

  Future<void> createQuickAction(QuickActionButton action) async {
    final list = _readCollection(_quickActionsKey);
    list.add(action.toJson());
    await _writeCollection(_quickActionsKey, list);
  }

  Future<void> updateQuickAction(QuickActionButton action) async {
    final list = _readCollection(_quickActionsKey);
    final idx = list.indexWhere((q) => q['id'] == action.id);
    if (idx >= 0) list[idx] = action.toJson();
    await _writeCollection(_quickActionsKey, list);
  }

  Future<void> deleteQuickAction(String id) async {
    final list = _readCollection(_quickActionsKey);
    list.removeWhere((q) => q['id'] == id);
    await _writeCollection(_quickActionsKey, list);
  }

  // ─── GROUPS ──────────────────────────────────────────────────────────────────
  Future<List<CareGroup>> getAllGroups() async {
    return _readCollection(_groupsKey).map(CareGroup.fromJson).toList();
  }

  Future<CareGroup?> getGroupById(String id) async {
    final all = await getAllGroups();
    try {
      return all.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<CareGroup?> getGroupByInviteCode(String code) async {
    final all = await getAllGroups();
    try {
      return all.firstWhere(
          (g) => g.inviteCode.toUpperCase() == code.toUpperCase());
    } catch (_) {
      return null;
    }
  }

  Future<CareGroup?> getGroupForUser(String userId) async {
    final all = await getAllGroups();
    try {
      return all.firstWhere(
          (g) => g.elderlyId == userId || g.memberIds.contains(userId));
    } catch (_) {
      return null;
    }
  }

  Future<void> createGroup(CareGroup group) async {
    final list = _readCollection(_groupsKey);
    list.add(group.toJson());
    await _writeCollection(_groupsKey, list);
  }

  Future<void> updateGroup(CareGroup group) async {
    final list = _readCollection(_groupsKey);
    final idx = list.indexWhere((g) => g['id'] == group.id);
    if (idx >= 0) list[idx] = group.toJson();
    await _writeCollection(_groupsKey, list);
  }

  Future<void> deleteGroup(String id) async {
    final list = _readCollection(_groupsKey);
    list.removeWhere((g) => g['id'] == id);
    await _writeCollection(_groupsKey, list);
  }

  /// Add caregiver to group (enforces max 5)
  Future<bool> joinGroup(String groupId, String caregiverId) async {
    final group = await getGroupById(groupId);
    if (group == null) return false;
    if (group.isFull) return false;
    if (group.memberIds.contains(caregiverId)) return true;
    final updated = group.copyWith(
      memberIds: [...group.memberIds, caregiverId],
    );
    await updateGroup(updated);
    return true;
  }

  Future<void> leaveGroup(String groupId, String userId) async {
    final group = await getGroupById(groupId);
    if (group == null) return;
    final newMembers = group.memberIds.where((id) => id != userId).toList();
    final updated = group.copyWith(memberIds: newMembers);
    await updateGroup(updated);
  }

  // ─── ACTION REQUESTS ─────────────────────────────────────────────────────────
  Future<List<ActionRequest>> getRequestsByGroup(String groupId) async {
    return _readCollection(_requestsKey)
        .map(ActionRequest.fromJson)
        .where((r) => r.groupId == groupId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> createRequest(ActionRequest req) async {
    final list = _readCollection(_requestsKey);
    list.add(req.toJson());
    await _writeCollection(_requestsKey, list);
  }

  Future<void> updateRequest(ActionRequest req) async {
    final list = _readCollection(_requestsKey);
    final idx = list.indexWhere((r) => r['id'] == req.id);
    if (idx >= 0) list[idx] = req.toJson();
    await _writeCollection(_requestsKey, list);
  }

  Future<void> deleteRequest(String id) async {
    final list = _readCollection(_requestsKey);
    list.removeWhere((r) => r['id'] == id);
    await _writeCollection(_requestsKey, list);
  }

  // ─── MOMENTS ─────────────────────────────────────────────────────────────────
  Future<List<Moment>> getMomentsByGroup(String groupId) async {
    return _readCollection(_momentsKey)
        .map(Moment.fromJson)
        .where((m) => m.groupId == groupId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> createMoment(Moment moment) async {
    final list = _readCollection(_momentsKey);
    list.add(moment.toJson());
    await _writeCollection(_momentsKey, list);
  }

  Future<void> updateMoment(Moment moment) async {
    final list = _readCollection(_momentsKey);
    final idx = list.indexWhere((m) => m['id'] == moment.id);
    if (idx >= 0) list[idx] = moment.toJson();
    await _writeCollection(_momentsKey, list);
  }

  Future<void> deleteMoment(String id) async {
    final list = _readCollection(_momentsKey);
    list.removeWhere((m) => m['id'] == id);
    await _writeCollection(_momentsKey, list);
  }
}
