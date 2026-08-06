# Bugs

List of current bugs or correctness issues.

- [8-5-2026] We should maybe try to prioritize radio stations that are "closer" (by country not exact location) to the user. Currently the suggested items seem like a random assortment that contain the search term.

- [8-5-2026] Trying to add a radio by url shows multiple input boxes instead of just 1.

- [8-5-2026] Added radio stations don't show when searching.

- [8-5-2026] There is no image for the radio station when playing. We might also consider using the artwork of the currently playing song from the radio (maybe station logo when deck is minimized and song artwork when in full screen)

The three Connect entries below wait on ADR-0008's transfer semantics:
one decision about what "start playing there" does to the local engine,
which they all block on and which deserves its own slice.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs ADR-0008's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same ADR-0008 dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
