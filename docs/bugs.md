# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-21-2026] "From the file" in reference to the cover art of a music track should be changed. Not obvious what it's even talking about from the user perspective.

- [8-21-2026] Fullscreen "Playing from a mix" off center.

- [8-21-2026] Playing a music track from the homescreen should automatically start a mix or similar. Currently only play that singular track and stops. If fact, we should favor continuous listening in most cases. Maybe having the ability to turn off kind of like youtube music / apple music do with a simple toggle (that the client remembers).

- [8-21-2026] I don't think radio listening time is counted in listening stats. 

- [8-18-2026] when you change a track and then go back it keeps playing from the spot that you were at. It should restart? We shouldn't be remembering positions of old tracks? at most we remember the position of the last track that was playing so users can continue if they needed to stop. This actually occurs both ways forward and backward.

- [8-18-2026] [web] music track changes repaint the entire screen when in fullscreen.

- [8-18-2026] when in full screen and listening to a playlist or anything with a queue, the upcoming song's artist name is on the far right. it should be next to the song name on the left. we can keep the number of items remaining on the right.

- [8-18-2026] when using the instant mix button, while listening to a song, it changes songs to the new mix instead of adding songs to your queue. should keep playing the song your listening to.

- [8-18-2026] Radio page -> hit search button top right -> hit back button -> goes to home page and not back to the radio page. Need to add back awareness or page history.

- [8-18-2026] Radio has a hickup in audio in the first couple of seconds of each song? !!! After furth investigating its not every song. However, it does happen occasionally. Need to check if this is on our end or from the radio stations / network issues that we can't control.

- [8-17-2026] Maybe we should gray out the visualizer option if the file has not been analyzed yet. Can have a tooltip that states the reason for the grayout.

- [8-17-2026] [web at least] for the full screen visualizer, we should change the button in the top left to be changed from the downward arrow to the left arrow to indicate the "go back" action it actually takes.

- [8-17-2026] [web] Right click doesn't work at all for anything. Doesn't even show normal browser options. We might want to look into the other platforms to see if this is universal.

- [8-16-2026] Connect's routed transport verbs all go straight at the engine (`connect_controller.dart` around 264-276) instead of through `QueueGateway`, which exists for exactly this and which the media session does use. `play` bypasses `QueueGateway.play` and so cannot restart a queue whose start failed - the case that method was written for. `stop` runs `queue.clear(); await engine.stop();` and `pause` runs `engine.pause()`, neither of which lets go of a tuned station, so a routed stop during live radio leaves the face and the deck bar still naming a station nothing is playing. The lock-screen half of that is fixed (`onStop` lands on `QueueGateway.stop`); Connect is not, because a routed verb is a Connect-semantics decision alongside the three entries at the bottom of this file. Note the fix is not a straight substitution: `QueueGateway.stop` deliberately leaves the queue standing, so the routed stop needs both it and the existing `clear`, in the order the surrounding comment requires.

- [8-8-2026] The Edit station dialog may drop its save: filled a new stream URL and name, clicked "Save changes", the dialog closed, and the server still had the old values (the same edit through PUT /radio/stations/{pid} landed fine). Seen once under Playwright-driven text entry, so it could be an automation artifact rather than the dialog - needs a manual check before trusting it.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
