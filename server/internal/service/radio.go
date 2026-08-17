package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/oklog/ulid/v2"
	"golang.org/x/text/language"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// RadioStation is the API-facing station shape.
type RadioStation struct {
	PID         string
	Name        string
	StreamURL   string
	HomepageURL string
	LogoURL     string
	CreatedAt   time.Time
}

// RadioStationEdit is the create and update request.
type RadioStationEdit struct {
	Name        string
	StreamURL   string
	HomepageURL string
	LogoURL     string
}

// RadioDirectoryEntry is one station directory match.
type RadioDirectoryEntry struct {
	Name        string
	StreamURL   string
	HomepageURL string
	LogoURL     string
	Tags        string
	Country     string
	// CountryCode is the directory's ISO 3166-1 alpha-2 code, used to
	// rank a listener's own country first. Country is the display name
	// ("The Netherlands") and cannot do that job: matching it against a
	// BCP 47 region subtag would need a name table, which is a worse
	// answer than reading the code the directory already sends. Not on
	// the wire; ranking happens here.
	CountryCode string
	Codec       string
	BitrateKbps int
}

// defaultRadioDirectoryBase is the public radio-browser instance.
const defaultRadioDirectoryBase = "https://all.api.radio-browser.info"

// RadioStations lists the shared station library.
func (l *Library) RadioStations(ctx context.Context) ([]RadioStation, error) {
	rows, err := l.db.ListRadioStations(ctx)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]RadioStation, 0, len(rows))
	for _, r := range rows {
		out = append(out, radioStationDTO(r))
	}
	return out, nil
}

// RadioStationByPID reads one station.
func (l *Library) RadioStationByPID(ctx context.Context, apiStationPID string) (RadioStation, error) {
	row, err := l.radioStationRow(ctx, apiStationPID)
	if err != nil {
		return RadioStation{}, err
	}
	return radioStationDTO(row), nil
}

// CreateRadioStation adds a station to the shared library.
func (l *Library) CreateRadioStation(ctx context.Context, uc *UserCtx, edit RadioStationEdit) (RadioStation, error) {
	row, err := l.validateStationEdit(ctx, edit)
	if err != nil {
		return RadioStation{}, err
	}
	row.ID = ulid.Make().String()
	row.CreatedBy = uc.ID
	row.CreatedAtNS = time.Now().UnixNano()
	if err := l.db.CreateRadioStation(ctx, row); err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return RadioStation{}, &Error{Kind: KindConflict, Msg: "a station with this stream URL already exists, or the station cap is reached"}
		}
		return RadioStation{}, &Error{Kind: KindInternal, Err: err}
	}
	return radioStationDTO(row), nil
}

// UpdateRadioStation replaces a station's fields.
func (l *Library) UpdateRadioStation(ctx context.Context, apiStationPID string, edit RadioStationEdit) (RadioStation, error) {
	existing, err := l.radioStationRow(ctx, apiStationPID)
	if err != nil {
		return RadioStation{}, err
	}
	row, err := l.validateStationEdit(ctx, edit)
	if err != nil {
		return RadioStation{}, err
	}
	row.ID = existing.ID
	row.CreatedBy = existing.CreatedBy
	row.CreatedAtNS = existing.CreatedAtNS
	if err := l.db.UpdateRadioStation(ctx, row); err != nil {
		switch {
		case errors.Is(err, wdb.ErrNotFound):
			return RadioStation{}, errNotFound("no station " + apiStationPID)
		case errors.Is(err, wdb.ErrConflict):
			return RadioStation{}, &Error{Kind: KindConflict, Msg: "a station with this stream URL already exists"}
		}
		return RadioStation{}, &Error{Kind: KindInternal, Err: err}
	}
	// The logo cache is keyed by pid, which an edit does not change, so a
	// new logo URL would be shadowed by a day-old copy of the old one.
	if row.LogoURL != existing.LogoURL {
		l.forgetRadioLogo(apiStationPID)
	}
	return radioStationDTO(row), nil
}

// DeleteRadioStation removes a station.
func (l *Library) DeleteRadioStation(ctx context.Context, apiStationPID string) error {
	row, err := l.radioStationRow(ctx, apiStationPID)
	if err != nil {
		return err
	}
	if err := l.db.DeleteRadioStation(ctx, row.ID); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no station " + apiStationPID)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	// PIDs are ULIDs and never reused, so this reclaims the bytes rather
	// than preventing a stale hit.
	l.forgetRadioLogo(apiStationPID)
	l.forgetRadioTitle(apiStationPID)
	return nil
}

// RadioStreamSource resolves a station's stream URL for the proxy,
// re-validating the URL policy at fetch time (the row may predate a
// policy change).
func (l *Library) RadioStreamSource(ctx context.Context, apiStationPID string) (string, error) {
	row, err := l.radioStationRow(ctx, apiStationPID)
	if err != nil {
		return "", err
	}
	if err := l.validateStreamURL(row.StreamURL); err != nil {
		return "", err
	}
	return row.StreamURL, nil
}

