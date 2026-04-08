import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/schedule_model.dart';
import '../models/quick_action_model.dart';
import '../models/group_model.dart';
import '../models/request_model.dart';
import '../models/moment_model.dart';
import '../models/safezone_model.dart';
import '../models/alarm_prefs.dart';
import 'notification_service.dart';

/// ---------------------------------------------------------------------------
/// DataService — hybrid storage layer:
///
///   FIRESTORE (shared, real-time across devices):
///     • users            → /users/{id}
///     • groups           → /groups/{id}
///     • schedules        → /schedules/{id}
///     • quick_actions    → /quick_actions/{id}
///     • action_requests  → /action_requests/{id}
///     • safe_zones       → /safe_zones/{elderlyId}
///
///   SHARED PREFERENCES (device-local only):
///     • current user session  (ec_current_user_id)
///     • event cache           (ec_events_cache / ec_events_cache_ts)
///     • user interests        (ec_user_interests_<userId>)
///     • raw key-value helpers used by EventService
///
///   BACKEND SERVER (unchanged — not Firebase):
///     • Moments images & event data  →  ApiService / EventService
///
/// To disable Firestore and fall back to SharedPreferences for all
/// collections (e.g. during tests) set [useFirestore] = false before
/// calling [init()].
/// ---------------------------------------------------------------------------
class DataService {
  // ── Firestore collection names ───────────────────────────────────────────
  static const String _colUsers         = 'users';
  static const String _colGroups        = 'groups';
  static const String _colSchedules     = 'schedules';
  static const String _colActions       = 'quick_actions';
  static const String _colRequests      = 'action_requests';
  static const String _colSafeZone      = 'safe_zones';
  // Notification documents are ephemeral — written here, deleted after read.
  static const String _colNotifications = 'notifications';
  // Alarm preferences (Firestore + local cache)
  static const String _colAlarmPrefs        = 'alarm_prefs';
  static const String _alarmPrefsKeyPrefix   = 'ec_alarm_prefs_';

  // ── SharedPrefs keys (local-only) ────────────────────────────────────────
  static const String _currentUserKey = 'ec_current_user_id';

  // ── Singleton ─────────────────────────────────────────────────────────────
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;

  /// Set to false in unit tests to skip Firestore entirely.
  bool useFirestore = true;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // ── FCM TOKEN ─────────────────────────────────────────────────────────────

