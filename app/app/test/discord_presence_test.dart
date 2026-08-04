import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/desktop/discord_binder.dart';
import 'package:waxdeck/src/desktop/discord_presence.dart';

/// A Discord that records what it was told, and can refuse to be there.
class _FakeDiscord implements DiscordPresencePort {
  /// Whether a Discord client is listening at all.
  bool running = true;

  final List<String> connected = <String>[];
  final List<DiscordActivity?> published = <DiscordActivity?>[];
  int closes = 0;

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