// SearchRadioDirectory queries the public station directory by name,
// then ranks the listener's own country first.
//
// The ranking is a stable partition rather than a `countrycode` filter
// on the query, and the difference matters to someone searching for a
// station they already know: a filter would hide a good foreign match
// entirely, where a partition only moves it down.
// The directory is a volunteer pool of mirrors behind one round-robin
// name, so a single sick mirror used to be the whole feature failing:
// the pooled connection pinned it and every retry landed back on it.
// One search may therefore try a few mirrors before giving up, and a
// mirror that just failed sorts last for a few minutes afterwards.
func (l *Library) SearchRadioDirectory(ctx context.Context, uc *UserCtx, q string, limit int) ([]RadioDirectoryEntry, error) {
	callCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	var (
		raw       []radioDirectoryRow
		answered  bool
		attempts  int
		throttles int
		lastErr   error
		lastCode  int
	)
	for _, base := range l.radioDirectoryMirrors(callCtx) {
		if attempts >= radioMirrorAttempts {
			break
		}
		attempts++
		body, code, err := l.fetchRadioDirectory(callCtx, base, q, limit)
		if err == nil && code == http.StatusOK {
			rows, decodeErr := decodeRadioDirectory(body)
			if decodeErr == nil {
				raw, answered = rows, true
				break
			}
			// A 200 that is not a list of stations is a sick mirror
			// answering rather than an answer: an empty body, an error
			// page, or the JSON literal `null` - which unmarshals
			// cleanly into nothing and would otherwise be reported as
			// "no stations match" while healthy mirrors went unasked.
			err = decodeErr
		}
		// The caller went away. A directory search is typeahead-shaped,
		// so every keystroke cancels the one before it, and the fetch
		// returns instantly with a context error. That says nothing
		// about the mirror it was talking to, and cooling it here would
		// put five healthy hosts at the back of the queue for five
		// minutes because somebody typed five letters.
		if callCtx.Err() != nil {
			break
		}
		// A 4xx that is not a throttle is this request's own fault, and
		// every other mirror would repeat it. Asking them anyway would
		// spend the budget to hear the same no three times.
		if code >= 400 && code < 500 && code != http.StatusTooManyRequests {
			return nil, &Error{Kind: KindDirectory, Msg: fmt.Sprintf("the station directory answered status %d", code)}
		}
		lastErr, lastCode = err, code
		if code == http.StatusTooManyRequests || code == http.StatusServiceUnavailable {
			throttles++
		}
		l.coolRadioMirror(base)
	}
	if !answered {
		switch {
		// Every mirror asked said it was too busy, which is a different
		// thing from being broken and reads as one to a listener: the
		// wording matches the podcast directory's for the same state.
		case attempts > 0 && throttles == attempts:
			return nil, &Error{Kind: KindDirectory, Msg: "the station directory is busy; try again shortly", Err: lastErr}
		// Only a status worth printing. A mirror that answered 200 with
		// something that is not a list of stations lands here too, and
		// "the station directory answered status 200" tells a listener
		// nothing at all.
		case lastCode >= 400:
			return nil, &Error{Kind: KindDirectory, Msg: fmt.Sprintf("the station directory answered status %d", lastCode), Err: lastErr}
		default:
			return nil, &Error{Kind: KindDirectory, Msg: "the station directory could not be reached", Err: lastErr}
		}
	}
	out := make([]RadioDirectoryEntry, 0, len(raw))
	for _, r := range raw {
		stream := r.URLResolved
		if stream == "" {
			stream = r.URL
		}
		if stream == "" || r.Name == "" {
			continue
		}
		out = append(out, RadioDirectoryEntry{
			Name:        r.Name,
			StreamURL:   stream,
			HomepageURL: r.Homepage,
			LogoURL:     r.Favicon,
			Tags:        r.Tags,
			Country:     r.Country,
			CountryCode: r.CountryCode,
			Codec:       r.Codec,
			BitrateKbps: r.Bitrate,
		})
	}
	rankRadioByRegion(out, l.listenerRegion(ctx, uc))
	return out, nil
}

// radioDirectoryRow is one station as the directory sends it.
type radioDirectoryRow struct {
	Name        string `json:"name"`
	URL         string `json:"url"`
	URLResolved string `json:"url_resolved"`
	Homepage    string `json:"homepage"`
	Favicon     string `json:"favicon"`
	Tags        string `json:"tags"`
	Country     string `json:"country"`
	CountryCode string `json:"countrycode"`
	Codec       string `json:"codec"`
	Bitrate     int    `json:"bitrate"`
}

// decodeRadioDirectory parses a mirror's answer, refusing anything that
// is not a list. A nil result is the refusal that matters: `null` decodes
// without error into no rows at all, and reporting that as an empty
// search would turn one sick mirror into "there are no jazz stations".
func decodeRadioDirectory(body []byte) ([]radioDirectoryRow, error) {
	var rows []radioDirectoryRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if rows == nil {
		return nil, errors.New("the directory answered no list of stations")
	}
	return rows, nil
}

const (
	// radioMirrorAttempts bounds one search's mirror hops.
	radioMirrorAttempts = 3
	// radioMirrorTimeout is one mirror's slice of the search budget, and
	// the two multiply to fit inside it: three hops at three seconds sit
	// under the ten-second budget, where the five seconds this first had
	// meant two hanging mirrors spent the whole thing and the third
	// attempt returned instantly on a dead context. A healthy mirror
	// answers a name search in well under a second.
	radioMirrorTimeout = 3 * time.Second
	// radioMirrorLookupTimeout bounds SRV discovery, which happens at
	// most hourly and must not eat a search's budget when DNS is slow.
	radioMirrorLookupTimeout = 2 * time.Second
	// radioMirrorTTL is how long discovered mirrors are reused.
	radioMirrorTTL = time.Hour
	// radioMirrorFailTTL is how long a resolver that could not answer is
	// remembered. Some networks drop SRV entirely, and without a
	// negative memory every search on such a host would spend the whole
	// lookup budget before falling back to the round-robin name -- a
	// permanent tax on the feature this change exists to speed up.
	// Shorter than the positive TTL, since DNS coming back is ordinary.
	radioMirrorFailTTL = 5 * time.Minute
	// radioMirrorCooldown is how long a failed mirror sorts last.
	radioMirrorCooldown = 5 * time.Minute
	// radioDirectorySRVName is the directory's mirror-discovery record.
	// Its targets are the per-mirror hostnames, which is what makes
	// rotation possible at all: they carry their own valid certificates,
	// where the round-robin name in defaultRadioDirectoryBase resolves
	// to a set this process cannot steer within.
	radioDirectorySRVName = "radio-browser.info"
)

