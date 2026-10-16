import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';

/// Listens this client could not report and has nowhere durable to keep:
/// the web build runs no sync engine, so a listen that failed to send
/// used to go with the session that made it.
///
/// Held while the account that made them stays signed in, and sent with
/// the next report that gets through, or when the server is back. The
/// server deduplicates on the session id, so sending one twice costs
/// nothing.
class ListenOutbox {
  final List<ListenSession> _held = <ListenSession>[];
  bool _flushing = false;

  /// Enough for a long offline stretch; the oldest go first past it.
  static const _cap = 200;

  void keep(ListenSession listen) {
    _held.add(listen);
    if (_held.length > _cap) _held.removeAt(0);
  }

  /// Sends what is held. A refusal is the server's answer and is dropped;
  /// anything else keeps the batch for the next try.
  Future<void> flush(WaxDeckRepository repository) async {
    if (_held.isEmpty || _flushing) return;
    _flushing = true;
    final batch = List<ListenSession>.of(_held);
    try {
      await repository.reportListens(batch);
      _held.removeWhere(batch.contains);
    } on WaxDeckApiException catch (error) {
      if (error.isRefusal) _held.removeWhere(batch.contains);
    } finally {
      _flushing = false;
    }
  }
}

/// One account's: a listen held when one account signs out must never be
/// sent under the next one's token.
final listenOutboxProvider = Provider<ListenOutbox>((ref) {
  ref.watch(signedInAccountProvider);
  return ListenOutbox();
});
