import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'l10n.dart';

/// Loads the faces the resolved interface locale writes in.
///
/// Deferred faces are otherwise warmed from metadata on the API
/// transport, which never carries a static UI string: a Devanagari
/// interface would draw its own chrome in boxes until an album title
/// happened to need the same face.
///
/// The sample is an ARB key rather than a locale-to-script table nobody
/// would remember to extend.
class LocaleFontWarmup extends StatefulWidget {
  const LocaleFontWarmup({
    super.key,
    required this.child,
    this.warm = WaxFonts.ensureFor,
  });

  final Widget child;

  /// Seam for tests; the app always warms through [WaxFonts].
  final Future<void> Function(String sample) warm;

  @override
  State<LocaleFontWarmup> createState() => _LocaleFontWarmupState();
}

class _LocaleFontWarmupState extends State<LocaleFontWarmup> {
  Locale? _warmed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _warmed) return;
    _warmed = locale;
    // Nothing waits on a face: text that raced ahead of one re-lays out
    // when the loader completes, and a build that ships without the
    // asset degrades to the platform's own fallback.
    unawaited(widget.warm(context.l10n.localeFontSample));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
