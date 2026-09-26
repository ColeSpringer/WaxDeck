import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'sync_engine_test.dart' show ScriptedRepository;

const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _track = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';

/// A transfer engine that moves no bytes and records everything: every
/// transfer starts, pauses, and finishes on the test's schedule.
class FakeTransferEngine implements TransferEnginePort {
  final _events = StreamController<TransferEvent>.broadcast();

  final started = <TransferRequest>[];
  final canceled = <String>[];
  final paused = <String>[];
  final resumed = <String>[];

  /// The URL each resume was handed, null where it kept its own.
  final resumedWith = <String?>[];
  final described = <TransferGroup>[];

  /// Every call that touches a transfer or its notification, in order.
  final calls = <String>[];

  /// What a previous run left in the plugin's records.
  List<TrackedTransfer> tracked = <TrackedTransfer>[];
  Object? trackedError;
  var recovered = 0;

  NotificationPermission permission = NotificationPermission.granted;
  var permissionRequests = 0;

  /// Held open, a permission request waits on it.
  Completer<void>? requestGate;

  /// Ids handed out, in order.
  final ids = <String>[];

  /// What [pause] answers.
  bool pausable = true;

  /// Set, a start is refused.
  bool refuse = false;

  /// Awaited by [report] once the event has been delivered, so a test
  /// asserts against bookkeeping the manager has finished.
  Future<void> Function()? settle;

  var _next = 0;

  @override
  Stream<TransferEvent> get events => _events.stream;

  @override
  Future<List<TrackedTransfer>> trackedTransfers() async {
    calls.add('tracked');
    final error = trackedError;
    if (error != null) throw error;
    return tracked;
  }

  @override
  Future<void> recover() async {
    calls.add('recover');
    recovered++;
  }

  @override
  Future<void> describe(TransferGroup group) async {
    calls.add('describe:${group.id}');
    described.add(group);
  }

  @override
  Future<String> start(TransferRequest request) async {
    if (refuse) throw StateError('refused');
    started.add(request);
    final id = 'task-${_next++}';
    calls.add('start:$id');
    ids.add(id);
    return id;
  }

  @override
  Future<bool> pause(String taskId) async {
    paused.add(taskId);
    return pausable;
  }

  @override
  Future<void> resume(String taskId, {String? url, DateTime? staleAt}) async {
    resumed.add(taskId);
    resumedWith.add(url);
  }

  @override
  Future<void> cancel(List<String> taskIds) async => canceled.addAll(taskIds);

  @override
  Future<NotificationPermission> notificationPermission() async => permission;

  @override
  Future<NotificationPermission> requestNotificationPermission() async {
    permissionRequests++;
    await requestGate?.future;
    return permission = NotificationPermission.granted;
  }

  /// Reports an event and waits for the manager to act on it.
  Future<void> report(
    String taskId, {
    TransferState? state,
    double? fraction,
    String? path,
    String? pid,
    String? fileName,
    int? httpStatus,
  }) async {
    _events.add(
      TransferEvent(
        taskId: taskId,
        state: state,
        fraction: fraction,
        path: path,
        pid: pid,
        fileName: fileName,
        httpStatus: httpStatus,
      ),
    );
    await pumpEventQueue();
    await settle?.call();
    await pumpEventQueue();
  }

  @override
  void dispose() => _events.close();
}

/// A repository answering download-info per pid.
class _DownloadRepository extends ScriptedRepository {
  final Map<String, DownloadInfo> infoByPid = <String, DownloadInfo>{};
  final fetched = <String>[];

  /// Held open, a download-info read waits on it.
  Completer<void>? infoGate;

  /// Held open, a download-info read for that pid waits on it.
  final holdFor = <String, Completer<void>>{};

  /// Set, a download-info read fails with it.
  Object? infoError;

  @override
  Future<DownloadInfo> getDownloadInfo(String pid) async {
    fetched.add(pid);
    await (holdFor[pid] ?? infoGate)?.future;
    final error = infoError;
    if (error != null) throw error;
    final info = infoByPid[pid];
    if (info == null) {
      throw const WaxDeckApiException(code: 'not-found', message: 'no item');
    }
    return info;
  }
}

DownloadInfo _info(
  String pid, {
  required int parts,
  String hashPrefix = 'ess',
  int? durationMs = 60000,
  String etag = '1-1',
  DateTime? expiresAt,
}) => DownloadInfo(
  pid: pid,
  files: <DownloadFileInfo>[
    for (var i = 0; i < parts; i++)
      DownloadFileInfo(
        url: 'https://example.test/$pid/$i',
        mimeType: 'audio/mp4',
        sizeBytes: 4194304,
        fileName: 'part$i.m4b',
        essenceHash: '$hashPrefix$i',
        etag: etag,
        durationMs: durationMs,
      ),
  ],
  expiresAt: expiresAt ?? DateTime.utc(2026, 7, 30),
);

const _copy = DownloadCopy(
  downloading: _downloading,
  downloaded: 'Done',
  failed: 'Failed',
  part: _part,
);

String _downloading(String progress) => 'Getting $progress';

String _part(String title, int number, int total) => '$title ($number/$total)';

