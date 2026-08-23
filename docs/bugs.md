# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-23-2026] i think clients all try to look at a specific port thats only available over LAN. we need to make sure clients work over non local networks with vpns, tailscale, through reverse proxies, etc. 

- [8-23-2026] clients dont have ability to adjust streaming quality. necessary for off LAN streaming.

- [8-22-2026] we need a way to handle users putting their files in the library location manually (not through our clients). do we ignore the files? if not, how do we intake them? maybe default to just taking them as is. no metadata search or anything. Not sure how we would handle differentiating between music, podcast, or audiobook (likely mostly music and audiobooks). maybe flags can be set for how a user wants that to be dealt with as have them as settings wouldnt be useful until after setup. the discovery of them at all is something we need to look into as well.

- [8-22-2026] maybe reject file types that we dont support such as audible files (aax, aaxc). need to look into / confirm exactly what we can/want to support.

- [8-22-2026] A track the engine refuses stops the queue dead instead of being skipped. `/media/stream` reverse-proxies WaxFlow, which answers 415 for a file it cannot decode - the fixture library's deliberately corrupt FLAC is one, and a real library has its own. The client treats that as the end of playback: the player's whole body is replaced by "Playback stopped / Playback failed to start / Try again" and the queue does not advance, so one bad file in a queue of fifty ends the sitting. The engine is right to refuse; the decision is what the client should do with a refusal - skipping to the next entry and saying which one was skipped is the shape every other player has. Reproduced with `flac-garbage-1000ms-44100hz-2ch.flac` reached through "Keep playing similar", which is how an ordinary listener meets it.

- [8-22-2026] An instant mix with nothing left to add says the track has no mix. `InstantMixSheet._mix` passes the whole standing queue as `excludePids`, which is right - a mix must not repeat what is already queued - but playing a row on a listing screen queues the whole loaded listing, so on a small library the exclusion is the whole catalog and the mix comes back empty. The sheet then shows "No mix available for this track", which says the seed has no neighbours; it has plenty, they are all already queued. Two different answers wearing one sentence. Either the empty result needs to say which it is, or the exclusion needs to be the part of the queue still ahead rather than all of it. `discovery.spec.ts:13` met this and now plays from an album so its own subject is testable, which is a spec working around it rather than the thing being fixed.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
