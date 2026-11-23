import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'app_host.dart';
import 'fakes.dart';

final _gate = Provider<TransferGate>(pinRefreshGate);

DownloadedItem _item({required bool complete, bool active = false}) =>
    DownloadedItem(
      pid: 'tr-1',
      sizeBytes: 1,
      files: 1,
      complete: complete,
      active: active,
    );

void main() {
  test('the gate the app builds is shut until the sync engine is connected, '
      'while a download is moving, and while the player waits on the '
      'network', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    final audio = FakeEngine();
    final sync = SyncEngine(
      db: db,
      repository: FakeRepository(),
      channelFactory: FakeLink().factory,
    );
    addTearDown(sync.dispose);
    final container = appContainer(
      downloads: downloads,
      sync: sync,
      mirror: db,
      engine: audio,
    );
    addTearDown(container.dispose);
    final gate = container.read(_gate);

    expect(await gate.isOpen(), isFalse, reason: 'the engine has not started');
    await sync.start();
    await pumpEventQueue();
    expect(sync.current.online, isTrue);
    expect(await gate.isOpen(), isTrue);

    // Held or finished, a download is not one in flight.
    downloads.setStored([_item(complete: true, active: true)]);
    expect(await gate.isOpen(), isTrue);
    downloads.setStored([_item(complete: false)]);
    expect(await gate.isOpen(), isTrue);
    downloads.setStored([_item(complete: false, active: true)]);
    expect(await gate.isOpen(), isFalse);
    downloads.setStored(const []);

    await audio.load('http://deck.local/stream');
    expect(
      await gate.isOpen(),
      isTrue,
      reason: 'steady playback holds nothing',
    );
    audio.buffer();
    expect(await gate.isOpen(), isFalse);
    audio.buffer(on: false);
    expect(await gate.isOpen(), isTrue);
  });
}
