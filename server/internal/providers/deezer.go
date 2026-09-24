package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// DeezerConfig configures the Deezer cover provider. Zero values take
// the documented defaults.
type DeezerConfig struct {
	// BaseURL defaults to "https://api.deezer.com" (key-free API).
	BaseURL string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 500ms.
	MinInterval time.Duration
	// CacheTTL defaults to 24h.
	CacheTTL time.Duration
}

// Deezer supplies release-group cover art from its album search, a
// release's own cover by barcode, and artist portraits from its artist
// search. The by-name answers are gated on a name match.
type Deezer struct {
	base      string
	ttl       time.Duration
	core      *core
	quotaWait time.Duration
}

// NewDeezer builds a provider from cfg, applying defaults for zero
// fields.
func NewDeezer(cfg DeezerConfig) *Deezer {
	base := cfg.BaseURL
	if base == "" {
		base = "https://api.deezer.com"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = defaultEnrichInterval
	}
	ttl := cfg.CacheTTL
	if ttl == 0 {
		ttl = defaultEnrichTTL
	}
	return &Deezer{
		base:      strings.TrimRight(base, "/"),
		ttl:       ttl,
		core:      newCore(cfg.HTTPClient, ua, interval),
		quotaWait: deezerQuotaWindow,
	}
}

// deezerQuotaWindow is how long Deezer's request quota counts back.
const deezerQuotaWindow = 5 * time.Second

// Name is the stable provenance id.
func (d *Deezer) Name() string { return "deezer" }

// Capabilities reports the front cover, artist art, and scalar fields.
//
// Not CapAuxArt: Deezer serves one picture per album and one per
// artist, so it has nothing to put in a back, disc, or booklet slot.
//
// Not CapGenres either, and that is a decision rather than a gap.
// Deezer's genre names live behind a request per genre group, so
// answering the genre rung would cost a lookup apiece on top of the
// album fetch, and Discogs already owns genres in the chain ahead of
// the built-ins.
func (d *Deezer) Capabilities() enrich.Capability {
	return enrich.CapCover | enrich.CapArtistArt | enrich.CapFields
}

// Enrich answers a release-group cover, an artist portrait, or the
// scalar fields of one album or one track - each from its own lookup
// and each gated on an identifier or a name match.
func (d *Deezer) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	switch req.Type {
	case enrich.TargetReleaseGroup:
		if !req.Wants(capabilityForArtRole(req.Type, model.ArtRoleFront)) {
			return nil, nil
		}
		return d.enrichReleaseGroup(ctx, req)
	case enrich.TargetArtist:
		// The front mask, not CapArtistArt alone: the identity phase
		// asks about an artist through the cover pass, so reading only
		// the backfill's own bit would answer nothing on the path a
		// stock install actually runs.
		if !req.Wants(capabilityForArtRole(req.Type, model.ArtRoleFront)) {
			return nil, nil
		}
		return d.enrichArtist(ctx, req)
	case enrich.TargetRelease:
		art := req.Wants(capabilityForArtRole(req.Type, model.ArtRoleFront))
		fields := req.Wants(enrich.CapFields)
		if !art && !fields {
			return nil, nil
		}
		return d.enrichRelease(ctx, req, art, fields)
	case enrich.TargetRecording:
		if !req.Wants(enrich.CapFields) {
			return nil, nil
		}
		return d.enrichRecordingFields(ctx, req)
	default:
		return nil, nil
	}
}

// enrichRelease answers an album's cover, from its barcode alone (a title
// search names a record, not a pressing), and its label and year, from the
// barcode or else the album search.
func (d *Deezer) enrichRelease(ctx context.Context, req enrich.Request, art, fields bool) (*enrich.Candidate, error) {
	album, err := d.upcAlbum(ctx, req.Barcode)
	if err != nil {
		return nil, err
	}
	cand := &enrich.Candidate{Confidence: 0.7}
	var coverErr error
	if art && album != nil && deezerPicture(album.CoverXL) {
		// A picture that will not load is not the fields' problem.
		data, mediaType, err := fetchImage(ctx, d.core, album.CoverXL)
		if err != nil {
			coverErr = err
		} else {
			cand.Cover = coverImage(data, mediaType, album.CoverXL)
		}
	}
	if fields {
		if album == nil {
			if album, err = d.searchAlbum(ctx, req); err != nil {
				return nil, err
			}
		}
		if album != nil {
			cand.Fields = map[string]string{}
			if label := strings.TrimSpace(album.Label); label != "" {
				cand.Fields["label"] = label
			}
			if year := releaseYear(album.ReleaseDate); year != "" {
				cand.Fields["year"] = year
			}
		}
	}
	if cand.Cover == nil && len(cand.Fields) == 0 {
		return nil, coverErr
	}
	return cand, nil
}

