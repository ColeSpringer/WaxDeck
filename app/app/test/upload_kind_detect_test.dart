import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

// What the add flows guess about a pick before the person says: an
// audiobook's grouping from where the files sit.

PickedAudioFile _file(String name, [String dir = '']) =>
    PickedAudioFile(name: name, size: 8, relativeDir: dir);

void main() {
  group('defaultUploadGrouping', () {
    UploadGrouping bookOf(List<PickedAudioFile> files) =>
        defaultUploadGrouping(MediaType.audiobook, files);

    test('an audiobook from one folder is one book', () {
      expect(
        bookOf([_file('01.mp3', 'Book'), _file('02.mp3', 'Book')]),
        UploadGrouping.album,
      );
    });

    test('disc subfolders stay inside their book', () {
      expect(
        bookOf([_file('01.mp3', 'Book/CD1'), _file('01.mp3', 'Book/CD2')]),
        UploadGrouping.album,
      );
      expect(
        bookOf([
          _file('01.mp3', 'Book/Disc 1'),
          _file('01.mp3', 'Book/disc 2'),
          _file('01.mp3', 'Book/Part 3'),
        ]),
        UploadGrouping.album,
      );
      expect(
        bookOf([_file('00.mp3', 'Book'), _file('01.mp3', 'Book/CD1')]),
        UploadGrouping.album,
      );
    });

    // The folder names read as a disc or part of the folder above. The
    // same list pins the server's fold (server/internal/match/
    // cluster_test.go, bookSubfolders), so this default and the
    // server's grouping agree.
    const bookSubfolders = <String, bool>{
      'CD1': true,
      'cd 2': true,
      'Disc 1': true,
      'disc_2': true,
      'Disk-3': true,
      'DISC.4': true,
      'Part 1': true,
      'part 12': true,
      'Part_3': true,
      'Part1': true,
      'Bonus': false,
      'Disc': false,
      'Part One': false,
      'Pt 1': false,
      'Side A': false,
      'Vol 1': false,
      'CD1 Extras': false,
      'Discography 2': false,
      'Partita 2': false,
      'Part\u00A01': true,
      'Part\u20031': false,
    };

    test('the subfolders read as a disc or part of their book', () {
      for (final MapEntry(key: name, value: folds) in bookSubfolders.entries) {
        expect(
          bookOf([_file('00.mp3', 'Book'), _file('01.mp3', 'Book/$name')]),
          folds ? UploadGrouping.album : UploadGrouping.auto,
          reason: name,
        );
      }
    });

    test('a folder of book folders is left to the server', () {
      expect(
        bookOf([
          _file('01.mp3', 'Books/First'),
          _file('01.mp3', 'Books/Second'),
        ]),
        UploadGrouping.auto,
      );
      expect(
        bookOf([_file('01.mp3', 'First'), _file('01.mp3', 'Second')]),
        UploadGrouping.auto,
      );
      expect(
        bookOf([_file('01.mp3', 'A/CD1'), _file('01.mp3', 'B/CD1')]),
        UploadGrouping.auto,
      );
    });

    test('several .m4b are separate books even in one folder', () {
      expect(
        bookOf([_file('one.m4b', 'Shelf'), _file('two.M4B', 'Shelf')]),
        UploadGrouping.auto,
      );
    });

    test('one .m4b with its extras in a folder is one book', () {
      expect(
        bookOf([_file('book.m4b', 'Book'), _file('cover-notes.mp3', 'Book')]),
        UploadGrouping.album,
      );
    });

    test('loose picks are left to the server', () {
      expect(
        bookOf([_file('book-1.m4b'), _file('book-2.m4b')]),
        UploadGrouping.auto,
      );
      expect(bookOf([_file('01.mp3'), _file('02.mp3')]), UploadGrouping.auto);
      expect(
        bookOf([_file('01.mp3', 'Book'), _file('loose.mp3')]),
        UploadGrouping.auto,
      );
    });

    test('music is always auto-detected', () {
      expect(
        defaultUploadGrouping(MediaType.music, [
          _file('01.flac', 'Album'),
          _file('02.flac', 'Album'),
        ]),
        UploadGrouping.auto,
      );
    });
  });
}
