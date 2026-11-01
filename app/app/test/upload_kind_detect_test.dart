import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

// What the add flows guess about a pick before the person says: the kind
// from the file names, and an audiobook's grouping from where the files sit.

PickedAudioFile _file(String name, [String dir = '']) =>
    PickedAudioFile(name: name, size: 8, relativeDir: dir);

void main() {
  group('detectUploadMediaType', () {
    test('any .m4b makes an audiobook, whatever its case', () {
      expect(detectUploadMediaType(['book.m4b']), MediaType.audiobook);
      expect(detectUploadMediaType(['BOOK.M4B']), MediaType.audiobook);
      expect(
        detectUploadMediaType(['one.flac', 'two.M4b']),
        MediaType.audiobook,
      );
    });

    test('anything else is music', () {
      expect(detectUploadMediaType(['a.flac', 'b.mp3']), MediaType.music);
      expect(detectUploadMediaType(['book.m4a']), MediaType.music);
      expect(detectUploadMediaType(['m4b.mp3']), MediaType.music);
      expect(detectUploadMediaType(const <String>[]), MediaType.music);
    });
  });

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
