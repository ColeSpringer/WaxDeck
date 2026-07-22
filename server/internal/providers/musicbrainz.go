package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
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
		for _, st := range rel.ReleaseGroup.SecondaryTypes {
			if strings.EqualFold(st, "Compilation") {
				out.Compilation = true
			}
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