/// An unfinished record for one file, as a previous run left it.
Future<void> _pending(
  MirrorDatabase db,
  String pid,
  int index, {
  String state = 'pending',
}) => db
    .into(db.downloadRecords)
    .insert(
      DownloadRecordsCompanion.insert(
        pid: pid,
        fileIndex: index,
        essenceHash: 'ess$index',
        etag: '1-1',
        fileName: 'ess$index.m4b',
        localPath: '',
        sizeBytes: 1,
        state: state,
      ),
    );

/// A gate a test opens and shuts.
class _FakeGate implements TransferGate {
  bool opened = true;
  final _changes = StreamController<bool>.broadcast();

  /// Waited on after a move, so the manager has acted on it.
  Future<void> Function()? settle;

  @override
  Future<bool> isOpen() async => opened;

  @override
  Stream<bool> get changes => _changes.stream;

  Future<void> move({required bool open}) async {
    opened = open;
    _changes.add(open);
    await pumpEventQueue();
    await settle?.call();
  }

  void dispose() => _changes.close();
}

/// Retries a test fires by hand.
class _Timers {
  final pending = <_FakeTimer>[];

  Timer call(Duration wait, void Function() fire) {
    final timer = _FakeTimer(wait, fire);
    pending.add(timer);
    return timer;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.wait, this._fire);

  final Duration wait;
  final void Function() _fire;
  var _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _fire();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  late MirrorDatabase db;
  late FakeTransferEngine engine;
  late _FakeGate gate;
  late _DownloadRepository repo;
  late _Timers timers;
  late BackgroundDownloadManager manager;
  late Directory tmp;

  /// Before the default download-info's URLs expire.
  var now = DateTime.utc(2026, 7, 29, 12);

  BackgroundDownloadManager build({int maxRunning = 3}) {
    final built = BackgroundDownloadManager(
      db: db,
      repository: () => repo,
      engine: engine,
      gate: gate,
      copy: () => _copy,
      clock: () => now,
      maxRunning: maxRunning,
      timer: timers.call,
    );
    engine.settle = () => built.settled;
    gate.settle = () => built.settled;
    return built;
  }

  setUp(() {
    db = inMemoryMirrorDatabase();
    engine = FakeTransferEngine();
    gate = _FakeGate();
    repo = _DownloadRepository();
    timers = _Timers();
    now = DateTime.utc(2026, 7, 29, 12);
    manager = build();
    tmp = Directory.systemTemp.createTempSync('waxdeck-downloads-test');
  });

  tearDown(() async {
    manager.dispose();
    gate.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Finishes an item's transfers one after another, with real files.
  Future<List<String>> completeAll(String pid) async {
    final paths = <String>[];
    final done = <String>{};
    while (true) {
      final i = [
        for (var i = 0; i < engine.ids.length; i++)
          if (engine.started[i].pid == pid &&
              !done.contains(engine.ids[i]) &&
              !engine.canceled.contains(engine.ids[i]))
            i,
      ].firstOrNull;
      if (i == null) return paths;
      done.add(engine.ids[i]);
      final file = File('${tmp.path}/${engine.started[i].fileName}')
        ..writeAsStringSync('bytes');
      paths.add(file.path);
      await engine.report(
        engine.ids[i],
        state: TransferState.complete,
        fraction: 1,
        path: file.path,
      );
    }
  }

  /// Lands [taskId] with a real file behind it.
  Future<void> land(String taskId, String fileName) => engine.report(
    taskId,
    state: TransferState.complete,
    path: (File('${tmp.path}/$fileName')..writeAsStringSync('a')).path,
  );

  Future<List<String>> states() async => [
    for (final row in await db.select(db.downloadRecords).get()) row.state,
  ];

  group('download', () {
    test('records every file and fetches them one at a time', () async {
      repo.infoByPid[_book] = _info(_book, parts: 3);
      await manager.download(_book);

      expect(await states(), ['pending', 'pending', 'pending']);
      expect(engine.started.map((r) => r.fileName), ['ess0.m4b']);

      await land(engine.ids.single, 'ess0.m4b');

      expect(engine.started.map((r) => r.fileName), ['ess0.m4b', 'ess1.m4b']);
    });

    test('names a file safely from a structured essence hash', () async {
      repo.infoByPid[_book] = _info(
        _book,
        parts: 1,
        hashPrefix: 'sha256/mp3-frames-v1:beef',
      );
      await manager.download(_book);

      final name = engine.started.single.fileName;
      expect(
        name,
        isNot(anyOf(contains('/'), contains(r'\'), contains(':'))),
        reason: 'a file name may not carry separators or a Windows colon',
      );
      expect(p.extension(name), '.m4b');
      expect(p.basenameWithoutExtension(name), contains('beef'));
    });

    test(
      'two essences that differ only in punctuation keep two names',
      () async {
        repo.infoByPid[_book] = _info(
          _book,
          parts: 1,
          hashPrefix: 'sha256/a:b',
        );
        await manager.download(_book);
        repo.infoByPid[_track] = _info(
          _track,
          parts: 1,
          hashPrefix: 'sha256:a/b',
        );
        await manager.download(_track);

        final names = engine.started.map((r) => r.fileName).toSet();
        expect(names, hasLength(2));
      },
    );

    test('keeps bytes it already holds and refreshes the record', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1, durationMs: null);
      await manager.download(_book);
      await completeAll(_book);

      repo.infoByPid[_book] = _info(
        _book,
        parts: 1,
        durationMs: 90000,
        etag: '2-2',
      );
      await manager.download(_book);

      expect(engine.started, hasLength(1));
      final row = await db.select(db.downloadRecords).getSingle();
      expect(row.durationMs, 90000);
      expect(row.etag, '2-2');
      expect(row.state, 'complete');
    });

    test('re-fetches a file whose audio changed', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await completeAll(_book);

      repo.infoByPid[_book] = _info(_book, parts: 1, hashPrefix: 'other');
      await manager.download(_book);

      expect(engine.started, hasLength(2));
      final row = await db.select(db.downloadRecords).getSingle();
      expect(row.state, 'pending');
      expect(row.essenceHash, 'other0');
    });

    test('items past the running limit wait their turn', () async {
      const pids = <String>[
        'tr-01JZX5N8QW3F4V9T2B7KDTRACKA',
        'tr-01JZX5N8QW3F4V9T2B7KDTRACKB',
        'tr-01JZX5N8QW3F4V9T2B7KDTRACKC',
      ];
      for (final pid in pids) {
        repo.infoByPid[pid] = _info(pid, parts: 1, hashPrefix: pid);
      }
      manager.dispose();
      engine = FakeTransferEngine();
      manager = build(maxRunning: 2);
      for (final pid in pids) {
        await manager.download(pid);
      }
      expect(engine.started.map((r) => r.pid), pids.take(2));

      await completeAll(pids.first);

      expect(engine.started.map((r) => r.pid), pids);
    });

    test('asking again for an item on its way starts nothing new', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      await engine.report(engine.ids.single, fraction: 0.5);

      await manager.download(_book);

      expect(engine.started, hasLength(1));
      expect(engine.canceled, isEmpty);
    });

    test('a start the engine refuses gives the item up', () async {
      engine.refuse = true;
      repo.infoByPid[_book] = _info(_book, parts: 1);
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);

      await manager.download(_book);
      await pumpEventQueue();

      expect(await db.select(db.downloadRecords).get(), isEmpty);
      expect(seen.single.failed, isTrue);
    });
  });

