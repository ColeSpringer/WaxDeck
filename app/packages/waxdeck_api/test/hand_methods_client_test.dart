import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _user = {
  'id': 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  'username': 'listener',
  'roles': ['user'],
  'uploadEnabled': false,
};

const _loginAnswer = {'user': _user, 'token': 'tok-1', 'csrfToken': 'csrf-1'};

const _timeline = {
  'pid': 'tl-1',
  'url': '/media/timeline/tl-1.flac',
  'mimeType': 'audio/flac',
  'durationMs': 9000,
  'expiresAt': '2026-10-16T00:00:00Z',
  'envelopeRate': 100,
  'boundaries': [
    {'pid': 'tr-1', 'offsetSamples': 0, 'durationSamples': 441000},
  ],
};

void main() {
  group('createQueueTimeline', () {
    test('sends the queue and reads the timeline a 201 carries', () async {
      final adapter = RecordingAdapter(status: 201, body: _timeline);
      final timeline = await clientOn(
        adapter,
      ).createQueueTimeline(['tr-1'], crossfadeSeconds: 2.5, formats: ['flac']);

      final sent = adapter.sent.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/player/timeline');
      expect(sent.json, {
        'itemPids': ['tr-1'],
        'crossfadeSeconds': 2.5,
        'formats': ['flac'],
      });
      expect(timeline.pid, 'tl-1');
      expect(timeline.url, 'http://host:4420/media/timeline/tl-1.flac');
      expect(timeline.members.single.pid, 'tr-1');
    });

    test('a 202 is the measuring exception, with the job to poll', () async {
      final client = clientOn(
        RecordingAdapter(status: 202, body: {'pid': 'jb-7'}),
      );
      await expectLater(
        client.createQueueTimeline(['tr-1']),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'timeline-measuring')
              .having((e) => e.statusCode, 'statusCode', 202)
              .having((e) => e.params, 'params', {'job': 'jb-7'}),
        ),
      );
    });

    test('a 202 with no readable job names an empty one', () async {
      final client = clientOn(RecordingAdapter(status: 202, body: 'later'));
      await expectLater(
        client.createQueueTimeline(['tr-1']),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'timeline-measuring')
              .having((e) => e.statusCode, 'statusCode', 202)
              .having((e) => e.params, 'params', {'job': ''}),
        ),
      );
    });

    test('any other failure is the server\'s own answer', () async {
      final client = clientOn(
        RecordingAdapter(
          status: 400,
          body: {'code': 'invalid-request', 'message': 'no pids'},
        ),
      );
      await expectLater(
        client.createQueueTimeline(const []),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'invalid-request')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });

  group('an entity call goes to the endpoint its pid prefix names', () {
    const playState = {'pid': 'x', 'starred': true, 'rating': 80};
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);

    for (final (prefix, root) in const [
      ('ar-1', 'artists'),
      ('al-1', 'albums'),
    ]) {
      test('$prefix reads its play state under /$root', () async {
        final adapter = RecordingAdapter(body: playState);
        final state = await clientOn(adapter).getEntityPlayState(prefix);
        expect(adapter.sent.single.method, 'GET');
        expect(adapter.sent.single.path, '/$root/$prefix/play-state');
        expect(state.starred, isTrue);
        expect(state.rating, 80);
      });

      test('$prefix stars under /$root', () async {
        final adapter = RecordingAdapter(body: playState);
        await clientOn(adapter).setEntityStar(prefix, true, recordedAt: at);
        expect(adapter.sent.single.method, 'PUT');
        expect(adapter.sent.single.path, '/$root/$prefix/star');
        expect(adapter.sent.single.json, {
          'starred': true,
          'recordedAt': '2026-01-02T03:04:05.000Z',
        });
      });

      test('$prefix rates under /$root, and clears with null', () async {
        final adapter = RecordingAdapter(body: playState);
        final client = clientOn(adapter);
        await client.setEntityRating(prefix, 80);
        await client.setEntityRating(prefix, null);
        expect(adapter.sent.map((s) => (s.method, s.path)), [
          ('PUT', '/$root/$prefix/rating'),
          ('PUT', '/$root/$prefix/rating'),
        ]);
        expect(adapter.sent.map((s) => s.json), [
          {'rating': 80},
          {'rating': null},
        ]);
      });
    }

    test('another prefix is refused before anything is sent', () async {
      final adapter = RecordingAdapter(body: playState);
      final client = clientOn(adapter);
      await expectLater(client.getEntityPlayState('tr-1'), throwsArgumentError);
      await expectLater(
        client.setEntityStar('tr-1', true),
        throwsArgumentError,
      );
      await expectLater(
        client.setEntityRating('bk-1', 50),
        throwsArgumentError,
      );
      expect(adapter.sent, isEmpty);
    });
  });

  group('getWaveform', () {
    test('asks for the part by default', () async {
      final sent = await requestOf((c) => c.getWaveform('bk-1'));
      expect(sent.method, 'GET');
      expect(sent.path, '/items/bk-1/waveform');
      expect(sent.query, isEmpty);
    });

    test('asks for the whole item with span=item', () async {
      final sent = await requestOf(
        (c) => c.getWaveform('bk-1', wholeItem: true),
      );
      expect(sent.query, {
        'span': ['item'],
      });
    });
  });

  group('resolving pids', () {
    test('no entity pids is nothing to ask', () async {
      final adapter = RecordingAdapter(body: {'entities': <Object?>[]});
      final resolved = await clientOn(adapter).resolveEntities(const []);
      expect(resolved.cards, isEmpty);
      expect(adapter.sent, isEmpty);
    });

    test('no item pids is nothing to ask', () async {
      final adapter = RecordingAdapter(body: {'items': <Object?>[]});
      final resolved = await clientOn(adapter).resolveItems(const []);
      expect(resolved.items, isEmpty);
      expect(resolved.departed, isEmpty);
      expect(adapter.sent, isEmpty);
    });

    test('entity pids are sent as the lookup', () async {
      final adapter = RecordingAdapter(body: {'entities': <Object?>[]});
      await clientOn(adapter).resolveEntities(['ar-1', 'al-1']);
      final sent = adapter.sent.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/library/entities');
      expect(sent.json, {
        'pids': ['ar-1', 'al-1'],
      });
    });
  });

  group('rescanLibrary', () {
    const job = {'pid': 'jb-1', 'kind': 'scan', 'state': 'queued'};

    test('a plain rescan posts no body', () async {
      final adapter = RecordingAdapter(body: job);
      final started = await clientOn(adapter).rescanLibrary();
      final sent = adapter.sent.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/library/rescan');
      expect(sent.body, isEmpty);
      expect(started.pid, 'jb-1');
    });

    test('a forced rescan posts force', () async {
      final adapter = RecordingAdapter(body: job);
      await clientOn(adapter).rescanLibrary(force: true);
      expect(adapter.sent.single.json, {'force': true});
    });
  });

  group('signing in without a password', () {
    test('bootstrap posts the first account and holds its token', () async {
      final adapter = RecordingAdapter(status: 201, body: _loginAnswer);
      final client = clientOn(adapter);
      final result = await client.bootstrap(
        username: 'admin',
        password: 'hunter2',
        displayName: 'Admin',
      );
      final sent = adapter.sent.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/auth/bootstrap');
      expect(sent.json, {
        'username': 'admin',
        'password': 'hunter2',
        'displayName': 'Admin',
      });
      expect(result.token, 'tok-1');
      expect(client.authToken, 'tok-1');
    });

    test('bootstrap leaves an unset display name out', () async {
      final sent = await requestOf(
        (c) => c.bootstrap(username: 'admin', password: 'hunter2'),
      );
      expect(sent.json, {'username': 'admin', 'password': 'hunter2'});
    });

    test('oidcExchange posts the code and holds the token', () async {
      final adapter = RecordingAdapter(body: _loginAnswer);
      final client = clientOn(adapter);
      final result = await client.oidcExchange(
        code: 'c1',
        verifier: 'v1',
        deviceName: 'Pixel',
      );
      final sent = adapter.sent.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/auth/oidc/exchange');
      expect(sent.json, {
        'code': 'c1',
        'verifier': 'v1',
        'deviceName': 'Pixel',
      });
      expect(result.token, 'tok-1');
      expect(client.authToken, 'tok-1');
    });

    test('oidcExchange leaves an unset verifier and device out', () async {
      final sent = await requestOf((c) => c.oidcExchange(code: 'c1'));
      expect(sent.json, {'code': 'c1'});
    });
  });

  group('a facet key', () {
    // The server keys the pair on the facet, so a facet with no key sends
    // an empty one (the unknown bucket) and a key with no facet is not sent.
    final calls =
        <String, Future<Object?> Function(WaxDeckClient, String?, String?)>{
          'listItems': (c, facet, key) =>
              c.listItems(facet: facet, facetKey: key),
          'listFacets': (c, facet, key) =>
              c.listFacets('genre', facet: facet, facetKey: key),
          'browse': (c, facet, key) =>
              c.browse(DiscoveryList.newest, facet: facet, facetKey: key),
        };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      group(name, () {
        test('is empty when the facet is set and the key is not', () async {
          final sent = await requestOf((c) => call(c, 'genre', null));
          expect(sent.query['facet'], ['genre']);
          expect(sent.query['facetKey'], ['']);
        });

        test('is the key given with the facet', () async {
          final sent = await requestOf((c) => call(c, 'genre', 'rock'));
          expect(sent.query['facet'], ['genre']);
          expect(sent.query['facetKey'], ['rock']);
        });

        test('is an empty key given with the facet', () async {
          final sent = await requestOf((c) => call(c, 'genre', ''));
          expect(sent.query['facetKey'], ['']);
        });

        test('is not sent without the facet', () async {
          final sent = await requestOf((c) => call(c, null, 'rock'));
          expect(sent.query, isNot(contains('facet')));
          expect(sent.query, isNot(contains('facetKey')));
        });
      });
    }
  });
}
