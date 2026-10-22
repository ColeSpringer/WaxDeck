package service

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Public share links. A share row names a target the owner could see
// at creation; the capability token derives from the row id with the
// server key (auth.ShareTokens), so nothing secret is stored and the
// owner's listing recomputes URLs at read time. The public page and
// its media fetches resolve through ResolveShare, which re-checks
// lifetime and revocation on every hit.

// ShareInfo is one share link, owner-facing.
type ShareInfo struct {
	ID            string // sh-... API pid; the bare id keys the token
	OwnerID       string
	OwnerName     string // display name; only the all-shares listing fills it
	TargetPID     string // API pid
	TargetKind    string // track | playlist | book | episode | album
	TargetTitle   string
	AllowDownload bool
	PositionMs    int64
	CreatedAt     time.Time
	ExpiresAt     time.Time // zero = never
	Plays         int
}

// SharePageResult is one page of the listing.
type SharePageResult struct {
	Shares []ShareInfo
	Next   string
}

// SharePublic is a share resolved for anonymous serving: the target
// items in play order plus display fields for the landing page.
type SharePublic struct {
	Share       ShareInfo
	Title       string
	Subtitle    string
	Items       []ItemSummary // members the owner reaches, play order
	ArtItemPID  string        // API pid whose artwork represents the page
	OwnerUserID string        // billing identity for transcode gating
	// Audio says how each member plays, by member pid. A member it does
	// not name plays no way at all.
	Audio map[string]ShareAudio
}

// ShareAudio is how one member of a share plays for its visitors.
type ShareAudio string

const (
	// ShareAudioLocal is a file on this server.
	ShareAudioLocal ShareAudio = "local"
	// ShareAudioRelay is an episode the server has not fetched whose
	// feed names audio the enclosure relay serves.
	ShareAudioRelay ShareAudio = "relay"
)

// Plays reports whether a visitor can hear the member, which the zero
// value of a member the share does not name cannot.
func (a ShareAudio) Plays() bool { return a == ShareAudioLocal || a == ShareAudioRelay }

// shareKindForPrefix maps a target prefix onto the stored kind.
var shareKindForPrefix = map[string]string{
	PrefixTrack:    "track",
	PrefixPlaylist: "playlist",
	PrefixBook:     "book",
	PrefixEpisode:  "episode",
	PrefixAlbum:    "album",
}

// CreateShare validates a target and records a share link.
func (l *Library) CreateShare(ctx context.Context, uc *UserCtx, targetAPIPID string, expiresIn time.Duration, allowDownload bool, positionMs int64) (ShareInfo, error) {
	prefix, _, ok := parseAPIPID(targetAPIPID)
	if !ok {
		return ShareInfo{}, errInvalid("malformed pid")
	}
	kind, ok := shareKindForPrefix[prefix]
	if !ok {
		return ShareInfo{}, errInvalid("only tracks, albums, playlists, books, and episodes can be shared")
	}
	// Either prefix reaches a track or a book; the link records what the
	// item is now, under the pid every answer carries.
	if kind == "track" || kind == "book" {
		it, err := l.getVisibleItem(ctx, uc, targetAPIPID)
		if err != nil {
			return ShareInfo{}, err
		}
		switch it.Kind {
		case model.KindTrack:
			kind = "track"
		case model.KindBook:
			kind = "book"
		}
		targetAPIPID = itemAPIPID(it)
	}
	if positionMs != 0 && kind != "episode" {
		return ShareInfo{}, errInvalid("positionMs is for episode shares")
	}
	if positionMs < 0 {
		return ShareInfo{}, errInvalid("positionMs must not be negative")
	}
	if allowDownload && !uc.Download {
		return ShareInfo{}, &Error{Kind: KindForbidden,
			Msg: "sharing with download needs your own download permission"}
	}
	title, err := l.shareTargetTitle(ctx, uc, kind, targetAPIPID)
	if err != nil {
		return ShareInfo{}, err
	}
	row := wdb.Share{
		ID:            ulid.Make().String(),
		UserID:        uc.ID,
		TargetPID:     targetAPIPID,
		TargetKind:    kind,
		AllowDownload: allowDownload,
		PositionMs:    positionMs,
		CreatedAt:     time.Now().UTC(),
	}
	if expiresIn > 0 {
		row.ExpiresAt = row.CreatedAt.Add(expiresIn)
	}
	if err := l.db.InsertShare(ctx, row); err != nil {
		return ShareInfo{}, &Error{Kind: KindInternal, Err: err}
	}
	info := shareInfo(row)
	info.TargetTitle = title
	// A link serves whatever its owner can reach when it is opened, so
	// this entry is the one record of what it published.
	detail := map[string]any{"targetPid": targetAPIPID, "targetKind": kind, "allowDownload": allowDownload}
	if !row.ExpiresAt.IsZero() {
		detail["expiresAt"] = row.ExpiresAt.Format(time.RFC3339)
	}
	l.Audit(ctx, uc, "share.create", AuditTarget{Kind: "share", PID: info.ID, Name: title}, detail)
	return info, nil
}

