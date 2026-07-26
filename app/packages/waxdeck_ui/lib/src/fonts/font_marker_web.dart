import 'dart:js_interop';

@JS('__waxFontsLoaded')
external set _waxFontsLoaded(JSAny? value);

final List<String> _families = <String>[];

/// Publishes the successfully installed on-demand families to
/// `window.__waxFontsLoaded`.
///
/// A face only lands here after `FontLoader.load` succeeded, which on
/// web means the engine parsed the bytes; the e2e suite reads it to
/// prove a face was actually installed, not merely fetched (a rejected
/// file and a fetched one look identical on the network).
void markFontLoaded(String family) {
  _families.add(family);
  _waxFontsLoaded = _families.map((f) => f.toJS).toList().toJS;
}
