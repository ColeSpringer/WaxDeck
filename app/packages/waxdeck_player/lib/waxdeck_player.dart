/// WaxDeck-owned audio engine facade.
///
/// App code imports this package only; community audio plugins are an
/// implementation detail behind [AudioEnginePort].
library;

export 'src/audio_engine_port.dart';
export 'src/bootstrap/bootstrap.dart';
export 'src/just_audio_engine.dart';