  /// Saves [token] on the Firestore user document so other devices can send
  /// this device a push notification.
  Future<void> saveFcmToken(String userId, String token) async {
    if (!useFirestore) return;
    await _db.collection(_colUsers).doc(userId).set(
      {'fcmToken': token, 'fcmTokenUpdatedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  /// Returns the FCM tokens for every member of [groupId], including the
  /// elderly and all caregivers. Skips users with no token.
  Future<List<String>> getFcmTokensForGroup(
      String groupId, {
      String? excludeUserId,
  }) async {
    if (!useFirestore) return [];
    try {
      final group = await getGroupById(groupId);
      if (group == null) return [];

      final userIds = [
        if (group.elderlyId.isNotEmpty) group.elderlyId,
        ...group.memberIds,
      ];

      final tokens = <String>[];
      for (final uid in userIds) {
        if (uid == excludeUserId) continue;
        final doc = await _db.collection(_colUsers).doc(uid).get();
        if (!doc.exists) continue;
        // ignore: unnecessary_cast
        final data = doc.data() as Map<String, dynamic>?;
        final token = data?['fcmToken'] as String?;
        if (token != null && token.isNotEmpty) tokens.add(token);
      }
      return tokens;
    } catch (e) {
      debugPrint('getFcmTokensForGroup error: $e');
      return [];
    }
  }

  // ── CROSS-DEVICE NOTIFICATIONS VIA FIRESTORE STREAM ─────────────────────
  //
  // Architecture: instead of a Cloud Function (which requires the Blaze plan),
  // we write a small notification document to Firestore.  Every signed-in
  // device runs a Firestore stream listener (started in AuthProvider after
  // login) that watches for documents addressed to itself and shows a local
  // notification immediately — even when the app is in the background.
  // The document is deleted right after being read to avoid re-delivery.
  //
  // When the app IS fully terminated, FCM Data-only messages (sent from another
  // device calling [sendPushToTokens]) wake the app's background isolate and
  // show the notification through the top-level handler in notification_service.

  /// Writes a notification document addressed to the given [targetUserId].
  /// The recipient's device, if online, will read and display it immediately.
  Future<void> sendNotificationDocument({
    required String targetUserId,
    required String title,
    required String body,
    String channel = 'eldercare_high_priority',
    String? payload,
  }) async {
    if (!useFirestore) return;
    try {
      await _db.collection(_colNotifications).add({
        'targetUserId': targetUserId,
        'title': title,
        'body': body,
        'channel': channel,
        'payload': payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('sendNotificationDocument error: $e');
    }
  }

  /// Watches for notification documents addressed to [userId] and fires the
  /// local notification immediately, then deletes the document.
  /// Call this once after login; cancel the returned [StreamSubscription]
  /// on logout.
  Stream<void> streamIncomingNotifications(String userId) {
    if (!useFirestore) return const Stream.empty();
    return _db
        .collection(_colNotifications)
        .where('targetUserId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snap) async {
          for (final doc in snap.docs) {
            final data = doc.data();
            final title   = data['title']   as String? ?? 'ElderCare';
            final body    = data['body']    as String? ?? '';
            final channel = data['channel'] as String? ?? 'eldercare_high_priority';
            final payload = data['payload'] as String?;

            // Show local notification on this device.
            await NotificationService().showInstantAlert(
              title: title,
              body: body,
              channel: channel,
              payload: payload,
            );

            // Delete so it is not delivered twice.
            await doc.reference.delete();
          }
        });
  }

  // ── Generic helpers ───────────────────────────────────────────────────────

  /// Read raw string from SharedPrefs (used by EventService for cache/interests)
  String? getRawString(String key) => _prefs.getString(key);

  /// Write raw string to SharedPrefs (used by EventService for cache/interests)
  Future<void> setRawString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  // ── USERS ─────────────────────────────────────────────────────────────────

  Future<List<UserModel>> getAllUsers() async {
    if (!useFirestore) return _localUsers();
    final snap = await _db.collection(_colUsers).get();
    return snap.docs.map((d) => UserModel.fromJson(_docData(d))).toList();
  }

  Future<UserModel?> getUserById(String id) async {
    if (!useFirestore) {
      final all = await _localUsers();
      try { return all.firstWhere((u) => u.id == id); } catch (_) { return null; }
    }
    final doc = await _db.collection(_colUsers).doc(id).get();
    if (!doc.exists) return null;
    return UserModel.fromJson(_docData(doc));
  }

  Future<UserModel?> getUserByEmail(String email) async {
    if (!useFirestore) {
      final all = await _localUsers();
      try {
        return all.firstWhere((u) => u.email.toLowerCase() == email.toLowerCase());
      } catch (_) { return null; }
    }
    final snap = await _db
        .collection(_colUsers)
        .where('email', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return UserModel.fromJson(_docData(snap.docs.first));
  }

  Future<void> createUser(UserModel user) async {
    final json = user.toJson()..['email'] = user.email.toLowerCase();
    if (!useFirestore) { await _localWriteUser(json); return; }
    await _db.collection(_colUsers).doc(user.id).set(json);
  }

  Future<void> updateUser(UserModel user) async {
    final json = user.toJson()..['email'] = user.email.toLowerCase();
    if (!useFirestore) { await _localUpdateUser(json); return; }
    await _db.collection(_colUsers).doc(user.id).set(json, SetOptions(merge: true));
  }

  Future<void> deleteUser(String id) async {
    if (!useFirestore) { await _localDeleteUser(id); return; }
    await _db.collection(_colUsers).doc(id).delete();
  }

  // ── INTERESTS (Stored on User Doc) ────────────────────────────────────────

  Future<List<String>> getUserInterests(String userId) async {
    if (!useFirestore) return _localGetUserInterests(userId);
    final doc = await _db.collection(_colUsers).doc(userId).get();
    if (!doc.exists) return [];
    final data = doc.data() as Map<String, dynamic>;
    if (data['interests'] != null) {
      return (data['interests'] as List).cast<String>();
    }
    return [];
  }

  Future<void> saveUserInterests(String userId, List<String> interests) async {
    if (!useFirestore) { await _localSaveUserInterests(userId, interests); return; }
    await _db.collection(_colUsers).doc(userId).set({
      'interests': interests,
    }, SetOptions(merge: true));
  }

  Future<bool> hasSetInterests(String userId) async {
    if (!useFirestore) return _localHasSetInterests(userId);
    final doc = await _db.collection(_colUsers).doc(userId).get();
    if (!doc.exists) return false;
    final data = doc.data() as Map<String, dynamic>;
    return data['interests'] != null && (data['interests'] as List).isNotEmpty;
  }

  // ── AUTH SESSION (always local) ───────────────────────────────────────────

  Future<void> setCurrentUserId(String id) async =>
      _prefs.setString(_currentUserKey, id);

  String? getCurrentUserId() => _prefs.getString(_currentUserKey);

  Future<void> clearCurrentUser() async => _prefs.remove(_currentUserKey);

  // ── SCHEDULES ─────────────────────────────────────────────────────────────

  Future<List<ScheduleItem>> getSchedulesByGroup(String groupId) async {
    if (!useFirestore) return _localSchedules(groupId);
    try {
      final snap = await _db
          .collection(_colSchedules)
          .where('groupId', isEqualTo: groupId)
          .get();
      final list = snap.docs.map((d) => ScheduleItem.fromJson(_docData(d))).toList();
      list.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      return list;
    } catch (e) {
      debugPrint('Error getSchedulesByGroup: $e');
      return [];
    }
  }

  Stream<List<ScheduleItem>> streamSchedulesByGroup(String groupId) {
    if (!useFirestore) return Stream.value([]);
    return _db
        .collection(_colSchedules)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => ScheduleItem.fromJson(_docData(d))).toList();
          list.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
          return list;
        })
        .handleError((e) {
          debugPrint('Stream error schedules: $e');
        });
  }

  Future<void> createSchedule(ScheduleItem item) async {
    if (!useFirestore) { await _localWriteSchedule(item.toJson()); return; }
    await _db.collection(_colSchedules).doc(item.id).set(item.toJson());
  }

  Future<void> updateSchedule(ScheduleItem item) async {
    if (!useFirestore) { await _localUpdateSchedule(item.toJson()); return; }
    await _db.collection(_colSchedules).doc(item.id).set(item.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteSchedule(String id) async {
    if (!useFirestore) { await _localDeleteSchedule(id); return; }
    await _db.collection(_colSchedules).doc(id).delete();
  }

  // ── QUICK ACTIONS ─────────────────────────────────────────────────────────

  Future<List<QuickActionButton>> getQuickActionsByGroup(String groupId) async {
    if (!useFirestore) return _localQuickActions(groupId);
    final snap = await _db
        .collection(_colActions)
        .where('groupId', isEqualTo: groupId)
        .get();
    return snap.docs.map((d) => QuickActionButton.fromJson(_docData(d))).toList();
  }

  Future<void> createQuickAction(QuickActionButton action) async {
    if (!useFirestore) { await _localWriteQuickAction(action.toJson()); return; }
    await _db.collection(_colActions).doc(action.id).set(action.toJson());
  }

  Future<void> updateQuickAction(QuickActionButton action) async {
    if (!useFirestore) { await _localUpdateQuickAction(action.toJson()); return; }
    await _db.collection(_colActions).doc(action.id).set(action.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteQuickAction(String id) async {
    if (!useFirestore) { await _localDeleteQuickAction(id); return; }
    await _db.collection(_colActions).doc(id).delete();
  }

  // ── GROUPS ────────────────────────────────────────────────────────────────

  Future<List<CareGroup>> getAllGroups() async {
    if (!useFirestore) return _localGroups();
    final snap = await _db.collection(_colGroups).get();
    return snap.docs.map((d) => CareGroup.fromJson(_docData(d))).toList();
  }

  Future<CareGroup?> getGroupById(String id) async {
    if (!useFirestore) {
      final all = await _localGroups();
      try { return all.firstWhere((g) => g.id == id); } catch (_) { return null; }
    }
    final doc = await _db.collection(_colGroups).doc(id).get();
    if (!doc.exists) return null;
    return CareGroup.fromJson(_docData(doc));
  }

  Future<CareGroup?> getGroupByInviteCode(String code) async {
    // inviteCode is the first 8 chars of the group id (uppercase).
    // We query by the 'inviteCode' field we store in Firestore.
    if (!useFirestore) {
      final all = await _localGroups();
      try {
        return all.firstWhere(
            (g) => g.inviteCode.toUpperCase() == code.toUpperCase());
      } catch (_) { return null; }
    }
    final snap = await _db
        .collection(_colGroups)
        .where('inviteCode', isEqualTo: code.toUpperCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return CareGroup.fromJson(_docData(snap.docs.first));
  }

  Future<CareGroup?> getGroupForUser(String userId) async {
    if (!useFirestore) {
      final all = await _localGroups();
      try {
        return all.firstWhere(
            (g) => g.elderlyId == userId || g.memberIds.contains(userId));
      } catch (_) { return null; }
    }
    // Try as caregiver member first
    var snap = await _db
        .collection(_colGroups)
        .where('memberIds', arrayContains: userId)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) return CareGroup.fromJson(_docData(snap.docs.first));
    // Then try as elderly
    snap = await _db
        .collection(_colGroups)
        .where('elderlyId', isEqualTo: userId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return CareGroup.fromJson(_docData(snap.docs.first));
  }

  Future<void> createGroup(CareGroup group) async {
    final json = group.toJson()..['inviteCode'] = group.inviteCode;
    if (!useFirestore) { await _localWriteGroup(json); return; }
    await _db.collection(_colGroups).doc(group.id).set(json);
  }

  Future<void> updateGroup(CareGroup group) async {
    final json = group.toJson()..['inviteCode'] = group.inviteCode;
    if (!useFirestore) { await _localUpdateGroup(json); return; }
    await _db.collection(_colGroups).doc(group.id).set(json, SetOptions(merge: true));
  }

  Future<void> deleteGroup(String id) async {
    if (!useFirestore) { await _localDeleteGroup(id); return; }
    await _db.collection(_colGroups).doc(id).delete();
  }

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
    await updateGroup(group.copyWith(memberIds: newMembers));
  }

  // ── ACTION REQUESTS ───────────────────────────────────────────────────────

  Future<List<ActionRequest>> getRequestsByGroup(String groupId) async {
    if (!useFirestore) return _localRequests(groupId);
    try {
      final snap = await _db
          .collection(_colRequests)
          .where('groupId', isEqualTo: groupId)
          .get();
      final list = snap.docs.map((d) => ActionRequest.fromJson(_docData(d))).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      debugPrint('Error getRequestsByGroup: $e');
      return [];
    }
  }

  Stream<List<ActionRequest>> streamRequestsByGroup(String groupId) {
    if (!useFirestore) return Stream.value([]);
    return _db
        .collection(_colRequests)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => ActionRequest.fromJson(_docData(d))).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        })
        .handleError((e) {
          debugPrint('Stream error requests: $e');
        });
  }

  Future<void> createRequest(ActionRequest req) async {
    if (!useFirestore) { await _localWriteRequest(req.toJson()); return; }
    await _db.collection(_colRequests).doc(req.id).set(req.toJson());
  }

  Future<void> updateRequest(ActionRequest req) async {
    if (!useFirestore) { await _localUpdateRequest(req.toJson()); return; }
    await _db.collection(_colRequests).doc(req.id).set(req.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteRequest(String id) async {
    if (!useFirestore) { await _localDeleteRequest(id); return; }
    await _db.collection(_colRequests).doc(id).delete();
  }

  // ── MOMENTS (local only — actual data lives on backend server) ────────────
  // These local methods only cache moment metadata for offline use.
  // The authoritative store is the Node.js server (ApiService).

  Future<List<Moment>> getMomentsByGroup(String groupId) async {
    return _readLocalCollection('ec_moments')
        .map(Moment.fromJson)
        .where((m) => m.groupId == groupId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> createMoment(Moment moment) async {
    final list = _readLocalCollection('ec_moments');
    list.add(moment.toJson());
    await _writeLocalCollection('ec_moments', list);
  }

  Future<void> updateMoment(Moment moment) async {
    final list = _readLocalCollection('ec_moments');
    final idx = list.indexWhere((m) => m['id'] == moment.id);
    if (idx >= 0) list[idx] = moment.toJson();
    await _writeLocalCollection('ec_moments', list);
  }

  Future<void> deleteMoment(String id) async {
    final list = _readLocalCollection('ec_moments');
    list.removeWhere((m) => m['id'] == id);
    await _writeLocalCollection('ec_moments', list);
  }

  // ── SAFE ZONE ─────────────────────────────────────────────────────────────

  Future<SafeZoneSettings?> getSafeZone(String elderlyId) async {
    if (!useFirestore) return _localGetSafeZone(elderlyId);
    final doc = await _db.collection(_colSafeZone).doc(elderlyId).get();
    if (!doc.exists) return null;
    try {
      return SafeZoneSettings.fromJson(_docData(doc));
    } catch (_) { return null; }
  }

  Future<void> saveSafeZone(SafeZoneSettings settings) async {
    if (!useFirestore) { await _localSaveSafeZone(settings); return; }
    await _db
        .collection(_colSafeZone)
        .doc(settings.elderlyId)
        .set(settings.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteSafeZone(String elderlyId) async {
    if (!useFirestore) { await _localDeleteSafeZone(elderlyId); return; }
    await _db.collection(_colSafeZone).doc(elderlyId).delete();
  }

  // ── ALARM PREFERENCES ────────────────────────────────────────────────
  //
  // Stored in two places:
  //   • Firestore /alarm_prefs/{userId}  (shared — survives reinstalls)
  //   • SharedPreferences                (local cache — instant reads)

  /// Returns the current [AlarmPrefs] for [userId].
  /// Reads from Firestore when available, falls back to SharedPreferences.
  Future<AlarmPrefs> getAlarmPrefs(String userId) async {
    if (useFirestore) {
      try {
        final doc = await _db.collection(_colAlarmPrefs).doc(userId).get();
        if (doc.exists) {
          final prefs = AlarmPrefs.fromJson(_docData(doc));
          await _prefs.setString(
              '$_alarmPrefsKeyPrefix$userId', jsonEncode(prefs.toJson()));
          return prefs;
        }
      } catch (e) {
        debugPrint('getAlarmPrefs Firestore error: \$e');
      }
    }
    final raw = _prefs.getString('$_alarmPrefsKeyPrefix$userId');
    if (raw != null && raw.isNotEmpty) {
      try {
        return AlarmPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return const AlarmPrefs();
  }

  /// Persists [prefs] for [userId] to Firestore and local cache.
  Future<void> saveAlarmPrefs(String userId, AlarmPrefs prefs) async {
    await _prefs.setString(
        '$_alarmPrefsKeyPrefix$userId', jsonEncode(prefs.toJson()));
    if (useFirestore) {
      try {
        await _db
            .collection(_colAlarmPrefs)
            .doc(userId)
            .set(prefs.toJson(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('saveAlarmPrefs Firestore error: \$e');
      }
    }
  }

  /// Clears alarm prefs for [userId] (resets to defaults).
  Future<void> deleteAlarmPrefs(String userId) async {
    await _prefs.remove('$_alarmPrefsKeyPrefix$userId');
    if (useFirestore) {
      try {
        await _db.collection(_colAlarmPrefs).doc(userId).delete();
      } catch (e) {
        debugPrint('deleteAlarmPrefs error: \$e');
      }
    }
  }

  // =========================================================================
  // FIRESTORE HELPER
  // =========================================================================

  /// Converts a Firestore document snapshot to a plain Map, handling
  /// Timestamp → ISO-8601 string conversion so existing fromJson() methods work.
  Map<String, dynamic> _docData(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return _convertTimestamps(data);
  }

  Map<String, dynamic> _convertTimestamps(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      } else if (value is Map<String, dynamic>) {
        return MapEntry(key, _convertTimestamps(value));
      } else if (value is List) {
        return MapEntry(key, value.map((e) {
          if (e is Map<String, dynamic>) return _convertTimestamps(e);
          if (e is Timestamp) return e.toDate().toIso8601String();
          return e;
        }).toList());
      }
      return MapEntry(key, value);
    });
  }

  // =========================================================================
  // LOCAL (SharedPreferences) FALLBACKS
  // Used when useFirestore = false, or for moment metadata cache.
  // =========================================================================

  List<Map<String, dynamic>> _readLocalCollection(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _writeLocalCollection(
      String key, List<Map<String, dynamic>> data) async {
    await _prefs.setString(key, jsonEncode(data));
  }

  // -- Users (local fallback) --
  static const String _localUsersKey = 'ec_users';

  Future<List<UserModel>> _localUsers() =>
      Future.value(_readLocalCollection(_localUsersKey)
          .map(UserModel.fromJson)
          .toList());

  Future<void> _localWriteUser(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localUsersKey);
    list.add(json);
    await _writeLocalCollection(_localUsersKey, list);
  }

  Future<void> _localUpdateUser(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localUsersKey);
    final idx = list.indexWhere((u) => u['id'] == json['id']);
    if (idx >= 0) list[idx] = json;
    await _writeLocalCollection(_localUsersKey, list);
  }

  Future<void> _localDeleteUser(String id) async {
    final list = _readLocalCollection(_localUsersKey);
    list.removeWhere((u) => u['id'] == id);
    await _writeLocalCollection(_localUsersKey, list);
  }

  // -- Schedules (local fallback) --
  static const String _localSchedulesKey = 'ec_schedules';

  Future<List<ScheduleItem>> _localSchedules(String groupId) =>
      Future.value(_readLocalCollection(_localSchedulesKey)
          .map(ScheduleItem.fromJson)
          .where((s) => s.groupId == groupId)
          .toList()
        ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime)));

  Future<void> _localWriteSchedule(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localSchedulesKey);
    list.add(json);
    await _writeLocalCollection(_localSchedulesKey, list);
  }

  Future<void> _localUpdateSchedule(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localSchedulesKey);
    final idx = list.indexWhere((s) => s['id'] == json['id']);
    if (idx >= 0) list[idx] = json;
    await _writeLocalCollection(_localSchedulesKey, list);
  }

  Future<void> _localDeleteSchedule(String id) async {
    final list = _readLocalCollection(_localSchedulesKey);
    list.removeWhere((s) => s['id'] == id);
    await _writeLocalCollection(_localSchedulesKey, list);
  }

  // -- Quick Actions (local fallback) --
  static const String _localActionsKey = 'ec_quick_actions';

  Future<List<QuickActionButton>> _localQuickActions(String groupId) =>
      Future.value(_readLocalCollection(_localActionsKey)
          .map(QuickActionButton.fromJson)
          .where((q) => q.groupId == groupId)
          .toList());

  Future<void> _localWriteQuickAction(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localActionsKey);
    list.add(json);
    await _writeLocalCollection(_localActionsKey, list);
  }

  Future<void> _localUpdateQuickAction(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localActionsKey);
    final idx = list.indexWhere((q) => q['id'] == json['id']);
    if (idx >= 0) list[idx] = json;
    await _writeLocalCollection(_localActionsKey, list);
  }

  Future<void> _localDeleteQuickAction(String id) async {
    final list = _readLocalCollection(_localActionsKey);
    list.removeWhere((q) => q['id'] == id);
    await _writeLocalCollection(_localActionsKey, list);
  }

  // -- Groups (local fallback) --
  static const String _localGroupsKey = 'ec_groups';

  Future<List<CareGroup>> _localGroups() =>
      Future.value(_readLocalCollection(_localGroupsKey)
          .map(CareGroup.fromJson)
          .toList());

  Future<void> _localWriteGroup(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localGroupsKey);
    list.add(json);
    await _writeLocalCollection(_localGroupsKey, list);
  }

  Future<void> _localUpdateGroup(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localGroupsKey);
    final idx = list.indexWhere((g) => g['id'] == json['id']);
    if (idx >= 0) list[idx] = json;
    await _writeLocalCollection(_localGroupsKey, list);
  }

  Future<void> _localDeleteGroup(String id) async {
    final list = _readLocalCollection(_localGroupsKey);
    list.removeWhere((g) => g['id'] == id);
    await _writeLocalCollection(_localGroupsKey, list);
  }

  // -- Requests (local fallback) --
  static const String _localRequestsKey = 'ec_requests';

  Future<List<ActionRequest>> _localRequests(String groupId) =>
      Future.value(_readLocalCollection(_localRequestsKey)
          .map(ActionRequest.fromJson)
          .where((r) => r.groupId == groupId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  Future<void> _localWriteRequest(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localRequestsKey);
    list.add(json);
    await _writeLocalCollection(_localRequestsKey, list);
  }

  Future<void> _localUpdateRequest(Map<String, dynamic> json) async {
    final list = _readLocalCollection(_localRequestsKey);
    final idx = list.indexWhere((r) => r['id'] == json['id']);
    if (idx >= 0) list[idx] = json;
    await _writeLocalCollection(_localRequestsKey, list);
  }

  Future<void> _localDeleteRequest(String id) async {
    final list = _readLocalCollection(_localRequestsKey);
    list.removeWhere((r) => r['id'] == id);
    await _writeLocalCollection(_localRequestsKey, list);
  }

  // -- SafeZone (local fallback) --
  static String _localSafeZoneKey(String elderlyId) => 'ec_safezone:$elderlyId';

  Future<SafeZoneSettings?> _localGetSafeZone(String elderlyId) async {
    final raw = _prefs.getString(_localSafeZoneKey(elderlyId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return SafeZoneSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  Future<void> _localSaveSafeZone(SafeZoneSettings settings) async {
    await _prefs.setString(
      _localSafeZoneKey(settings.elderlyId),
      jsonEncode(settings.toJson()),
    );
  }

  Future<void> _localDeleteSafeZone(String elderlyId) async {
    await _prefs.remove(_localSafeZoneKey(elderlyId));
  }

  // -- Interests (local fallback) --
  static const String _localInterestsPrefix = 'ec_user_interests_';

  Future<List<String>> _localGetUserInterests(String userId) async {
    final raw = _prefs.getString('$_localInterestsPrefix$userId');
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<String>();
    } catch (_) { return []; }
  }

  Future<void> _localSaveUserInterests(String userId, List<String> interests) async {
    await _prefs.setString('$_localInterestsPrefix$userId', jsonEncode(interests));
  }

  Future<bool> _localHasSetInterests(String userId) async {
    return _prefs.getString('$_localInterestsPrefix$userId') != null;
  }
}
