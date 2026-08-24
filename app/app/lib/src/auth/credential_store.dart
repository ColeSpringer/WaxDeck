import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the native bearer token lives between launches. WaxDeck-owned
/// port: feature code never touches the storage plugin directly.
///
/// Web builds use [InMemoryCredentialStore], which persists nothing; the
/// HttpOnly session cookie is the credential there.
abstract interface class CredentialStorePort {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clearToken();

  /// The adopted server address, beside the token because the two live
  /// and die together: a token is only ever presented to the server
  /// that minted it.
  Future<String?> readServerAddress();
  Future<void> writeServerAddress(String address);
  Future<void> clearServerAddress();
}

/// OS-keychain-backed store over flutter_secure_storage.
///
/// Every call swallows storage failures: a missing keychain (locked
/// keyring on Linux, plugin absent in widget tests) must degrade to a
/// fresh login, never crash startup.
class SecureCredentialStore implements CredentialStorePort {
  const SecureCredentialStore();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'waxdeck.authToken';
  static const _addressKey = 'waxdeck.serverAddress';

  @override
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {
      // Best effort; the session still works until the app exits.
    }
  }

  @override
  Future<void> clearToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // Nothing readable survives if the read path fails the same way.
    }
  }

  @override
  Future<String?> readServerAddress() async {
    try {
      return await _storage.read(key: _addressKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeServerAddress(String address) async {
    try {
      await _storage.write(key: _addressKey, value: address);
    } catch (_) {
      // Best effort; the address holds until the app exits.
    }
  }

  @override
  Future<void> clearServerAddress() async {
    try {
      await _storage.delete(key: _addressKey);
    } catch (_) {
      // Nothing readable survives if the read path fails the same way.
    }
  }
}

/// Non-persistent store for web builds and tests.
class InMemoryCredentialStore implements CredentialStorePort {
  String? token;
  String? serverAddress;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<String?> readServerAddress() async => serverAddress;

  @override
  Future<void> writeServerAddress(String address) async =>
      serverAddress = address;

  @override
  Future<void> clearServerAddress() async => serverAddress = null;
}