// fetchRadioDirectory asks one mirror. It answers the body, the status
// it answered with (zero when it answered nothing), and the error that
// says which of those happened.
func (l *Library) fetchRadioDirectory(ctx context.Context, base, q string, limit int) ([]byte, int, error) {
	u := base + "/json/stations/search?" + url.Values{
		"name":       {q},
		"limit":      {fmt.Sprint(limit)},
		"hidebroken": {"true"},
		"order":      {"votes"},
		"reverse":    {"true"},
	}.Encode()
	callCtx, cancel := context.WithTimeout(ctx, radioMirrorTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(callCtx, http.MethodGet, u, nil)
	if err != nil {
		return nil, 0, err
	}
	// The directory asks clients to identify themselves.
	req.Header.Set("User-Agent", "WaxDeck")
	resp, err := l.radioClient().Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, resp.StatusCode, fmt.Errorf("the station directory answered status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, resp.StatusCode, err
	}
	return body, resp.StatusCode, nil
}

// radioDirectoryMirrors answers the bases one search may try, best
// first. A configured base answers alone; otherwise the mirrors are
// shuffled so a household spreads its load, and the ones that recently
// failed sort last.
func (l *Library) radioDirectoryMirrors(ctx context.Context) []string {
	if base := strings.TrimRight(l.radioDirectoryBase, "/"); base != "" {
		return []string{base}
	}
	bases := l.radioDirectoryMirrorList
	if len(bases) == 0 {
		bases = l.discoverRadioMirrors(ctx)
	}
	if len(bases) == 0 {
		// DNS said nothing useful, so the round-robin name is still
		// there: no mirrors discovered leaves the old behaviour exactly
		// as it was rather than leaving the feature with no host.
		return []string{defaultRadioDirectoryBase}
	}
	out := make([]string, 0, len(bases))
	for _, base := range bases {
		if base = strings.TrimRight(base, "/"); base != "" {
			out = append(out, base)
		}
	}
	rand.Shuffle(len(out), func(i, j int) { out[i], out[j] = out[j], out[i] })
	cold := l.coldRadioMirrors()
	sort.SliceStable(out, func(i, j int) bool { return !cold[out[i]] && cold[out[j]] })
	return out
}

// discoverRadioMirrors resolves the directory's mirror hostnames, reusing
// the last answer for an hour so a dial full of searches costs one lookup.
func (l *Library) discoverRadioMirrors(ctx context.Context) []string {
	l.radioMirrorsMu.Lock()
	// Both answers are cached, and the empty one for less time: the
	// question is "have we asked lately", not "did we like the reply".
	ttl := radioMirrorTTL
	if len(l.radioMirrors) == 0 {
		ttl = radioMirrorFailTTL
	}
	if !l.radioMirrorsAt.IsZero() && time.Since(l.radioMirrorsAt) < ttl {
		cached := append([]string(nil), l.radioMirrors...)
		l.radioMirrorsMu.Unlock()
		return cached
	}
	l.radioMirrorsMu.Unlock()

	lookupCtx, cancel := context.WithTimeout(ctx, radioMirrorLookupTimeout)
	defer cancel()
	var bases []string
	if _, addrs, err := net.DefaultResolver.LookupSRV(lookupCtx, "api", "tcp", radioDirectorySRVName); err == nil {
		bases = radioMirrorBases(addrs)
	}
	// A search is typeahead-shaped, so the caller going away cancels the
	// lookup instantly and says nothing whatever about DNS. Caching that
	// as "there are no mirrors" would pin the round-robin name for the
	// next five minutes - the pinned-sick-mirror failure this whole path
	// exists to end. The attempt loop already refuses to cool a mirror
	// for the same reason.
	if ctx.Err() != nil {
		l.radioMirrorsMu.Lock()
		cached := append([]string(nil), l.radioMirrors...)
		l.radioMirrorsMu.Unlock()
		return cached
	}
	l.radioMirrorsMu.Lock()
	// A resolver that stopped answering does not un-discover the mirrors
	// it named an hour ago: those are stable hostnames, and holding them
	// beats falling back to the one name they exist to replace. Only a
	// cache with nothing in it records the empty answer.
	if len(bases) > 0 || len(l.radioMirrors) == 0 {
		l.radioMirrors = bases
	}
	l.radioMirrorsAt = time.Now()
	cached := append([]string(nil), l.radioMirrors...)
	l.radioMirrorsMu.Unlock()
	return cached
}

// radioMirrorBases turns SRV targets into directory bases. The port the
// record carries is deliberately ignored: the mirrors serve HTTPS on the
// default port, and a record advertising anything else would only get a
// certificate mismatch.
func radioMirrorBases(addrs []*net.SRV) []string {
	out := make([]string, 0, len(addrs))
	for _, a := range addrs {
		host := strings.TrimSuffix(a.Target, ".")
		if host == "" {
			continue
		}
		out = append(out, "https://"+host)
	}
	return out
}

// coolRadioMirror sorts a mirror last for the next few minutes.
func (l *Library) coolRadioMirror(base string) {
	l.radioMirrorsMu.Lock()
	defer l.radioMirrorsMu.Unlock()
	if l.radioMirrorCold == nil {
		l.radioMirrorCold = map[string]time.Time{}
	}
	l.radioMirrorCold[base] = time.Now().Add(radioMirrorCooldown)
}

// coldRadioMirrors is the set still in cooldown, forgetting the ones that
// have served theirs so the map cannot grow with every mirror ever seen.
func (l *Library) coldRadioMirrors() map[string]bool {
	l.radioMirrorsMu.Lock()
	defer l.radioMirrorsMu.Unlock()
	now := time.Now()
	cold := make(map[string]bool, len(l.radioMirrorCold))
	for base, until := range l.radioMirrorCold {
		if until.After(now) {
			cold[base] = true
			continue
		}
		delete(l.radioMirrorCold, base)
	}
	return cold
}

// listenerRegion is the region subtag of the caller's stored locale, or
// empty when there is not one.
func (l *Library) listenerRegion(ctx context.Context, uc *UserCtx) string {
	if uc == nil {
		return ""
	}
	return regionOfLocale(l.PrefsForUser(ctx, uc.ID).Locale)
}

// regionOfLocale reads the region subtag out of a BCP 47 tag, answering
// empty when the tag does not carry one.
//
// Empty is the common answer and the correct one. A locale is optional,
// and `en` is as valid a tag as `en-US`, so most installs have nothing
// here. What is deliberately not done is inferring: x/text will happily
// resolve `en` to `US` at low confidence, and a listener in Nairobi
// getting American stations first because they picked English is worse
// than the unranked list they had. Only a region the listener actually
// wrote counts, which is what language.Exact means here.
func regionOfLocale(locale string) string {
	if locale == "" {
		return ""
	}
	tag, err := language.Parse(locale)
	if err != nil {
		return ""
	}
	region, conf := tag.Region()
	if conf != language.Exact {
		return ""
	}
	return region.String()
}

// rankRadioByRegion moves stations in the listener's own country to the
// front, in place, keeping the directory's vote order inside each half.
//
// Stability is the whole design. Vote order is the directory's ranking
// and it is a good one; this only says that between two stations the
// directory likes equally, the local one is likelier to be the one meant.
// An empty region leaves the slice untouched, which is exactly the
// behaviour installs had before this existed.
func rankRadioByRegion(entries []RadioDirectoryEntry, region string) {
	if region == "" || len(entries) < 2 {
		return
	}
	local := make([]RadioDirectoryEntry, 0, len(entries))
	rest := make([]RadioDirectoryEntry, 0, len(entries))
	for _, e := range entries {
		if strings.EqualFold(e.CountryCode, region) {
			local = append(local, e)
			continue
		}
		rest = append(rest, e)
	}
	copy(entries, local)
	copy(entries[len(local):], rest)
}

// Logo cache and fetch bounds.
const (
	// radioLogoMaxBytes caps one logo. Directory logos are favicons and
	// small cover squares; anything past this is not a logo, and the
	// read stops rather than buffering whatever a station host sends.
	radioLogoMaxBytes = 512 << 10
	// radioLogoCacheBytes bounds the whole cache. At the 500-station cap
	// with logos in the tens of kilobytes this holds the entire dial;
	// the budget exists so one household's stations cannot be turned
	// into a memory leak by a handful of stations serving 512 KB each.
	radioLogoCacheBytes = 24 << 20
	// radioLogoFreshFor is how long a fetched logo is reused. A station
	// changing its mark is a once-in-years event.
	radioLogoFreshFor = 24 * time.Hour
	// radioLogoMissFreshFor is the same for "this station has no logo we
	// can draw", which is a transient far more often (a host down, a
	// certificate expired), so it is remembered for less.
	radioLogoMissFreshFor = time.Hour
	// radioLogoTimeout bounds one upstream fetch. A logo nobody can get
	// in this long is a monogram; the grid is not waiting on it.
	radioLogoTimeout = 10 * time.Second
)

// RadioLogo is a station logo ready to serve.
type RadioLogo struct {
	Bytes    []byte
	MimeType string
	// ETag is the content-addressed validator, quoted and ready for the
	// header.
	ETag string
}

// radioLogo is one cache entry. Empty Bytes means the station has no
// logo that can be drawn, which is worth remembering too.
type radioLogo struct {
	logo    RadioLogo
	fetched time.Time
}

// freshFor is how long this entry is worth answering from. A miss gets
// the shorter one: it is worth not asking a dead host thirty times a
// paint, and it is not worth an hour of a station's new logo not drawing.
func (e radioLogo) freshFor() time.Duration {
	if len(e.logo.Bytes) == 0 {
		return radioLogoMissFreshFor
	}
	return radioLogoFreshFor
}

// radioLogoMimes are the image types a station logo may be served as,
// keyed by what the station host called it. A station answering
// text/html where a favicon used to be has no logo, and a proxy that
// passed the type through would have clients rendering an error page as
// a picture.
//
// SVG is deliberately absent, and its absence is a security boundary
// rather than a coverage gap. A station's logo URL is attacker-supplied
// in the fullest sense - any account may add a station, pointing
// anywhere - and this endpoint serves the fetched bytes from WaxDeck's
// *own* origin. An SVG opened as a document executes its script in that
// origin, so proxying one would be stored XSS with a public write path
// into it. Sanitizing SVG is a real and unforgiving job (namespaces,
// entities, xlink, CSS, foreignObject) and not one worth doing for a
// decorative favicon: a station whose mark is an SVG draws the monogram,
// which is exactly what a station with no mark draws.
//
// What is left cannot carry script, and the sniff below is what keeps
// that true: this map is only what a host *claimed*, and bytes are
// served under the type they actually are.
var radioLogoMimes = map[string]string{
	"image/jpeg":  "image/jpeg",
	"image/jpg":   "image/jpeg",
	"image/pjpeg": "image/jpeg",
	"image/png":   "image/png",
	"image/webp":  "image/webp",
	"image/gif":   "image/gif",
	// Hosts label favicons every which way; the sniff below decides. The
	// empty key is a host that named no type, which is not a claim of
	// anything, and the sniff still gates what comes back.
	"":                         "",
	"image/x-icon":             "",
	"image/vnd.microsoft.icon": "",
	"application/octet-stream": "",
	"binary/octet-stream":      "",
}

// RadioStationLogo answers a station's logo, fetching it through the
// guarded client the stream proxy uses and caching the result.
//
// Not-found is the answer to every way there is no picture, all cached
// alike: the caller draws a monogram either way, and none of them is
// worth retrying per paint.
func (l *Library) RadioStationLogo(ctx context.Context, apiStationPID string) (RadioLogo, error) {
	row, err := l.radioStationRow(ctx, apiStationPID)
	if err != nil {
		return RadioLogo{}, err
	}
	cached, hit, wait := l.claimRadioLogo(apiStationPID)
	if hit {
		return radioLogoOrNotFound(cached, apiStationPID)
	}
	if wait != nil {
		// Somebody is already asking this host; wait for their answer.
		select {
		case <-wait:
		case <-ctx.Done():
			return RadioLogo{}, errNotFound("no logo for station " + apiStationPID)
		}
		cached, hit, wait = l.claimRadioLogo(apiStationPID)
		if hit {
			return radioLogoOrNotFound(cached, apiStationPID)
		}
		// One wait is the limit: the fetch waited on stored nothing because
		// its caller went away, and queueing behind a chain of those would
		// report a logo missing that is not. Falls through owning nothing.
	}
	if wait == nil {
		defer l.endRadioLogoFetch(apiStationPID)
	}
	// A station whose row names no logo is not a station with no logo:
	// every By-URL add and every directory entry whose favicon was
	// blank, SVG, or dead arrives this way, which is most of them. Go
	// and look before answering the monogram. The result is cached like
	// any other, so the search happens once per station per refresh
	// window rather than per paint.
	// Read once, before the branch. Tested and then read again, a
	// listener opening the stream between the two would have the branch
	// taken on one URL and the fetch run against another.
	hint := l.radioLogoHint(apiStationPID)
	logo, fetchErr := RadioLogo{}, error(nil)
	switch {
	case row.LogoURL != "":
		logo, fetchErr = l.fetchRadioLogo(ctx, row.LogoURL)
	// What the station said about itself while somebody was listening to
	// it, which beats going looking: the operator named this URL in the
	// stream's own headers. Only tried before discovery, never instead
	// of it - a hint that does not answer falls through to the search
	// rather than costing the station its picture.
	case hint != "":
		logo, fetchErr = l.fetchRadioLogo(ctx, hint)
		if fetchErr != nil {
			logo, fetchErr = l.discoverRadioLogo(ctx, row.HomepageURL, row.StreamURL)
		}
	default:
		logo, fetchErr = l.discoverRadioLogo(ctx, row.HomepageURL, row.StreamURL)
	}
	// A failure is remembered, unreachable hosts included: thirty stations
	// behind one dead host would otherwise cost thirty ten-second waits per
	// paint. The exception is the caller going away, which says nothing
	// about the station; the parent context is what tells them apart, since
	// the fetch's own deadline is a child of it.
	callerLeft := fetchErr != nil && ctx.Err() != nil
	if !callerLeft {
		l.storeRadioLogo(apiStationPID, logo)
	}
	if fetchErr != nil {
		return RadioLogo{}, errNotFound("no logo for station " + apiStationPID)
	}
	return logo, nil
}

// fetchRadioLogo gets one logo URL through the guarded client. Every
// failure is the same failure to the caller; the error exists to say
// which of them happened in a log.
func (l *Library) fetchRadioLogo(ctx context.Context, logoURL string) (RadioLogo, error) {
	if logoURL == "" {
		return RadioLogo{}, errors.New("the station has no logo url")
	}
	u, err := url.Parse(logoURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return RadioLogo{}, errors.New("the logo url is not http or https")
	}
	callCtx, cancel := context.WithTimeout(ctx, radioLogoTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(callCtx, http.MethodGet, logoURL, nil)
	if err != nil {
		return RadioLogo{}, err
	}
	req.Header.Set("User-Agent", "WaxDeck")
	req.Header.Set("Accept", "image/*")
	// The stream proxy's client: private destinations refused at dial
	// time after DNS resolution, redirects bounded. A logo URL is
	// attacker-supplied in exactly the way a stream URL is.
	resp, err := l.radioClient().Do(req)
	if err != nil {
		return RadioLogo{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		// A 4xx is this URL's own answer and will be the same tomorrow -
		// a station whose StreamUrl 404s must cost one fetch a day, not
		// one every five minutes for as long as somebody listens. The
		// two throttle-shaped codes are the exception: those do change.
		if resp.StatusCode >= 400 && resp.StatusCode < 500 &&
			resp.StatusCode != http.StatusRequestTimeout &&
			resp.StatusCode != http.StatusTooManyRequests {
			return RadioLogo{}, fmt.Errorf("the logo host answered status %d: %w", resp.StatusCode, errRadioArtNotImage)
		}
		return RadioLogo{}, fmt.Errorf("the logo host answered status %d", resp.StatusCode)
	}
	declared, _, _ := strings.Cut(resp.Header.Get("Content-Type"), ";")
	mime, allowed := radioLogoMimes[strings.ToLower(strings.TrimSpace(declared))]
	if !allowed {
		return RadioLogo{}, fmt.Errorf("the logo host answered %q: %w", declared, errRadioArtNotImage)
	}
	// One byte past the cap, so a body at exactly the limit is served and
	// one over it is refused rather than silently truncated into a
	// corrupt image.
	body, err := io.ReadAll(io.LimitReader(resp.Body, radioLogoMaxBytes+1))
	if err != nil {
		return RadioLogo{}, err
	}
	if len(body) == 0 {
		return RadioLogo{}, fmt.Errorf("the logo host answered an empty body: %w", errRadioArtNotImage)
	}
	if len(body) > radioLogoMaxBytes {
		return RadioLogo{}, fmt.Errorf("the logo is larger than %d bytes: %w", radioLogoMaxBytes, errRadioArtNotImage)
	}
	// The bytes decide, and they decide alone. What the host called the
	// body only got it this far; the served type is what the body
	// actually is, so nothing reaches a browser labelled as something it
	// is not. That also means markup can never be served from here: text
	// and XML sniff as themselves and are refused, with no branch that
	// takes a host's word for a type the sniffer disagrees with.
	sniffed := http.DetectContentType(body)
	served, ok := radioLogoMimes[sniffed]
	if !ok || served == "" {
		return RadioLogo{}, fmt.Errorf("the logo bytes are %q: %w", sniffed, errRadioArtNotImage)
	}
	mime = served
	sum := sha256.Sum256(body)
	return RadioLogo{
		Bytes:    body,
		MimeType: mime,
		ETag:     `"` + hex.EncodeToString(sum[:16]) + `"`,
	}, nil
}

// radioLogoOrNotFound turns a cache hit into the endpoint's two answers:
// the bytes, or the not-found every way of having no picture comes to.
func radioLogoOrNotFound(cached RadioLogo, apiStationPID string) (RadioLogo, error) {
	if len(cached.Bytes) == 0 {
		return RadioLogo{}, errNotFound("no logo for station " + apiStationPID)
	}
	return cached, nil
}

// claimRadioLogo answers a station's cached logo, or says who is fetching
// it. Three outcomes: a hit (second return true), a fetch already running
// to wait on (third return non-nil), or neither - in which case the
// caller now owns the fetch and must release it with
// [Library.endRadioLogoFetch].
func (l *Library) claimRadioLogo(apiStationPID string) (RadioLogo, bool, chan struct{}) {
	l.radioLogosMu.Lock()
	defer l.radioLogosMu.Unlock()
	if logo, ok := l.freshRadioLogoLocked(apiStationPID); ok {
		return logo, true, nil
	}
	if wait, ok := l.radioLogoFlights[apiStationPID]; ok {
		return RadioLogo{}, false, wait
	}
	l.radioLogoFlights[apiStationPID] = make(chan struct{})
	return RadioLogo{}, false, nil
}

// endRadioLogoFetch releases the fetch the caller owned, waking whoever
// is waiting on it.
func (l *Library) endRadioLogoFetch(apiStationPID string) {
	l.radioLogosMu.Lock()
	wait := l.radioLogoFlights[apiStationPID]
	delete(l.radioLogoFlights, apiStationPID)
	l.radioLogosMu.Unlock()
	if wait != nil {
		close(wait)
	}
}

// freshRadioLogoLocked answers a station's cached logo while it is fresh.
// The second return distinguishes "cached, and there is nothing to draw"
// from "not cached". Callers hold the lock.
func (l *Library) freshRadioLogoLocked(apiStationPID string) (RadioLogo, bool) {
	entry, ok := l.radioLogos[apiStationPID]
	if !ok {
		return RadioLogo{}, false
	}
	if time.Since(entry.fetched) > entry.freshFor() {
		return RadioLogo{}, false
	}
	return entry.logo, true
}

// storeRadioLogo caches one result, evicting oldest-first until the
// whole cache is inside its byte budget.
func (l *Library) storeRadioLogo(apiStationPID string, logo RadioLogo) {
	l.radioLogosMu.Lock()
	defer l.radioLogosMu.Unlock()
	// A miss never replaces a logo that is still good. Reaching here means
	// the cache said nothing fresh when this fetch started, so an entry
	// that is fresh now was stored by somebody else while it ran - and of
	// two answers about the same station, the one with a picture in it is
	// the one to keep. Without this a second caller falling through the
	// one-wait limit could put an hour of "no logo" over bytes fetched a
	// moment earlier.
	if len(logo.Bytes) == 0 {
		if previous, ok := l.freshRadioLogoLocked(apiStationPID); ok && len(previous.Bytes) > 0 {
			return
		}
	}
	if previous, ok := l.radioLogos[apiStationPID]; ok {
		l.radioLogosBytes -= len(previous.logo.Bytes)
		// Re-fetched after its TTL ran out, so it goes to the back with the
		// other new arrivals. Left where it was, a logo fetched a moment ago
		// would be evicted ahead of one cached hours earlier, which is the
		// opposite of what the order is for.
		l.dropRadioLogoOrder(apiStationPID)
	}
	l.radioLogosOrder = append(l.radioLogosOrder, apiStationPID)
	l.radioLogos[apiStationPID] = radioLogo{logo: logo, fetched: time.Now()}
	l.radioLogosBytes += len(logo.Bytes)
	for l.radioLogosBytes > radioLogoCacheBytes && len(l.radioLogosOrder) > 1 {
		oldest := l.radioLogosOrder[0]
		l.radioLogosOrder = l.radioLogosOrder[1:]
		l.radioLogosBytes -= len(l.radioLogos[oldest].logo.Bytes)
		delete(l.radioLogos, oldest)
	}
}

// forgetRadioLogo drops a station's cached logo, so an edit that changes
// the URL is drawn from the new one rather than from a day-old copy of
// the old.
func (l *Library) forgetRadioLogo(apiStationPID string) {
	l.radioLogosMu.Lock()
	defer l.radioLogosMu.Unlock()
	l.dropRadioLogoLocked(apiStationPID)
	// The hint goes with it. On a delete it would otherwise outlive the
	// station for the life of the process, so the map would grow with
	// every station ever streamed; on an edit that cleared the logo URL
	// it would keep answering for a decision the operator has just
	// reversed.
	delete(l.radioLogoHints, apiStationPID)
}

// dropRadioLogoLocked forgets one cached logo. Callers hold the lock.
func (l *Library) dropRadioLogoLocked(apiStationPID string) {
	entry, ok := l.radioLogos[apiStationPID]
	if !ok {
		return
	}
	l.radioLogosBytes -= len(entry.logo.Bytes)
	delete(l.radioLogos, apiStationPID)
	l.dropRadioLogoOrder(apiStationPID)
}

// dropRadioLogoOrder removes one pid from the eviction order. Callers hold
// the lock.
func (l *Library) dropRadioLogoOrder(apiStationPID string) {
	for i, pid := range l.radioLogosOrder {
		if pid == apiStationPID {
			l.radioLogosOrder = append(l.radioLogosOrder[:i], l.radioLogosOrder[i+1:]...)
			return
		}
	}
}

// radioTitleFreshFor bounds how long an observed in-stream title stays
// reportable: metadata blocks recur every few seconds while a proxied
// listener is connected, so anything older means the stream closed.
//
// A bound on the stream rather than on the song, and only because
// NoteRadioAlive rides the blocks that carry nothing. Announcements
// come once a track, so reading those alone expired the title mid-play
// on every song over two minutes.
const radioTitleFreshFor = 2 * time.Minute

// radioTitleHoldFor bounds a title standing on nothing but the
// station's silence, since a stream outlives the automation narrating
// it. Sized against the longest thing announced once - a classical work
// - rather than against a song; a DJ mix outlasts it and falls back to
// the station mark, which is the honest answer by then.
const radioTitleHoldFor = 45 * time.Minute

// NoteRadioTitle records the in-stream ICY title the proxy just
// observed for a station.
func (l *Library) NoteRadioTitle(apiStationPID, title string) {
	l.NoteRadioMeta(apiStationPID, title, "")
}

// NoteRadioAlive records that the proxy saw a metadata block, whatever
// it said. Titles arrive once a song; these arrive every metaint, so
// this is what freshness above is actually measuring. A refresh only -
// a station with no observed title has nothing to keep fresh.
func (l *Library) NoteRadioAlive(apiStationPID string) {
	l.radioTitlesMu.Lock()
	defer l.radioTitlesMu.Unlock()
	t, ok := l.radioTitles[apiStationPID]
	if !ok {
		return
	}
	t.seenNS = time.Now().UnixNano()
	l.radioTitles[apiStationPID] = t
}

// forgetRadioTitle drops a station's observed title, for a station that
// no longer exists.
func (l *Library) forgetRadioTitle(apiStationPID string) {
	l.radioTitlesMu.Lock()
	defer l.radioTitlesMu.Unlock()
	delete(l.radioTitles, apiStationPID)
}

// NoteRadioMeta records a title and the picture the station announced
// with it.
//
// The art belongs to the announcement, not to the station, so every
// announcement replaces it - including with nothing. A bumper or an
// un-annotated track announced with no picture clears the last one and
// the ladder falls to the rungs below, which is the honest answer; the
// alternative is a cover that sticks to whatever plays next.
//
// An empty title is not a clear: automation sends an empty StreamTitle
// over idents and jingles, and honouring it emptied the face mid-song.
// A block with no title key at all is already ignored; an empty one says
// as much. radioTitleHoldFor is what bounds a title gone wrong.
func (l *Library) NoteRadioMeta(apiStationPID, title, artURL string) {
	if title == "" {
		l.NoteRadioAlive(apiStationPID)
		return
	}
	l.radioTitlesMu.Lock()
	prev, had := l.radioTitles[apiStationPID]
	// The same picture announced against a different song is the
	// station's own mark, not that song's cover. Stations do this - a
	// channel logo in StreamUrl on every track is a whole class of them -
	// and taking it for cover art would park one image on the
	// full-screen face forever, outranking the lookup that would have
	// found the actual sleeve. A picture that changes with the title is
	// what a per-track cover looks like.
	fixed := prev.artFixed
	if had && artURL != "" && prev.title != title && prev.artURL != "" {
		fixed = prev.artURL == artURL
	}
	now := time.Now().UnixNano()
	l.radioTitles[apiStationPID] = radioTitle{
		title:       title,
		artURL:      artURL,
		artFixed:    fixed,
		seenNS:      now,
		announcedNS: now,
	}
	l.radioTitlesMu.Unlock()
	// Demoted rather than discarded: a station mark is exactly what the
	// logo rung wants, and this one came from the station itself.
	if fixed && artURL != "" {
		l.NoteRadioLogoHint(apiStationPID, artURL)
	}
}

// RadioNowPlaying reports a station's last observed in-stream title
// while it is fresh; empty otherwise.
func (l *Library) RadioNowPlaying(apiStationPID string) string {
	title, _ := l.RadioNowPlayingMeta(apiStationPID)
	return title
}

// RadioNowPlayingMeta reports the last observed title and the picture
// announced with it, both read under one lock so the two describe the
// same song: a second read could land the other side of a rollover.
//
// Two clocks, because the stream stopping and the station going quiet
// are different failures.
func (l *Library) RadioNowPlayingMeta(apiStationPID string) (string, string) {
	l.radioTitlesMu.Lock()
	defer l.radioTitlesMu.Unlock()
	t, ok := l.radioTitles[apiStationPID]
	if !ok {
		return "", ""
	}
	now := time.Now().UnixNano()
	if now-t.seenNS > int64(l.radioTitleFresh) || now-t.announcedNS > int64(radioTitleHoldFor) {
		// Dropped where it is found rather than left for a write that may
		// never come, the same rule the art cache next door keeps: a
		// station stops being relayed and nothing else would ever revisit
		// its entry.
		delete(l.radioTitles, apiStationPID)
		return "", ""
	}
	// A mark the station repeats on every song is not this song's cover,
	// so it is not offered as one: it has already gone to the logo rung,
	// which is where the ladder draws it from.
	if t.artFixed {
		return t.title, ""
	}
	return t.title, t.artURL
}

// NoteRadioLogoHint records the logo a station named in its connect
// headers (`icy-logo`), which is a better answer than going looking for
// one and costs nothing to keep.
func (l *Library) NoteRadioLogoHint(apiStationPID, logoURL string) {
	if logoURL == "" {
		return
	}
	l.radioLogosMu.Lock()
	defer l.radioLogosMu.Unlock()
	if l.radioLogoHints == nil {
		l.radioLogoHints = map[string]string{}
	}
	if l.radioLogoHints[apiStationPID] == logoURL {
		return
	}
	l.radioLogoHints[apiStationPID] = logoURL
	// The station this arrives for is precisely the one that has "no
	// logo we can draw" cached: the dial painted, discovery came up
	// empty, and the answer was remembered for an hour. Only now, the
	// moment somebody played it, has the station said where its mark
	// is. Without dropping that entry the hint would sit unread until
	// the miss went stale, which is the whole hour it exists to save.
	l.dropRadioLogoLocked(apiStationPID)
}

func (l *Library) radioLogoHint(apiStationPID string) string {
	l.radioLogosMu.Lock()
	defer l.radioLogosMu.Unlock()
	return l.radioLogoHints[apiStationPID]
}

// radioTitle is one station's last observed in-stream announcement.
type radioTitle struct {
	title  string
	artURL string
	// artFixed marks a picture the station announces whatever is
	// playing, which makes it the station's mark rather than a cover.
	artFixed bool
	// seenNS is the last block of any kind, announcedNS the last one that
	// named a song. Freshness needs both.
	seenNS      int64
	announcedNS int64
}

// RadioHTTP is the guarded client the stream proxy uses: private
// destinations refused at dial time (after DNS resolution, defeating
// rebinding) unless the server allows LAN stations, redirects capped,
// no overall timeout (radio streams are unbounded).
func (l *Library) RadioHTTP() *http.Client { return l.radioClient() }

func (l *Library) radioClient() *http.Client {
	l.radioHTTPOnce.Do(func() {
		dialer := &net.Dialer{Timeout: 10 * time.Second}
		if !l.allowPrivateRadioHosts {
			dialer.Control = func(network, address string, _ syscall.RawConn) error {
				return refusePrivateAddr(address)
			}
		}
		transport := http.DefaultTransport.(*http.Transport).Clone()
		transport.DialContext = dialer.DialContext
		transport.ResponseHeaderTimeout = 15 * time.Second
		l.radioHTTP = &http.Client{
			Transport: transport,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if len(via) >= 5 {
					return errors.New("too many redirects")
				}
				return nil
			},
		}
	})
	return l.radioHTTP
}

// radioStationRow parses an API station pid and reads its row.
func (l *Library) radioStationRow(ctx context.Context, apiStationPID string) (wdb.RadioStation, error) {
	prefix, pid, ok := parseAPIPID(apiStationPID)
	if !ok || prefix != PrefixRadioStation {
		return wdb.RadioStation{}, errNotFound("no station " + apiStationPID)
	}
	row, err := l.db.RadioStationByID(ctx, string(pid))
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return wdb.RadioStation{}, errNotFound("no station " + apiStationPID)
		}
		return wdb.RadioStation{}, &Error{Kind: KindInternal, Err: err}
	}
	return row, nil
}

