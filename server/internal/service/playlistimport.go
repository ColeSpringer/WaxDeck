package service

import (
	"context"
	"encoding/csv"
	"errors"
	"io"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
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
	MBID            string
	ASIN            string
	ISBN            string
	ISRC            string
	Artist          string
	Title           string
	Album           string
	DurationMs      int64
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

// ImportStreamingPlaylist parses an export, resolves it against the
// library, and creates a playlist from what matched.
func (l *Library) ImportStreamingPlaylist(ctx context.Context, uc *UserCtx, in PlaylistImportInput) (PlaylistImportOutcome, error) {
	var (
		refs     []PortableRefDTO
		listName string
		err      error
	)
	switch in.Source {
	case "portable":
		if len(in.Refs) == 0 {
			return PlaylistImportOutcome{}, errInvalid("the portable source needs refs")
		}
		if in.Payload != "" {
			return PlaylistImportOutcome{}, errInvalid("the portable source takes refs, not payload")
		}
		refs = in.Refs
	case "spotify", "ytmusic", "csv":
		refs, listName, err = parseDelimitedExport(in.Payload, ',')
	case "applemusic":
		refs, listName, err = parseDelimitedExport(in.Payload, '\t')
	case "text":
		refs, err = parseTextExport(in.Payload)
	default:
		return PlaylistImportOutcome{}, errInvalid("unknown source " + in.Source)
	}
	if err != nil {
		return PlaylistImportOutcome{}, err
	}
	if len(refs) == 0 {
		return PlaylistImportOutcome{}, errInvalid("the export carries no entries")
	}
	if len(refs) > importEntryCap {
		refs = refs[:importEntryCap]
	}
	name := strings.TrimSpace(in.Name)
	if name == "" {
		name = listName
	}
	if name == "" {
		name = "Imported playlist"
	}
	modelRefs := make([]model.PortableRef, len(refs))
	for i, r := range refs {
		modelRefs[i] = toModelRef(r)
	}
	res, err := l.lib.ResolvePlaylistRefs(ctx, modelRefs)
	if err != nil {
		return PlaylistImportOutcome{}, classify(err)
	}
	// The local trim retry runs before the network-paced ISRC upgrade
	// so the bounded lookup budget goes to entries nothing local fixes.
	if err := l.retryMissesWithTrimmedArtist(ctx, refs, modelRefs, res); err != nil {
		return PlaylistImportOutcome{}, err
	}
	l.upgradeMissesByISRC(ctx, refs, modelRefs, res)
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
	pid, err := l.lib.Playlists().CreateStatic(ctx, name, model.PID(uc.CatalogPID), model.VisibilityPrivate)
	if err != nil {
		return PlaylistImportOutcome{}, classify(err)
	}
	if err := l.lib.Playlists().Add(ctx, pid, members...); err != nil {
		return PlaylistImportOutcome{}, classify(err)
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
func (l *Library) retryMissesWithTrimmedArtist(ctx context.Context, refs []PortableRefDTO, modelRefs []model.PortableRef, res []model.RefResolution) error {
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
	again, err := l.lib.ResolvePlaylistRefs(ctx, retryRefs)
	if err != nil {
		return classify(err)
	}
	for j, r := range again {
		if r.Rung != model.MatchNone {
			res[retryIdx[j]] = r
		}
	}
	return nil
}

// upgradeMissesByISRC retries unresolved entries whose export carried
// an ISRC: the identifier upgrades to a recording MBID through
// MusicBrainz and the ladder runs again on the strong rung. Bounded
// and best-effort; without internet the import stands as resolved.
func (l *Library) upgradeMissesByISRC(ctx context.Context, refs []PortableRefDTO, modelRefs []model.PortableRef, res []model.RefResolution) {
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
		again, err := l.lib.ResolvePlaylistRefs(ctx, []model.PortableRef{upgraded})
		if err == nil && len(again) == 1 && again[0].Rung != model.MatchNone {
			res[i] = again[0]
		}
	}
}

// ExportPlaylistPortable exports a playlist the caller can see as
// portable refs.
func (l *Library) ExportPlaylistPortable(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (string, []PortableRefDTO, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return "", nil, err
	}
	refs, err := l.lib.ExportPlaylistRefs(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		return "", nil, classify(err)
	}
	out := make([]PortableRefDTO, len(refs))
	for i, r := range refs {
		out[i] = PortableRefDTO{
			Kind:            string(r.Kind),
			Essence:         r.Essence,
			Fingerprint:     r.Fingerprint,
			FingerprintAlgo: r.FingerprintAlgo,
			MBID:            r.MBID,
			ASIN:            r.ASIN,
			ISBN:            r.ISBN,
			Artist:          r.Artist,
			Title:           r.Title,
			Album:           r.Album,
			DurationMs:      r.DurationMS,
		}
	}
	return pl.Name, out, nil
}

func toModelRef(r PortableRefDTO) model.PortableRef {
	kind := model.Kind(r.Kind)
	switch kind {
	case model.KindTrack, model.KindBook, model.KindEpisode:
	default:
		kind = model.KindTrack
	}
	return model.PortableRef{
		Kind:            kind,
		Essence:         r.Essence,
		Fingerprint:     r.Fingerprint,
		FingerprintAlgo: r.FingerprintAlgo,
		MBID:            r.MBID,
		ASIN:            r.ASIN,
		ISBN:            r.ISBN,
		Artist:          r.Artist,
		Title:           r.Title,
		Album:           r.Album,
		DurationMS:      r.DurationMs,
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
		for i, f := range fields {
			if i >= len(rec) {
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
				e.DurationMs = parseClockDuration(v)
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
