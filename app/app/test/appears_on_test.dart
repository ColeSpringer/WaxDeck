import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

ItemSummary _track(
  String title, {
  required String album,
  String? albumPid,
  String artist = 'Nightjar',
}) => ItemSummary(
  pid: 'tr-$title',
  mediaType: MediaType.music,
  title: title,
  artist: artist,
  album: album,
  albumPid: albumPid,
  durationMs: 210000,
);

void main() {
  group('appearsOnAlbums', () {
    // The query answers items and the shelf shows albums, so an artist
    // credited on six tracks of one compilation is one card.
    test('collapses credited tracks to one card per release', () {
      final credited = <ItemSummary>[
        for (var i = 0; i < 6; i++)
          _track('Guest $i', album: 'Big Compilation', albumPid: 'al-comp'),
      ];

      final albums = appearsOnAlbums(credited, const <ArtistAlbum>[]);

      expect(albums, hasLength(1));
      expect(albums.single.title, 'Big Compilation');
      expect(albums.single.tracks, hasLength(6));
    });

    // A release the artist heads is already drawn under Releases;
    // leaving it here makes the screen repeat itself.
    test('excludes releases already drawn as the artist own', () {
      final own = <ArtistAlbum>[
        ArtistAlbum(
          title: 'Their Own Record',
          pid: 'al-own',
          tracks: <ItemSummary>[
            _track('One', album: 'Their Own Record', albumPid: 'al-own'),
          ],
        ),
      ];
      final credited = <ItemSummary>[
        _track('One', album: 'Their Own Record', albumPid: 'al-own'),
        _track('Guest', album: 'Someone Else', albumPid: 'al-other'),
      ];

      final albums = appearsOnAlbums(credited, own);

      expect(albums.map((a) => a.pid), <String>['al-other']);
    });

    // Two releases can share a title, so the exclusion keys on the pid.
    // Dropping both because one matched is the bug the Releases shelf
    // avoids by opening its tiles positionally.
    test('two releases sharing a title are told apart by pid', () {
      final own = <ArtistAlbum>[
        ArtistAlbum(
          title: 'Greatest Hits',
          pid: 'al-mine',
          tracks: <ItemSummary>[
            _track('Mine', album: 'Greatest Hits', albumPid: 'al-mine'),
          ],
        ),
      ];
      final credited = <ItemSummary>[
        _track('Mine', album: 'Greatest Hits', albumPid: 'al-mine'),
        _track('Theirs', album: 'Greatest Hits', albumPid: 'al-theirs'),
      ];

      final albums = appearsOnAlbums(credited, own);

      expect(albums.map((a) => a.pid), <String>['al-theirs']);
      expect(albums.single.title, 'Greatest Hits');
    });

    // A loose folder of tagged files has no album entity, so title is
    // the only handle it has and the exclusion has to fall back to it.
    test('a release with no entity is excluded by title', () {
      final own = <ArtistAlbum>[
        ArtistAlbum(
          title: 'Untagged Folder',
          tracks: <ItemSummary>[_track('One', album: 'Untagged Folder')],
        ),
      ];
      final credited = <ItemSummary>[
        _track('One', album: 'Untagged Folder'),
        _track('Two', album: 'Another Folder'),
      ];

      final albums = appearsOnAlbums(credited, own);

      expect(albums.map((a) => a.title), <String>['Another Folder']);
    });

    // Matching every own title would drop this; it is a different record.
    test('a loose release sharing a title with an own one is kept', () {
      final own = <ArtistAlbum>[
        ArtistAlbum(
          title: 'Greatest Hits',
          pid: 'al-mine',
          tracks: <ItemSummary>[
            _track('Mine', album: 'Greatest Hits', albumPid: 'al-mine'),
          ],
        ),
      ];
      final credited = <ItemSummary>[_track('Guest', album: 'Greatest Hits')];

      final albums = appearsOnAlbums(credited, own);

      expect(albums, hasLength(1));
      expect(albums.single.title, 'Greatest Hits');
      expect(albums.single.pid, isNull);
    });

    test('nothing credited is an empty shelf, not an error', () {
      expect(
        appearsOnAlbums(const <ItemSummary>[], const <ArtistAlbum>[]),
        isEmpty,
      );
    });
  });
}
