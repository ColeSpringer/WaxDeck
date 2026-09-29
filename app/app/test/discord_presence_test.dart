import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/desktop/discord_binder.dart';
import 'package:waxdeck/src/desktop/discord_cover.dart';
import 'package:waxdeck/src/desktop/discord_ipc_io.dart';
import 'package:waxdeck/src/desktop/discord_presence.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// A Discord that records what it was told, and can refuse to be there.
class _FakeDiscord implements DiscordPresencePort {
  /// Whether a Discord client is listening at all.
  bool running = true;

  final List<String> connected = <String>[];
  final List<DiscordActivity?> published = <DiscordActivity?>[];
  int closes = 0;

  @override
  bool takesImageUrls = true;

  @override
  void Function()? onImageRefused;

  @override
  Future<bool> connect(String applicationId) async {
    connected.add(applicationId);
    return running;
  }

  @override
  Future<void> publish(DiscordActivity? activity) async =>
      published.add(activity);

  @override
  Future<void> close() async => closes++;
}

void main() {
  /// The real ceiling is fifteen seconds; the behaviour under test is
  /// the coalescing, not the number, so it is scaled down the way the
  /// queue persister's debounce is in its own tests.
  const interval = Duration(milliseconds: 20);

  late _FakeDiscord discord;
  late DiscordPresenceBinder binder;

  setUp(() {
    discord = _FakeDiscord();
    binder = DiscordPresenceBinder(discord, interval: interval);
  });

  /// Crosses the coalescing window, so whatever was held is sent.
  Future<void> settle() => Future<void>.delayed(interval * 3);

  group('what it says of playback', () {
    test('a skip still loading names the next track, without a bar', () {
      // Cleared instead, the status waited out Discord's fifteen seconds
      // to come back.
      final shown = presenceOf(
        NowPlaying(
          entry: const QueueEntry(queueId: '1', pid: 'tr-B'),
          item: testItem('tr-B', title: 'Second'),
          loading: true,
        ),
        playing: true,
      );
      expect(shown?.title, 'Second');
      expect(shown?.start, isNull);
    });

    test('a start that failed says nothing', () {
      expect(
        presenceOf(
          NowPlaying(
            entry: const QueueEntry(queueId: '1', pid: 'tr-B'),
            item: testItem('tr-B'),
            error: StateError('refused'),
          ),
          playing: false,
        ),
        isNull,
      );
    });
  });

  test('nothing is published while presence is off', () async {
    binder.show(const DiscordActivity(title: 'Track'));
    await settle();

    expect(discord.connected, isEmpty);
    expect(discord.published, isEmpty);
  });

  group('which application it publishes as', () {
    test('is WaxDeck itself when the override is empty', () {
      // The field is an override, not a requirement: a switch turned on
      // with nothing else touched has to publish, or the feature looks
      // broken to everybody who never opens the second control.
      expect(kWaxDeckDiscordApplicationId, isNotEmpty);
      expect(discordApplicationId(''), kWaxDeckDiscordApplicationId);
      expect(discordApplicationId('   '), kWaxDeckDiscordApplicationId);
    });

    test('is the override when there is one, trimmed', () {
      expect(discordApplicationId(' 42 '), '42');
    });
  });

  test('turning it on mid-album publishes the album', () async {
    binder.show(const DiscordActivity(title: 'Track', artist: 'Artist'));
    await binder.configure('12345');
    await Future<void>.delayed(Duration.zero);

    expect(discord.connected, <String>['12345']);
    expect(discord.published.single!.title, 'Track');
  });

  test('updates coalesce to the ceiling, newest state winning', () async {
    await binder.configure('12345');
    binder.show(const DiscordActivity(title: 'First'));
    await Future<void>.delayed(Duration.zero);
    expect(discord.published.map((a) => a?.title), <String?>['First']);

    // Three tracks skipped through inside one window. Discord drops
    // updates past about one every fifteen seconds, so the one that has
    // to survive is the newest rather than the oldest queued.
    binder.show(const DiscordActivity(title: 'Second'));
    binder.show(const DiscordActivity(title: 'Third'));
    expect(discord.published.map((a) => a?.title), <String?>['First']);

    await settle();
    expect(discord.published.map((a) => a?.title), <String?>['First', 'Third']);
  });

  test('an unchanged activity does not spend the budget', () async {
    await binder.configure('12345');
    for (var i = 0; i < 5; i++) {
      binder.show(const DiscordActivity(title: 'Track', artist: 'Artist'));
      await settle();
    }
    // The position ticks reach the binder too; only what Discord would
    // draw differently is worth an update.
    expect(discord.published, hasLength(1));
  });

  test('a seek republishes, because the progress bar moved', () async {
    await binder.configure('12345');
    final at = DateTime.utc(2026, 8, 4, 12);
    binder.show(DiscordActivity(title: 'Track', start: at));
    await settle();
    binder.show(
      DiscordActivity(
        title: 'Track',
        start: at.add(const Duration(minutes: 1)),
      ),
    );
    await settle();

    expect(discord.published, hasLength(2));
  });

  test('a start that only drifted is the same moment', () async {
    // Wall clock minus position never reads the same twice, so an exact
    // comparison would spend the budget on every publish.
    await binder.configure('12345');
    final at = DateTime.utc(2026, 8, 4, 12);
    binder.show(DiscordActivity(title: 'Track', start: at));
    await settle();
    for (final drift in const <Duration>[
      Duration(microseconds: 1),
      Duration(milliseconds: 250),
      Duration(milliseconds: -600),
    ]) {
      binder.show(DiscordActivity(title: 'Track', start: at.add(drift)));
      await settle();
    }

    expect(discord.published, hasLength(1));
  });

  test('pausing drops the timestamps rather than the track', () async {
    // Discord runs its bar from the start regardless, so a pause has to
    // take the timestamps away.
    await binder.configure('12345');
    final at = DateTime.utc(2026, 8, 4, 12);
    binder.show(
      DiscordActivity(
        title: 'Track',
        artist: 'Artist',
        start: at,
        end: at.add(const Duration(minutes: 4)),
      ),
    );
    await settle();
    binder.show(const DiscordActivity(title: 'Track', artist: 'Artist'));
    await settle();

    expect(discord.published, hasLength(2));
    expect(discord.published.last!.title, 'Track');
    expect(discord.published.last!.artist, 'Artist');
    expect(discord.published.last!.start, isNull);
    expect(discord.published.last!.end, isNull);
  });

  test('changing the id reconnects under the new one', () async {
    await binder.configure('12345');
    await binder.configure('67890');
    expect(discord.connected, <String>['12345', '67890']);
  });

  test('turning it off stops publishing', () async {
    await binder.configure('12345');
    binder.show(const DiscordActivity(title: 'Track'));
    await settle();

    await binder.configure(null);
    expect(discord.closes, greaterThan(0));

    binder.show(const DiscordActivity(title: 'Another'));
    await settle();
    expect(discord.published.map((a) => a?.title), <String?>['Track']);
  });

  test('no Discord running costs the status and nothing else', () async {
    discord.running = false;
    await binder.configure('12345');
    binder.show(const DiscordActivity(title: 'Track'));
    await settle();

    expect(discord.published, isEmpty);
  });

  group('the album cover', () {
    late List<String> albumReads;
    late Map<String, String?> mbids;

    DiscordCoverResolver resolver({
      Future<String?> Function(String mbid)? front,
      DateTime Function()? clock,
    }) => DiscordCoverResolver(
      clock: clock,
      album: (pid) async {
        albumReads.add(pid);
        return AlbumDetail(pid: pid, title: 'Album', mbid: mbids[pid]);
      },
      front:
          front ??
          (mbid) async => 'https://archive.org/download/mbid-$mbid/front.jpg',
    );

    setUp(() {
      albumReads = <String>[];
      mbids = <String, String?>{'al-1': 'm1', 'al-2': 'm2'};
    });

    test('is the image the release resolves to', () async {
      binder = DiscordPresenceBinder(
        discord,
        interval: interval,
        covers: resolver(),
      );
      await binder.configure('12345');
      binder.show(const DiscordActivity(title: 'Track'), albumPid: 'al-1');
      await settle();

      expect(
        discord.published.last!.largeImageUrl,
        'https://archive.org/download/mbid-m1/front.jpg',
      );
    });

    test('is the application asset without a release id', () async {
      mbids['al-1'] = null;
      binder = DiscordPresenceBinder(
        discord,
        interval: interval,
        covers: resolver(),
      );
      await binder.configure('12345');
      binder.show(const DiscordActivity(title: 'Track'), albumPid: 'al-1');
      await settle();

      expect(discord.published.single!.largeImageUrl, isNull);
    });

    test('is the application asset when the archive lookup fails', () async {
      binder = DiscordPresenceBinder(
        discord,
        interval: interval,
        covers: resolver(front: (_) async => throw const HttpException('503')),
      );
      await binder.configure('12345');
      binder.show(const DiscordActivity(title: 'Track'), albumPid: 'al-1');
      await settle();

      expect(discord.published.single!.largeImageUrl, isNull);
    });

    test('reads each album once', () async {
      binder = DiscordPresenceBinder(
        discord,
        interval: interval,
        covers: resolver(),
      );
      await binder.configure('12345');
      for (final (title, album) in const [
        ('One', 'al-1'),
        ('Two', 'al-1'),
        ('Three', 'al-2'),
        ('Four', 'al-1'),
      ]) {
        binder.show(DiscordActivity(title: title), albumPid: album);
        await settle();
      }

      expect(albumReads, <String>['al-1', 'al-2']);
      expect(
        discord.published.last!.largeImageUrl,
        'https://archive.org/download/mbid-m1/front.jpg',
      );
    });

    test('a lookup failing any way waits out the retry window', () async {
      var now = DateTime.utc(2026, 9, 27);
      var reads = 0;
      final covers = DiscordCoverResolver(
        // A malformed answer surfaces as an Error, not an Exception.
        album: (pid) async {
          reads++;
          throw StateError('no album in that answer');
        },
        front: (_) async => null,
        clock: () => now,
      );

      await covers.lookUp('al-1');
      expect(covers.lookUp('al-1'), isNull);
      now = now.add(const Duration(minutes: 6));
      await covers.lookUp('al-1');
      expect(reads, 2);
    });

    test(
      'waits a moment for a new album\'s cover before the first send',
      () async {
        binder = DiscordPresenceBinder(
          discord,
          interval: interval,
          coverWait: const Duration(seconds: 1),
          covers: resolver(
            front: (mbid) async {
              await Future<void>.delayed(interval * 2);
              return 'https://coverartarchive.org/release/$mbid/front-250';
            },
          ),
        );
        await binder.configure('12345');
        binder.show(const DiscordActivity(title: 'Track'), albumPid: 'al-1');
        await Future<void>.delayed(interval * 8);

        // One send, with the cover: not the logo, then the cover 15 s on.
        expect(discord.published, hasLength(1));
        expect(
          discord.published.single!.largeImageUrl,
          'https://coverartarchive.org/release/m1/front-250',
        );
      },
    );

    test('is not looked up once Discord has refused image URLs', () async {
      discord.takesImageUrls = false;
      binder = DiscordPresenceBinder(
        discord,
        interval: interval,
        covers: resolver(),
      );
      await binder.configure('12345');
      binder.show(const DiscordActivity(title: 'Track'), albumPid: 'al-1');
      await settle();

      expect(albumReads, isEmpty);
    });

    test('a miss is asked again a day later', () async {
      var now = DateTime.utc(2026, 9, 27);
      mbids['al-1'] = null;
      final covers = resolver(clock: () => now);
      await covers.lookUp('al-1');
      expect(covers.lookUp('al-1'), isNull);

      // Identified by a pass since, say.
      now = now.add(const Duration(hours: 25));
      mbids['al-1'] = 'm1';
      await covers.lookUp('al-1');
      expect(albumReads, ['al-1', 'al-1']);
      expect(covers.coverOf('al-1'), isNotNull);
    });

    test('a retry asks the archive again, not the server', () async {
      var now = DateTime.utc(2026, 9, 27);
      var fronts = 0;
      final covers = resolver(
        clock: () => now,
        front: (mbid) async {
          if (++fronts == 1) throw const HttpException('503');
          return 'https://coverartarchive.org/release/$mbid/front-250';
        },
      );
      await covers.lookUp('al-1');
      now = now.add(const Duration(minutes: 6));
      await covers.lookUp('al-1');

      expect(fronts, 2);
      expect(albumReads, ['al-1']);
    });

    test('is not looked up while presence is off', () async {
      binder = DiscordPresenceBinder(
        discord,
        interval: interval,
        covers: resolver(),
      );
      binder.show(const DiscordActivity(title: 'Track'), albumPid: 'al-1');
      await settle();

      expect(albumReads, isEmpty);
    });

    test('failed lookups are remembered no further back than covers', () async {
      final covers = resolver(
        front: (_) async => throw const HttpException('503'),
      );
      // One past the 256 albums it keeps.
      for (var i = 0; i <= 256; i++) {
        mbids['al-x$i'] = 'm$i';
        await covers.lookUp('al-x$i');
      }

      // The oldest is forgotten whole: asked again at once, album and all.
      final again = covers.lookUp('al-x0');
      expect(again, isNotNull);
      await again;
      expect(albumReads.where((pid) => pid == 'al-x0'), hasLength(2));
    });

    test('switch off and on again without redialling', () async {
      binder = DiscordPresenceBinder(
        discord,
        interval: interval,
        covers: resolver(),
      );
      await binder.configure('12345');
      binder.show(const DiscordActivity(title: 'Track'), albumPid: 'al-1');
      await settle();
      expect(discord.published.last!.largeImageUrl, isNotNull);

      binder.covers = null;
      await settle();
      expect(discord.published.last!.title, 'Track');
      expect(discord.published.last!.largeImageUrl, isNull);

      binder.covers = resolver();
      await settle();
      expect(
        discord.published.last!.largeImageUrl,
        'https://archive.org/download/mbid-m1/front.jpg',
      );
      expect(discord.connected, hasLength(1));
    });

    group('a newer album', () {
      late Map<String, Completer<String?>> fronts;

      setUp(() {
        fronts = <String, Completer<String?>>{};
        binder = DiscordPresenceBinder(
          discord,
          interval: interval,
          coverWait: interval * 10,
          covers: resolver(
            front: (mbid) => (fronts[mbid] = Completer<String?>()).future,
          ),
        );
      });

      test('waits for its own cover, not the one before it', () async {
        await binder.configure('12345');
        binder.show(const DiscordActivity(title: 'One'), albumPid: 'al-1');
        await Future<void>.delayed(interval * 5);
        binder.show(const DiscordActivity(title: 'Two'), albumPid: 'al-2');
        // Past the first album's wait, inside the second's.
        await Future<void>.delayed(interval * 7);
        expect(discord.published, isEmpty);

        fronts['m2']!.complete('https://coverartarchive.org/release/m2/x');
        await Future<void>.delayed(interval);
        expect(discord.published.single!.title, 'Two');
        expect(
          discord.published.single!.largeImageUrl,
          'https://coverartarchive.org/release/m2/x',
        );
      });

      test('keeps its wait when the one before it lands late', () async {
        await binder.configure('12345');
        binder.show(const DiscordActivity(title: 'One'), albumPid: 'al-1');
        await Future<void>.delayed(interval * 5);
        binder.show(const DiscordActivity(title: 'Two'), albumPid: 'al-2');
        fronts['m1']!.complete('https://coverartarchive.org/release/m1/x');
        await Future<void>.delayed(interval);
        // Paused, say: a change worth sending, still inside the wait.
        binder.show(
          DiscordActivity(title: 'Two', start: DateTime.utc(2026, 9, 28)),
          albumPid: 'al-2',
        );
        await Future<void>.delayed(interval);

        expect(discord.published, isEmpty);
      });
    });
  });

  test('the covers switch leaves presence connected', () async {
    final port = _FakeDiscord();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(FakeRepository()),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        localeOverrideProvider.overrideWithValue(null),
        discordPresencePortProvider.overrideWithValue(port),
      ],
    );
    addTearDown(container.dispose);
    container.read(discordPresenceEnabledProvider.notifier).set(true);
    final binding = container.listen(discordPresenceProvider, (_, _) {});
    addTearDown(binding.close);
    await Future<void>.delayed(Duration.zero);
    expect(port.connected, hasLength(1));

    container.read(discordCoversEnabledProvider.notifier).set(false);
    await Future<void>.delayed(Duration.zero);

    expect(port.connected, hasLength(1));
  });

  group('the archive lookup', () {
    late HttpServer server;
    late List<String> methods;

    setUp(() async {
      methods = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        methods.add(request.method);
        final response = request.response;
        switch (request.uri.path) {
          case '/release/m1/front-250':
            response.statusCode = HttpStatus.temporaryRedirect;
            response.headers.set('location', '/download/m1.jpg');
          case '/download/m1.jpg':
            response.statusCode = HttpStatus.found;
            response.headers.set(
              'location',
              'http://127.0.0.1:${server.port}/items/m1.jpg',
            );
          case '/items/m1.jpg':
            response.headers.contentType = ContentType('image', 'jpeg');
          case '/release/down/front-250':
            response.statusCode = HttpStatus.serviceUnavailable;
          case '/release/slow/front-250':
            response.statusCode = HttpStatus.requestTimeout;
          case '/release/busy/front-250':
            response.statusCode = HttpStatus.tooManyRequests;
          case '/release/denied/front-250':
            response.statusCode = HttpStatus.forbidden;
          default:
            response.statusCode = HttpStatus.notFound;
        }
        unawaited(response.close());
      });
    });

    tearDown(() => server.close(force: true));

    Uri archive() => Uri.parse('http://127.0.0.1:${server.port}');

    test('names the archive\'s own address once the image is found', () async {
      // The storage node a redirect lands on is chosen per request.
      expect(
        await coverArtFront('m1', archive: archive()),
        'http://127.0.0.1:${server.port}/release/m1/front-250',
      );
      expect(methods, everyElement('HEAD'));
    });

    test('only a missing image is a miss', () async {
      await expectLater(
        coverArtFront('denied', archive: archive()),
        throwsException,
      );
    });

    test('a client of its own is kept open for the next', () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      await coverArtFront('m9', archive: archive(), client: client);
      expect(
        await coverArtFront('m9', archive: archive(), client: client),
        isNull,
      );
    });

    test('answers none for a release with no front image', () async {
      expect(await coverArtFront('m9', archive: archive()), isNull);
    });

    test('fails rather than answering none when the archive is down', () {
      expect(coverArtFront('down', archive: archive()), throwsException);
    });

    test('a throttled or timed-out answer is a failure, not a miss', () async {
      await expectLater(
        coverArtFront('slow', archive: archive()),
        throwsException,
      );
      await expectLater(
        coverArtFront('busy', archive: archive()),
        throwsException,
      );
    });
  });

  group('the IPC client', () {
    late ServerSocket server;
    late StreamIterator<Map<String, Object?>> frames;
    late Socket peer;
    late DiscordIpcPresence ipc;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('wax-discord');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/discord-ipc-0';
      server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      addTearDown(server.close);
      final received = StreamController<Map<String, Object?>>();
      final connected = Completer<void>();
      server.listen((socket) {
        peer = socket;
        // A client dialling again resets the socket it left.
        socket.done.ignore();
        socket.listen(
          _frameReader((frame) {
            if (frame.containsKey('client_id')) socket.add(_frame(_ready));
            received.add(frame);
          }),
          onError: (Object _) {},
        );
        // A test that dials again is answered on the new socket.
        if (!connected.isCompleted) connected.complete();
      });
      frames = StreamIterator(received.stream);
      ipc = DiscordIpcPresence(paths: () => <String>[path]);
      addTearDown(ipc.close);
      expect(await ipc.connect('42'), isTrue);
      await connected.future;
      await frames.moveNext();
      expect(frames.current['client_id'], '42');
    });

    Future<Object?> nextImage() async {
      await frames.moveNext();
      final args = frames.current['args']! as Map<String, Object?>;
      final activity = args['activity']! as Map<String, Object?>;
      return (activity['assets']! as Map<String, Object?>)['large_image'];
    }

    test('sends a cover URL as the image, and the asset without one', () async {
      await ipc.publish(
        const DiscordActivity(
          title: 'Track',
          largeImageUrl: 'https://archive.org/x.jpg',
        ),
      );
      expect(await nextImage(), 'https://archive.org/x.jpg');
      await ipc.publish(const DiscordActivity(title: 'Other'));
      expect(await nextImage(), kDiscordCoverAsset);
    });

    Map<String, Object?> refusal(Object? nonce, String message) =>
        <String, Object?>{
          'cmd': 'SET_ACTIVITY',
          'evt': 'ERROR',
          'nonce': nonce,
          'data': <String, Object?>{'code': 4000, 'message': message},
        };

    test(
      'an image Discord refuses falls back to the asset for the connection',
      () async {
        final refused = Completer<void>();
        ipc.onImageRefused = refused.complete;
        await ipc.publish(
          const DiscordActivity(
            title: 'Track',
            largeImageUrl: 'https://archive.org/x.jpg',
          ),
        );
        expect(await nextImage(), 'https://archive.org/x.jpg');
        peer.add(
          _frame(
            refusal(
              frames.current['nonce'],
              'child "activity" fails because [child "assets" fails because '
              '[child "large_image" fails]]',
            ),
          ),
        );

        // Said to the caller, whose clock the resend keeps.
        await refused.future;
        expect(ipc.takesImageUrls, isFalse);
        await ipc.publish(
          const DiscordActivity(
            title: 'Next',
            largeImageUrl: 'https://archive.org/y.jpg',
          ),
        );
        expect(await nextImage(), kDiscordCoverAsset);

        // A Discord dialled again is asked again.
        expect(await ipc.connect('42'), isTrue);
        await frames.moveNext();
        expect(ipc.takesImageUrls, isTrue);
      },
    );

    test('an error about something else keeps the images', () async {
      await ipc.publish(
        const DiscordActivity(
          title: 'Track',
          largeImageUrl: 'https://archive.org/x.jpg',
        ),
      );
      expect(await nextImage(), 'https://archive.org/x.jpg');
      peer.add(
        _frame(
          refusal(
            frames.current['nonce'],
            'child "activity" fails because [child "details" fails]',
          ),
        ),
      );
      await peer.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await ipc.publish(
        const DiscordActivity(
          title: 'Next',
          largeImageUrl: 'https://archive.org/y.jpg',
        ),
      );
      expect(await nextImage(), 'https://archive.org/y.jpg');
    });

    test('commands never answered are not remembered forever', () async {
      const cover = DiscordActivity(
        title: 'Track',
        largeImageUrl: 'https://archive.org/x.jpg',
      );
      String? first;
      for (var i = 0; i < 40; i++) {
        await ipc.publish(cover);
        await nextImage();
        first ??= frames.current['nonce']! as String;
      }
      // Answered only now, far too late to be about the cover in view.
      peer.add(_frame(refusal(first, 'child "large_image" fails')));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await ipc.publish(cover);
      expect(await nextImage(), 'https://archive.org/x.jpg');
    });

    test('a frame too long to be Discord is dropped, not waited on', () async {
      await ipc.publish(
        const DiscordActivity(
          title: 'Track',
          largeImageUrl: 'https://archive.org/x.jpg',
        ),
      );
      expect(await nextImage(), 'https://archive.org/x.jpg');
      final junk = Uint8List(8);
      ByteData.view(junk.buffer)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 1 << 30, Endian.little);
      peer.add(junk);
      await peer.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final refused = Completer<void>();
      ipc.onImageRefused = refused.complete;
      peer.add(
        _frame(refusal(frames.current['nonce'], 'child "large_image" fails')),
      );

      await refused.future;
    });

    test('an image Discord accepts keeps being sent', () async {
      await ipc.publish(
        const DiscordActivity(
          title: 'Track',
          largeImageUrl: 'https://archive.org/x.jpg',
        ),
      );
      expect(await nextImage(), 'https://archive.org/x.jpg');
      peer.add(
        _frame(<String, Object?>{
          'cmd': 'SET_ACTIVITY',
          'evt': null,
          'nonce': frames.current['nonce'],
          'data': <String, Object?>{},
        }),
      );
      await peer.flush();
      // Long enough for the reply to be read; a misread would resend.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await ipc.publish(
        const DiscordActivity(
          title: 'Next',
          largeImageUrl: 'https://archive.org/y.jpg',
        ),
      );
      expect(await nextImage(), 'https://archive.org/y.jpg');
      expect(
        ((frames.current['args']! as Map)['activity']! as Map)['details'],
        'Next',
      );
    });
  }, skip: Platform.isWindows ? 'Unix sockets only' : false);

  group('dialling Discord', () {
    late String path;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('wax-discord');
      addTearDown(() => dir.delete(recursive: true));
      path = '${dir.path}/discord-ipc-0';
    });

    String? titleOf(Map<String, Object?> command) =>
        ((command['args']! as Map)['activity']! as Map)['details'] as String?;

    test(
      'an update right after dialling waits for Discord to be ready',
      () async {
        final discord = await _SlowDiscord.bind(path);
        addTearDown(discord.close);
        final ipc = DiscordIpcPresence(paths: () => <String>[path]);
        addTearDown(ipc.close);

        expect(await ipc.connect('42'), isTrue);
        await ipc.publish(const DiscordActivity(title: 'Track'));

        final shown = await discord.shown.first.timeout(
          const Duration(seconds: 2),
        );
        expect(titleOf(shown), 'Track');
      },
    );

    test(
      'a Discord that hangs up on the handshake is not a connection',
      () async {
        final discord = await _SlowDiscord.bind(path, refuse: true);
        addTearDown(discord.close);
        final ipc = DiscordIpcPresence(paths: () => <String>[path]);
        addTearDown(ipc.close);

        expect(await ipc.connect('42'), isFalse);
      },
    );

    test('updates while Discord gets ready dial it once, in order', () async {
      final ipc = DiscordIpcPresence(paths: () => <String>[path]);
      addTearDown(ipc.close);
      // Nothing there yet: the id is kept, and the next update dials.
      expect(await ipc.connect('42'), isFalse);
      final discord = await _SlowDiscord.bind(path);
      addTearDown(discord.close);

      await Future.wait(<Future<void>>[
        ipc.publish(const DiscordActivity(title: 'First')),
        ipc.publish(const DiscordActivity(title: 'Second')),
      ]);

      final shown = await discord.shown
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 2));
      expect(discord.callers, 1);
      expect(shown.map(titleOf), <String>['First', 'Second']);
    });

    test('a Discord that never answers the handshake is passed over', () async {
      final silent = await _SlowDiscord.bind('$path-silent', silent: true);
      addTearDown(silent.close);
      final discord = await _SlowDiscord.bind(path);
      addTearDown(discord.close);
      final ipc = DiscordIpcPresence(
        paths: () => <String>['$path-silent', path],
        answerWithin: const Duration(milliseconds: 200),
      );
      addTearDown(ipc.close);

      final connected = await ipc
          .connect('42')
          .timeout(const Duration(seconds: 2));
      expect(connected, isTrue);
      await ipc.publish(const DiscordActivity(title: 'Track'));
      final shown = await discord.shown.first.timeout(
        const Duration(seconds: 2),
      );
      expect(titleOf(shown), 'Track');
    });

    test('stopping while Discord gets ready keeps no connection', () async {
      final discord = await _SlowDiscord.bind(path);
      addTearDown(discord.close);
      final ipc = DiscordIpcPresence(paths: () => <String>[path]);

      final dialling = ipc.connect('42');
      await discord.greeted;
      await ipc.close();

      expect(await dialling, isFalse);
      await discord.left.timeout(const Duration(seconds: 2));
    });
  }, skip: Platform.isWindows ? 'Unix sockets only' : false);

  test('off and on again mid-track shows the track again', () async {
    await binder.configure('12345');
    binder.show(const DiscordActivity(title: 'Track'));
    await settle();
    await binder.configure(null);
    final before = discord.published.length;

    await binder.configure('12345');
    await settle();

    expect(discord.published.length, greaterThan(before));
    expect(discord.published.last!.title, 'Track');
  });

  test('a refused image is sent again on the binder\'s own clock', () async {
    await binder.configure('12345');
    binder.show(
      const DiscordActivity(
        title: 'Track',
        largeImageUrl: 'https://coverartarchive.org/release/m1/front-250',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final before = discord.published.length;
    expect(before, 1);

    // Refused as soon as it was sent, inside the ceiling.
    discord.takesImageUrls = false;
    discord.onImageRefused!();
    expect(discord.published.length, before);
    await settle();

    expect(discord.published.length, before + 1);
    expect(discord.published.last!.title, 'Track');
    expect(discord.published.last!.largeImageUrl, isNull);
  });

  test('disposing clears the status on the way out', () async {
    await binder.configure('12345');
    binder.show(const DiscordActivity(title: 'Track'));
    await settle();

    await binder.dispose();
    // A Discord left showing a track this app stopped playing is the
    // failure people notice.
    expect(discord.published.last, isNull);
    expect(discord.closes, greaterThan(0));
  });
}

Uint8List _frame(Map<String, Object?> body, {int opcode = 1}) {
  final bytes = utf8.encode(jsonEncode(body));
  final frame = Uint8List(8 + bytes.length);
  ByteData.view(frame.buffer)
    ..setUint32(0, opcode, Endian.little)
    ..setUint32(4, bytes.length, Endian.little);
  frame.setRange(8, frame.length, bytes);
  return frame;
}

/// What Discord says to a handshake it accepts.
const Map<String, Object?> _ready = <String, Object?>{
  'cmd': 'DISPATCH',
  'evt': 'READY',
  'data': <String, Object?>{'v': 1},
};

/// A Discord as slow to answer a handshake as the real one can be (it
/// took 29 s once), and as deaf to any command that came before READY.
class _SlowDiscord {
  _SlowDiscord._(this._server);

  final ServerSocket _server;
  final StreamController<Map<String, Object?>> _shown =
      StreamController<Map<String, Object?>>();

  final Completer<void> _greeted = Completer<void>();
  final Completer<void> _left = Completer<void>();

  /// Connections made to it.
  int callers = 0;

  /// The commands it acted on.
  Stream<Map<String, Object?>> get shown => _shown.stream;

  /// Done once a handshake arrived, and once its caller hung up.
  Future<void> get greeted => _greeted.future;
  Future<void> get left => _left.future;

  /// [silent] never answers a handshake at all, nor hangs up.
  static Future<_SlowDiscord> bind(
    String path, {
    bool refuse = false,
    bool silent = false,
  }) async {
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final discord = _SlowDiscord._(server);
    server.listen((socket) {
      discord.callers++;
      socket.done.ignore();
      var ready = false;
      socket.listen(
        _frameReader((frame) {
          if (!frame.containsKey('client_id')) {
            if (ready) discord._shown.add(frame);
            return;
          }
          if (!discord._greeted.isCompleted) discord._greeted.complete();
          if (silent) return;
          if (refuse) {
            socket.add(
              _frame(const <String, Object?>{
                'code': 4000,
                'message': 'Invalid Client ID',
              }, opcode: 2),
            );
            unawaited(socket.close());
            return;
          }
          Timer(const Duration(milliseconds: 100), () {
            ready = true;
            socket.add(_frame(_ready));
          });
        }),
        onError: (Object _) {},
        onDone: () {
          if (!discord._left.isCompleted) discord._left.complete();
        },
      );
    });
    return discord;
  }

  Future<void> close() => _server.close();
}

/// Splits a byte stream into the JSON bodies of its frames.
void Function(Uint8List) _frameReader(
  void Function(Map<String, Object?>) onFrame,
) {
  final buffer = BytesBuilder();
  return (chunk) {
    buffer.add(chunk);
    var bytes = buffer.takeBytes();
    while (bytes.length >= 8) {
      final length = ByteData.sublistView(bytes).getUint32(4, Endian.little);
      if (bytes.length < 8 + length) break;
      onFrame(
        jsonDecode(utf8.decode(bytes.sublist(8, 8 + length)))
            as Map<String, Object?>,
      );
      bytes = bytes.sublist(8 + length);
    }
    buffer.add(bytes);
  };
}
