package service

import (
	"context"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
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
	TargetPID     string // API pid
	TargetKind    string // track | playlist | book | episode
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
	Items       []ItemSummary // playable members, play order
	ArtItemPID  string        // API pid whose artwork represents the page
	OwnerUserID string        // billing identity for transcode gating
}

// shareKindForPrefix maps a target prefix onto the stored kind.
var shareKindForPrefix = map[string]string{
	PrefixTrack:    "track",
	PrefixPlaylist: "playlist",
	PrefixBook:     "book",
	PrefixEpisode:  "episode",
}

// CreateShare validates a target and records a share link.
func (l *Library) CreateShare(ctx context.Context, uc *UserCtx, targetAPIPID string, expiresIn time.Duration, allowDownload bool, positionMs int64) (ShareInfo, error) {
	prefix, _, ok := parseAPIPID(targetAPIPID)
	if !ok {
		return ShareInfo{}, errInvalid("malformed pid")
	}
	kind, ok := shareKindForPrefix[prefix]
	if !ok {
		return ShareInfo{}, errInvalid("only tracks, playlists, books, and episodes can be shared")
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
		// Ownership, not mere visibility: the public page serves the
		// owner's member view for the link's whole life, and resolve
		// deliberately skips visibility (the capability URL is the
		// authorization). Another user's shared playlist is theirs to
		// publish; letting a viewer mint a link for it would keep
		// serving it even after the owner flips it private, through a
		// link the owner cannot revoke.
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
		show, err := l.getShow(ctx, apiPID(PrefixPodcast, det.Episode.PodcastPID))
		if err == nil && l.showIsPrivate(ctx, show) {
			return "", &Error{Kind: KindForbidden,
				Msg: "episodes of private feeds cannot be shared"}
		}
		return it.Title, nil
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
	for _, r := range rows {
		info := shareInfo(r)
		// Titles resolve at read time so renames show through; a target
		// gone from the catalog reads as an empty title.
		if title, err := l.shareTitleLoose(ctx, r); err == nil {
			info.TargetTitle = title
		}
		out.Shares = append(out.Shares, info)
	}
	if more {
		last := rows[len(rows)-1]
		out.Next = encodeShareCursor(last.CreatedAt.UnixNano(), last.ID)
	}
	return out, nil
}

// shareTitleLoose resolves a target title without a caller (listing
// and public rendering); missing targets answer empty, not an error.
func (l *Library) shareTitleLoose(ctx context.Context, r wdb.Share) (string, error) {
	_, pid, ok := parseAPIPID(r.TargetPID)
	if !ok {
		return "", nil
	}
	if r.TargetKind == "playlist" {
		name, _, err := l.playlistNameAndOwner(ctx, pid)
		if err != nil {
			return "", nil
		}
		return name, nil
	}
	it, err := l.lib.Get(ctx, pid)
	if err != nil {
		return "", nil
	}
	return it.Title, nil
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
	return nil
}

// ResolveShare answers a live share for anonymous serving: not-found
// for unknown, revoked, or expired ids, and the target resolved to
// playable members. Resolution ignores per-user visibility on purpose:
// the owner chose to publish this target, and the capability URL is
// the authorization.
func (l *Library) ResolveShare(ctx context.Context, shareID string) (*SharePublic, error) {
	row, err := l.db.ShareByID(ctx, shareID)
	if err == wdb.ErrNotFound {
		return nil, errNotFound("no such share")
	}
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if row.Revoked {
		return nil, errNotFound("no such share")
	}
	if !row.ExpiresAt.IsZero() && time.Now().After(row.ExpiresAt) {
		return nil, errNotFound("no such share")
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
	if row.TargetKind == "episode" {
		det, err := l.getEpisode(ctx, row.TargetPID)
		if err != nil {
			return nil, errNotFound("no such share")
		}
		show, err := l.getShow(ctx, apiPID(PrefixPodcast, det.Episode.PodcastPID))
		if err != nil {
			return nil, errNotFound("no such share")
		}
		if l.showIsPrivate(ctx, show) {
			return nil, errNotFound("no such share")
		}
	}
	// Downloads stop when the owner's own download permission is
	// withdrawn; an unreadable owner degrades the same way (the
	// stream still serves, the download link does not).
	if pub.Share.AllowDownload {
		owner, err := l.db.UserByID(ctx, row.UserID)
		if err != nil {
			pub.Share.AllowDownload = false
		} else if ouc, err := l.UserCtx(ctx, owner); err != nil || !ouc.Download {
			pub.Share.AllowDownload = false
		}
	}
	switch row.TargetKind {
	case "playlist":
		name, ownerCatalogPID, err := l.playlistNameAndOwner(ctx, pid)
		if err != nil {
			return nil, errNotFound("no such share")
		}
		pub.Title = name
		pub.Subtitle = "Playlist"
		items, err := l.playlistMemberViews(ctx, pid, ownerCatalogPID, 500)
		if err != nil {
			return nil, err
		}
		for _, it := range items {
			pub.Items = append(pub.Items, summary(it))
		}
	default:
		it, err := l.lib.Get(ctx, pid)
		if err != nil {
			return nil, errNotFound("no such share")
		}
		pub.Title = it.Title
		pub.Subtitle = it.Artist
		pub.Items = []ItemSummary{summary(it)}
	}
	if len(pub.Items) > 0 {
		pub.ArtItemPID = pub.Items[0].PID
	}
	return pub, nil
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
	blob, err := l.lib.ResolveArt(ctx, model.EntityRef{Type: entity, PID: it.PID}, size)
	if err != nil {
		return ArtBlob{}, classify(err)
	}
	mime := artMimes[strings.TrimPrefix(blob.Format, "image/")]
	if mime == "" {
		mime = "image/jpeg"
	}
	return ArtBlob{Bytes: blob.Bytes, MimeType: mime, SourceHash: blob.SourceHash}, nil
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

// playlistNameAndOwner answers a playlist's display name and owner
// catalog pid without a caller context (share resolution).
func (l *Library) playlistNameAndOwner(ctx context.Context, pid model.PID) (string, model.PID, error) {
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		return "", "", classify(err)
	}
	return pl.Name, pl.OwnerPID, nil
}

// playlistMemberViews answers a playlist's members in play order,
// evaluated as the owner (the share publishes the owner's list),
// capped so a pathological playlist cannot balloon a public page.
func (l *Library) playlistMemberViews(ctx context.Context, pid, ownerPID model.PID, cap int) ([]*model.ItemView, error) {
	items, err := l.lib.Playlists().Items(ctx, pid, ownerPID)
	if err != nil {
		return nil, classify(err)
	}
	if len(items) > cap {
		items = items[:cap]
	}
	return items, nil
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
