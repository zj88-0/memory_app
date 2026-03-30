import 'dart:convert';
import 'package:http/http.dart' as http;

/// STT Service — calls the Node.js Express server for speech-to-text.
/// The server uses Google Cloud Speech-to-Text with Singlish/SG models.
/// Change [baseUrl] to your server's address.
class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  // ── Change this to your server IP/hostname ────────────────────────────────
  //static const String baseUrl = 'http://10.0.2.2:3000'; // Android emulator → localhost
  static const String baseUrl = 'http://172.17.109.145:3000';

  /// Send a WAV/M4A audio file to the server and get back a transcript.
  /// [langCode] is one of: 'en-SG', 'zh-SG', 'ms-MY', 'ta-SG'
  Future<String?> transcribe(String filePath, String langCode) async {
    try {
      final uri = Uri.parse('$baseUrl/stt');
      final request = http.MultipartRequest('POST', uri)
        ..fields['language'] = langCode
        ..files.add(await http.MultipartFile.fromPath('audio', filePath));
      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['transcript'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Map app language codes to BCP-47 codes for STT
  static String toBcp47(String appLang) {
    switch (appLang) {
      case 'zh':
        return 'zh-SG'; // Mandarin Singapore
      case 'ms':
        return 'ms-MY'; // Malay
      case 'ta':
        return 'ta-SG'; // Tamil Singapore
      default:
        return 'en-SG'; // English Singapore (Singlish-aware)
    }
  }
}
