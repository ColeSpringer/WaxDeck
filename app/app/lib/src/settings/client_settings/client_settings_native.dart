import 'package:waxdeck_data/waxdeck_data.dart';

/// The native build's per-device settings store: the local mirror, which
/// is already open and already durable.
///
/// A null [db] is a widget test, which gets values that live as long as
/// the test does.
ClientSettingsStore createClientSettingsStore(MirrorDatabase? db) =>
    db == null ? MemoryClientSettingsStore() : DriftClientSettingsStore(db);