// deezerPicture reports whether a Deezer image URL names a picture: where it
// holds none it names a stand-in, a path with no image hash in it.
func deezerPicture(rawURL string) bool {
	u, err := url.Parse(rawURL)
	return err == nil && rawURL != "" && !strings.Contains(u.Path, "//")
}

// deezerAlbum is one album as the album endpoints answer it.
type deezerAlbum struct {
	ID          int64  `json:"id"`
	Label       string `json:"label"`
	ReleaseDate string `json:"release_date"`
	CoverXL     string `json:"cover_xl"`
}

// upcAlbum looks an album up by barcode, nil when Deezer holds none. Deezer
// files an EAN-13 that starts with a zero as its 12-digit UPC, and a code
// that fails its checksum can only miss, so it is not sent.
func (d *Deezer) upcAlbum(ctx context.Context, barcode string) (*deezerAlbum, error) {
	upc, ok := model.NormalizeBarcode(barcode)
	if !ok || upc == "" {
		return nil, nil
	}
	if len(upc) == 13 && upc[0] == '0' {
		upc = upc[1:]
	}
	var hit deezerAlbum
	if err := d.getJSON(ctx, d.base+"/album/upc:"+url.PathEscape(upc), &hit); err != nil {
		return nil, err
	}
	if hit.ID == 0 {
		return nil, nil
	}
	return &hit, nil
}

// searchAlbum finds the album by title and artist, then fetches it: a
// search hit carries no label or release date, where the UPC endpoint
// answers the album itself in one request.
func (d *Deezer) searchAlbum(ctx context.Context, req enrich.Request) (*deezerAlbum, error) {
	if req.Title == "" {
		return nil, nil
	}
	query := `album:"` + req.Title + `"`
	if req.Artist != "" {
		query = `artist:"` + req.Artist + `" ` + query
	}
	q := url.Values{}
	q.Set("q", query)
	var parsed struct {
		Data []struct {
			ID     int64  `json:"id"`
			Title  string `json:"title"`
			Artist struct {
				Name string `json:"name"`
			} `json:"artist"`
		} `json:"data"`
	}
	if err := d.getJSON(ctx, d.base+"/search/album?"+q.Encode(), &parsed); err != nil {
		return nil, err
	}
	for _, hit := range parsed.Data {
		if hit.ID == 0 || !nameMatch(hit.Title, req.Title) {
			continue
		}
		if req.Artist != "" && !nameMatch(hit.Artist.Name, req.Artist) {
			continue
		}
		var album deezerAlbum
		if err := d.getJSON(ctx, fmt.Sprintf("%s/album/%d", d.base, hit.ID), &album); err != nil {
			return nil, err
		}
		return &album, nil
	}
	return nil, nil
}

// deezerDurationSlack is how far a search hit's length may sit from the
// catalog's and still be the same recording. Wide enough for a tagged
// duration rounded to the second and a store's own rounding, narrow
// enough to reject an edit or a live take of the same title.
const deezerDurationSlack = 2

// enrichRecordingFields answers a track's tempo and ISRC. Keyed on the
// ISRC when the catalog holds one, since that names the recording
// outright; otherwise a track search matched on artist, title, and
// duration, because a title alone selects the wrong take routinely.
//
// Composer is in the fill set and Deezer does not carry one, so it is
// simply absent from the answer rather than guessed at.
func (d *Deezer) enrichRecordingFields(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	track, err := d.recordingTrack(ctx, req)
	if err != nil || track == nil {
		return nil, err
	}
	fields := map[string]string{}
	// Deezer reports 0 for a track it has not analyzed, which is not a
	// tempo; writing it would put a false zero where nothing was known.
	// The value is a float on the wire and a whole number in the
	// catalog, which refuses a fraction outright rather than rounding a
	// number nobody typed - so it is rounded here, where the rounding is
	// a fact about the transport rather than about the listener.
	if track.BPM > 0 {
		fields["bpm"] = strconv.Itoa(int(math.Round(track.BPM)))
	}
	if isrc := strings.TrimSpace(track.ISRC); isrc != "" {
		fields["isrc"] = isrc
	}
	if len(fields) == 0 {
		return nil, nil
	}
	return &enrich.Candidate{Confidence: 0.7, Fields: fields}, nil
}

// deezerTrack is one track as the track endpoints answer it.
type deezerTrack struct {
	ID   int64   `json:"id"`
	BPM  float64 `json:"bpm"`
	ISRC string  `json:"isrc"`
}

