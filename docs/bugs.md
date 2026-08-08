# Bugs

List of current bugs or correctness issues.

- [8-7-2026] if you hit the stop button for a radio station in full screen it then displays a "nothing is playing" screen. maybe we should default to when hitting that button it minimizes to the deck since, for radio specifically, there is nothing for the user to do once you disconnect from the station.

- [8-7-2026] The artwork retrieved sometimes seems like its low resolution for radio cover art. This might be due to source resolution so may not be fixable.

- [8-7-2026] The artwork for radio cover art sometimes disappears during the song (including the song info artist and title which is probably related to the disappearance). This seems to mostly happen towards the end when there is about 30 seconds to a minute left.

- [8-7-2026] Maybe we should make the fullscreen cover art appearance for radio dynamic (maybe the others too?) to the art it wants to display? currently its circular which results in album artwork being cutoff. I guess circular would be ok for radio station logos or the default artwork we use.

- [8-7-2026] radio station artwork just retrieves from top of list which results in sometimes displaying compilation albums. we should prioritize the album version, then the single version, then whatever version(s) are left.

- [8-7-2026] there are alignment issues everywhere. a lot of dead space. all in all just not as polished of an experience as we would like.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs ADR-0008's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same ADR-0008 dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
