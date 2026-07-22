/// The platform resolution point for file picking and drop-item
/// conversion, on the local_file_reader conditional-import pattern:
/// dart:io platforms get native dialogs with real paths and folder
/// recursion, the web build gets lazy browser-file references, and
/// anything else gets the inert stub (provider stays null, affordances
/// hide).
library;

export 'file_picker_stub.dart'
    if (dart.library.io) 'file_picker_io.dart'
    if (dart.library.js_interop) 'file_picker_web.dart';
