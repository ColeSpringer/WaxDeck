import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/saf_folder_picker.dart';

// The Android folder pick behind a mocked waxdeck/saf channel: the
// walk arrives unfiltered from Kotlin, and everything with a policy in
// it - the extension filter, DRM accounting, ordering, windowed reads -
// happens Dart-side, which is the half a host test can pin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('waxdeck/saf');
  final log = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          log.add(call);
          return handler(call);
        });
  }

  Map<String, Object?> entry(String name, String relativeDir, {int size = 4}) =>
      {
        'name': name,
        'size': size,
        'relativeDir': relativeDir,
        'uri': 'content://tree/doc%2F$name',
      };

  setUp(log.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a cancelled pick is an empty pick', () async {
    mock((call) async => null);
    final pick = await pickSafAudioFolder(const UploadFormatSets());
    expect(pick.files, isEmpty);
    expect(pick.skippedUnsupported, 0);
    expect(pick.skippedDrm, 0);
  });

  test(
    'the walk is filtered, counted, and ordered like the desktop one',
    () async {
      mock((call) async {
        expect(call.method, 'pickTree');
        return [
          entry('b.flac', 'Boxset/CD2'),
          entry('cover.jpg', 'Boxset'),
          entry('a.mp3', 'Boxset/CD1'),
          entry('book.aax', 'Boxset'),
          entry('top.mp3', 'Boxset'),
        ];
      });
      final pick = await pickSafAudioFolder(const UploadFormatSets());
      expect(pick.files.map((f) => f.name).toList(), [
        'top.mp3',
        'a.mp3',
        'b.flac',
      ]);
      expect(pick.files.first.relativeDir, 'Boxset');
      expect(pick.skippedUnsupported, 1, reason: 'the jpg fell to the filter');
      expect(pick.skippedDrm, 1, reason: 'the Audible file counts apart');
    },
  );

  test('the server-reported set is what filters', () async {
    mock((call) async => [entry('take.wv', 'Rips'), entry('drop.mp3', 'Rips')]);
    final pick = await pickSafAudioFolder(
      const UploadFormatSets(accepted: {'wv'}, rejected: {}),
    );
    expect(pick.files.single.name, 'take.wv');
    expect(pick.skippedUnsupported, 1);
    expect(pick.skippedDrm, 0);
  });

  test(
    'a file whose provider reports no size is counted, not vanished',
    () async {
      // Kotlin crosses unknown sizes as -1: a session must declare its
      // size up front, so the file cannot upload - but a folder of these
      // must still explain itself instead of reading as an empty pick.
      mock(
        (call) async => [
          entry('ok.mp3', 'Drive'),
          entry('phantom.mp3', 'Drive', size: -1),
        ],
      );
      final pick = await pickSafAudioFolder(const UploadFormatSets());
      expect(pick.files.single.name, 'ok.mp3');
      expect(pick.skippedUnsupported, 1);
    },
  );

  test('a picked file reads in windows over the channel', () async {
    mock((call) async {
      if (call.method == 'pickTree') {
        return [entry('one.mp3', 'Album', size: 8)];
      }
      expect(call.method, 'readChunk');
      final args = (call.arguments as Map).cast<String, Object?>();
      final start = args['start']! as int;
      final length = args['length']! as int;
      return Uint8List.fromList(
        List.generate(length, (i) => (start + i) & 0xff),
      );
    });
    final pick = await pickSafAudioFolder(const UploadFormatSets());
    final file = pick.files.single;
    expect(file.path, isNull, reason: 'a SAF file is not a filesystem path');

    // One bounded window: the transfer's own shape.
    final window = <int>[
      for (final chunk in await file.openRead!(2, 6).toList()) ...chunk,
    ];
    expect(window, [2, 3, 4, 5]);
    final read = log.last;
    expect((read.arguments as Map)['uri'], 'content://tree/doc%2Fone.mp3');

    // No bounds: the whole file, ending at its declared size.
    final whole = <int>[
      for (final chunk in await file.openRead!().toList()) ...chunk,
    ];
    expect(whole, hasLength(8));
  });

  test('a document that ended early ends the stream short', () async {
    mock((call) async {
      if (call.method == 'pickTree') {
        return [entry('gone.mp3', 'Album', size: 100)];
      }
      return Uint8List(0);
    });
    final pick = await pickSafAudioFolder(const UploadFormatSets());
    final chunks = await pick.files.single.openRead!().toList();
    expect(chunks, isEmpty);
  });
}
