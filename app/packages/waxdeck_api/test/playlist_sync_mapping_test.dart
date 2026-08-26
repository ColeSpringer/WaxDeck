import 'package:test/test.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

void main() {
  test('mirror-trash serializes to its wire value', () {
    // The repository maps mode strings with an explicit switch because
    // built_value's valueOf takes Dart identifiers: handed the wire
    // string, it falls to the unknown-default constant, whose wire
    // name the server refuses. These two facts are what make the
    // switch load-bearing; if either moves, revisit
    // _playlistSourceModeToGen in client.dart.
    expect(
      gen.standardSerializers.serializeWith(
        gen.PlaylistSourceUpdateModeEnum.serializer,
        gen.PlaylistSourceUpdateModeEnum.mirrorTrash,
      ),
      'mirror-trash',
    );
    expect(
      gen.PlaylistSourceUpdateModeEnum.valueOf('mirror-trash'),
      gen.PlaylistSourceUpdateModeEnum.unknownDefaultOpenApi,
    );
  });
}
