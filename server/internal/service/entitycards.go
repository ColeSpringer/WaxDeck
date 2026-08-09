package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"
)

// This file answers the one question a client holding a bare list of
// entity pids has: what do I draw for these? A pinned shelf stores pids
// (Prefs.pinned) because a pin is a handle and not a snapshot, so
// something has to turn the handles back into cards.
//
// Six prefixes, four read paths, one ordered answer. The mixing is the
// point: a shelf holding an album, a show, and a book is one shelf, and
// making the client fan out to three endpoints and reassemble the order
// would put the contract's ordering promise in the least reliable place.

// EntityCard is the display facts behind one entity pid.
//
// No artwork field: /items/{pid}/art already takes every prefix here
// except rg-, which statically has none, so a client builds the URL from
// the pid it already holds.
type EntityCard struct {
	PID   string
	Kind  string
	Title string
	// Artist is the context line - an album's or book's artist, a show's
	// author. Empty for an artist, whose title is the name.
	Artist string
	Year   int
	// ItemCount is a pointer because absent and zero differ: a smart
	// playlist's count is deliberately not taken (evaluating every stored
	// rule to draw a card is the work the listing path skips too), and a
	// card showing "0 tracks" for it would be a lie rather than a gap.
	ItemCount *int
}

// maxEntityCards bounds one request, matching the contract's maxItems and
// Prefs.pinned's own cap: the list this resolves is exactly that list.
const maxEntityCards = 64

// entityCardKind maps an API prefix to the card's kind, which is what a
// tap opens.
var entityCardKind = map[string]string{
	PrefixAlbum:        "album",
	PrefixArtist:       "artist",
	PrefixReleaseGroup: "release-group",
	PrefixPlaylist:     "playlist",
	PrefixPodcast:      "podcast",
	PrefixBook:         "book",
}

// EntityCards resolves a mixed list of entity pids to the facts a card
// draws, in request order, and names the pids that are gone for good.
//
// Anything that cannot be answered for is dropped rather than erroring:
// unknown, deleted, merged away, unsubscribed, or outside the caller's
// grant all leave the list one card shorter. That is the same display-drop
// the radio dial does with a departed station, and it is what lets
// Prefs.pinned hold a pid nothing resolves without a preference write
// failing over it.
//
// The second return is the departed subset of the misses: pids that no
// longer name anything on this server, for anyone. A pid that exists
// and is merely out of the caller's sight - a grant that could be
// widened, a show they could resubscribe to, a book in the trash - is
// omitted from the cards and NOT listed departed, because what is
// gone-for-you-today may be back tomorrow and a client that pruned it
// would have turned a temporary state into a permanent loss. Departed
// is the signal a pinned list prunes on (ADR-0054's consequence).
func (l *Library) EntityCards(ctx context.Context, uc *UserCtx, apiPIDs []string) ([]EntityCard, []string, error) {
	if len(apiPIDs) > maxEntityCards {
		return nil, nil, errInvalid(fmt.Sprintf("at most %d pids", maxEntityCards))
	}
	// Grouped by prefix so each kind is read in one batch, then rebuilt
	// positionally. A duplicate pid answers once per occurrence, which is
	// what makes the response index-alignable with the request.
	//
	// Canonicalized first, which is load-bearing rather than tidy: the
	// catalog keys its batch answer by the *stored* pid, so a lower-case
	// ULID (which Crockford base32 parses happily, and which the
	// contract's own pattern forbids) would be read successfully and then
	// silently fail to match on the way out - one card missing from a
	// shelf with nothing to say why. Prefs.pinned is stored upper-case
	// for the same reason.
	canonical := make([]string, 0, len(apiPIDs))
	byPrefix := map[string][]model.PID{}
	for _, api := range apiPIDs {
		prefix, pid, ok := parseAPIPID(api)
		if !ok || entityCardKind[prefix] == "" {
			return nil, nil, errInvalid("not a pinnable entity pid: " + api)
		}
		pid = model.PID(strings.ToUpper(string(pid)))
		canonical = append(canonical, apiPID(prefix, pid))
		byPrefix[prefix] = append(byPrefix[prefix], pid)
	}

	cards := map[string]EntityCard{}
	gone := map[string]bool{}
	for prefix, pids := range byPrefix {
		var (
			got map[string]EntityCard
			dep map[string]bool
			err error
		)
		switch prefix {
		case PrefixAlbum, PrefixArtist, PrefixReleaseGroup:
			got, dep, err = l.entityKindCards(ctx, uc, prefix, pids)
		case PrefixPlaylist:
			got, dep, err = l.playlistCards(ctx, uc, pids)
		case PrefixPodcast:
			got, dep, err = l.showCards(ctx, uc, pids)
		case PrefixBook:
			got, dep, err = l.bookCards(ctx, uc, pids)
		}
		if err != nil {
			return nil, nil, err
		}
		for pid, card := range got {
			cards[pid] = card
		}
		for pid := range dep {
			gone[pid] = true
		}
	}

	out := make([]EntityCard, 0, len(canonical))
	// Departed pids ride in request order, a repeated pid once: it is a
	// set of handles to prune, not a positional answer.
	departed := make([]string, 0, len(gone))
	listed := map[string]bool{}
	for _, api := range canonical {
		if card, ok := cards[api]; ok {
			out = append(out, card)
		}
		if gone[api] && !listed[api] {
			listed[api] = true
			departed = append(departed, api)
		}
	}
	return out, departed, nil
}