  group('progress', () {
    test("a fraction is the item's, across its files", () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      final seen = <double>[];
      manager.progress.listen((p) => seen.add(p.fraction));

      await engine.report(engine.ids[0], fraction: 0.5);
      await land(engine.ids[0], 'ess0.m4b');
      await engine.report(engine.ids[1], fraction: 0.5);

      expect(seen, [0.25, 0.75]);
    });

    test('completion waits for every file of the item', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);

      await land(engine.ids[0], 'ess0.m4b');
      expect(seen.where((p) => p.complete), isEmpty);
      expect(await manager.isComplete(_book), isFalse);

      await land(engine.ids[1], 'ess1.m4b');
      expect(seen.where((p) => p.complete), hasLength(1));
      expect(await manager.isComplete(_book), isTrue);
    });

    test('a failure is reported so a waiter stops waiting', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);

      await engine.report(engine.ids.single, state: TransferState.failed);

      expect(seen.single.failed, isTrue);
    });

    test('a failed file discards the whole item', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      await land(engine.ids[0], 'ess0.m4b');

      await engine.report(
        engine.ids[1],
        state: TransferState.failed,
        httpStatus: 500,
      );

      expect(await db.select(db.downloadRecords).get(), isEmpty);
      expect(File('${tmp.path}/ess0.m4b').existsSync(), isFalse);
    });

    test('a pause from outside is not an ending', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);

      await engine.report(engine.ids.single, state: TransferState.paused);
      expect(seen, isEmpty);

      await land(engine.ids.single, 'ess0.m4b');
      expect(await manager.isComplete(_book), isTrue);
    });
  });

  group('remove', () {
    test(
      'stops the transfer in flight before deleting rows or files',
      () async {
        repo.infoByPid[_book] = _info(_book, parts: 2);
        await manager.download(_book);

        await manager.remove(_book);

        expect(engine.canceled, engine.ids);
        expect(await db.select(db.downloadRecords).get(), isEmpty);
      },
    );

    test('a canceled transfer reporting late touches nothing', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final id = engine.ids.first;
      await manager.remove(_book);

      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);
      await land(id, 'ess0.m4b');

      expect(seen, isEmpty);
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test('unlinks the bytes it held', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      final paths = await completeAll(_book);
      expect(paths.every((p) => File(p).existsSync()), isTrue);

      await manager.remove(_book);

      expect(paths.any((p) => File(p).existsSync()), isFalse);
      expect(await manager.localFor(_book), isNull);
    });

    test('leaves a file a second item still holds', () async {
      repo.infoByPid[_track] = _info(_track, parts: 1, hashPrefix: 'shared');
      await manager.download(_track);
      final shared = File('${tmp.path}/shared0.m4b')..writeAsStringSync('a');
      await engine.report(
        engine.ids.first,
        state: TransferState.complete,
        path: shared.path,
      );
      const sibling = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK2';
      repo.infoByPid[sibling] = _info(sibling, parts: 1, hashPrefix: 'shared');
      await manager.download(sibling);
      await engine.report(
        engine.ids.last,
        state: TransferState.complete,
        path: shared.path,
      );

      await manager.remove(_track);
      expect(shared.existsSync(), isTrue, reason: 'the sibling points at it');

      await manager.remove(sibling);
      expect(shared.existsSync(), isFalse, reason: 'that was the last one');
    });

    test('two items removed at once still unlink what they shared', () async {
      repo.infoByPid[_track] = _info(_track, parts: 1, hashPrefix: 'shared');
      await manager.download(_track);
      final shared = File('${tmp.path}/shared0.m4b')..writeAsStringSync('a');
      await engine.report(
        engine.ids.first,
        state: TransferState.complete,
        path: shared.path,
      );
      const sibling = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK2';
      repo.infoByPid[sibling] = _info(sibling, parts: 1, hashPrefix: 'shared');
      await manager.download(sibling);
      await engine.report(
        engine.ids.last,
        state: TransferState.complete,
        path: shared.path,
      );

      await Future.wait([manager.remove(_track), manager.remove(sibling)]);

      expect(shared.existsSync(), isFalse, reason: 'nothing holds it now');
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });
  });

  group('cancel', () {
    test('stops the transfer and drops the pending rows', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);

      await manager.cancel(_book);

      expect(engine.canceled, hasLength(1));
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test(
      'discards the parts that did land, not just the pending rows',
      () async {
        repo.infoByPid[_book] = _info(_book, parts: 3);
        await manager.download(_book);
        await land(engine.ids[0], 'ess0.m4b');

        await manager.cancel(_book);

        expect(await db.select(db.downloadRecords).get(), isEmpty);
        expect(await manager.localFor(_book), isNull);
        expect(File('${tmp.path}/ess0.m4b').existsSync(), isFalse);
        expect(engine.canceled, [engine.ids[1]]);
      },
    );
  });

  group('pause', () {
    test('answers false for an item it does not hold', () async {
      expect(await manager.pause(_book), isFalse);
      expect(engine.paused, isEmpty);
    });

    test('holds the item: its part stops and the rest wait', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);

      expect(await manager.pause(_book), isTrue);
      expect(engine.paused, [engine.ids.single]);
      await land(engine.ids.single, 'ess0.m4b');

      expect(engine.started, hasLength(1), reason: 'the item is paused');
    });

    test('a part that will not pause goes back in the queue', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      engine.pausable = false;

      expect(await manager.pause(_book), isTrue);
      expect(engine.canceled, ['task-0']);

      await manager.resume(_book);
      await manager.settled;
      expect(engine.started.map((r) => r.fileName), ['ess0.m4b', 'ess0.m4b']);
    });

    test('resume goes on where it stopped', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await manager.pause(_book);

      await manager.resume(_book);

      expect(engine.resumed, ['task-0']);
      expect(engine.resumedWith, [null]);
    });

    test('resume after its URL expired goes on with a fresh one', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await manager.pause(_book);
      now = DateTime.utc(2026, 7, 31);
      repo.infoByPid[_book] = _info(
        _book,
        parts: 1,
        expiresAt: DateTime.utc(2026, 8, 1),
      );

      await manager.resume(_book);
      await manager.settled;

      expect(engine.resumed, ['task-0']);
      expect(engine.resumedWith, ['https://example.test/$_book/0']);
      expect(engine.canceled, isEmpty, reason: 'its bytes are kept');
    });

    test('a pause is remembered until it is lifted', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);

      await manager.pause(_book);
      expect(await states(), ['paused', 'paused']);
      expect((await manager.stored()).single.paused, isTrue);

      await manager.resume(_book);
      expect(await states(), ['pending', 'pending']);
    });
  });

  group('wifi hold', () {
    test('nothing starts while the gate is shut', () async {
      await gate.move(open: false);
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);

      expect(engine.started, isEmpty);
      expect(await states(), ['pending', 'pending']);
    });

    test('the queue moves once it opens', () async {
      await gate.move(open: false);
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);

      await gate.move(open: true);

      expect(engine.started.map((r) => r.fileName), ['ess0.m4b']);
    });

    test(
      'a running part parks when it shuts and goes on when it opens',
      () async {
        repo.infoByPid[_book] = _info(_book, parts: 2);
        await manager.download(_book);

        await gate.move(open: false);
        expect(engine.paused, ['task-0']);

        await gate.move(open: true);
        expect(engine.resumed, ['task-0']);
        expect(engine.resumedWith, [null]);
      },
    );

    test('a part that will not park goes back in the queue', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      engine.pausable = false;

      await gate.move(open: false);
      expect(engine.canceled, ['task-0']);

      await gate.move(open: true);
      expect(engine.started.map((r) => r.fileName), ['ess0.m4b', 'ess0.m4b']);
    });

    test("the gate leaves the listener's pause alone", () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await manager.pause(_book);

      await gate.move(open: false);
      await gate.move(open: true);

      expect(engine.paused, ['task-0']);
      expect(engine.resumed, isEmpty);
    });

    test('a resume while shut waits for the gate', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await manager.pause(_book);
      await gate.move(open: false);

      await manager.resume(_book);
      expect(engine.resumed, isEmpty);

      await gate.move(open: true);
      expect(engine.resumed, ['task-0']);
    });

    test('a cancel drops what the gate was holding', () async {
      await gate.move(open: false);
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);

      await manager.cancel(_book);
      await gate.move(open: true);

      expect(engine.started, isEmpty);
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test('a parked part its pause failed goes back in the queue', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await gate.move(open: false);

      await engine.report('task-0', state: TransferState.failed);
      expect(await states(), ['pending'], reason: 'not given up');

      await gate.move(open: true);
      expect(engine.started.map((r) => r.fileName), ['ess0.m4b', 'ess0.m4b']);
    });

    test('a late report of running strands nothing', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await gate.move(open: false);

      await engine.report('task-0', state: TransferState.running);
      await engine.report('task-0', state: TransferState.paused);
      await gate.move(open: true);

      expect(engine.resumed, ['task-0']);
    });

    test('a gate that opens while a download is asked for starts it', () async {
      await gate.move(open: false);
      repo
        ..infoByPid[_book] = _info(_book, parts: 1)
        ..infoGate = Completer<void>();
      final asked = manager.download(_book);
      await pumpEventQueue();

      await gate.move(open: true);
      repo.infoGate!.complete();
      await asked;
      await manager.settled;

      expect(engine.started, hasLength(1));
    });
  });

  group('expiry', () {
    test('a 401 resumes the part on a fresh URL, bytes kept', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);

      await engine.report(
        'task-0',
        state: TransferState.failed,
        httpStatus: 401,
      );
      await manager.settled;

      expect(repo.fetched, [_book, _book]);
      expect(engine.resumed, ['task-0']);
      expect(engine.resumedWith, ['https://example.test/$_book/0']);
      expect(await states(), ['pending']);
    });

    test('a long download is not given up for expiring', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);

      for (var i = 0; i < 6; i++) {
        await engine.report('task-0', fraction: i / 10);
        await engine.report(
          'task-0',
          state: TransferState.failed,
          httpStatus: 401,
        );
        await manager.settled;
      }

      expect(engine.resumed, hasLength(6));
      expect(await states(), ['pending']);
    });

    test('a URL that keeps failing fresh is taken at its word', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);

      for (var i = 0; i < 4; i++) {
        await engine.report(
          'task-0',
          state: TransferState.failed,
          httpStatus: 401,
        );
        await manager.settled;
      }

      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test('a woken part whose URL expired goes on with a fresh one', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await gate.move(open: false);
      now = DateTime.utc(2026, 7, 31);
      repo.infoByPid[_book] = _info(
        _book,
        parts: 1,
        expiresAt: DateTime.utc(2026, 8, 1),
      );

      await gate.move(open: true);
      await manager.settled;

      expect(engine.resumedWith, ['https://example.test/$_book/0']);
    });

    test("an expiry is the part's own, not its item's", () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      now = DateTime.utc(2026, 7, 30, 6);
      repo.infoByPid[_book] = _info(
        _book,
        parts: 2,
        expiresAt: DateTime.utc(2026, 8, 1),
      );
      await manager.download(_book);
      await gate.move(open: false);

      now = DateTime.utc(2026, 7, 31);
      await gate.move(open: true);
      await manager.settled;

      expect(engine.resumedWith, [
        'https://example.test/$_book/0',
      ], reason: 'task-0 still holds the URL it started with');
    });

    test('a download-info that fails is asked again later', () async {
      await _pending(db, _book, 0);
      repo.infoError = const WaxDeckApiException(
        code: 'transport',
        message: 'offline',
      );

      await manager.recover();
      await manager.settled;
      expect(timers.pending, hasLength(1));
      expect(engine.started, isEmpty);

      repo
        ..infoError = null
        ..infoByPid[_book] = _info(_book, parts: 1);
      timers.pending.single.fire();
      await manager.settled;

      expect(engine.started.single.fileName, 'ess0.m4b');
    });

    test('a cancel wins over a download-info still on its way', () async {
      await _pending(db, _book, 0);
      repo
        ..infoByPid[_book] = _info(_book, parts: 1)
        ..infoGate = Completer<void>();
      await manager.recover();
      await pumpEventQueue();

      await manager.cancel(_book);
      repo.infoGate!.complete();
      await manager.settled;

      expect(engine.started, isEmpty);
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test('a failed read waits out its backoff while others move', () async {
      await _pending(db, _book, 0);
      repo.infoError = const WaxDeckApiException(
        code: 'transport',
        message: 'offline',
      );
      await manager.recover();
      await manager.settled;
      repo
        ..infoError = null
        ..infoByPid[_track] = _info(_track, parts: 1);

      await manager.download(_track);
      await completeAll(_track);
      await manager.settled;

      expect(repo.fetched, [_book, _track]);
    });

    test('a gate that opens asks again at once', () async {
      await _pending(db, _book, 0);
      repo.infoError = const WaxDeckApiException(
        code: 'transport',
        message: 'offline',
      );
      await manager.recover();
      await manager.settled;
      repo
        ..infoError = null
        ..infoByPid[_book] = _info(_book, parts: 1);

      await gate.move(open: false);
      await gate.move(open: true);
      await manager.settled;

      expect(engine.started.single.fileName, 'ess0.m4b');
    });

    test('reads wait their turn like transfers', () async {
      const pids = <String>[
        'tr-01JZX5N8QW3F4V9T2B7KDTRACKA',
        'tr-01JZX5N8QW3F4V9T2B7KDTRACKB',
        'tr-01JZX5N8QW3F4V9T2B7KDTRACKC',
      ];
      for (final pid in pids) {
        await _pending(db, pid, 0);
        repo.infoByPid[pid] = _info(pid, parts: 1);
      }
      manager.dispose();
      engine = FakeTransferEngine();
      manager = build(maxRunning: 2);

      await manager.recover();
      await manager.settled;

      expect(repo.fetched, pids.take(2));
    });

    test('a read in flight holds its place against a resume', () async {
      const other = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';
      await _pending(db, _book, 0, state: 'paused');
      await _pending(db, other, 0);
      repo
        ..infoByPid[_book] = _info(_book, parts: 1)
        ..infoByPid[other] = _info(other, parts: 1)
        ..holdFor[other] = Completer<void>();
      manager.dispose();
      engine = FakeTransferEngine();
      manager = build(maxRunning: 1);
      await manager.recover();
      await pumpEventQueue();

      await manager.resume(_book);
      await pumpEventQueue();
      expect(engine.started, isEmpty, reason: 'the read holds the one place');

      repo.holdFor[other]!.complete();
      await manager.settled;
      expect(engine.started.map((r) => r.pid), [other]);
    });
  });

  group('start', () {
    test(
      'a transfer the OS killed is picked up and lands on its record',
      () async {
        await _pending(db, _book, 0);
        engine.tracked = const [
          TrackedTransfer(taskId: 'old-0', pid: _book, fileName: 'ess0.m4b'),
        ];

        await manager.recover();
        await land('old-0', 'ess0.m4b');

        expect(await manager.isComplete(_book), isTrue);
        expect(engine.calls, ['tracked', 'describe:$_book', 'recover']);
      },
    );

    test(
      'a completion that beats the pickup lands through its record',
      () async {
        await _pending(db, _book, 0);

        await engine.report(
          'old-0',
          state: TransferState.complete,
          path: (File('${tmp.path}/ess0.m4b')..writeAsStringSync('b')).path,
          pid: _book,
          fileName: 'ess0.m4b',
        );

        expect(await manager.isComplete(_book), isTrue);
      },
    );

    test('a failure it has no mapping for discards nothing', () async {
      await _pending(db, _book, 0, state: 'complete');

      await engine.report(
        'stale',
        state: TransferState.canceled,
        pid: _book,
        fileName: 'ess0.m4b',
      );

      expect(await manager.isComplete(_book), isTrue);
    });

    test('a pending record with nothing behind it is fetched afresh', () async {
      await _pending(db, _book, 0);
      repo.infoByPid[_book] = _info(_book, parts: 1);

      await manager.recover();
      await manager.settled;

      expect(repo.fetched, [_book]);
      expect(engine.started.single.fileName, 'ess0.m4b');
    });

    test('a pending record the server no longer has is dropped', () async {
      await _pending(db, _book, 0);

      await manager.recover();
      await manager.settled;

      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test(
      'a part in flight keeps its transfer; the rest wait behind it',
      () async {
        await _pending(db, _book, 0);
        await _pending(db, _book, 1);
        repo.infoByPid[_book] = _info(_book, parts: 2);
        engine.tracked = const [
          TrackedTransfer(taskId: 'old-0', pid: _book, fileName: 'ess0.m4b'),
        ];

        await manager.recover();
        await manager.settled;
        expect(engine.canceled, isEmpty);
        expect(engine.started, isEmpty);

        await land('old-0', 'ess0.m4b');
        await manager.settled;
        expect(engine.started.single.fileName, 'ess1.m4b');
      },
    );

    test('records it cannot read leave the rows to go on from', () async {
      await _pending(db, _book, 0);
      repo.infoByPid[_book] = _info(_book, parts: 1);
      engine.trackedError = StateError('undecodable record');

      await manager.recover();
      await manager.settled;

      expect(engine.recovered, 1);
      expect(engine.started.single.fileName, 'ess0.m4b');
    });

    test('a transfer that finished while the app was away lands', () async {
      await _pending(db, _book, 0);
      final file = File('${tmp.path}/ess0.m4b')..writeAsStringSync('bytes');
      engine.tracked = [
        TrackedTransfer(
          taskId: 'old-0',
          pid: _book,
          fileName: 'ess0.m4b',
          state: TransferState.complete,
          path: file.path,
        ),
      ];

      await manager.recover();

      expect(await manager.isComplete(_book), isTrue);
      expect(engine.canceled, ['old-0'], reason: 'its record is forgotten');
    });

    test('a transfer for nothing this device holds is stopped', () async {
      engine.tracked = const [
        TrackedTransfer(taskId: 'old-0', pid: _book, fileName: 'ess0.m4b'),
      ];

      await manager.recover();

      expect(engine.canceled, ['old-0']);
    });

    test('a parked transfer goes on at start where the gate is open', () async {
      await _pending(db, _book, 0);
      engine.tracked = [
        TrackedTransfer(
          taskId: 'old-0',
          pid: _book,
          fileName: 'ess0.m4b',
          state: TransferState.paused,
          staleAt: DateTime.utc(2026, 7, 30),
        ),
      ];

      await manager.recover();

      expect(engine.resumed, ['old-0']);
      expect(engine.resumedWith, [null]);
    });

    test(
      'a parked transfer whose URL expired goes on with a fresh one',
      () async {
        await _pending(db, _book, 0);
        repo.infoByPid[_book] = _info(_book, parts: 1);
        engine.tracked = [
          TrackedTransfer(
            taskId: 'old-0',
            pid: _book,
            fileName: 'ess0.m4b',
            state: TransferState.paused,
            staleAt: DateTime.utc(2026, 7, 29),
          ),
        ];

        await manager.recover();
        await manager.settled;

        expect(engine.resumedWith, ['https://example.test/$_book/0']);
        expect(engine.canceled, isEmpty);
      },
    );

    test('a transfer that runs behind a shut gate is parked', () async {
      await gate.move(open: false);
      await _pending(db, _book, 0);
      engine.tracked = const [
        TrackedTransfer(taskId: 'old-0', pid: _book, fileName: 'ess0.m4b'),
      ];

      await manager.recover();

      expect(engine.paused, ['old-0']);
    });

    test('a pause from before the restart still holds', () async {
      await _pending(db, _book, 0, state: 'paused');
      engine.tracked = [
        TrackedTransfer(
          taskId: 'old-0',
          pid: _book,
          fileName: 'ess0.m4b',
          state: TransferState.paused,
          staleAt: DateTime.utc(2026, 7, 30),
        ),
      ];

      await manager.recover();
      await manager.settled;

      expect(engine.resumed, isEmpty);
      await manager.resume(_book);
      expect(engine.resumed, ['old-0']);
    });

    test('the pickup never asks for notifications', () async {
      engine.permission = NotificationPermission.undetermined;
      await _pending(db, _book, 0);
      repo.infoByPid[_book] = _info(_book, parts: 1);

      await manager.recover();
      await manager.settled;

      expect(engine.started, hasLength(1));
      expect(engine.permissionRequests, 0);
    });
  });

  group('notifications', () {
    test('an item describes its notices before its first part', () async {
      await db
          .into(db.mirrorItems)
          .insert(
            MirrorItemsCompanion.insert(
              pid: _book,
              ulid: 'BOOK01',
              mediaType: 'audiobook',
              title: 'There And Back Again',
              durationMs: 1000,
              sortKey: 'there',
            ),
          );
      repo.infoByPid[_book] = _info(_book, parts: 20);

      await manager.download(_book);

      expect(engine.calls, [
        'describe:$_book',
        'describe:$_book.parts',
        'start:task-0',
      ]);
      expect(engine.described.map((g) => g.announceDone), [true, false]);
      final first = engine.started.single;
      expect(first.displayName, 'There And Back Again (1/20)');
      expect(first.group, '$_book.parts');
    });

    test('only the last part announces the item', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      await land('task-0', 'ess0.m4b');

      expect(engine.started.last.group, _book);
      expect(engine.started.last.displayName, 'part0.m4b (2/2)');
    });

    test("a one-file item keeps its file's own name", () async {
      repo.infoByPid[_track] = _info(_track, parts: 1);

      await manager.download(_track);

      expect(engine.started.single.displayName, 'part0.m4b');
      expect(engine.started.single.group, _track);
      expect(engine.described.map((g) => g.id), [_track]);
    });

    test('an undetermined permission is asked of the OS once a run', () async {
      engine.permission = NotificationPermission.undetermined;
      repo.infoByPid[_book] = _info(_book, parts: 1);
      repo.infoByPid[_track] = _info(_track, parts: 1);

      await manager.download(_book);
      await manager.download(_track);

      expect(engine.permissionRequests, 1);
    });

    test('a denial with a rationale asks the app before the OS', () async {
      engine.permission = NotificationPermission.deniedExplainable;
      final asks = <void>[];
      manager.notificationRationale.listen(asks.add);
      repo.infoByPid[_book] = _info(_book, parts: 1);
      repo.infoByPid[_track] = _info(_track, parts: 1);

      await manager.download(_book);
      await manager.download(_track);
      await pumpEventQueue();

      expect(asks, hasLength(1));
      expect(engine.permissionRequests, 0);
      await manager.requestNotificationPermission();
      expect(engine.permissionRequests, 1);
    });

    test('a plain denial is taken as the answer', () async {
      engine.permission = NotificationPermission.denied;
      final asks = <void>[];
      manager.notificationRationale.listen(asks.add);
      repo.infoByPid[_book] = _info(_book, parts: 1);

      await manager.download(_book);
      await pumpEventQueue();

      expect(asks, isEmpty);
      expect(engine.permissionRequests, 0);
    });

    test('a download does not wait on the permission prompt', () async {
      engine
        ..permission = NotificationPermission.undetermined
        ..requestGate = Completer<void>();
      repo.infoByPid[_book] = _info(_book, parts: 1);

      await manager.download(_book);

      expect(engine.started, hasLength(1));
      engine.requestGate!.complete();
    });

    test('two asks at once reach the OS once', () async {
      engine.requestGate = Completer<void>();

      final first = manager.requestNotificationPermission();
      final second = manager.requestNotificationPermission();
      engine.requestGate!.complete();
      await Future.wait([first, second]);

      expect(engine.permissionRequests, 1);
    });
  });

  group('bookkeeping', () {
    test('an item with nothing left has nothing to act on', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await completeAll(_book);

      expect(await manager.pause(_book), isFalse);
      await manager.resume(_book);
      expect(engine.resumed, isEmpty);
      await manager.cancel(_book);
      expect(engine.canceled, isEmpty);
    });

    test('a second report for a finished transfer is ignored', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final id = engine.ids.single;
      final real = File('${tmp.path}/ess0.m4b')..writeAsStringSync('a');
      await engine.report(id, state: TransferState.complete, path: real.path);

      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);
      final elsewhere = File('${tmp.path}/elsewhere.m4b')
        ..writeAsStringSync('b');
      await engine.report(
        id,
        state: TransferState.complete,
        path: elsewhere.path,
      );

      expect(seen, isEmpty);
      final row = await db.select(db.downloadRecords).getSingle();
      expect(row.localPath, real.path);
    });

    test('a failed transfer is forgotten too', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final id = engine.ids.single;
      await engine.report(id, state: TransferState.failed);

      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);
      await engine.report(id, state: TransferState.failed);
      expect(seen, isEmpty);
    });
  });

  group('localFor', () {
    test('answers the parts in reading order, with their durations', () async {
      repo.infoByPid[_book] = _info(_book, parts: 3);
      await manager.download(_book);
      final paths = await completeAll(_book);

      final local = await manager.localFor(_book);
      expect(local!.parts.map((p) => p.path), paths);
      expect(local.parts.map((p) => p.durationMs), [60000, 60000, 60000]);
      expect(local.sequenced, isTrue);
    });

    test('parts with no stored duration cannot be sequenced', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2, durationMs: null);
      await manager.download(_book);
      await completeAll(_book);

      final local = await manager.localFor(_book);
      expect(local!.parts, hasLength(2));
      expect(local.sequenced, isFalse);
    });

    test('answers nothing while a part is still pending', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      await land(engine.ids[0], 'ess0.m4b');

      expect(await manager.localFor(_book), isNull);
    });

    test('answers nothing when the bytes were evicted behind us', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final paths = await completeAll(_book);
      File(paths.single).deleteSync();

      expect(await manager.localFor(_book), isNull);
    });

    test('carries a carved track its window', () async {
      repo.infoByPid[_track] = DownloadInfo(
        pid: _track,
        files: <DownloadFileInfo>[
          const DownloadFileInfo(
            url: 'https://example.test/rip',
            mimeType: 'audio/flac',
            sizeBytes: 100,
            fileName: 'rip.flac',
            essenceHash: 'rip',
            etag: '1-1',
          ),
        ],
        spanStartMs: 60000,
        spanEndMs: 240000,
        expiresAt: DateTime.utc(2026, 7, 30),
      );
      await manager.download(_track);
      await completeAll(_track);

      final local = await manager.localFor(_track);
      expect(local!.spanStartMs, 60000);
      expect(local.spanEndMs, 240000);
    });
  });

  group('stored', () {
    test('is per item, with its files summed', () async {
      repo.infoByPid[_book] = _info(_book, parts: 3);
      await manager.download(_book);
      await completeAll(_book);
      repo.infoByPid[_track] = _info(_track, parts: 1, hashPrefix: 'tr');
      await manager.download(_track);

      final rows = await manager.stored();
      final book = rows.firstWhere((r) => r.pid == _book);
      expect(book.files, 3);
      expect(book.sizeBytes, 3 * 4194304);
      expect(book.complete, isTrue);
      final track = rows.firstWhere((r) => r.pid == _track);
      expect(track.complete, isFalse);
      expect(track.paused, isFalse);
    });
  });

  test('a record survives a schema upgrade with its duration null', () async {
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: _book,
            fileIndex: 0,
            essenceHash: 'old',
            etag: '1-1',
            fileName: 'old.m4b',
            localPath: '${tmp.path}/old.m4b',
            sizeBytes: 10,
            state: 'complete',
            durationMs: const Value(null),
          ),
        );
    File('${tmp.path}/old.m4b').writeAsStringSync('x');

    final local = await manager.localFor(_book);
    expect(local!.parts.single.durationMs, isNull);
    expect(local.sequenced, isFalse);
  });
}
