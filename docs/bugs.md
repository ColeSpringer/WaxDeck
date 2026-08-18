# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [8-18-2026] when you change a track and then go back it keeps playing from the spot that you were at. It should restart? We shouldn't be remembering positions of old tracks? at most we remember the position of the last track that was playing so users can continue if they needed to stop.

- [8-18-2026] [web] music track changes repaint the entire screen when in fullscreen.

- [8-18-2026] when in full screen and listening to a playlist or anything with a queue, the upcoming song's artist name is on the far right. it should be next to the song name on the left. we can keep the number of items remaining on the right.

- [8-18-2026] when using the instant mix button, while listening to a song, it changes songs to the new mix instead of adding songs to your queue. should keep playing the song your listening to.

- [8-18-2026] Radio page -> hit search button top right -> hit back button -> goes to home page and not back to the radio page. Need to add back awareness or page history.

- [8-18-2026] Radio has a hickup in audio in the first couple of seconds of each song? !!! After furth investigating its not every song. However, it does happen occasionally. Need to check if this is on our end or from the radio stations / network issues that we can't control.

- [8-17-2026] [web] We have nothing that shows when you mouse over cover art. Maybe add a play button (transparent? not overly intrusive) when mousing over playable artwork?  

- [8-17-2026] Maybe we should gray out the visualizer option if the file has not been analyzed yet. Can have a tooltip that states the reason for the grayout.

- [8-17-2026] [web at least] for the full screen visualizer, we should change the button in the top left to be changed from the downward arrow to the left arrow to indicate the "go back" action it actually takes.

- [8-17-2026] I don't think we have a way to edit metadata for individual tracks.

- [8-17-2026] the editing album metadata screen is worthless. needs an overhaul.

- [8-17-2026] [web] Right click doesn't work at all for anything. Doesn't even show normal browser options. We might want to look into the other platforms to see if this is universal.

- [8-17-2026] For radio, the artwork for the song should also show in the minimized deck. Not just when in fullscreen.

- [8-16-2026] Connect's routed transport verbs all go straight at the engine (`connect_controller.dart` around 264-276) instead of through `QueueGateway`, which exists for exactly this and which the media session does use. `play` bypasses `QueueGateway.play` and so cannot restart a queue whose start failed - the case that method was written for. `stop` runs `queue.clear(); await engine.stop();` and `pause` runs `engine.pause()`, neither of which lets go of a tuned station, so a routed stop during live radio leaves the face and the deck bar still naming a station nothing is playing. The lock-screen half of that is fixed (`onStop` lands on `QueueGateway.stop`); Connect is not, because a routed verb is a Connect-semantics decision alongside the three entries at the bottom of this file. Note the fix is not a straight substitution: `QueueGateway.stop` deliberately leaves the queue standing, so the routed stop needs both it and the existing `clear`, in the order the surrounding comment requires.

- [8-9-2026] I dont think the android app respects system theme. I believe it defaults to light mode.

- [8-9-2026] Android app has a large forheard.

- [8-8-2026] I cant figure out how to actually get to the matadata editor (web). Need to work on some of the inuitiveness of the UI/UX

- [8-8-2026] The review queue can be crowded (see screenshot) and there is no way to resize. Having resize capabilites might be hard to do given the mobile constraints but I dont think there is any reason to give the pending queue as much room or more as the file you clicked on.

- [8-8-2026] Uploaded music seems to only add to the tracks section? The tracks all have an artist, album, genere, and year in their file but dont show under the sections? **Diagnosed, and it is not the upload path.** An as-is import and an identified one go through the same `importEntryFiles`, and a test now pins that an as-is upload of a file tagged ARTIST/ALBUMARTIST/ALBUM/GENRE lands in all four browse dimensions with no decision and no rescan (`TestDeclinedImportLinksItsEntities`). The one dimension that did not pick the file up is `year` - and a *scanned* file carrying the same `DATE` tag lands in `[Unknown Year]` as well, so that half is about which tag key a year is read from, on both paths, and is the only part of this entry still open. What remains to reproduce is the original report itself: which sections were empty, for which files, and whether the library had been rescanned since. Without that, there is nothing left here to fix on the upload side.

- [8-8-2026] We should also have the addition button in the music section. Currently, its the only section that does not have it. Can be kind of like the home add surface but more music specific?

- [8-8-2026] Uploads only accept file selections. Not useful when trying to upload albums or entire music collections. Also need to make sure that the upload surface is up to standard security practices.

- [8-8-2026] Under listening stats, when you select the time period to take into account, there is a noticable visual change. It looks like its redrawing the elements. This might not be fixable and I guess it's not really a bug. However, I think it would be worth making it a less jarring transition if we can.

- [8-8-2026] I believe we implemented the ability to search for podcasts by name to add but it doesnt show in the UI.

- [8-8-2026] A `WaxTextField` still shows no label unless its caller asks for
  one, and 35 of the 38 do not. The component treats `label` as the accessible
  name alone and paints only `hint`, which Material removes on the first
  keystroke, so any field seeded from the server reads as a box with a value in
  it. `showLabel` now draws the label above the box, and the three transcoding
  limits - the case that found this, three identical boxes reading "0" on the
  screen where mixing up server-wide and per-listener throttles everybody - use
  it. What is left is the decision the flag deliberately does not take: whether
  drawing the label should be the default. It should probably be opt-out rather
  than opt-in, since the component's own doc says a field with a visible label
  passes the same string, but flipping it changes the height of 35 fields at
  once and moves goldens with them, so it wants doing on purpose. Two smaller
  things to fold in when it is: `WaxTextField` has no helper-text slot, which
  is why Backups' retention pair is still raw Material `TextField`s with
  `InputDecoration(labelText:, helperText:)` - so the two admin screens draw a
  labelled field two different ways; and a hint on a pre-filled field is dead
  weight either way.

- [8-8-2026] The item editor offers Save to callers who cannot save. `/metadata/:pid` is inside the signed-in shell with no gate, and `GET /items/{pid}/metadata` answers anyone who can see the item, so any signed-in user reaches the full editable form; `EditItemMetadata` then refuses with 403 unless the caller is an administrator or the person whose upload brought the item in. A blanket admin gate is the wrong fix and would break the case the permission exists for - an uploader curating their own upload - and the client has no way to tell the two apart, because the metadata read carries no "may I curate this" signal. So the fix is a field on the read rather than a check on the screen. (The album half of the same route is unaffected: `editEntity` is strictly administrators, which is a question the client can already answer, and `AlbumEditorScreen` refuses on the screen rather than only on the menu row that opens it - the location is shareable and the web build puts it in the path.)

- [8-8-2026] The station dial with exactly one pinned station reads as a broken artifact: a full-width empty tick ruler, a single floating logo, and the needle drawn through it, with nothing communicating "these are your pinned stations" or that the band scrolls. The component is built for a handful of pins (capped at 12) and degenerates below two or three. The first pin is also easy to make without noticing (the star on the fullscreen player), so the band appears out of nowhere on the next hub visit and looks like a rendering bug rather than a feature. Wants a designed single-pin state, or holding the band back until it has enough pins to read as a dial.

- [8-8-2026] The Edit station dialog may drop its save: filled a new stream URL and name, clicked "Save changes", the dialog closed, and the server still had the old values (the same edit through PUT /radio/stations/{pid} landed fine). Seen once under Playwright-driven text entry, so it could be an automation artifact rather than the dialog - needs a manual check before trusting it.

- [8-8-2026] clicking the search bar in the top left (web) brings you to the search page immediately. this shouldnt move you until you hit search/enter.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs Connect's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same Connect-semantics dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