// entityKindCards resolves the three catalog-entity kinds through
// EntityByPIDs, which is also the visibility gate for a restricted
// caller: an entity whose every member sits outside the grant is dropped
// rather than handed out as a pid the tap cannot follow.
//
// Departed here is a pid the batch read did not answer at all: deleted,
// merged away, or never real, which the catalog collapses into absence
// (EntityByPIDs omits unknown pids rather than erroring). An entity the
// read DID answer but the grant hides is out of the cards and out of
// departed both - it exists, and a widened grant brings it back.
func (l *Library) entityKindCards(ctx context.Context, uc *UserCtx, prefix string, pids []model.PID) (map[string]EntityCard, map[string]bool, error) {
	kind, ok := entityKindForPrefix(prefix)
	if !ok {
		return nil, nil, errInvalid("no entity kind for prefix " + prefix)
	}
	infos, err := l.lib.EntityByPIDs(ctx, kind, pids)
	if err != nil {
		return nil, nil, classify(err)
	}
	departed := map[string]bool{}
	for _, pid := range pids {
		if info, ok := infos[pid]; !ok || info == nil {
			departed[apiPID(prefix, pid)] = true
		}
	}
	out := make(map[string]EntityCard, len(infos))
	// Album and release-group cards want an artist line the entity does
	// not carry: an album links to its release group and a release group
	// to its artist, so the names come from one hop or two, each batched.
	names := l.entityArtistNames(ctx, prefix, infos)
	for pid, info := range infos {
		if info == nil {
			continue
		}
		if !uc.AllLibraries && !l.entityInLibraries(info, uc) {
			continue
		}
		card := EntityCard{
			PID:    apiPID(prefix, pid),
			Kind:   entityCardKind[prefix],
			Title:  info.Name,
			Year:   info.Year,
			Artist: names[pid],
		}
		// Catalog-wide, because EntityByPIDs takes no library scope, so
		// the count is answered only to a caller it is true for. A card
		// advertising nine tracks that opens onto three would be worse
		// than a card with no count on it, and the contract says absent
		// is legal.
		if uc.AllLibraries {
			count := info.ItemCount
			card.ItemCount = &count
		}
		out[card.PID] = card
	}
	return out, departed, nil
}

// entityArtistNames resolves the artist line for album and release-group
// cards, in at most two batched hops. An artist card needs none (its
// title is the name), and a failed hop leaves the line empty rather than
// failing the whole read: a card with no artist under it still opens the
// right screen, and a shelf is not worth an error page.
func (l *Library) entityArtistNames(ctx context.Context, prefix string, infos map[model.PID]*read.EntityInfo) map[model.PID]string {
	if prefix != PrefixAlbum && prefix != PrefixReleaseGroup {
		return nil
	}
	// An album's own artist link is empty (the schema hangs it off the
	// release group), so albums hop through their groups first.
	groups := map[model.PID]model.PID{}
	if prefix == PrefixAlbum {
		rgPIDs := make([]model.PID, 0, len(infos))
		for pid, info := range infos {
			if info == nil || info.ReleaseGroupPID == "" {
				continue
			}
			groups[pid] = info.ReleaseGroupPID
			rgPIDs = append(rgPIDs, info.ReleaseGroupPID)
		}
		if len(rgPIDs) == 0 {
			return nil
		}
		rgs, err := l.lib.EntityByPIDs(ctx, read.EntityReleaseGroup, rgPIDs)
		if err != nil {
			l.log.Warn("resolving album release groups for cards", "err", err)
			return nil
		}
		infos = rgs
	}

	artistOf := map[model.PID]model.PID{}
	artistPIDs := make([]model.PID, 0, len(infos))
	for pid, info := range infos {
		if info == nil || info.ArtistPID == "" {
			continue
		}
		artistOf[pid] = info.ArtistPID
		artistPIDs = append(artistPIDs, info.ArtistPID)
	}
	if len(artistPIDs) == 0 {
		return nil
	}
	artists, err := l.lib.EntityByPIDs(ctx, read.EntityArtist, artistPIDs)
	if err != nil {
		l.log.Warn("resolving artists for cards", "err", err)
		return nil
	}
	byGroup := make(map[model.PID]string, len(artistOf))
	for pid, artistPID := range artistOf {
		if info := artists[artistPID]; info != nil {
			byGroup[pid] = info.Name
		}
	}
	if prefix == PrefixReleaseGroup {
		return byGroup
	}
	out := make(map[model.PID]string, len(groups))
	for albumPID, rgPID := range groups {
		if name := byGroup[rgPID]; name != "" {
			out[albumPID] = name
		}
	}
	return out
}

