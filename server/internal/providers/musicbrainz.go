package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/match"
)

// MusicBrainzConfig configures the MusicBrainz client. Zero values take
// the documented defaults.
type MusicBrainzConfig struct {
	// BaseURL defaults to "https://musicbrainz.org/ws/2".
	BaseURL string
	// UserAgent is required by MusicBrainz etiquette; defaults to the
	// WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 1100ms (etiquette: one request per second).
	MinInterval time.Duration
	// CacheTTL defaults to 7 days (release data is stable).
	CacheTTL time.Duration
}

// MusicBrainz looks up releases against the MusicBrainz web service. It
// serves the match engine's candidate lookups; fingerprint resolution
// belongs to AcoustID (see Source).
type MusicBrainz struct {
	base string
	ttl  time.Duration
	core *core
}

// NewMusicBrainz builds a client from cfg, applying defaults for zero
// fields.
func NewMusicBrainz(cfg MusicBrainzConfig) *MusicBrainz {
	base := cfg.BaseURL
	if base == "" {
		base = "https://musicbrainz.org/ws/2"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = 1100 * time.Millisecond
	}
	ttl := cfg.CacheTTL
	if ttl == 0 {
		ttl = 7 * 24 * time.Hour
	}
	return &MusicBrainz{
		base: strings.TrimRight(base, "/"),
		ttl:  ttl,
		core: newCore(cfg.HTTPClient, ua, interval),
	}
}

// Minimal shapes for the JSON actually consumed; everything else in the
// MusicBrainz payload is ignored.
type mbArtistCredit struct {
	Name       string `json:"name"`
	JoinPhrase string `json:"joinphrase"`
}

type mbLabelInfo struct {
	CatalogNumber string `json:"catalog-number"`
	Label         *struct {
		Name string `json:"name"`
	} `json:"label"`
}

type mbRecording struct {
	ID     string `json:"id"`
	Length *int   `json:"length"`
}

type mbTrack struct {
	Position     int              `json:"position"`
	Title        string           `json:"title"`
	Length       *int             `json:"length"`
	Recording    *mbRecording     `json:"recording"`
	ArtistCredit []mbArtistCredit `json:"artist-credit"`
}

type mbMedium struct {
	Tracks []mbTrack `json:"tracks"`
}

type mbReleaseGroup struct {
	ID               string   `json:"id"`
	FirstReleaseDate string   `json:"first-release-date"`
	PrimaryType      string   `json:"primary-type"`
	SecondaryTypes   []string `json:"secondary-types"`
}

type mbRelease struct {
	ID           string           `json:"id"`
	Title        string           `json:"title"`
	Date         string           `json:"date"`
	Country      string           `json:"country"`
	Barcode      string           `json:"barcode"`
	ArtistCredit []mbArtistCredit `json:"artist-credit"`
	ReleaseGroup *mbReleaseGroup  `json:"release-group"`
	LabelInfo    []mbLabelInfo    `json:"label-info"`
	Media        []mbMedium       `json:"media"`
}

// ReleaseByMBID fetches one release with its tracklist. A 404 is a clean
// miss: (nil, nil).
func (m *MusicBrainz) ReleaseByMBID(ctx context.Context, mbid string) (*match.Release, error) {
	q := url.Values{}
	q.Set("inc", "recordings artist-credits release-groups labels")
	q.Set("fmt", "json")
	u := m.base + "/release/" + url.PathEscape(mbid) + "?" + q.Encode()
	body, status, err := m.core.get(ctx, u, m.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: musicbrainz release %s: status %d", mbid, status)
	}
	var rel mbRelease
	if err := json.Unmarshal(body, &rel); err != nil {
		return nil, fmt.Errorf("providers: decode musicbrainz release %s: %w", mbid, err)
	}
	return mapMBRelease(&rel, ""), nil
}

