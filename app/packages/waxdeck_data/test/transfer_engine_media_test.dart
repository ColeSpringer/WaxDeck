import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck_data/src/transfer_engine_io.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the media directory is the plugin\'s own destination, under the '
      'application support directory', () async {
    final support = await Directory.systemTemp.createTemp('waxdeck-support');
    addTearDown(() => support.delete(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _pathProvider,
      (MethodCall call) async => support.path,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(_pathProvider, null));

    // A sweep that cannot resolve this is silent, so it is pinned: it is
    // the directory a completion's path is resolved in.
    expect(
      await mediaDirectoryPath(),
      p.join(support.path, 'waxdeck', 'media'),
    );
  });

  test('a later test finds no handler left behind', () {
    expect(
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .checkMockMessageHandler(_pathProvider.name, null),
      isTrue,
      reason: 'it would answer with a directory already deleted',
    );
  });
}
