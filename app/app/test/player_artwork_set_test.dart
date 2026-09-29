import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/metadata/artwork_manager.dart' show ArtSlot;
import 'package:waxdeck/src/player/player_artwork_set.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

const _track = 'tr-01JZX5N8QW3F4V9T2B7KDMUSIC1';
const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';

ArtRoles _roles(List<String> roles) => ArtRoles(
  roles: [for (final role in roles) ArtRoleInfo(role: role, format: 'jpeg')],
);

/// A track holding nothing that shows its album's front.
const _inheriting = ArtRoles(
  roles: [],
  artSource: ArtSource(source: 'enrichment', level: 'album'),
);

List<(String, ArtSlot)> _shape(List<PlayerArtwork> set) => [
  for (final artwork in set) (artwork.pid, artwork.slot),
];

void main() {
  test('an inherited front is shown once, then the album\'s other slots', () {
    final set = playerArtworkSet(
      pid: _track,
      own: _inheriting,
      albumPid: _album,
      album: _roles(['booklet', 'front', 'back']),
    );
    expect(_shape(set), [
      (_track, ArtSlot.front),
      (_album, ArtSlot.back),
      (_album, ArtSlot.booklet),
    ]);
    expect(set.first.info, isNull);
  });

  test('a track with a front of its own shows the album\'s too', () {
    final set = playerArtworkSet(
      pid: _track,
      own: _roles(['back', 'front']),
      albumPid: _album,
      album: _roles(['front']),
    );
    expect(_shape(set), [
      (_track, ArtSlot.front),
      (_track, ArtSlot.back),
      (_album, ArtSlot.front),
    ]);
  });

  test('a pin left on a cleared front holds no picture', () {
    // The endpoint answers the album's cover for such a track, so the
    // album's front is the one it already shows.
    final set = playerArtworkSet(
      pid: _track,
      own: const ArtRoles(
        roles: [ArtRoleInfo(role: 'front', locked: true)],
        artSource: ArtSource(source: 'enrichment', level: 'album'),
      ),
      albumPid: _album,
      album: _roles(['front', 'disc']),
    );
    expect(_shape(set), [(_track, ArtSlot.front), (_album, ArtSlot.disc)]);
  });

  test('a track that shows no cover starts at a picture it has', () {
    final set = playerArtworkSet(
      pid: _track,
      own: _roles([]),
      albumPid: _album,
      album: _roles(['back', 'disc']),
    );
    expect(_shape(set), [(_album, ArtSlot.back), (_album, ArtSlot.disc)]);
  });

  test('with nothing else to show, the empty cover stays', () {
    final set = playerArtworkSet(
      pid: _track,
      own: _roles([]),
      albumPid: _album,
      album: _roles([]),
    );
    expect(_shape(set), [(_track, ArtSlot.front)]);
  });

  test('a role this build does not name is left out', () {
    final set = playerArtworkSet(pid: _track, own: _roles(['front', 'spine']));
    expect(_shape(set), [(_track, ArtSlot.front)]);
  });

  test('a book turns through its own slots alone', () {
    const book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
    final set = playerArtworkSet(pid: book, own: _roles(['front', 'back']));
    expect(_shape(set), [(book, ArtSlot.front), (book, ArtSlot.back)]);
  });

  test('nothing read yet is the cover alone', () {
    expect(_shape(playerArtworkSet(pid: _track, albumPid: _album)), [
      (_track, ArtSlot.front),
    ]);
  });
}
