import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pairing_controller.dart';

/// Android Keystore-backed storage adapter for the companion's pairing secret.
class SecureKeyStore implements KeyValueStore {
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}
