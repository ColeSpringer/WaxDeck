import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auto/auto_browse.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

void main() {
  test('the browse tree serves the mirror: root, library, leaves', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    await db.batch(
      (b) => b.insertAll(db.mirrorItems, [
        MirrorItemsCompanion.insert(
          pid: 'tr-BBB',
          ulid: 'BBB',
          mediaType: 'music',
          title: 'Bravo',
          artist: const Value('Fixture Artist'),
          durationMs: 1000,
          sortKey: 'bravo',
        ),
        MirrorItemsCompanion.insert(
          pid: 'tr-AAA',
          ulid: 'AAA',
          mediaType: 'music',
          title: 'Alpha',
          artist: const Value('Fixture Artist'),
          durationMs: 1000,
          sortKey: 'alpha',
        ),
      ]),
    );
    final source = MirrorBrowseSource(db);

    final root = await source.children(browseRootId);
    expect(root, hasLength(1));
    expect(root.single.title, 'Library');
    expect(root.single.playable, isFalse);

    final library = await source.children(root.single.id);
    expect(library.map((e) => e.title), ['Alpha', 'Bravo']);
    expect(library.every((e) => e.playable), isTrue);
    expect(library.first.id, 'tr-AAA');

    expect(await source.children('nonsense'), isEmpty);
  });
}