// playlistCards resolves playlists one at a time - the catalog has no
// batch read for them and the list is capped at 64 - through the same
// visibility rule the listing uses: yours, or shared.
//
// The catalog read and the visibility rule are applied separately here
// rather than through resolvePlaylist, because they answer differently:
// a playlist the catalog has no row for is departed, while one that
// exists and is somebody else's private list is only invisible - the
// owner sharing it again brings the card back, and pruning the pin
// meanwhile would make that a loss.
func (l *Library) playlistCards(ctx context.Context, uc *UserCtx, pids []model.PID) (map[string]EntityCard, map[string]bool, error) {
	out := make(map[string]EntityCard, len(pids))
	departed := map[string]bool{}
	for _, pid := range pids {
		api := apiPID(PrefixPlaylist, pid)
		pl, err := l.lib.Playlists().Get(ctx, pid)
		if err != nil {
			if KindOf(classify(err)) == KindNotFound {
				departed[api] = true
				continue
			}
			return nil, nil, classify(err)
		}
		if string(pl.OwnerPID) != uc.CatalogPID && pl.Visibility != model.VisibilityShared {
			continue
		}
		// The listing row's count, not the opened playlist's: cached for a
		// static list and deliberately absent for a smart one, which is the
		// same trade a grid of tiles makes.
		dto := l.playlistDTO(ctx, uc, pl, false)
		out[api] = EntityCard{
			PID:       api,
			Kind:      entityCardKind[PrefixPlaylist],
			Title:     dto.Name,
			Artist:    dto.OwnerName,
			ItemCount: dto.ItemCount,
		}
	}
	return out, departed, nil
}

// showCards resolves podcast shows, scoped to the caller's subscriptions
// the way every other show surface is: an unsubscribed show is not on
// this listener's shelf, and unsubscribing is how a pinned show leaves.
//
// An unsubscribed show is invisible, never departed: the show still
// exists, resubscribing brings the card back, and the show's own screen
// keeps its unpin row for exactly this state. Departed is a subscribed
// show the server no longer has - the one absence resubscribing cannot
// mend.
func (l *Library) showCards(ctx context.Context, uc *UserCtx, pids []model.PID) (map[string]EntityCard, map[string]bool, error) {
	subs, err := l.subscribedShowSet(ctx, uc)
	if err != nil {
		return nil, nil, err
	}
	out := make(map[string]EntityCard, len(pids))
	departed := map[string]bool{}
	for _, pid := range pids {
		if !subs[string(pid)] {
			continue
		}
		api := apiPID(PrefixPodcast, pid)
		pod, err := l.getShow(ctx, api)
		if err != nil {
			if KindOf(err) == KindNotFound {
				departed[api] = true
				continue
			}
			return nil, nil, err
		}
		out[api] = EntityCard{
			PID:    api,
			Kind:   entityCardKind[PrefixPodcast],
			Title:  pod.Title,
			Artist: pod.Author,
		}
	}
	return out, departed, nil
}

// bookCards resolves books, which are items rather than entities: the
// same per-item visibility and content rules every other item read
// applies, and a book that fails either is dropped.
//
// Departed is a book the catalog itself cannot find. One that exists
// and is out of the caller's sight - a grant, a content rule, the
// trash a restore could empty - is dropped without being departed,
// because each of those states can end with the book back.
func (l *Library) bookCards(ctx context.Context, uc *UserCtx, pids []model.PID) (map[string]EntityCard, map[string]bool, error) {
	out := make(map[string]EntityCard, len(pids))
	departed := map[string]bool{}
	for _, pid := range pids {
		api := apiPID(PrefixBook, pid)
		it, err := l.getItem(ctx, api)
		if err != nil {
			if KindOf(err) == KindNotFound {
				departed[api] = true
				continue
			}
			return nil, nil, err
		}
		if !l.itemVisible(ctx, uc, it.PID) || !l.allowedByContent(ctx, uc, it) {
			continue
		}
		out[api] = EntityCard{
			PID:    api,
			Kind:   entityCardKind[PrefixBook],
			Title:  it.Title,
			Artist: it.Artist,
			Year:   it.Year,
		}
	}
	return out, departed, nil
}
