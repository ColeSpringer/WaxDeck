import 'dart:io';

/// True under `flutter test` (the tool exports FLUTTER_TEST). The sync
/// machinery never self-starts there: widget tests own their world, and
/// a test that wants the engine overrides its providers explicitly.
bool get inFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');
