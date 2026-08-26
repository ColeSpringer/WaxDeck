# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-25-2026] on the homescreen, when there are items on off screen an arrow appears that you are supposed to be able to click and move the shelf view. However, currently when you go to click it you will instead click the track underneath it and start playing and the shelf won't move at all. Also, its not overly obvious that there is flowover as the button doesnt show until you hover over it.

- [8-25-2026] For the queue in fullscreen, the album artwork shows in the right. I like the idea but we should have it on the left where the song and artist are. im thinking a little bit to the right of the "Up Next" text would look good

- [8-25-2026] the letters that appear on the right when looking at the albums page (for example) are somewhat hard to read given the background. Might just be worthwhile to do a whole audit of both dark and light mode to make sure contrast meets ally standards and also just to make sure that we have enough subtle variety to make things interesting to look at and informative.

- [8-25-2026] Whjen adding a podcast by url, the text hint states "Feed or channel url" when those are seperate depending on if you have RSS or youtube selected.

- [8-25-2026] In the same screen shot mentioned in the metadata editor icon item in this doc, there is the "Music" identifier. This also seems like its out of place and not in a good location.

- [8-25-2026] In the metadata editor you can't edit the source. Not sure what that limitation exists.

- [8-25-2026] some metadata editor icons don't really make sense. You have a checkmark as a selection tool and a pencil as a lock mechanism. Also the checkmark is on the upper right completely away from anything useful. Seems out of place and would make more sense in a different location. (see screenshot)

- [8-24-2026] Starting a track or podcast (haven't tried audiobooks) immediately go into the fullscreen page. Full screen should be an intentional choice. It should start playing minimized dock and if the user wants to have it in full screen they can do that themselves.

- [8-24-2026] It doesn't seem like podcasts update listening stats?

- [8-24-2026] Starting a podcast episode is slow on initial play (not downloaded). That might just be a network issue that is not fixable but we should look into that.

- [8-24-2026] The double yellow underline that you see sometimes (the letters on the right when looking through library items like albums or in the admin console over the main headers such as "library" and "people") is ugly.

- [8-24-2026] Undoing "mark finished" can swallow another device's real completion. The undo is two writes - the position back, then the flags beside it (book_screen.dart `_undo`) - and an end-of-book checkpoint from another device landing between them is refused its finished mark while `played` still stands (`spokenWordCrossing`, server/internal/service/playback.go around 316); the flags-clear then lands last, leaving the book at 100 percent, unfinished, play count 0. A tens-of-milliseconds window needing a concurrent cross-device write, and it heals on the next listen past the threshold. Not WaxBin's: every catalog write applies as asked - the fix is an atomic undo, one request restoring position and flags together. The audiobooks spec's seeder used to be the "other device" here (8-24 soak, pass 3) and now waits the whole undo out.

- [8-23-2026] [desktop] A track that cannot be played hangs the desktop player instead of failing it. Measured through `integration_test/load_fault_test.dart -d linux` with a positive control: a good FLAC loads, and then garbage bytes, a truncated file, a missing file, an HTTP 404, an HTTP 502, a refused connection and a DNS failure all leave `engine.load` unsettled - no throw, no completion - for at least twenty seconds each. mpv through media_kit never reports the failure at all, so the session's load never returns, no error pane appears, and nothing gives up: the player sits on the last face indefinitely. Android throws promptly for the same seven, so this is media_kit rather than something shared. The fix is a load deadline in `JustAudioEngine` - past it the load is abandoned and reported as a `MediaLoadException` - which also gives the desktop a fault to classify at all.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
