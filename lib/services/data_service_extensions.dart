// data_service_extensions.dart
// Add these methods to DataService so EventService can read/write raw strings
// and access the server base URL.
//
// HOW TO USE:
//   Copy the methods below into your existing DataService class body
//   (in data_service.dart), inside the class definition.
//
// ─────────────────────────────────────────────────────────────────────────────

/*
  ── Add to DataService ────────────────────────────────────────────────────────

  // Server base URL — update this to your deployed server address
  String get serverBaseUrl => 'http://10.0.2.2:3000'; // Android emulator default
  // For iOS simulator use: 'http://localhost:3000'
  // For production: 'https://your-server.com'

  // Raw string helpers used by EventService to cache events + interests
  String? getRawString(String key) => _prefs.getString(key);

  Future<void> setRawString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  Future<void> removeRawString(String key) async {
    await _prefs.remove(key);
  }
*/
