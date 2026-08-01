# Bugs

List of current bugs or correctness issues.

- [7-31-2026] Appearance defaults to Dark instead of System Default.

- [7-31-2026] Tool tasks dont have a way to click and bring you to the finished item.

- [7-31-2026] No way to clear tool tasks. Done button is not clickable. No X indicator or anything.

- [8-1-2026] The radio page doesnt have the same "Add a show" button in the middle of the page as podcasts. "Add a station" button. They both have the plus sign in the top right. On the same note, the homepage uses a plus button on the buttom right instead of the button in the middle or the plus sign at the top. Need to fix the inconsistency.

- [8-1-2026] When you select the music section, it bring you to a page that is just a visual representation of the drop down menu items that show. This needs to be something else. An expansion of what shows on the home page? Default to playlists?

- [8-1-2026] The popup window for adding a podcast has inconsistent sizing for the buttons when selecting "RSS" or "Youtube" as source.

- [8-1-2026] when playing radio then selecting a podcast episode the audio does not switch over and the radio continues to play. The UI shows the podcast playing.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs ADR-0008's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same ADR-0008 dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.