// shareTargetTitle verifies the caller can see the target and answers
// its display title. Episodes of private feeds refuse: a capability
// URL must never leak paid content.
func (l *Library) shareTargetTitle(ctx context.Context, uc *UserCtx, kind, targetAPIPID string) (string, error) {
	switch kind {
	case "playlist":
		pl, err := l.PlaylistByPID(ctx, uc, targetAPIPID)
		if err != nil {
			return "", err
		}
		// Ownership, not mere visibility: the public page serves what
		// the owner can currently see of the list for the link's whole
		// life, with the capability URL as the authorization. Another
		// user's shared playlist is theirs to publish; letting a viewer
		// mint a link for it would keep serving it even after the owner
		// flips it private, through a link the owner cannot revoke.
		if !pl.IsOwner {
			return "", &Error{Kind: KindForbidden,
				Msg: "only your own playlists can be shared publicly"}
		}
		return pl.Name, nil
	case "episode":
		it, err := l.getVisibleItem(ctx, uc, targetAPIPID)
		if err != nil {
			return "", err
		}
		det, err := l.getEpisode(ctx, targetAPIPID)
		if err != nil {
			return "", err
		}
		// Fails closed, as resolving the link does: a show that cannot be
		// read cannot be shown not to be private.
		show, err := l.getShow(ctx, apiPID(PrefixPodcast, det.Episode.PodcastPID))
		if err != nil {
			return "", err
		}
		if l.showIsPrivate(ctx, show) {
			return "", &Error{Kind: KindForbidden,
				Msg: "episodes of private feeds cannot be shared"}
		}
		// A link nobody could hear through is not minted. One whose
		// episode later loses its audio (retention reclaims a YouTube
		// fetch, a feed drops the enclosure) says so on its page.
		if unfetchedEpisode(it) && !relayableEnclosure(show.SourceType, det.Episode.EnclosureURL, det.Episode.EnclosureType) {
			return "", &Error{Kind: KindConflict,
				Msg: "this episode has no audio on the server and its feed names none to relay; fetch it first"}
		}
		return clipFeedTitle(it.Title), nil
	case "album":
		_, pid, _ := parseAPIPID(targetAPIPID)
		info, err := l.lib.EntityByPID(ctx, read.EntityAlbum, pid)
		if err != nil {
			return "", classify(err)
		}
		// An owner can only share an album they can hear some of: one of
		// its tracks has to pass their library grants and content rules.
		if ok, err := l.entityVisible(ctx, uc, PrefixAlbum, pid); err != nil {
			return "", err
		} else if !ok {
			return "", errNotFound("no album with pid " + targetAPIPID)
		}
		return info.Name, nil
	default:
		it, err := l.getVisibleItem(ctx, uc, targetAPIPID)
		if err != nil {
			return "", err
		}
		return it.Title, nil
	}
}

