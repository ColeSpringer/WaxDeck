import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/server_address.dart';

void main() {
  group('serverAddressCandidates', () {
    test('a full URL is tried exactly as given', () {
      expect(serverAddressCandidates('https://wax.example.com'), [
        'https://wax.example.com',
      ]);
      expect(serverAddressCandidates('http://192.168.1.20:4420'), [
        'http://192.168.1.20:4420',
      ]);
    });

    test('a path-prefix base survives, trailing slashes do not', () {
      expect(serverAddressCandidates('https://home.example.com/wax/'), [
        'https://home.example.com/wax',
      ]);
    });

    test('a bare host tries https, http, then the default port', () {
      expect(serverAddressCandidates('wax.example.com'), [
        'https://wax.example.com',
        'http://wax.example.com',
        'http://wax.example.com:4420',
      ]);
    });

    test('a bare host naming a port skips the default-port guess', () {
      expect(serverAddressCandidates('192.168.1.20:4420'), [
        'https://192.168.1.20:4420',
        'http://192.168.1.20:4420',
      ]);
    });

    test('what cannot be an address answers no candidates at all', () {
      for (final input in [
        '',
        '   ',
        'wax example.com',
        'ftp://wax.example.com',
        'https://user:pass@wax.example.com',
        'https://wax.example.com/?q=1',
        'https://wax.example.com/#frag',
        'https://',
      ]) {
        expect(serverAddressCandidates(input), isEmpty, reason: '"$input"');
      }
    });
  });

  group('resolveBootServerAddress', () {
    test('the stored address wins', () async {
      final store = InMemoryCredentialStore()
        ..serverAddress = 'https://wax.example.com';
      expect(await resolveBootServerAddress(store), 'https://wax.example.com');
    });

    test('a fresh install with nothing stored sees the gate', () async {
      expect(await resolveBootServerAddress(InMemoryCredentialStore()), isNull);
    });

    test('a live pre-address session adopts the compile-time base', () async {
      final store = InMemoryCredentialStore()..token = 'tok';
      expect(await resolveBootServerAddress(store), 'http://localhost:4420');
      // And persists it, so the migration happens exactly once.
      expect(store.serverAddress, 'http://localhost:4420');
    });
  });
}
