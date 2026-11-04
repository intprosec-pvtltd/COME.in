import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class SessionManager {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'pg_access_token';
  Future<String?> restoreToken() => _storage.read(key: _tokenKey);
  Future<void> saveToken(String token) => _storage.write(key: _tokenKey,
  value: token);
  Future<void> clear() => _storage.delete(key: _tokenKey);
}