// Shares pages the caller's share links (or everyone's for admins).
func (l *Library) Shares(ctx context.Context, uc *UserCtx, all bool, cursor string, limit int) (SharePageResult, error) {
	if all && !uc.Admin {
		return SharePageResult{}, &Error{Kind: KindForbidden, Msg: "listing all shares is administrative"}
	}
	beforeNS, beforeID, err := decodeShareCursor(cursor)
	if err != nil {
		return SharePageResult{}, errInvalid("malformed cursor")
	}
	userID := uc.ID
	if all {
		userID = ""
	}
	rows, err := l.db.Shares(ctx, userID, beforeNS, beforeID, limit+1)
	if err != nil {
		return SharePageResult{}, &Error{Kind: KindInternal, Err: err}
	}
	more := len(rows) > limit
	if more {
		rows = rows[:limit]
	}
	out := SharePageResult{Shares: make([]ShareInfo, 0, len(rows))}
	// Owners are named only on the oversight listing: on a caller's own
	// page every row is theirs, so the name would be noise. Memoized per
	// page because one account usually mints several links in a row.
	owners := map[string]string{}
	for _, r := range rows {
		info := shareInfo(r)
		// Titles resolve at read time so renames show through; a target
		// gone from the catalog reads as an empty title.
		if title, err := l.shareTitleLoose(ctx, r); err == nil {
			info.TargetTitle = title
		}
		if all {
			info.OwnerName = l.shareOwnerName(ctx, r.UserID, owners)
		}
		out.Shares = append(out.Shares, info)
	}
	if more {
		last := rows[len(rows)-1]
		out.Next = encodeShareCursor(last.CreatedAt.UnixNano(), last.ID)
	}
	return out, nil
}

// shareOwnerName resolves who minted a link, memoized across the page.
// An account that no longer exists answers empty rather than an error -
// the link is still revocable, which is what the listing is for - and
// the miss is memoized too, so a departed owner costs one read.
func (l *Library) shareOwnerName(ctx context.Context, userID string, memo map[string]string) string {
	if name, ok := memo[userID]; ok {
		return name
	}
	name := ""
	if u, err := l.db.UserByID(ctx, userID); err == nil && u != nil {
		name = u.DisplayName
		if name == "" {
			name = u.Username
		}
	}
	memo[userID] = name
	return name
}

// shareTitleLoose resolves a target title without a caller (listing
// and public rendering); missing targets answer empty, not an error.
func (l *Library) shareTitleLoose(ctx context.Context, r wdb.Share) (string, error) {
	_, pid, ok := parseAPIPID(r.TargetPID)
	if !ok {
		return "", nil
	}
	if r.TargetKind == "playlist" {
		pl, err := l.sharedPlaylist(ctx, pid)
		if err != nil {
			return "", nil
		}
		return pl.Name, nil
	}
	it, err := l.lib.Get(ctx, pid)
	if err != nil || (r.TargetKind == "track" && it.Kind != model.KindTrack) {
		return "", nil
	}
	title, _, _ := itemNames(it)
	return title, nil
}

