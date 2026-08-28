import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/saf_folder_picker.dart';

// The Android folder pick behind a mocked waxdeck/saf channel: the walk
// arrives unfiltered from Kotlin a page at a time, and everything with
// a policy in it - the extension filter, DRM accounting, ordering,
// windowed reads - happens Dart-side, which is the half a host test can
// pin. The paging protocol itself is here too: pickTree grants a root,
// nextTreeBatch is pulled until it says done, and a walk left unfinished
// is disposed.
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

  /// Serves a grant of [root] followed by [batches], one per
  /// `nextTreeBatch`, the last one carrying `done`.
  ///
  /// Every method the protocol has is answered here and nothing else
  /// is: a method this mock has not been taught is a protocol change,
  /// and it should fail the test that made it rather than quietly
  /// answer null.
  void mockWalk(
    String root,
    List<List<Map<String, Object?>>> batches, {
    Future<Object?> Function(MethodCall call)? readChunk,
  }) {
    var next = 0;
    mock((call) async {
      switch (call.method) {
        case 'pickTree':
          return {'root': root, 'walk': 'walk-1'};
        case 'nextTreeBatch':
          expect(
            (call.arguments as Map)['walk'],
            'walk-1',
            reason: 'every call names the walk it belongs to',
          );
          final page = next < batches.length ? batches[next] : const [];
          next++;
          return {'entries': page, 'done': next >= batches.length};
        case 'disposeTreeWalk':
          expect((call.arguments as Map)['walk'], 'walk-1');
          return null;
        case 'readChunk':
          if (readChunk == null) {
            fail('this walk serves no readChunk');
          }
          return readChunk(call);
        default:
          fail('unexpected waxdeck/saf method ${call.method}');
      }
    });
  }

  List<String> methods() => log.map((c) => c.method).toList();

  setUp(log.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a cancelled pick is an empty pick, and walks nothing', () async {
    mock((call) async => null);
    final pick = await pickSafAudioFolder(const UploadFormatSets());
    expect(pick.files, isEmpty);
    expect(pick.skippedUnsupported, 0);
    expect(pick.skippedDrm, 0);
    // No grant, no walk: nothing to pull and nothing to dispose.
    expect(methods(), ['pickTree']);
  });

  test('the walk is pulled across batches, then filtered, counted, and ordered '
      'like the desktop one', () async {
    mockWalk('Boxset', [
      [entry('b.flac', 'CD2'), entry('cover.jpg', '')],
      [entry('a.mp3', 'CD1'), entry('book.aax', '')],
      [entry('top.mp3', '')],
    ]);
    final pick = await pickSafAudioFolder(const UploadFormatSets());
    expect(pick.files.map((f) => f.name).toList(), [
      'top.mp3',
      'a.mp3',
      'b.flac',
    ]);
    expect(pick.skippedUnsupported, 1, reason: 'the jpg fell to the filter');
    expect(pick.skippedDrm, 1, reason: 'the Audible file counts apart');

    // Pulled until the walk said it was done, and no further; a walk
    // that finished on its own has already dropped itself, so there
    // is nothing to dispose.
    expect(methods(), [
      'pickTree',
      'nextTreeBatch',
      'nextTreeBatch',
      'nextTreeBatch',
    ]);
    expect(log[1].arguments, {'walk': 'walk-1', 'max': 500});
  });

  test('the granted root is the directory every entry hangs off', () async {
    // Kotlin reports directories relative to the tree, so the root
    // crosses once rather than on every entry; the composed shape is
    // the one the desktop and web walks build.
    mockWalk('Boxset', [
      [entry('top.mp3', ''), entry('deep.mp3', 'CD1/Bonus')],
    ]);
    final pick = await pickSafAudioFolder(const UploadFormatSets());
    expect(pick.files.map((f) => f.relativeDir).toList(), [
      'Boxset',
      'Boxset/CD1/Bonus',
    ]);
  });

  test('the server-reported set is what filters', () async {
    mockWalk('Rips', [
      [entry('take.wv', ''), entry('drop.mp3', '')],
    ]);
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
      mockWalk('Drive', [
        [entry('ok.mp3', ''), entry('phantom.mp3', '', size: -1)],
      ]);
      final pick = await pickSafAudioFolder(const UploadFormatSets());
      expect(pick.files.single.name, 'ok.mp3');
      expect(pick.skippedUnsupported, 1);
    },
  );

  test('a walk that fails mid-tree raises, and is disposed', () async {
    mock((call) async {
      switch (call.method) {
        case 'pickTree':
          return {'root': 'Boxset', 'walk': 'walk-1'};
        case 'nextTreeBatch':
          if (log.where((c) => c.method == 'nextTreeBatch').length == 1) {
            return {
              'entries': [entry('one.mp3', '')],
              'done': false,
            };
          }
          throw PlatformException(code: 'enumerate-failed');
        default:
          return null;
      }
    });
    // Half a folder is not a pick: the caller words the failure rather
    // than seeing a short list it cannot tell from a small folder.
    await expectLater(
      pickSafAudioFolder(const UploadFormatSets()),
      throwsA(isA<PlatformException>()),
    );
    expect(methods().last, 'disposeTreeWalk');
  });

  test('a walk abandoned by a failing dispose still raises the walk\'s '
      'own error', () async {
    mock((call) async {
      if (call.method == 'pickTree') {
        return {'root': 'Boxset', 'walk': 'walk-1'};
      }
      if (call.method == 'nextTreeBatch') {
        throw PlatformException(code: 'enumerate-failed');
      }
      throw PlatformException(code: 'no-walk');
    });
    await expectLater(
      pickSafAudioFolder(const UploadFormatSets()),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'enumerate-failed',
        ),
      ),
    );
  });

  test('a page that is not a page raises rather than truncating', () async {
    // A short pick is indistinguishable from a small folder, so a walk
    // that answers nothing must never read as the end of one.
    mock((call) async {
      if (call.method == 'pickTree') {
        return {'root': 'Boxset', 'walk': 'walk-1'};
      }
      if (call.method == 'nextTreeBatch') return null;
      return null;
    });
    await expectLater(
      pickSafAudioFolder(const UploadFormatSets()),
      throwsA(isA<PlatformException>()),
    );
    expect(methods().last, 'disposeTreeWalk');
  });

  test('the page size asked for is the one that crosses', () async {
    // The on-device suite leans on this: a probe folder small enough
    // to push onto an emulator only crosses a page boundary if it can
    // ask for a small page.
    mockWalk('Boxset', [
      [entry('one.mp3', '')],
      [entry('two.mp3', '')],
    ]);
    final pick = await pickSafAudioFolder(const UploadFormatSets(), batch: 1);
    expect(pick.files.map((f) => f.name).toList(), ['one.mp3', 'two.mp3']);
    for (final call in log.where((c) => c.method == 'nextTreeBatch')) {
      expect((call.arguments as Map)['max'], 1);
    }
  });

  test('a picked file reads in windows over the channel', () async {
    mockWalk(
      'Album',
      [
        [entry('one.mp3', '', size: 8)],
      ],
      readChunk: (call) async {
        expect(call.method, 'readChunk');
        final args = (call.arguments as Map).cast<String, Object?>();
        final start = args['start']! as int;
        final length = args['length']! as int;
        return Uint8List.fromList(
          List.generate(length, (i) => (start + i) & 0xff),
        );
      },
    );
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
    mockWalk('Album', [
      [entry('gone.mp3', '', size: 100)],
    ], readChunk: (call) async => Uint8List(0));
    final pick = await pickSafAudioFolder(const UploadFormatSets());
    final chunks = await pick.files.single.openRead!().toList();
    expect(chunks, isEmpty);
  });
}
