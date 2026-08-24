# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-24-2026] from the homescreen, clicking on a podcast episode in new episodes starts playing the episode but playing an episode listed under recently added goes to the informational page for that episode. we should make the bahavior consistent. Also, we need to make it easier to go to the informational page. There is no options menu to open nor does a right click open anything to see the description/notes and such.

- [8-24-2026] Starting a track or podcast (haven't tried audiobooks) immediately go into the fullscreen page. Full screen should be an intentional choice. It should start playing minimized dock and if the user wants to have it in full screen they can do that themselves.

- [8-24-2026] It doesn't seem like podcasts update listening stats?

- [8-24-2026] Starting a podcast episode is slow on initial play (not downloaded). That might just be a network issue that is not fixable but we should look into that.

- [8-24-2026] When you go to add a podcast the search button states "Search directory". I don't think that is an accurate description. Makes it seem like your looking for local files.

- [8-24-2026] we still need to source artist images. the artists tab under music has no images. This probably also applies to podcasts

- [8-24-2026] The double yellow underline that you see sometimes (the letters on the right when looking through library items like albums or in the admin console over the main headers such as "library" and "people")

- [8-24-2026] On the homepage (and maybe others) when a track is too long there is no way to see the entire track name. it doesnt scroll or anything. I would think we would have at least the ability to hover over the track (on a desktop/web client) to be able to see a tooltip or something with the full title (or whatever missing information im not sure if its track specific.)

- [8-24-2026] Still done have a way to individually edit individual audio file metadata from the clients.

- [8-24-2026] Editing an entire albums metadata doesnt allow you to change most information (artist, release year, total tracks, etc.).

- [8-24-2026] "Art from the file. Borrowed from a track" on the album viewing page. Shouldn't be using 2 sentences. Maybe just having it as "Art from track 2" (just use the first track with cover art. they should be the same anyway since its an album).

- [8-24-2026] there is no way to click on the album artist of a track or just go straight to the album viewing page from the homepage (maybe other areas as well but i only checked homepage). On a related note, the album name doesnt show either. it just shows title and artist.

- [8-24-2026] Undoing "mark finished" can swallow another device's real completion. The undo is two writes - the position back, then the flags beside it (book_screen.dart `_undo`) - and an end-of-book checkpoint from another device landing between them is refused its finished mark while `played` still stands (`spokenWordCrossing`, server/internal/service/playback.go around 316); the flags-clear then lands last, leaving the book at 100 percent, unfinished, play count 0. A tens-of-milliseconds window needing a concurrent cross-device write, and it heals on the next listen past the threshold. Not WaxBin's: every catalog write applies as asked - the fix is an atomic undo, one request restoring position and flags together. The audiobooks spec's seeder used to be the "other device" here (8-24 soak, pass 3) and now waits the whole undo out.

- [8-23-2026] [desktop] A track that cannot be played hangs the desktop player instead of failing it. Measured through `integration_test/load_fault_test.dart -d linux` with a positive control: a good FLAC loads, and then garbage bytes, a truncated file, a missing file, an HTTP 404, an HTTP 502, a refused connection and a DNS failure all leave `engine.load` unsettled - no throw, no completion - for at least twenty seconds each. mpv through media_kit never reports the failure at all, so the session's load never returns, no error pane appears, and nothing gives up: the player sits on the last face indefinitely. Android throws promptly for the same seven, so this is media_kit rather than something shared. The fix is a load deadline in `JustAudioEngine` - past it the load is abandoned and reported as a `MediaLoadException` - which also gives the desktop a fault to classify at all.

- [8-23-2026] when adding a radio station, it takes a lot of time for the station image to be populated by anything. it sits blank for 20-30 seconds or so.

- [8-23-2026] i think clients all try to look at a specific port thats only available over LAN. we need to make sure clients work over non local networks with vpns, tailscale, through reverse proxies, etc. 

- [8-23-2026] clients dont have ability to adjust streaming quality. necessary for off LAN streaming.

- [8-22-2026] we need a way to handle users putting their files in the library location manually (not through our clients). do we ignore the files? if not, how do we intake them? maybe default to just taking them as is. no metadata search or anything. Not sure how we would handle differentiating between music, podcast, or audiobook (likely mostly music and audiobooks). maybe flags can be set for how a user wants that to be dealt with as have them as settings wouldnt be useful until after setup. the discovery of them at all is something we need to look into as well.

- [8-22-2026] An instant mix with nothing left to add says the track has no mix. `InstantMixSheet._mix` passes the whole standing queue as `excludePids`, which is right - a mix must not repeat what is already queued - but playing a row on a listing screen queues the whole loaded listing, so on a small library the exclusion is the whole catalog and the mix comes back empty. The sheet then shows "No mix available for this track", which says the seed has no neighbours; it has plenty, they are all already queued. Two different answers wearing one sentence. Either the empty result needs to say which it is, or the exclusion needs to be the part of the queue still ahead rather than all of it. `discovery.spec.ts:13` met this and now plays from an album so its own subject is testable, which is a spec working around it rather than the thing being fixed.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
