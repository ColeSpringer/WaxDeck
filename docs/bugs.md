# Bugs

List of current bugs or correctness issues.

- [8-5-2026] We should consider making the profile icon slightly larger. currently it is small enough to be hard to find for those who don't already know where to look.

- [8-5-2026] the (i) icon being used for the notications icon is irregular and not intuitive. We should use use the bell icon or something similarly more standard.

- [8-5-2026] I think that little moving icon we have in the player deck looks stupid. we either need to improve that with a better idea or remove it.

- [8-5-2026] It's not overly obvious how to bring hte mini deck player into the full player (need to click on the area with the track). It works but seems a little limited compared to competitors and feels poor from a UX standpoint. Also, double clicking the bar in an area sometimes brings up the full player and sometimes does not so the experience is also inconsistent.

- [8-5-2026] We should maybe try to prioritize radio stations that are "closer" (by country not exact location) to the user. Currently the suggested items seem like a random assortment that contain the search term.

- [8-5-2026] Trying to add a radio by url shows multiple input boxes instead of just 1.

- [8-5-2026] Added radio stations don't show when searching.

- [8-5-2026] The search bar in the upper left is almost purely cosmetic. clicking on it just brings you to the search page but you can't intereact/type with the search bar you originally clicked on.

- [8-5-2026] There is no image for the radio station when playing. We might also consider using the artwork of the currently playing song from the radio (maybe station logo when deck is minimized and song artwork when in full screen)

- [8-5-2026] Clicking on an empty page in any of the main screens (home, music, etc.) acts as a click of the add button even if you're click is no where near the button(s) you're supposed to use.

- [8-5-2026] Trashed items are still listed by `/library/items`. Deleting to trash archives the item (`state = archived`) and no item read path filters on state, so it keeps answering the listing: deleted tracks stay in the library everywhere the listing feeds. Reproduced directly - delete to trash, then poll the listing for 20s, and the item never leaves. A cue split is where it shows worst, because the archived carvings sit beside their replacements under the same two titles, so nothing that looks a cue title up in the listing can tell the pair apart - `TestCueSplitEndToEnd` asks by pid for that reason. (It is not what made that test flaky: the listing orders `ord ASC, pid ASC`, so the replacement's later ULID always sorts last and always wins a last-wins map. The flake was the listing answering before the replacements reached it, which the test now polls for.) The fix is a state predicate in `applyItemFilter` (reads.go around 29-51), but which surfaces get one is a decision worth an ADR rather than a filter dropped in: `remote` and `missing` items belong in a listing and `archived` ones do not, restore has to keep resolving an archived pid, and the same question applies to Browse, search, and the facet counts.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs ADR-0008's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same ADR-0008 dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.