// RecordingMBIDByISRC resolves an ISRC to its recording MBID, for the
// playlist importer's strong-identifier upgrade. An ISRC mapping to
// several recordings takes the first (they are the same performance by
// definition; MusicBrainz splits them only for edit-history reasons).
// A 404 is a clean miss: ("", nil).
func (m *MusicBrainz) RecordingMBIDByISRC(ctx context.Context, isrc string) (string, error) {
	q := url.Values{}
	q.Set("fmt", "json")
	u := m.base + "/isrc/" + url.PathEscape(isrc) + "?" + q.Encode()
	body, status, err := m.core.get(ctx, u, m.ttl)
	if err != nil {
		return "", err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound, http.StatusBadRequest:
		return "", nil
	default:
		return "", fmt.Errorf("providers: musicbrainz isrc %s: status %d", isrc, status)
	}
	var parsed struct {
		Recordings []mbRecording `json:"recordings"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", fmt.Errorf("providers: decode musicbrainz isrc %s: %w", isrc, err)
	}
	if len(parsed.Recordings) == 0 {
		return "", nil
	}
	return parsed.Recordings[0].ID, nil
}

// ReleasesByGroup fetches the releases in a release group, tracklists
// included (the browse endpoint honors inc=recordings per release).
func (m *MusicBrainz) ReleasesByGroup(ctx context.Context, rgMBID string) ([]*match.Release, error) {
	q := url.Values{}
	q.Set("release-group", rgMBID)
	q.Set("inc", "recordings artist-credits labels")
	q.Set("fmt", "json")
	q.Set("limit", "10")
	u := m.base + "/release?" + q.Encode()
	body, status, err := m.core.get(ctx, u, m.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: musicbrainz release group %s: status %d", rgMBID, status)
	}
	var parsed struct {
		Releases []mbRelease `json:"releases"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode musicbrainz release group %s: %w", rgMBID, err)
	}
	out := make([]*match.Release, 0, len(parsed.Releases))
	for i := range parsed.Releases {
		out = append(out, mapMBRelease(&parsed.Releases[i], rgMBID))
	}
	return out, nil
}

// SearchReleases finds releases by album artist and title text. Search
// results carry no recordings, so the top hits are hydrated through
// ReleaseByMBID (cached and paced); hits that fail to hydrate are
// skipped. A 400 (bad lucene edge case) or 404 is a clean miss.
func (m *MusicBrainz) SearchReleases(ctx context.Context, artist, album string, trackCount int) ([]*match.Release, error) {
	_ = trackCount // reserved for search refinement; the engine scores tracklists itself
	query := "release:" + luceneQuote(album)
	if artist != "" {
		query += " AND artist:" + luceneQuote(artist)
	}
	q := url.Values{}
	q.Set("query", query)
	q.Set("fmt", "json")
	q.Set("limit", "8")
	u := m.base + "/release?" + q.Encode()
	body, status, err := m.core.get(ctx, u, m.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusBadRequest, http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: musicbrainz search: status %d", status)
	}
	var parsed struct {
		Releases []struct {
			ID string `json:"id"`
		} `json:"releases"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode musicbrainz search: %w", err)
	}
	var out []*match.Release
	for i, hit := range parsed.Releases {
		if i >= 5 {
			break
		}
		rel, err := m.ReleaseByMBID(ctx, hit.ID)
		if err != nil {
			if ctx.Err() != nil {
				return nil, fmt.Errorf("providers: musicbrainz search hydration: %w", ctx.Err())
			}
			continue
		}
		if rel != nil {
			out = append(out, rel)
		}
	}
	return out, nil
}

// SearchRecordings finds releases carrying a recording that matches the artist
// and track title. It is the descriptive path for loose tracks with no album:
// the recording search returns the releases each hit appears on, and the
// distinct top releases are hydrated through ReleaseByMBID (cached and paced),
// so the engine scores full tracklists as with any other candidate. A 400 (bad
// lucene edge case) or 404 is a clean miss.
func (m *MusicBrainz) SearchRecordings(ctx context.Context, artist, title string) ([]*match.Release, error) {
	if strings.TrimSpace(title) == "" {
		return nil, nil
	}
	query := "recording:" + luceneQuote(title)
	if artist != "" {
		query += " AND artist:" + luceneQuote(artist)
	}
	q := url.Values{}
	q.Set("query", query)
	q.Set("fmt", "json")
	q.Set("limit", "8")
	u := m.base + "/recording?" + q.Encode()
	body, status, err := m.core.get(ctx, u, m.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusBadRequest, http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: musicbrainz recording search: status %d", status)
	}
	var parsed struct {
		Recordings []struct {
			Releases []struct {
				ID string `json:"id"`
			} `json:"releases"`
		} `json:"recordings"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode musicbrainz recording search: %w", err)
	}
	// Collect distinct release ids in hit order, capped so one loose track never
	// fans out into a page of hydration calls.
	var ids []string
	seen := make(map[string]bool)
	for _, rec := range parsed.Recordings {
		for _, rel := range rec.Releases {
			if rel.ID == "" || seen[rel.ID] {
				continue
			}
			seen[rel.ID] = true
			ids = append(ids, rel.ID)
			if len(ids) >= 5 {
				break
			}
		}
		if len(ids) >= 5 {
			break
		}
	}
	var out []*match.Release
	for _, id := range ids {
		rel, err := m.ReleaseByMBID(ctx, id)
		if err != nil {
			if ctx.Err() != nil {
				return nil, fmt.Errorf("providers: musicbrainz recording hydration: %w", ctx.Err())
			}
			continue
		}
		if rel != nil {
			out = append(out, rel)
		}
	}
	return out, nil
}

