import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

/// A value the generated client predates deserializes to the generator's
/// sentinel rather than throwing. These pin what each reader does with
/// one, which is the whole point of the sentinel: a page that loses a
/// card instead of a page that fails.
void main() {
  group('unknown enum values', () {
    test('a card kind this build predates drops the card, not the page', () {
      final card = gen.standardSerializers.deserializeWith(
        gen.EntityCard.serializer,
        <String, Object?>{'pid': 'al-1', 'kind': 'holo-cube', 'title': 'Ok'},
      )!;

      expect(card.kind, gen.EntityCardKindEnum.unknownDefaultOpenApi);
      expect(entityCardFromGen(card), isNull);
    });

    test('a browse sort this build predates drops its entry', () {
      final prefs = gen.standardSerializers.deserializeWith(
        gen.Prefs.serializer,
        <String, Object?>{
          'browseSorts': <String, Object?>{
            'album': 'hologram-order',
            'genre': 'count',
          },
        },
      )!;

      // Kept as a string map so the next save cannot carry the sentinel
      // back out as a wire value the server rejects.
      expect(prefsFromGen(prefs).browseSorts, {'genre': 'count'});
    });

    // The sentinel flag rewrote `valueOf` too, which is the half that
    // bites outbound: the request builders resolve app-supplied strings
    // through it, so a wrong one now reaches the server instead of
    // failing at the call. Pinned because nothing else says so.
    test('valueOf answers the sentinel for an unknown name', () {
      expect(
        gen.ScheduleKind.valueOf('holo-scan'),
        gen.ScheduleKind.unknownDefaultOpenApi,
      );
    });

    // The one place a sentinel could reach a request builder: a row is
    // saved under the kind it was listed with.
    test('a schedule kind this build predates is not listed', () {
      final page = gen.standardSerializers.deserializeWith(
        gen.ScheduleList.serializer,
        <String, Object?>{
          'schedules': <Object?>[
            <String, Object?>{
              'kind': 'defragment',
              'cron': '0 4 * * *',
              'enabled': true,
            },
            <String, Object?>{
              'kind': 'scan',
              'cron': '0 3 * * *',
              'enabled': true,
            },
          ],
        },
      )!;

      final kinds = page.schedules
          .where((s) => s.kind != gen.ScheduleKind.unknownDefaultOpenApi)
          .map(scheduleFromGen)
          .map((s) => s.kind)
          .toList();
      expect(kinds, ['scan']);
    });

    test('an unknown session kind degrades to device', () {
      final session = gen.standardSerializers
          .deserializeWith(gen.DeviceSession.serializer, <String, Object?>{
            'id': 'se-1',
            'kind': 'holo-deck',
            'createdAt': '2026-08-12T00:00:00Z',
            'lastSeenAt': '2026-08-12T00:00:00Z',
            'current': false,
          })!;

      expect(deviceSessionFromGen(session).kind, SessionKind.device);
    });
  });
}