// recordingTrack resolves the Deezer track this request names, with the
// fields already on it. The ISRC endpoint answers the track itself, so
// an identifier costs one request; see releaseAlbum.
func (d *Deezer) recordingTrack(ctx context.Context, req enrich.Request) (*deezerTrack, error) {
	if isrc := strings.TrimSpace(req.ISRC); isrc != "" {
		var hit deezerTrack
		if err := d.getJSON(ctx, d.base+"/track/isrc:"+url.PathEscape(isrc), &hit); err != nil {
			return nil, err
		}
		if hit.ID != 0 {
			return &hit, nil
		}
	}
	if req.Title == "" || req.Artist == "" {
		// A bare title names too many recordings for a by-name match to
		// be worth a write.
		return nil, nil
	}
	q := url.Values{}
	q.Set("q", `artist:"`+req.Artist+`" track:"`+req.Title+`"`)
	var parsed struct {
		Data []struct {
			ID       int64  `json:"id"`
			Title    string `json:"title"`
			Duration int    `json:"duration"`
			Artist   struct {
				Name string `json:"name"`
			} `json:"artist"`
		} `json:"data"`
	}
	if err := d.getJSON(ctx, d.base+"/search/track?"+q.Encode(), &parsed); err != nil {
		return nil, err
	}
	for _, hit := range parsed.Data {
		if hit.ID == 0 || !nameMatch(hit.Title, req.Title) || !nameMatch(hit.Artist.Name, req.Artist) {
			continue
		}
		if req.DurationSec > 0 && abs(hit.Duration-req.DurationSec) > deezerDurationSlack {
			continue
		}
		// The search hit carries neither tempo nor identifier, so this
		// rung does pay the second request.
		var track deezerTrack
		if err := d.getJSON(ctx, fmt.Sprintf("%s/track/%d", d.base, hit.ID), &track); err != nil {
			return nil, err
		}
		return &track, nil
	}
	return nil, nil
}

// getJSON fetches and decodes one paced Deezer read; see deezerRead.
func (d *Deezer) getJSON(ctx context.Context, u string, out any) error {
	body, err := d.deezerRead(ctx, u)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("providers: decode deezer read: %w", err)
	}
	return nil
}

// deezerRead refuses the failure Deezer answers with a 200. The catalog records
// any failure as a miss for its retry window, so a quota window is waited out
// once, and a failure is dropped from the cache rather than replayed.
func (d *Deezer) deezerRead(ctx context.Context, u string) ([]byte, error) {
	for waited := false; ; waited = true {
		body, status, err := d.core.get(ctx, u, d.ttl)
		if err != nil {
			return nil, err
		}
		if status != http.StatusOK {
			return nil, fmt.Errorf("providers: deezer read: status %d", status)
		}
		f := deezerError(body)
		if f == nil {
			return body, nil
		}
		d.core.forget(u)
		if waited || f.Code != deezerQuotaCode {
			return nil, f
		}
		t := time.NewTimer(d.quotaWait)
		select {
		case <-ctx.Done():
			t.Stop()
			return nil, ctx.Err()
		case <-t.C:
		}
	}
}

// deezerFailure is the error object of a failed read.
type deezerFailure struct {
	Type    string `json:"type"`
	Message string `json:"message"`
	Code    int    `json:"code"`
}

func (f *deezerFailure) Error() string {
	return "providers: deezer: " + f.Type + ": " + f.Message
}

// deezerQuotaCode is the code Deezer's request quota answers with.
const deezerQuotaCode = 4

// deezerError reads an in-band failure. An unknown UPC or ISRC arrives the
// same way and passes, the caller's empty id being the miss.
func deezerError(body []byte) *deezerFailure {
	var env struct {
		Error *deezerFailure `json:"error"`
	}
	if json.Unmarshal(body, &env) != nil || env.Error == nil {
		return nil
	}
	if env.Error.Type == deezerDataException {
		// "No data" for the identifier this asked about: a miss, and
		// the caller's zero id says so.
		return nil
	}
	return env.Error
}

// deezerDataException is the error type Deezer answers an unknown
// identifier with, as opposed to a quota or authentication failure.
const deezerDataException = "DataException"