// ReleaseMBIDsForRecording answers the releases an announced artist and
// title sit on, best first, or nothing when the search matched nothing.
//
// A search rather than SearchRecordings, deliberately: that one hydrates
// up to five releases to build full candidates, which is five more paced
// round trips than a cover needs. This reads the release ids the search
// already returned and costs one request.
//
// Several rather than one, because having a release is not having a
// picture of it: the caller asks the archive in this order and stops at
// the first that answers.
//
// Ranked rather than taken in search order, which is what the index
// happened to store and puts compilations first about as often as not -
// so a song on the radio drew a greatest-hits sleeve it was never
// released on. Album, then single, then the rest, compilations behind
// their own kind; the search order breaks ties, so the best-matching
// recording still wins between two releases of the same kind.
func (m *MusicBrainz) ReleaseMBIDsForRecording(ctx context.Context, artist, title string) ([]string, error) {
	if strings.TrimSpace(title) == "" {
		return nil, nil
	}
	query := "recording:" + luceneQuote(title)
	if artist != "" {
		query += " AND artist:" + luceneQuote(artist)
	}
	q := url.Values{}
	q.Set("query", query)
	q.Set("fmt", "json")
	q.Set("limit", "3")
	body, status, err := m.core.get(ctx, m.base+"/recording?"+q.Encode(), m.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusBadRequest, http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: musicbrainz recording search: status %d", status)
	}
	// The search index embeds each release's group inline, types
	// included, so the ranking below costs no extra request.
	var parsed struct {
		Recordings []struct {
			Releases []struct {
				ID           string          `json:"id"`
				ReleaseGroup *mbReleaseGroup `json:"release-group"`
			} `json:"releases"`
		} `json:"recordings"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode musicbrainz recording search: %w", err)
	}
	type candidate struct {
		id   string
		rank int
	}
	// Every release in the body, not a prefix of it: truncating first
	// would rank whatever the index happened to list early, which is the
	// ordering this exists to distrust - a song on two dozen compilations
	// would fill the cut and the album behind them would never be seen.
	// The body is already read and capped, so this costs nothing upstream.
	seen := map[string]bool{}
	var pool []candidate
	for _, rec := range parsed.Recordings {
		for _, rel := range rec.Releases {
			if rel.ID == "" || seen[rel.ID] {
				continue
			}
			seen[rel.ID] = true
			pool = append(pool, candidate{rel.ID, coverReleaseRank(rel.ReleaseGroup)})
		}
	}
	slices.SortStableFunc(pool, func(a, b candidate) int { return a.rank - b.rank })
	walk := pool[:min(len(pool), maxCoverReleases)]
	out := make([]string, len(walk))
	for i, c := range walk {
		out[i] = c.id
	}
	return out, nil
}

// coverReleaseRank orders one release by how likely it is to carry the
// picture somebody means by this song: album, single, then everything
// else, with compilations behind their own kind. An unknown or absent
// group ranks with the rest rather than being dropped - a release with
// a cover is still a cover.
func coverReleaseRank(rg *mbReleaseGroup) int {
	if rg == nil {
		return 2
	}
	rank := 2
	switch {
	case strings.EqualFold(rg.PrimaryType, "Album"):
		rank = 0
	case strings.EqualFold(rg.PrimaryType, "Single"):
		rank = 1
	}
	if isCompilation(rg.SecondaryTypes) {
		rank += 3
	}
	return rank
}

func isCompilation(secondaryTypes []string) bool {
	return slices.ContainsFunc(secondaryTypes, func(st string) bool {
		return strings.EqualFold(st, "Compilation")
	})
}

// maxCoverReleases bounds how many of a recording's releases are worth
// asking the archive about.
//
// More than one because a recording is on many releases and only some
// carry art: a single is routinely entered twice, once for the digital
// release nobody uploaded a sleeve for and once for the album that has
// one. Taking the first and stopping is why a current chart track drew
// nothing while its cover sat in the archive one release along. Bounded
// because the tail is long and each miss is another paced request.
const maxCoverReleases = 6

// LookupFingerprint is not a MusicBrainz capability; the composite Source
// routes fingerprints to AcoustID. Returning an error here keeps a bare
// MusicBrainz from silently claiming the whole CandidateSource port.
func (m *MusicBrainz) LookupFingerprint(ctx context.Context, fp match.Fingerprint) ([]match.FingerprintHit, error) {
	return nil, errors.New("providers: fingerprint lookup requires acoustid")
}

// luceneQuote wraps s in a quoted lucene phrase. Inside quotes only the
// backslash and the quote character need escaping.
func luceneQuote(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return `"` + s + `"`
}

// mapMBRelease converts a MusicBrainz release payload to the engine's
// shape. groupMBID overrides the release-group id for browse responses,
// which omit the release-group block.
func mapMBRelease(rel *mbRelease, groupMBID string) *match.Release {
	artist := joinCredit(rel.ArtistCredit)
	out := &match.Release{
		MBID:             rel.ID,
		ReleaseGroupMBID: groupMBID,
		Title:            rel.Title,
		Artist:           artist,
		Year:             yearFromDate(rel.Date),
		Media:            len(rel.Media),
		Country:          rel.Country,
		Barcode:          rel.Barcode,
		Compilation:      strings.EqualFold(artist, "Various Artists"),
	}
	if rel.ReleaseGroup != nil {
		if out.ReleaseGroupMBID == "" {
			out.ReleaseGroupMBID = rel.ReleaseGroup.ID
		}
		if out.Year == 0 {
			out.Year = yearFromDate(rel.ReleaseGroup.FirstReleaseDate)
		}
		if isCompilation(rel.ReleaseGroup.SecondaryTypes) {
			out.Compilation = true
		}
	}
	if len(rel.LabelInfo) > 0 {
		out.CatalogNumber = rel.LabelInfo[0].CatalogNumber
		if rel.LabelInfo[0].Label != nil {
			out.Label = rel.LabelInfo[0].Label.Name
		}
	}
	for di, medium := range rel.Media {
		for _, tr := range medium.Tracks {
			rt := match.ReleaseTrack{
				Title:    tr.Title,
				Disc:     di + 1,
				Position: tr.Position,
			}
			length := tr.Length
			if tr.Recording != nil {
				rt.RecordingMBID = tr.Recording.ID
				if length == nil {
					length = tr.Recording.Length
				}
			}
			if length != nil {
				rt.DurationSec = float64(*length) / 1000
			}
			// The track artist is carried only when it differs from the
			// release artist; the engine treats empty as "same artist".
			if ta := joinCredit(tr.ArtistCredit); ta != artist {
				rt.Artist = ta
			}
			out.Tracks = append(out.Tracks, rt)
		}
	}
	return out
}

// joinCredit renders an artist-credit list as MusicBrainz displays it:
// each name followed by its join phrase.
func joinCredit(credits []mbArtistCredit) string {
	var b strings.Builder
	for _, c := range credits {
		b.WriteString(c.Name)
		b.WriteString(c.JoinPhrase)
	}
	return b.String()
}

// yearFromDate extracts the leading four-digit year of a MusicBrainz
// date ("1997", "1997-01-20"); 0 when absent or malformed.
func yearFromDate(d string) int {
	if len(d) < 4 {
		return 0
	}
	y, err := strconv.Atoi(d[:4])
	if err != nil || y <= 0 {
		return 0
	}
	return y
}
