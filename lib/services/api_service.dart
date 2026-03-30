import 'dart:convert';
import 'package:http/http.dart' as http;

/// ApiService — handles HTTP calls to the Node.js server for
/// moments (image upload/fetch) and STT.
/// All local storage still goes through DataService.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  //static const String baseUrl = 'http://10.0.2.2:3000';
  static const String baseUrl = 'http://172.17.109.145:3000';

  // ── Moments ──────────────────────────────────────────────────────────────────

  /// Upload a moment (with optional image file) to the server.
  Future<bool> uploadMoment({
    required String id,
    required String groupId,
    required String authorId,
    required String authorName,
    required String caption,
    String? imagePath,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/moments');
      final request = http.MultipartRequest('POST', uri)
        ..fields['id'] = id
        ..fields['groupId'] = groupId
        ..fields['authorId'] = authorId
        ..fields['authorName'] = authorName
        ..fields['caption'] = caption
        ..fields['createdAt'] = DateTime.now().toIso8601String();
      if (imagePath != null) {
        request.files
            .add(await http.MultipartFile.fromPath('image', imagePath));
      }
      final response =
          await request.send().timeout(const Duration(seconds: 30));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      // print('Upload Error: $e');
      return false;
    }
  }

  /// Fetch moments for a group from the server.
  Future<List<Map<String, dynamic>>> fetchMoments(String groupId) async {
    try {
      final uri = Uri.parse('$baseUrl/moments/$groupId');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Delete a moment from the server.
  Future<bool> deleteMoment(String momentId) async {
    try {
      final uri = Uri.parse('$baseUrl/moments/$momentId');
      final response =
          await http.delete(uri).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get image URL for a moment
  static String imageUrl(String momentId) => '$baseUrl/moments/image/$momentId';
}
