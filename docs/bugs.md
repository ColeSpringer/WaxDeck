# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-23-2026] [desktop] A track that cannot be played hangs the desktop player instead of failing it. Measured through `integration_test/load_fault_test.dart -d linux` with a positive control: a good FLAC loads, and then garbage bytes, a truncated file, a missing file, an HTTP 404, an HTTP 502, a refused connection and a DNS failure all leave `engine.load` unsettled - no throw, no completion - for at least twenty seconds each. mpv through media_kit never reports the failure at all, so the session's load never returns, no error pane appears, and nothing gives up: the player sits on the last face indefinitely. Android throws promptly for the same seven, so this is media_kit rather than something shared. The fix is a load deadline in `JustAudioEngine` - past it the load is abandoned and reported as a `MediaLoadException` - which also gives the desktop a fault to classify at all.

- [8-23-2026] when adding a radio station, it takes a lot of time for the station image to be populated by anything. it sits blank for 20-30 seconds or so.

- [8-23-2026] i think clients all try to look at a specific port thats only available over LAN. we need to make sure clients work over non local networks with vpns, tailscale, through reverse proxies, etc. 

- [8-23-2026] clients dont have ability to adjust streaming quality. necessary for off LAN streaming.

- [8-22-2026] we need a way to handle users putting their files in the library location manually (not through our clients). do we ignore the files? if not, how do we intake them? maybe default to just taking them as is. no metadata search or anything. Not sure how we would handle differentiating between music, podcast, or audiobook (likely mostly music and audiobooks). maybe flags can be set for how a user wants that to be dealt with as have them as settings wouldnt be useful until after setup. the discovery of them at all is something we need to look into as well.

- [8-22-2026] An instant mix with nothing left to add says the track has no mix. `InstantMixSheet._mix` passes the whole standing queue as `excludePids`, which is right - a mix must not repeat what is already queued - but playing a row on a listing screen queues the whole loaded listing, so on a small library the exclusion is the whole catalog and the mix comes back empty. The sheet then shows "No mix available for this track", which says the seed has no neighbours; it has plenty, they are all already queued. Two different answers wearing one sentence. Either the empty result needs to say which it is, or the exclusion needs to be the part of the queue still ahead rather than all of it. `discovery.spec.ts:13` met this and now plays from an album so its own subject is testable, which is a spec working around it rather than the thing being fixed.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
