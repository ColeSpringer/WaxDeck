import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/uploads_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

class _FakePicker implements FilePickerPort {
  _FakePicker(this.files);

  final List<PickedAudioFile> files;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => files;
}

Widget _host(FakeRepository repo, {FilePickerPort? picker}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    if (picker != null) filePickerProvider.overrideWithValue(picker),
  ],
  child: const MaterialApp(home: UploadsScreen()),
);

void main() {
  testWidgets('renders session states and the duplicate warning', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 1048576,
      sizeBytes: 4194304,
    );
    repo.uploadsById['up-2'] = testUpload(
      'up-2',
      fileName: 'meridian-2.flac',
      state: 'staged',
      reviewEntryId: 'rv-9',
      duplicate: const DuplicateWarning(
        itemPid: 'tr-9',
        kind: 'content',
        title: 'Neon Meridian',
        artist: 'The Cardinal Waves',
      ),
    );
    repo.uploadsById['up-3'] = testUpload(
      'up-3',
      fileName: 'meridian-3.flac',
      state: 'imported',
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final receivingRow = find.byKey(const ValueKey('upload-row-up-1'));
    expect(receivingRow, findsOneWidget);
    expect(
      find.descendant(
        of: receivingRow,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: receivingRow, matching: find.text('25% received')),
      findsOneWidget,
    );
    expect(find.text('staged'), findsOneWidget);
    expect(find.text('imported'), findsOneWidget);
    expect(find.byKey(const ValueKey('upload-duplicate-up-2')), findsOneWidget);
    expect(
      find.text('Duplicate (exact copy): Neon Meridian by The Cardinal Waves'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('upload-review-up-2')), findsOneWidget);
  });

  testWidgets('hides the pick button while no picker port is wired', (
    tester,
  ) async {
    await tester.pumpWidget(_host(FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('upload-pick')), findsNothing);
    expect(find.text('No uploads yet'), findsOneWidget);
  });

  testWidgets('add from URL queues an acquisition', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Always visible, picker port or not.
    await tester.tap(find.byKey(const Key('upload-from-url')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('acquire-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('acquire-url')),
      'https://tube.example/watch?v=neon-meridian',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acquire-submit')));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls, hasLength(1));
    expect(
      repo.acquisitionCalls.single.url,
      'https://tube.example/watch?v=neon-meridian',
    );
    expect(repo.acquisitionCalls.single.mediaType, MediaType.music);
    expect(repo.acquisitionCalls.single.format, 'best');
    expect(find.byKey(const Key('acquire-dialog')), findsNothing);
  });

  testWidgets('acquiring can pick a download format', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('upload-from-url')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('acquire-url')),
      'https://tube.example/watch?v=neon-meridian',
    );
    await tester.pumpAndSettle();

    // Open the format dropdown and choose MP3.
    await tester.tap(find.byKey(const Key('acquire-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MP3').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('acquire-submit')));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls.single.format, 'mp3');
  });

  testWidgets('picking a file chunks it up and seals the session', (
    tester,
  ) async {
    final repo = FakeRepository();
    // 2.5 MiB: two full 1 MiB chunks plus a remainder.
    final bytes = Uint8List(2621440);
    final picker = _FakePicker([
      PickedAudioFile(name: 'fresh-cut.flac', bytes: bytes),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('upload-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload-media-confirm')));
    await tester.pumpAndSettle();

    expect(repo.putUploadDataCalls, hasLength(3));
    expect(repo.putUploadDataCalls[0].offset, 0);
    expect(repo.putUploadDataCalls[1].offset, 1048576);
    expect(repo.putUploadDataCalls[2].offset, 2097152);
    expect(repo.putUploadDataCalls[2].byteCount, 524288);
    final session = repo.uploadsById.values.single;
    expect(session.state, 'staged');
    expect(session.mediaType, MediaType.music);
    expect(find.text('staged'), findsOneWidget);
  });
}
