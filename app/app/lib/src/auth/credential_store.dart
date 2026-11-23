import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the native bearer token lives between launches. WaxDeck-owned
/// port: feature code never touches the storage plugin directly.
///
/// Web builds use [InMemoryCredentialStore], which persists nothing; the
/// HttpOnly session cookie is the credential there.
abstract interface class CredentialStorePort {
  Future<String?> readToken();
  Future<void> writeToken(String token);

  /// Drops the token, and the session remembered for it.
  Future<void> clearToken();

  /// The session the server last answered for the token, as the record
  /// [rememberedRecord] makes of it: what a start that cannot reach the
  /// server opens on. Kept where the token is, so nothing about the
  /// account sits anywhere less protected, and gone when the token goes.
  Future<String?> readSession();
  Future<void> writeSession(String session);

  /// Drops the remembered session and keeps the token: the token turned
  /// out to answer for another account.
  Future<void> clearSession();

  /// The adopted server address, beside the token because the two live
  /// and die together: a token is only ever presented to the server
  /// that minted it.
  Future<String?> readServerAddress();
  Future<void> writeServerAddress(String address);
  Future<void> clearServerAddress();
}

/// [session], a session as text, as the record kept for [token]: beside a
/// digest of the token, never the token, so the record says which token
/// the server answered it for and holds no credential. The store's token
/// and session are two writes and either can fail alone; the digest is
/// what keeps a session one of them left behind from being read as
/// another token's.
String rememberedRecord(String token, String session) =>
    jsonEncode({'for': _digest(token), 'session': session});

/// The session text [record] holds, when it was kept for [token]: null
/// for another token's record, and for text that is no record.
String? rememberedFor(String token, String record) {
  try {
    if (jsonDecode(record) case {
      'for': final String digest,
      'session': final String session,
    } when digest == _digest(token)) {
      return session;
    }
  } on FormatException {
    // Not a record.
  }
  return null;
}

String _digest(String token) => sha256.convert(utf8.encode(token)).toString();

/// OS-keychain-backed store over flutter_secure_storage.
///
/// Every call swallows storage failures: a missing keychain (locked
/// keyring on Linux, plugin absent in widget tests) must degrade to a
/// fresh login, never crash startup.
class SecureCredentialStore implements CredentialStorePort {
  const SecureCredentialStore();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'waxdeck.authToken';
  static const _sessionKey = 'waxdeck.session';
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
    // First, and on its own, so a token delete that fails does not keep
    // the session too. One this fails to clear stays for a token that
    // went, and its digest keeps it from being read as the next one's.
    await clearSession();
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // Nothing readable survives if the read path fails the same way.
    }
  }

  @override
  Future<String?> readSession() async {
    try {
      return await _storage.read(key: _sessionKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeSession(String session) async {
    try {
      await _storage.write(key: _sessionKey, value: session);
    } catch (_) {
      // Best effort; a start out of the server's reach asks to sign in.
    }
  }

  @override
  Future<void> clearSession() async {
    try {
      await _storage.delete(key: _sessionKey);
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
  String? session;
  String? serverAddress;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clearToken() async {
    session = null;
    token = null;
  }

  @override
  Future<String?> readSession() async => session;

  @override
  Future<void> writeSession(String value) async => session = value;

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<String?> readServerAddress() async => serverAddress;

  @override
  Future<void> writeServerAddress(String address) async =>
      serverAddress = address;

  @override
  Future<void> clearServerAddress() async => serverAddress = null;
}
