import 'package:dio/dio.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Starts loading any on-demand script faces (Arabic, Hebrew, Thai, CJK)
/// the server's metadata will need on screen.
///
/// One interceptor on the API transport instead of a warm call in every
/// controller: each response body is walked once, right where every DTO
/// arrives, so no screen can forget its corner of the library. The walk
/// is fire-and-forget (rendering never waits on a font; text that raced
/// ahead of its face re-lays out when the loader lands) and
/// [WaxFonts.scriptsIn] stops reporting a script once its load has
/// started, so the cost decays to a near-empty scan per string once a
/// library's faces are in.
class FontWarmupInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    _scan(response.data);
    handler.next(response);
  }

  void _scan(Object? node) {
    if (node is String) {
      for (final script in WaxFonts.scriptsIn(node)) {
        WaxFonts.ensureScript(script);
      }
    } else if (node is List<Object?>) {
      node.forEach(_scan);
    } else if (node is Map<Object?, Object?>) {
      node.values.forEach(_scan);
    }
  }
}
