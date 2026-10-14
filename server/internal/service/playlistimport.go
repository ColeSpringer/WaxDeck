package service

import (
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"maps"
	"math"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// Streaming-service playlist import and portable-ref export. Matching
// rides the catalog's portable-ref resolve ladder (essence, strong
// external identifiers, acoustic fingerprint, then descriptive
// artist/title/album/duration); unresolved entries are the
// missing-tracks report.

// PortableRefDTO mirrors the catalog's portable ref on the API
// boundary, plus ISRC (an importer-side anchor the ladder upgrades to
// a recording MBID before resolving).
type PortableRefDTO struct {
	Kind            string
	Essence         string
	Fingerprint     []byte
	FingerprintAlgo int
	// FingerprintBucket is where the fingerprint was stored; zero probes at
	// DurationMs's bucket.
	FingerprintBucket int64
	MBID              string
	ASIN              string
	ISBN              string
	ISRC              string
	Artist            string
	Title             string
	Album             string
	DurationMs        int64
}

// PlaylistImportInput is one import request.
type PlaylistImportInput struct {
	Source  string
	Name    string
	Payload string
	Refs    []PortableRefDTO
}

// ImportMiss is one unmatched entry of the report.
type ImportMiss struct {
	Artist     string
	Title      string
	Album      string
	DurationMs int64
}

// RungCounts reports how many entries each resolve rung matched.
type RungCounts struct {
	Essence     int
	StrongID    int
	Fingerprint int
	Descriptive int
}

// PlaylistImportOutcome is the import report.
type PlaylistImportOutcome struct {
	PlaylistPID string // empty when nothing resolved
	Name        string
	Requested   int
	Resolved    int
	Missing     []ImportMiss
	Rungs       RungCounts
}

// ISRCResolver upgrades an ISRC to a recording MBID; the MusicBrainz
// provider implements it. Nil disables the upgrade (imports still run
// on the descriptive rung).
type ISRCResolver interface {
	RecordingMBIDByISRC(ctx context.Context, isrc string) (string, error)
}

// importEntryCap bounds parsed entries per import.
const importEntryCap = 10000

// isrcLookupBudget bounds the strong-identifier upgrade: lookups are
// paced at MusicBrainz etiquette (one per second), so only entries the
// local ladder failed get one, up to this many, inside an overall
// wall-clock budget. The import stays a synchronous request.
const (
	isrcLookupCap    = 20
	isrcLookupWindow = 20 * time.Second
)

// parsePlaylistExport parses one export into portable refs plus any
// playlist name the export itself carries. It is shared by the one-shot
// import and the matched-source playlist binding, which stores the
// parsed refs and re-resolves them on demand.
func parsePlaylistExport(src, payload string, portableRefs []PortableRefDTO) ([]PortableRefDTO, string, error) {
	var (
		refs     []PortableRefDTO
		listName string
		err      error
	)
	switch src {
	case "portable":
		if len(portableRefs) == 0 {
			return nil, "", errInvalid("the portable source needs refs")
		}
		if payload != "" {
			return nil, "", errInvalid("the portable source takes refs, not payload")
		}
		for i, r := range portableRefs {
			if r.FingerprintBucket < 0 || r.FingerprintBucket > math.MaxInt32 {
				return nil, "", errInvalid(fmt.Sprintf("refs[%d]: fingerprintBucket must be between 0 and %d", i, math.MaxInt32))
			}
		}
		refs = portableRefs
	case "spotify", "ytmusic", "csv":
		refs, listName, err = parseDelimitedExport(payload, ',')
	case "applemusic":
		refs, listName, err = parseDelimitedExport(payload, '\t')
	case "text":
		refs, err = parseTextExport(payload)
	default:
		return nil, "", errInvalid("unknown source " + src)
	}
	if err != nil {
		return nil, "", err
	}
	if len(refs) == 0 {
		return nil, "", errInvalid("the export carries no entries")
	}
	if len(refs) > importEntryCap {
		refs = refs[:importEntryCap]
	}
	return refs, listName, nil
}

// resolvePlaylistImportRefs runs the resolve ladder plus its two
// upgrade passes over parsed refs, one resolution per ref in order, each
// pass keeping only matches the filter's caller may hold, and answers
// the views the passes read beside them.
func (l *Library) resolvePlaylistImportRefs(ctx context.Context, f memberFilter, refs []PortableRefDTO) ([]model.RefResolution, map[model.PID]*model.ItemView, error) {
	modelRefs := make([]model.PortableRef, len(refs))
	for i, r := range refs {
		modelRefs[i] = toModelRef(r)
	}
	res, views, err := l.resolveReachable(ctx, f, modelRefs)
	if err != nil {
		return nil, nil, err
	}
	// The local trim retry runs before the network-paced ISRC upgrade
	// so the bounded lookup budget goes to entries nothing local fixes.
	if err := l.retryMissesWithTrimmedArtist(ctx, f, refs, modelRefs, res, views); err != nil {
		return nil, nil, err
	}
	l.upgradeMissesByISRC(ctx, f, refs, modelRefs, res, views)
	return res, views, nil
}

// resolveReachable resolves refs against the whole catalog, as the
// resolver always does, then turns every match the filter's caller may
// not hold into a miss. A hidden match reads exactly like no match, and
// filtering inside each pass lets the retries look past it. An import
// takes a tie between copies of one recording: any of them serves.
func (l *Library) resolveReachable(ctx context.Context, f memberFilter, refs []model.PortableRef) ([]model.RefResolution, map[model.PID]*model.ItemView, error) {
	return l.resolveVisible(ctx, f, refs, waxbin.ResolveOptions{AcceptSameRecording: true})
}

// resolveVisible is the resolve both directions share: the catalog's
// ladder, then every match the filter's caller may not hold made a miss,
// answering the matched views beside the resolutions.
func (l *Library) resolveVisible(ctx context.Context, f memberFilter, refs []model.PortableRef, opts waxbin.ResolveOptions) ([]model.RefResolution, map[model.PID]*model.ItemView, error) {
	res, err := l.lib.ResolvePlaylistRefsWith(ctx, refs, opts)
	if err != nil {
		return nil, nil, classify(err)
	}
	var pids []model.PID
	for _, r := range res {
		if r.Rung != model.MatchNone {
			pids = append(pids, r.PID)
		}
	}
	views, err := l.itemViewsByPID(ctx, pids)
	if err != nil {
		return nil, nil, err
	}
	if f, err = l.withTagVerdicts(ctx, f, slices.Collect(maps.Values(views))); err != nil {
		return nil, nil, err
	}
	for i, r := range res {
		if r.Rung == model.MatchNone {
			continue
		}
		if v := views[r.PID]; v == nil || !l.memberVisible(ctx, f, v) {
			res[i] = model.RefResolution{Ref: r.Ref, Rung: model.MatchNone}
		}
	}
	return res, views, nil
}

// ImportStreamingPlaylist parses an export, resolves it against the
// library, and creates a playlist from what matched.
func (l *Library) ImportStreamingPlaylist(ctx context.Context, uc *UserCtx, in PlaylistImportInput) (PlaylistImportOutcome, error) {
	refs, listName, err := parsePlaylistExport(in.Source, in.Payload, in.Refs)
	if err != nil {
		return PlaylistImportOutcome{}, err
	}
	name := strings.TrimSpace(in.Name)
	if name == "" {
		name = listName
	}
	if name == "" {
		name = "Imported playlist"
	}
	// The new list is static, so a trashed match is a miss too.
	res, _, err := l.resolvePlaylistImportRefs(ctx, memberFilter{uc: uc, subs: l.newSubscriptionFilter(uc)}, refs)
	if err != nil {
		return PlaylistImportOutcome{}, err
	}
	out := PlaylistImportOutcome{Name: name, Requested: len(refs)}
	var members []model.PID
	for i, r := range res {
		switch r.Rung {
		case model.MatchEssence:
			out.Rungs.Essence++
		case model.MatchStrongID:
			out.Rungs.StrongID++
		case model.MatchFingerprint:
			out.Rungs.Fingerprint++
		case model.MatchDescriptive:
			out.Rungs.Descriptive++
		default:
			out.Missing = append(out.Missing, ImportMiss{
				Artist:     refs[i].Artist,
				Title:      refs[i].Title,
				Album:      refs[i].Album,
				DurationMs: refs[i].DurationMs,
			})
			continue
		}
		out.Resolved++
		members = append(members, r.PID)
	}
	if out.Resolved == 0 {
		return out, nil
	}
	pid, err := l.createStaticWith(ctx, name, model.PID(uc.CatalogPID), model.VisibilityPrivate, members)
	if err != nil {
		return PlaylistImportOutcome{}, err
	}
	l.emitPlaylistEvent(ctx, uc, false, string(pid))
	out.PlaylistPID = apiPID(PrefixPlaylist, pid)
	return out, nil
}

// retryMissesWithTrimmedArtist re-resolves unresolved entries whose
// artist cell looks multi-credited ("A, B", "A; B", "A feat. B"),
// using the primary credit alone: exports join every contributing
// artist into one cell while library tags usually carry just the
// primary. The trim runs only on misses so comma-carrying band names
// ("Earth, Wind & Fire", "Tyler, the Creator") keep their exact
// first-pass match. Purely local, so every miss gets the retry.
func (l *Library) retryMissesWithTrimmedArtist(ctx context.Context, f memberFilter, refs []PortableRefDTO, modelRefs []model.PortableRef, res []model.RefResolution, views map[model.PID]*model.ItemView) error {
	var retryIdx []int
	var retryRefs []model.PortableRef
	for i := range res {
		if res[i].Rung != model.MatchNone {
			continue
		}
		trimmed := firstArtist(refs[i].Artist)
		if trimmed == "" || trimmed == refs[i].Artist {
			continue
		}
		upgraded := modelRefs[i]
		upgraded.Artist = trimmed
		retryIdx = append(retryIdx, i)
		retryRefs = append(retryRefs, upgraded)
	}
	if len(retryRefs) == 0 {
		return nil
	}
	again, seen, err := l.resolveReachable(ctx, f, retryRefs)
	if err != nil {
		return err
	}
	for j, r := range again {
		if r.Rung != model.MatchNone {
			res[retryIdx[j]], views[r.PID] = r, seen[r.PID]
		}
	}
	return nil
}

// upgradeMissesByISRC retries unresolved entries whose export carried
// an ISRC: the identifier upgrades to a recording MBID through
// MusicBrainz and the ladder runs again on the strong rung. Bounded
// and best-effort; without internet the import stands as resolved.
func (l *Library) upgradeMissesByISRC(ctx context.Context, f memberFilter, refs []PortableRefDTO, modelRefs []model.PortableRef, res []model.RefResolution, views map[model.PID]*model.ItemView) {
	if l.isrcResolver == nil {
		return
	}
	deadline := time.Now().Add(isrcLookupWindow)
	looked := 0
	for i := range res {
		if res[i].Rung != model.MatchNone || refs[i].ISRC == "" {
			continue
		}
		if looked >= isrcLookupCap || time.Now().After(deadline) {
			return
		}
		looked++
		lookupCtx, cancel := context.WithDeadline(ctx, deadline)
		mbid, err := l.isrcResolver.RecordingMBIDByISRC(lookupCtx, refs[i].ISRC)
		cancel()
		if err != nil || mbid == "" {
			continue
		}
		upgraded := modelRefs[i]
		upgraded.MBID = mbid
		again, seen, err := l.resolveReachable(ctx, f, []model.PortableRef{upgraded})
		if err == nil && len(again) == 1 && again[0].Rung != model.MatchNone {
			res[i], views[again[0].PID] = again[0], seen[again[0].PID]
		}
	}
}

// ExportPlaylistPortable exports the members of a playlist this caller
// can see as portable refs.
func (l *Library) ExportPlaylistPortable(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (string, []PortableRefDTO, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return "", nil, err
	}
	refs, err := l.reachableRefs(ctx, uc, pl)
	if err != nil {
		return "", nil, err
	}
	out := make([]PortableRefDTO, len(refs))
	for i, r := range refs {
		out[i] = PortableRefDTO{
			Kind:              string(r.Kind),
			Essence:           r.Essence,
			Fingerprint:       r.Fingerprint,
			FingerprintAlgo:   r.FingerprintAlgo,
			FingerprintBucket: r.FingerprintBucket,
			MBID:              r.MBID,
			ASIN:              r.ASIN,
			ISBN:              r.ISBN,
			Artist:            r.Artist,
			Title:             r.Title,
			Album:             r.Album,
			DurationMs:        r.DurationMS,
		}
	}
	return pl.Name, out, nil
}

// reachableRefs is the playlist's refs narrowed to the members this
// caller can see. The catalog exports a whole playlist, in order and
// without pids, so the members are read beside it and paired by
// position. Pairing is only sound over a list that held still: two
// members alike in kind, title and length pair either way round, so a
// reorder between the reads would hand a visible slot a hidden member's
// ref. The members are read on both sides of the export and the list's
// edit stamp around all three (an edit and its undo still move the
// stamp); a list that moved is read again once, then refused.
func (l *Library) reachableRefs(ctx context.Context, uc *UserCtx, pl *model.Playlist) ([]model.PortableRef, error) {
	f := l.newMemberFilter(uc, pl)
	if drawsAfresh(pl) {
		return l.drawnRefs(ctx, f, pl)
	}
	for range 2 {
		before, err := l.lib.Playlists().Get(ctx, pl.PID)
		if err != nil {
			return nil, classify(err)
		}
		members, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
		if err != nil {
			return nil, classify(err)
		}
		refs, err := l.lib.ExportPlaylistRefs(ctx, pl.PID, pl.OwnerPID)
		if err != nil {
			return nil, classify(err)
		}
		again, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
		if err != nil {
			return nil, classify(err)
		}
		after, err := l.lib.Playlists().Get(ctx, pl.PID)
		if err != nil {
			return nil, classify(err)
		}
		if before.UpdatedAt != after.UpdatedAt || !sameMembers(members, again) {
			continue
		}
		vf, err := l.withTagVerdicts(ctx, f, members)
		if err != nil {
			return nil, err
		}
		if out, ok := l.pairRefs(ctx, vf, members, refs); ok {
			return out, nil
		}
	}
	return nil, &Error{Kind: KindConflict, Msg: "the playlist changed while it was exported; retry"}
}

// sameMembers reports whether two member reads hold the same items in
// the same order.
func sameMembers(a, b []*model.ItemView) bool {
	return slices.EqualFunc(a, b, func(x, y *model.ItemView) bool { return x.PID == y.PID })
}

// pairRefs keeps the refs of the visible members, reporting false when
// the two lists do not line up.
func (l *Library) pairRefs(ctx context.Context, f memberFilter, members []*model.ItemView, refs []model.PortableRef) ([]model.PortableRef, bool) {
	if len(members) != len(refs) {
		return nil, false
	}
	out := make([]model.PortableRef, 0, len(refs))
	for i, it := range members {
		r := refs[i]
		if !refNames(r, it) {
			return nil, false
		}
		if l.memberVisible(ctx, f, it) {
			out = append(out, r)
		}
	}
	return out, true
}

// drawsAfresh reports a smart list that shuffles anew on every read: a
// random limit with no pinned seed.
func drawsAfresh(pl *model.Playlist) bool {
	return pl.Kind != model.PlaylistStatic && pl.Rule != nil &&
		pl.Rule.LimitMode == query.LimitRandom && pl.Rule.LimitSeed == 0
}

// drawnRefs exports a list that draws afresh on every read, which no
// second read can pair with, so each ref is resolved back to the item it
// names instead. A ref is kept only when it resolves to one item of its
// own kind, title and length that the caller can see. Unlike an import
// it declines ties: a ref here must name the member it came from, not
// any copy of the recording, which may be one the caller cannot see.
func (l *Library) drawnRefs(ctx context.Context, f memberFilter, pl *model.Playlist) ([]model.PortableRef, error) {
	refs, err := l.lib.ExportPlaylistRefs(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		return nil, classify(err)
	}
	res, views, err := l.resolveVisible(ctx, f, refs, waxbin.ResolveOptions{})
	if err != nil {
		return nil, err
	}
	out := make([]model.PortableRef, 0, len(refs))
	for i, r := range res {
		if r.Rung != model.MatchNone && refNames(refs[i], views[r.PID]) {
			out = append(out, refs[i])
		}
	}
	return out, nil
}

// refNames reports whether a ref describes this item.
func refNames(r model.PortableRef, it *model.ItemView) bool {
	return r.Kind == it.Kind && r.Title == it.Title && r.DurationMS == it.DurationMS
}

func toModelRef(r PortableRefDTO) model.PortableRef {
	kind := model.Kind(r.Kind)
	switch kind {
	case model.KindTrack, model.KindBook, model.KindEpisode:
	default:
		kind = model.KindTrack
	}
	return model.PortableRef{
		Kind:              kind,
		Essence:           r.Essence,
		Fingerprint:       r.Fingerprint,
		FingerprintAlgo:   r.FingerprintAlgo,
		FingerprintBucket: r.FingerprintBucket,
		MBID:              r.MBID,
		ASIN:              r.ASIN,
		ISBN:              r.ISBN,
		Artist:            r.Artist,
		Title:             r.Title,
		Album:             r.Album,
		DurationMS:        r.DurationMs,
	}
}

// exportColumns maps the header spellings the known exports use onto
// entry fields. Matching is case-insensitive on the trimmed header.
var exportColumns = map[string]string{
	"track name":          "title",
	"song title":          "title",
	"song":                "title",
	"title":               "title",
	"name":                "title",
	"artist name":         "artist",
	"artist name(s)":      "artist",
	"artist":              "artist",
	"artists":             "artist",
	"album name":          "album",
	"album title":         "album",
	"album":               "album",
	"track duration (ms)": "durationMs",
	"duration (ms)":       "durationMs",
	"duration":            "duration",
	"time":                "duration",
	"isrc":                "isrc",
	"playlist name":       "playlistName",
}

// parseDelimitedExport reads a header-mapped CSV or TSV export
// (Exportify, Google Takeout, the Apple Music tab-separated export,
// generic spreadsheets). The playlist name column, when present, names
// the import.
func parseDelimitedExport(payload string, sep rune) ([]PortableRefDTO, string, error) {
	if strings.TrimSpace(payload) == "" {
		return nil, "", errInvalid("payload is empty")
	}
	r := csv.NewReader(strings.NewReader(payload))
	r.Comma = sep
	r.FieldsPerRecord = -1
	r.LazyQuotes = true
	header, err := r.Read()
	if err != nil {
		return nil, "", errInvalid("the export is not parseable")
	}
	fields := map[int]string{}
	for i, h := range header {
		key := strings.ToLower(strings.TrimSpace(strings.TrimPrefix(h, "\ufeff")))
		if f, ok := exportColumns[key]; ok {
			if _, taken := indexOfValue(fields, f); !taken {
				fields[i] = f
			}
		}
	}
	if _, ok := indexOfValue(fields, "title"); !ok {
		return nil, "", errInvalid("the export has no recognizable title column")
	}
	var out []PortableRefDTO
	listName := ""
	for {
		rec, err := r.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			// A malformed row is skipped, not fatal: exports from
			// spreadsheet round trips carry stray lines routinely.
			continue
		}
		var e PortableRefDTO
		e.Kind = string(model.KindTrack)
		// Columns apply left to right (map iteration order must never
		// decide a field), and the exact-milliseconds column beats a
		// clock-format one when an export carries both.
		for i := range rec {
			f, ok := fields[i]
			if !ok {
				continue
			}
			v := strings.TrimSpace(rec[i])
			switch f {
			case "title":
				e.Title = v
			case "artist":
				// The full cell, commas and all: "Earth, Wind & Fire"
				// must reach the resolver intact. Multi-artist cells
				// ("A, B") that miss get a second pass with the
				// primary credit trimmed out (see the import flow).
				e.Artist = v
			case "album":
				e.Album = v
			case "durationMs":
				if n, err := strconv.ParseInt(v, 10, 64); err == nil && n > 0 {
					e.DurationMs = n
				}
			case "duration":
				if e.DurationMs == 0 {
					e.DurationMs = parseClockDuration(v)
				}
			case "isrc":
				e.ISRC = v
			case "playlistName":
				if listName == "" {
					listName = v
				}
			}
		}
		if e.Title == "" {
			continue
		}
		out = append(out, e)
		if len(out) >= importEntryCap {
			break
		}
	}
	return out, listName, nil
}

