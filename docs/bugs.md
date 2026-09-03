# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-28-2026] When you save a song from the radio, there are 2 seperate actions with the same icon. The always visible magnifying glass searches your library for it and the one from the menu identifies it from a review entry.

- [8-28-2026] notification doesnt clear even after dealing with the task unless you specifally go and clear/click on the notification.

- [8-28-2026] When you click on an artist from the artist section in music, their informational page shows a track name instead of just their artist name? Check related screenshots in bug_screenshots.

- [8-28-2026] when review an album metadata search, there is not a clear seperator between the tracks you have and the tracks you dont. all the missing tracks appear to be in the same container as the last track you actually have. (see screenshot)

- [8-28-2026] The menu and star that show over radio stations that you have added don't seem aligned properly. They look out of place / bad. (see screenshot)

- [8-28-2026] The volume slider in full screen still looks a little off center (at least when listening to music tracks). I think thats because its taking the icon into account. i think it just needs to slide over a little bit to the left.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
