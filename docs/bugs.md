# Bugs

List of current bugs or correctness issues.

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

- [8-8-2026] Content rules are applied per item and never in an aggregation, so any bucket count can read higher than the list it opens - and a card built from one can open onto nothing. `allowedByContent` reads an item's tags and matches them against the caller's allow/deny rules in Go, one item at a time, which is why `listItems` filters correctly and `facetBuckets` does not: the facet query carries the state predicate and the library scope and nothing about tag rules. A listener with a deny rule sees the browse index count releases they cannot open, and as of the "Appears on" change now gets a card for one too - that shelf used to page `listItems`, which applied the rules, and reads album buckets since. (The `kind` dimension has the same shape for episodes, whose subscription scoping is also per-item; the music dimensions exclude episodes so only `kind` is affected there.) No upstream work: the rules are WaxDeck's own, stored in `users.tag_rules` and evaluated in `perms.go`, and the query builder already has the `tag.<KEY>` fields a predicate would compile to - `applyFacetFilter` uses them for custom tag dimensions. The fix is to compile allow/deny into the facet scope query, with two hazards worth naming before starting: `tagRuleMatches` folds case (`EqualFold`) where SQL comparison would not, and a deny rule over a set-valued tag field needs the field's own `isNot` semantics rather than a plain negation. Doing it there would also let `listItems` stop filtering in Go, which is where the two currently disagree.

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
