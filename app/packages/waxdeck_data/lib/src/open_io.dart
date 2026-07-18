import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// Opens the mirror database under the app support directory. Native
/// platforms only; web builds run without a local mirror for now (the
/// SPA stays server-backed and the event channel invalidates its
/// providers directly). The LazyDatabase defers the filesystem work to
/// first use, so construction is synchronous.
MirrorDatabase openMirrorDatabase() {
  return MirrorDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final dbDir = Directory(p.join(dir.path, 'waxdeck'));
      await dbDir.create(recursive: true);
      final file = File(p.join(dbDir.path, 'mirror.db'));
      return NativeDatabase.createInBackground(file);
    }),
  );
}

/// An in-memory mirror for tests.
MirrorDatabase inMemoryMirrorDatabase() {
  return MirrorDatabase(DatabaseConnection(NativeDatabase.memory()));
}
