/// Windowed reads over app-local files, so large uploads (audiobooks
/// run to hundreds of megabytes) never sit whole in memory. Behind a
/// conditional import: the io implementation serves native platforms
/// and tests, the stub keeps web builds compiling (web has no local
/// paths; its upload flows carry bytes).
library;

export 'local_file_reader_stub.dart'
    if (dart.library.io) 'local_file_reader_io.dart';