// indexOfValue finds the column index already mapped to a field.
func indexOfValue(fields map[int]string, want string) (int, bool) {
	for i, f := range fields {
		if f == want {
			return i, true
		}
	}
	return 0, false
}

// firstArtist trims a multi-artist cell ("A, B", "A; B", "A feat. B")
// to the primary credit. Retry-only: applying it at parse time would
// corrupt band names that legitimately carry a comma, so the full
// cell resolves first and this variant runs only on misses.
func firstArtist(v string) string {
	for _, sep := range []string{";", ",", " feat. ", " ft. "} {
		if i := strings.Index(v, sep); i > 0 {
			v = v[:i]
		}
	}
	return strings.TrimSpace(v)
}

// parseClockDuration reads "3:45" and "1:02:03" clock strings and bare
// second counts into milliseconds; 0 when unparseable.
func parseClockDuration(v string) int64 {
	if v == "" {
		return 0
	}
	if !strings.Contains(v, ":") {
		if secs, err := strconv.ParseFloat(v, 64); err == nil && secs > 0 {
			return int64(secs * 1000)
		}
		return 0
	}
	parts := strings.Split(v, ":")
	if len(parts) > 3 {
		return 0
	}
	total := int64(0)
	for _, p := range parts {
		n, err := strconv.ParseInt(strings.TrimSpace(p), 10, 64)
		if err != nil || n < 0 {
			return 0
		}
		total = total*60 + n
	}
	return total * 1000
}

// parseTextExport reads one "Artist - Title" per line; a line without
// a separator is a bare title.
func parseTextExport(payload string) ([]PortableRefDTO, error) {
	if strings.TrimSpace(payload) == "" {
		return nil, errInvalid("payload is empty")
	}
	var out []PortableRefDTO
	for _, line := range strings.Split(payload, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		e := PortableRefDTO{Kind: string(model.KindTrack)}
		for _, sep := range []string{" - ", " – ", " — "} {
			if artist, title, ok := strings.Cut(line, sep); ok {
				e.Artist, e.Title = strings.TrimSpace(artist), strings.TrimSpace(title)
				break
			}
		}
		if e.Title == "" {
			e.Title = line
		}
		out = append(out, e)
		if len(out) >= importEntryCap {
			break
		}
	}
	return out, nil
}
