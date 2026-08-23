/// WaxDeck-owned audio engine facade.
///
/// App code imports this package only; community audio plugins are an
/// implementation detail behind [AudioEnginePort].
library;

export 'src/audio_engine_port.dart';
export 'src/bootstrap/bootstrap.dart';
export 'src/fetchable/fetchable.dart';
export 'src/just_audio_engine.dart';
export 'src/audio_service_handler.dart';
export 'src/media_session_port.dart';
