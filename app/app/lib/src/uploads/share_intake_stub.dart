import 'share_intake.dart';

/// Web build: the browser has no share-sheet intents to receive.
ShareIntakePort createShareIntakePort() => const InertShareIntakePort();
