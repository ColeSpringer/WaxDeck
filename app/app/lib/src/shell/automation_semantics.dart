import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

/// Keeps the semantics tree live from the first frame on the web, where
/// browser automation drives the app through it. Elsewhere the platform
/// turns semantics on and off, which a held handle would mask: Android
/// relaunches the activity on some display changes and attaches a fresh
/// view, with an empty accessibility bridge, to the running engine, and
/// only the platform's off-then-on makes the framework send it a whole
/// tree instead of diffs.
SemanticsHandle? holdSemanticsForAutomation({bool web = kIsWeb}) =>
    web ? SemanticsBinding.instance.ensureSemantics() : null;
