import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> speak(String text, {String langCode = 'en'}) async {
    await _tts.stop();
    final locale = _localeFor(langCode);
    await _tts.setLanguage(locale);
    await _tts.speak(text);
  }

  Future<void> stop() async => _tts.stop();

  String _localeFor(String code) {
    switch (code) {
      case 'zh':
        return 'zh-CN';
      case 'ms':
        return 'ms-MY';
      case 'ta':
        return 'ta-IN';
      default:
        return 'en-US';
    }
  }
}