// RevokeShare revokes one link; the owner or an administrator may.
func (l *Library) RevokeShare(ctx context.Context, uc *UserCtx, apiShareID string) error {
	prefix, id, ok := parseAPIPID(apiShareID)
	if !ok || prefix != PrefixShare {
		return errNotFound("no share with pid " + apiShareID)
	}
	row, err := l.db.ShareByID(ctx, string(id))
	if err == wdb.ErrNotFound {
		return errNotFound("no share with pid " + apiShareID)
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if row.Revoked {
		return errNotFound("no share with pid " + apiShareID)
	}
	if row.UserID != uc.ID && !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "only the owner or an administrator may revoke a share"}
	}
	if err := l.db.RevokeShare(ctx, string(id)); err != nil {
		if err == wdb.ErrNotFound {
			return errNotFound("no share with pid " + apiShareID)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	// An owner pulling their own link is routine; an administrator
	// pulling someone else's is oversight, and recorded.
	if row.UserID != uc.ID {
		l.Audit(ctx, uc, "share.revoke", AuditTarget{Kind: "share", PID: apiShareID},
			map[string]any{"ownerId": row.UserID, "targetPid": row.TargetPID})
	}
	return nil
}

// ResolveShare answers a live share for anonymous serving: not-found
// for unknown, revoked, or expired ids, and the target resolved to the
// members its owner can see now. The capability URL authorizes the
// visitor for what the owner published, never for more than the owner
// still reaches: a disabled owner's links, and a target the owner has
// lost to a grant or a content rule, answer not-found, and a list serves
// only the members left. Nothing is cached, so a revocation bites on the
// next hit. A catalog away for a hand-off answers maintenance rather
// than not-found, so a visitor's player retries instead of giving up.
func (l *Library) ResolveShare(ctx context.Context, shareID string) (*SharePublic, error) {
	row, err := l.liveShareRow(ctx, shareID)
	if err != nil {
		return nil, err
	}
	owner, err := l.userCtxByID(ctx, row.UserID)
	if err != nil {
		if KindOf(err) == KindNotFound {
			return nil, errNotFound("no such share")
		}
		return nil, err
	}
	pub := &SharePublic{Share: shareInfo(*row), OwnerUserID: row.UserID}
	_, pid, ok := parseAPIPID(row.TargetPID)
	if !ok {
		return nil, errNotFound("no such share")
	}
	// Creation-time checks that must hold for the share's whole life
	// re-run here, and they fail closed: a feed that gained
	// credentials after the link was minted must not keep leaking
	// paid content, and a check that cannot be evaluated (a failed
	// episode or show read) must not quietly wave the request
	// through either.
	var episode *model.Episode
	if row.TargetKind == "episode" {
		det, err := l.getEpisode(ctx, row.TargetPID)
		if err != nil {
			return nil, shareMiss(err)
		}
		show, err := l.getShow(ctx, apiPID(PrefixPodcast, det.Episode.PodcastPID))
		if err != nil {
			return nil, shareMiss(err)
		}
		if l.showIsPrivate(ctx, show) {
			return nil, errNotFound("no such share")
		}
		episode = det.Episode
	}
	// Downloads stop when the owner's own download permission is
	// withdrawn (the stream still serves, the download link does not).
	if !owner.Download {
		pub.Share.AllowDownload = false
	}
	var views []*model.ItemView
	switch row.TargetKind {
	case "playlist":
		pl, err := l.sharedPlaylist(ctx, pid)
		if err != nil {
			return nil, shareMiss(err)
		}
		pub.Title = pl.Name
		pub.Subtitle = "Playlist"
		items, held, err := l.playlistMemberViews(ctx, owner, pl, 500)
		if err != nil {
			return nil, err
		}
		// A list the owner can no longer hear any of is gone, rather than
		// a page that names it over no rows.
		if held && len(items) == 0 {
			return nil, errNotFound("no such share")
		}
		views = items
	case "album":
		info, err := l.lib.EntityByPID(ctx, read.EntityAlbum, pid)
		if err != nil {
			return nil, shareMiss(err)
		}
		pub.Title = info.Name
		pub.Subtitle = "Album"
		items, err := l.albumMemberViews(ctx, owner, pid, 500)
		if err != nil {
			return nil, err
		}
		if len(items) == 0 {
			return nil, errNotFound("no such share")
		}
		views = items
	default:
		it, err := l.lib.Get(ctx, pid)
		if err != nil {
			return nil, shareMiss(err)
		}
		if !l.offers(ctx, owner, it) {
			return nil, errNotFound("no such share")
		}
		// A track's link never serves the book its track became: a scan
		// that folds tracks into a book reports no fold for the link to
		// follow, and the book holds parts the owner never shared.
		if row.TargetKind == "track" && it.Kind != model.KindTrack {
			return nil, errNotFound("no such share")
		}
		pub.Title, pub.Subtitle, _ = itemNames(it)
		views = []*model.ItemView{it}
	}
	for _, it := range views {
		pub.Items = append(pub.Items, summary(it))
	}
	if pub.Audio, err = l.shareAudio(ctx, views, episode); err != nil {
		return nil, err
	}
	if len(pub.Items) > 0 {
		pub.ArtItemPID = pub.Items[0].PID
	}
	return pub, nil
}

// liveShareRow reads a share that still serves: not-found for one
// unknown, revoked or expired.
func (l *Library) liveShareRow(ctx context.Context, shareID string) (*wdb.Share, error) {
	row, err := l.db.ShareByID(ctx, shareID)
	if err == wdb.ErrNotFound {
		return nil, errNotFound("no such share")
	}
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if row.Revoked || (!row.ExpiresAt.IsZero() && time.Now().After(row.ExpiresAt)) {
		return nil, errNotFound("no such share")
	}
	return row, nil
}

// ShareLive is the check a stream already running on a share repeats:
// not-found once the link is revoked or expired or its owner can no
// longer sign in, nil while it serves. Two row reads, where resolving the
// share again reads its whole target.
func (l *Library) ShareLive(ctx context.Context, shareID string) error {
	row, err := l.liveShareRow(ctx, shareID)
	if err != nil {
		return err
	}
	u, err := l.db.UserByID(ctx, row.UserID)
	if errors.Is(err, wdb.ErrNotFound) || (err == nil && (u.Disabled || u.Pending)) {
		return errNotFound("no such share")
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// shareMiss is the answer for a share whose target could not be read:
// not-found, failing closed, except for a catalog away for a hand-off,
// which is passed on as it is.
func shareMiss(err error) error {
	if KindOf(err) == KindMaintenance {
		return &Error{Kind: KindMaintenance, Err: err}
	}
	return errNotFound("no such share")
}

// shareAudio says how each of a share's members plays: a file on this
// server plays from it, an episode the server has not fetched relays when
// its feed names audio the relay serves, and anything else, a trashed
// member or one whose file is gone, is left out. One catalog read covers
// the unfetched episodes; known is an episode the resolution already
// read, which needs none.
func (l *Library) shareAudio(ctx context.Context, views []*model.ItemView, known *model.Episode) (map[string]ShareAudio, error) {
	out := make(map[string]ShareAudio, len(views))
	var unfetched []model.PID
	for _, it := range views {
		switch {
		case archived(it):
			// Before the episode arm: a trashed episode is not fetched
			// either, and is no more for playing than a trashed track.
		case it.State == model.StatePresent:
			out[itemAPIPID(it)] = ShareAudioLocal
		case unfetchedEpisode(it):
			unfetched = append(unfetched, it.PID)
		}
	}
	if len(unfetched) == 0 {
		return out, nil
	}
	eps := []*model.Episode{known}
	if known == nil || len(unfetched) != 1 || unfetched[0] != known.PID {
		var err error
		if eps, err = l.episodesByPIDs(ctx, unfetched); err != nil {
			return nil, err
		}
	}
	for _, ep := range eps {
		// The visitor's relay fails closed on a show it cannot read, so
		// the page does too.
		if source, ok := l.showSourceType(ctx, ep.PodcastPID); ok && relayableEnclosure(source, ep.EnclosureURL, ep.EnclosureType) {
			out[apiPID(PrefixEpisode, ep.PID)] = ShareAudioRelay
		}
	}
	return out, nil
}

// privateEpisodes answers whether a member is an episode of a private
// show, the rule an episode share is held to: a capability URL must
// never leak paid content, fetched or not. A show that cannot be read
// counts as private. Each show is read once per answerer, through
// readShow so its source is remembered for the audio check that follows,
// and the sticky private marks are read once for all of them, to be
// judged by privateShow like any other show's.
func (l *Library) privateEpisodes() func(context.Context, *model.ItemView) bool {
	private := map[model.PID]bool{}
	var marks map[string]string
	var marksErr error
	var marksRead bool
	return func(ctx context.Context, it *model.ItemView) bool {
		if it.Kind != model.KindEpisode {
			return false
		}
		hidden, known := private[it.PodcastPID]
		if known {
			return hidden
		}
		hidden = true
		if pod, err := l.readShow(ctx, it.PodcastPID); err == nil {
			l.showSources.Store(pod.PID, pod.SourceType)
			if !marksRead {
				marksRead = true
				if marks, marksErr = l.db.SyncStateWithPrefix(ctx, syncKeyShowPrivate); marksErr != nil {
					l.log.Warn("reading show privacy", "err", marksErr)
				}
			}
			hidden = privateShow(pod, marks[syncKeyShowPrivate+string(pod.PID)], marksErr)
		}
		private[it.PodcastPID] = hidden
		return hidden
	}
}

// albumMemberViews resolves the album tracks the owner can see, in disc
// then track order, for anonymous share serving. The album_pid field
// addresses the album by entity identity rather than a display-string
// match.
func (l *Library) albumMemberViews(ctx context.Context, owner *UserCtx, albumPID model.PID, cap int) ([]*model.ItemView, error) {
	q := l.scopedTo(ctx, owner, visibleTracks()).
		Where("album_pid", query.OpIs, string(albumPID)).
		OrderBy("disc_no", false).
		OrderBy("track_no", false).
		Build()
	var out []*model.ItemView
	cursor := read.Cursor("")
	for len(out) < cap {
		page, err := l.lib.QueryPage(ctx, q, cursor, 200, false, model.PID(""))
		if err != nil {
			return nil, classify(err)
		}
		out = append(out, page.Items...)
		if !page.HasMore {
			break
		}
		cursor = page.Next
	}
	if len(out) > cap {
		out = out[:cap]
	}
	return out, nil
}

// CountSharePlay bumps a share's anonymous play counter (best effort).
func (l *Library) CountSharePlay(ctx context.Context, shareID string) {
	if err := l.db.CountSharePlay(ctx, shareID); err != nil {
		l.log.Warn("counting share play", "share", shareID, "err", err)
	}
}

// PublicArt resolves artwork for a share page without a user context:
// the owner published the target deliberately, and the capability URL
// is the authorization.
func (l *Library) PublicArt(ctx context.Context, apiItemPID string, size int) (ArtBlob, error) {
	prefix, pid, ok := parseAPIPID(apiItemPID)
	if !ok || !itemPrefix(prefix) {
		return ArtBlob{}, errNotFound("no artwork for pid " + apiItemPID)
	}
	it, err := l.lib.Get(ctx, pid)
	if err != nil {
		return ArtBlob{}, classify(err)
	}
	entity := model.ArtTrack
	if it.Kind == model.KindEpisode {
		entity = model.ArtEpisode
	}
	blob, err := l.lib.ResolveArt(ctx, model.EntityRef{Type: entity, PID: it.PID}, model.ArtRoleFront, size)
	if err != nil {
		return ArtBlob{}, classify(err)
	}
	// artMime, not a table of its own: this is the one art response with
	// no session behind it, cacheable by anyone who revalidates, so the
	// type it declares has to be the same one the authenticated
	// endpoints derive rather than a second opinion that drifts.
	return ArtBlob{
		Bytes:      blob.Bytes,
		MimeType:   artMime(blob.Format),
		SourceHash: blob.SourceHash,
		Width:      blob.Width,
		Height:     blob.Height,
		// The rung this answered at, same as the authenticated read.
		// The share page's oversize guard reads it: without it every
		// blob looks unsized, and an original too big to paint would be
		// streamed to anonymous visitors, and into public caches, instead
		// of falling back to the placeholder.
		Box: blob.Box,
	}, nil
}

func shareInfo(r wdb.Share) ShareInfo {
	return ShareInfo{
		ID:            apiPID(PrefixShare, model.PID(r.ID)),
		OwnerID:       r.UserID,
		TargetPID:     r.TargetPID,
		TargetKind:    r.TargetKind,
		AllowDownload: r.AllowDownload,
		PositionMs:    r.PositionMs,
		CreatedAt:     r.CreatedAt,
		ExpiresAt:     r.ExpiresAt,
		Plays:         r.Plays,
	}
}

// sharedPlaylist answers the playlist a share targets, without a caller
// context (share resolution). It hands back the whole row rather than
// the two fields the title needs, so the member read below does not
// re-issue the same Get to reach the rule.
func (l *Library) sharedPlaylist(ctx context.Context, pid model.PID) (*model.Playlist, error) {
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	return pl, nil
}

// playlistMemberViews answers a playlist's members in play order as the
// owner's own listing shows them to the owner (the share publishes that
// list), less the episodes of private shows, capped so a pathological
// playlist cannot balloon a public page. The cap counts what the link
// serves, so private episodes cannot crowd out the members after them.
// held reports whether the list holds anything before the filter, so an
// empty list can be told from one the owner can no longer hear.
//
// The membership and the filter are the ones the owner's listing uses,
// so a smart list's rule is evaluated with the state predicate inside
// the query here too, and a rule that names `state` is honoured as
// written - the share and the listing have to agree, and two copies of
// the filter is the shape that drifts.
func (l *Library) playlistMemberViews(ctx context.Context, owner *UserCtx, pl *model.Playlist, cap int) (items []*model.ItemView, held bool, err error) {
	members, err := l.playlistMembers(ctx, pl)
	if err != nil {
		return nil, false, err
	}
	f, err := l.withTagVerdicts(ctx, l.newMemberFilter(owner, pl), members)
	if err != nil {
		return nil, false, err
	}
	private := l.privateEpisodes()
	items = make([]*model.ItemView, 0, min(len(members), cap))
	for _, it := range members {
		if len(items) == cap {
			break
		}
		if l.memberVisible(ctx, f, it) && !private(ctx, it) {
			items = append(items, it)
		}
	}
	return items, len(members) > 0, nil
}

func encodeShareCursor(ns int64, id string) string {
	return encodeLogCursor(ns, 0) + "." + id
}

func decodeShareCursor(c string) (ns int64, id string, err error) {
	if c == "" {
		return 0, "", nil
	}
	i := strings.LastIndex(c, ".")
	if i < 0 {
		return 0, "", errInvalid("malformed cursor")
	}
	ns, _, err = decodeLogCursor(c[:i])
	return ns, c[i+1:], err
}
