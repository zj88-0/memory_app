import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/event_model.dart';
import 'data_service.dart';
import 'api_service.dart';

/// All 10 interest categories the elderly can pick from.
const List<String> kAllInterestCategories = [
  'Exercise & Wellness',
  'Arts & Crafts',
  'Music & Entertainment',
  'Social & Community',
  'Learning & Education',
  'Nature & Gardening',
  'Food & Cooking',
  'Technology & Digital',
  'Religious & Spiritual',
  'Games & Recreation',
];

class EventService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal();

  static const String _eventsKey      = 'ec_events_cache';
  static const String _eventsCacheTs  = 'ec_events_cache_ts';

  // ── Interest CRUD (stored via DataService → Firestore / SharedPreferences) ───
  Future<List<String>> getUserInterests(String userId) async {
    return await DataService().getUserInterests(userId);
  }

  Future<void> saveUserInterests(String userId, List<String> categories) async {
    await DataService().saveUserInterests(userId, categories);
  }

  Future<bool> hasSetInterests(String userId) async {
    return await DataService().hasSetInterests(userId);
  }

  // ── Event fetching with local cache (TTL: 1 hour) ─────────────────────────
  Future<List<EventItem>> getEvents({List<String>? categories}) async {
    // Try to get fresh data from server
    try {
      final events = await _fetchFromServer(categories: categories);
      _cacheEvents(events);
      return events;
    } catch (e) {
      // Fall back to cache
      return _loadCachedEvents(categories: categories);
    }
  }

  Future<List<EventItem>> _fetchFromServer({List<String>? categories}) async {
    const base = ApiService.baseUrl;
    String url = '$base/events';
    if (categories != null && categories.isNotEmpty) {
      url += '?categories=${Uri.encodeComponent(categories.join(','))}';
    }
    final response = await http.get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
    final list = jsonDecode(response.body) as List;
    return list.map((j) => EventItem.fromJson(j as Map<String, dynamic>)).toList();
  }

  void _cacheEvents(List<EventItem> events) {
    final json = jsonEncode(events.map((e) => e.toJson()).toList());
    DataService().setRawString(_eventsKey, json);
    DataService().setRawString(_eventsCacheTs, DateTime.now().toIso8601String());
  }

  List<EventItem> _loadCachedEvents({List<String>? categories}) {
    final raw = DataService().getRawString(_eventsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final all = list
          .map((j) => EventItem.fromJson(j as Map<String, dynamic>))
          .where((e) => e.isUpcoming)
          .toList();
      if (categories == null || categories.isEmpty) return all;
      return all
          .where((e) => categories.any(
              (c) => e.category.toLowerCase().contains(c.toLowerCase())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get recommended events filtered by user's interest categories
  Future<List<EventItem>> getRecommendedEvents(String userId) async {
    final interests = await getUserInterests(userId);
    return getEvents(categories: interests.isEmpty ? null : interests);
  }
}
