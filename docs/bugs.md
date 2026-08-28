# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-25-2026] In the metadata editor you can't edit the source. Not sure what that limitation exists.

- [8-24-2026] Undoing "mark finished" can swallow another device's real completion. The undo is two writes - the position back, then the flags beside it (book_screen.dart `_undo`) - and an end-of-book checkpoint from another device landing between them is refused its finished mark while `played` still stands (`spokenWordCrossing`, server/internal/service/playback.go around 316); the flags-clear then lands last, leaving the book at 100 percent, unfinished, play count 0. A tens-of-milliseconds window needing a concurrent cross-device write, and it heals on the next listen past the threshold. Not WaxBin's: every catalog write applies as asked - the fix is an atomic undo, one request restoring position and flags together. The audiobooks spec's seeder used to be the "other device" here (8-24 soak, pass 3) and now waits the whole undo out.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
