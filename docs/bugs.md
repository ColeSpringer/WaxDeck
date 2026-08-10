# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add it not overly clear.

- [8-9-2026] I dont think the android app respects system theme. I believe it defaults to light mode.

- [8-9-2026] Android app has a large forheard.

- [8-8-2026] I cant figure out how to actually get to the matadata editor (web). Need to work on some of the inuitiveness of the UI/UX

- [8-8-2026] The review queue can be crowded (see screenshot) and there is no way to resize. Having resize capabilites might be hard to do given the mobile constraints but I dont think there is any reason to give the pending queue as much room or more as the file you clicked on.

- [8-8-2026] When playing a track, selected from under the tracks section, hitting the "next" button doesnt do anything. 

- [8-8-2026] Uploaded music seems to only add to the tracks section? The tracks all have an artist, album, genere, and year in their file but dont show under the sections? **Diagnosed, and it is not the upload path.** An as-is import and an identified one go through the same `importEntryFiles`, and a test now pins that an as-is upload of a file tagged ARTIST/ALBUMARTIST/ALBUM/GENRE lands in all four browse dimensions with no decision and no rescan (`TestDeclinedImportLinksItsEntities`). The one dimension that did not pick the file up is `year` - and a *scanned* file carrying the same `DATE` tag lands in `[Unknown Year]` as well, so that half is about which tag key a year is read from, on both paths, and is the only part of this entry still open. What remains to reproduce is the original report itself: which sections were empty, for which files, and whether the library had been rescanned since. Without that, there is nothing left here to fix on the upload side.

- [8-8-2026] We should also have the addition button in the music section. Currently, its the only section that does not have it. Can be kind of like the home add surface but more music specific?

- [8-8-2026] (Web) We can make the cover art a little bigger. Little small and there is plenty of dead space.

- [8-8-2026] Uploads only accept file selections. Not useful when trying to upload albums or entire music collections. Also need to make sure that the upload surface is up to standard security practices.

- [8-8-2026] There are some alignment issues that you can see under bug_screenshots. 

- [8-8-2026] Under listening stats, when you select the time period to take into account, there is a noticable visual change. It looks like its redrawing the elements. This might not be fixable and I guess it's not really a bug. However, I think it would be worth making it a less jarring transition if we can.

- [8-8-2026] Under curation, the review queue and admin console bring you to the same page (just to their respective section). The admin console is a pretty accurate name we can continue to use. On a related note, does it make sense to have this under curation along with uploads and review queue? The admin console has a lot of reponsbility outside of curation. So we either need to rename curation or bring out the admin console. My thought right now might be to remove the uploads section under curation as there are already ways to upload files in home with the addition button on the top right. Then we can have a dedicated notifcation tab and admin console. (consider also renaming "settings" to "App Settings" or something similar). Then we can have the admin console only be visible to admins.

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

- [8-8-2026] A client-side filter over a paged list silently stops at page one. The paged screens load their next page from a scroll listener (`if (position.pixels < position.maxScrollExtent - 600) return;`), so a first page that does not overflow the viewport produces no scroll event and never pages. That is unreachable while a screen draws everything it loaded - fifty rows always overflow - but three screens narrow the accumulated pages in the client before drawing them, and a narrow enough filter leaves a short list that cannot scroll: the books hub's finished/unfinished/author filters (`arrangeBooks` over `loaded`), the search-within-show field on a podcast (`_query`, "matched against the pages already loaded"), and the health screen's rule listing. The show search is the worst of the three because it reads as an answer rather than as a filter: type a term matching two of the fifty loaded episodes and the screen says two, with no indication that pages three onward were never asked for. Fixing it means giving those screens a paging trigger that does not depend on the viewport overflowing - a post-layout check for "nothing to scroll and more to fetch", or filtering server-side where the wire supports it. Found during phase 3 review; the pattern predates it and the saved-radio list shares the trigger but not the hazard, having no client-side filter.

- [8-7-2026] if you hit the stop button for a radio station in full screen it then displays a "nothing is playing" screen. maybe we should default to when hitting that button it minimizes to the deck since, for radio specifically, there is nothing for the user to do once you disconnect from the station.

- [8-7-2026] The artwork retrieved sometimes seems like its low resolution for radio cover art. This might be due to source resolution so may not be fixable.

- [8-7-2026] The artwork for radio cover art sometimes disappears during the song (including the song info artist and title which is probably related to the disappearance). This seems to mostly happen towards the end when there is about 30 seconds to a minute left.

- [8-7-2026] Maybe we should make the fullscreen cover art appearance for radio dynamic (maybe the others too?) to the art it wants to display? currently its circular which results in album artwork being cutoff. I guess circular would be ok for radio station logos or the default artwork we use.

- [8-7-2026] radio station artwork just retrieves from top of list which results in sometimes displaying compilation albums. we should prioritize the album version, then the single version, then whatever version(s) are left.

- [8-1-2026] Casting a fresh session from the device picker while local audio plays stops nothing locally: the picker creates the remote session without ending local playback, and the deck bar's precedence keeps the local face over the remote one (device_picker.dart around 313-356, precedence in deck_bar_host.dart around 80-91). Needs ADR-0008's transfer semantics before deciding what "start there" should do to the local engine.

- [8-1-2026] Casting while radio plays transfers a dead item session: mirrorSessionId never clears when radio takes the engine, so the picker (reachable via the settings screen during radio) offers a transfer of a session whose queue the engine no longer plays (connect_controller.dart around 91-99). Same ADR-0008 dependency.

- [8-1-2026] A routed set-rate from another device is silently reset at every gapless boundary: adopt() re-applies the locally configured speed, overwriting the rate the remote controller set (playback_session.dart adopt path). Whether the routed rate should persist across boundaries is a Connect-semantics decision.