// validateStationEdit checks the request fields and returns a row ready
// for identity and timestamps.
func (l *Library) validateStationEdit(ctx context.Context, edit RadioStationEdit) (wdb.RadioStation, error) {
	name := strings.TrimSpace(edit.Name)
	if name == "" {
		return wdb.RadioStation{}, errInvalid("a station needs a name")
	}
	if err := l.validateStreamURL(edit.StreamURL); err != nil {
		return wdb.RadioStation{}, err
	}
	for _, aux := range []string{edit.HomepageURL, edit.LogoURL} {
		if aux == "" {
			continue
		}
		if u, err := url.Parse(aux); err != nil || (u.Scheme != "http" && u.Scheme != "https") {
			return wdb.RadioStation{}, errInvalid("station URLs must be http or https")
		}
	}
	return wdb.RadioStation{
		Name:        name,
		StreamURL:   edit.StreamURL,
		HomepageURL: edit.HomepageURL,
		LogoURL:     edit.LogoURL,
	}, nil
}

// validateStreamURL enforces the stream URL policy: http or https,
// and no private-range destinations unless the server allows LAN
// stations. The name is resolved here as a write-time courtesy; the
// dial-time guard on the proxy client is the real boundary.
func (l *Library) validateStreamURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return errInvalid("the stream URL must be http or https")
	}
	if l.allowPrivateRadioHosts {
		return nil
	}
	// Best effort: an unresolvable name fails at fetch time instead.
	if hostResolvesPrivate(u.Hostname()) {
		return errInvalid("the stream URL resolves to a private address; the server does not allow private-range stations")
	}
	return nil
}

func radioStationDTO(r wdb.RadioStation) RadioStation {
	return RadioStation{
		PID:         PrefixRadioStation + "-" + r.ID,
		Name:        r.Name,
		StreamURL:   r.StreamURL,
		HomepageURL: r.HomepageURL,
		LogoURL:     r.LogoURL,
		CreatedAt:   time.Unix(0, r.CreatedAtNS).UTC(),
	}
}