// enrichReleaseGroup searches Deezer albums by artist and title, takes
// the first hit whose names match, and fetches its extra-large cover.
func (d *Deezer) enrichReleaseGroup(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Title == "" {
		return nil, nil
	}
	query := `album:"` + req.Title + `"`
	if req.Artist != "" {
		query = `artist:"` + req.Artist + `" ` + query
	}
	q := url.Values{}
	q.Set("q", query)
	var parsed struct {
		Data []struct {
			Title   string `json:"title"`
			CoverXL string `json:"cover_xl"`
			Artist  struct {
				Name string `json:"name"`
			} `json:"artist"`
		} `json:"data"`
	}
	if err := d.getJSON(ctx, d.base+"/search/album?"+q.Encode(), &parsed); err != nil {
		return nil, err
	}
	for _, hit := range parsed.Data {
		if !deezerPicture(hit.CoverXL) || !nameMatch(hit.Title, req.Title) {
			continue
		}
		if req.Artist != "" && !nameMatch(hit.Artist.Name, req.Artist) {
			continue
		}
		data, mediaType, err := fetchImage(ctx, d.core, hit.CoverXL)
		if err != nil {
			return nil, err
		}
		return &enrich.Candidate{
			Confidence: 0.7,
			Cover:      coverImage(data, mediaType, hit.CoverXL),
		}, nil
	}
	return nil, nil
}

// enrichArtist answers an artist portrait by name. The engine puts the
// artist's name in Artist rather than Title for this target, and the
// match is the same exact-ish fold the sweep uses: a by-name face lands
// catalog-wide, so a near miss is no answer at all. Compilation and
// unknown-artist stand-ins are refused outright, because Deezer holds
// real pages under several of them and a stranger's portrait would end
// up on every compilation in the library.
//
// The portrait lands under the front role. Upstream's art model gives
// an artist no separate portrait slot, and front is what both artist
// read surfaces resolve.
func (d *Deezer) enrichArtist(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	name := req.Artist
	if name == "" {
		name = req.Title
	}
	if name == "" || ArtistNamePlaceholder(name) {
		return nil, nil
	}
	res, err := d.ArtistImage(ctx, name)
	if err != nil {
		if errors.Is(err, ErrNoArtistImage) {
			return nil, nil
		}
		return nil, err
	}
	img := coverImage(res.Data, res.MIME, res.SourceURL)
	if img == nil {
		return nil, nil
	}
	return &enrich.Candidate{
		Confidence: 0.7,
		Art:        map[model.ArtRole]*model.ArtImage{model.ArtRoleFront: img},
	}, nil
}

// maxTitleCoverBytes bounds one cover fetched for an announced title.
// The shared image cap is 8 MiB, which is a lot to leave resident in a
// cache keyed by what a station chose to announce.
const maxTitleCoverBytes = 2 << 20

// FrontCover answers a cover for an announced artist and title, from the
// album the track belongs to. A track search rather than Enrich's album
// search, and both names matched: a wrong cover is worse than none.
func (d *Deezer) FrontCover(ctx context.Context, artist, title string) (TitleCoverResult, error) {
	if artist == "" || title == "" {
		return TitleCoverResult{}, ErrNoCover
	}
	q := url.Values{}
	q.Set("q", `artist:"`+artist+`" track:"`+title+`"`)
	var parsed struct {
		Data []struct {
			Title  string `json:"title"`
			Artist struct {
				Name string `json:"name"`
			} `json:"artist"`
			Album struct {
				CoverBig string `json:"cover_big"`
			} `json:"album"`
		} `json:"data"`
	}
	if err := d.getJSON(ctx, d.base+"/search?"+q.Encode(), &parsed); err != nil {
		return TitleCoverResult{}, err
	}
	// A song is routinely listed several times over - a single, an album,
	// a deluxe edition - so one unusable cover is not the end of the walk.
	var reachErr error
	for _, hit := range parsed.Data {
		if !deezerPicture(hit.Album.CoverBig) ||
			!coverNameMatch(hit.Artist.Name, artist) ||
			!coverNameMatch(hit.Title, title) {
			continue
		}
		data, _, err := fetchImage(ctx, d.core, hit.Album.CoverBig)
		if err != nil {
			reachErr = err
			continue
		}
		// The type comes from the bytes, not the header - these are served
		// from WaxDeck's own origin - and both refusals are facts about
		// this picture, so neither counts as Deezer being unreachable.
		mime, ok := coverArtMimes[http.DetectContentType(data)]
		if !ok || len(data) > maxTitleCoverBytes {
			continue
		}
		return TitleCoverResult{
			Data: data, MIME: mime,
			Provider:  d.Name(),
			SourceURL: hit.Album.CoverBig,
		}, nil
	}
	if reachErr != nil {
		return TitleCoverResult{}, reachErr
	}
	return TitleCoverResult{}, ErrNoCover
}

// ForgetMisses drops the track searches this rung cached, built as they
// are from strings a station announced. Enrichment's album searches go
// through the same client and are not the radio toggle's to clear.
func (d *Deezer) ForgetMisses() { d.core.forgetPrefix(d.base + "/search?") }
