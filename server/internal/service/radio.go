package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"syscall"
	"time"

	"github.com/oklog/ulid/v2"

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

// SearchRadioDirectory queries the public station directory by name.
func (l *Library) SearchRadioDirectory(ctx context.Context, q string, limit int) ([]RadioDirectoryEntry, error) {
	base := l.radioDirectoryBase
	if base == "" {
		base = defaultRadioDirectoryBase
	}
	u := strings.TrimRight(base, "/") + "/json/stations/search?" + url.Values{
		"name":       {q},
		"limit":      {fmt.Sprint(limit)},
		"hidebroken": {"true"},
		"order":      {"votes"},
		"reverse":    {"true"},
	}.Encode()
	callCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(callCtx, http.MethodGet, u, nil)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	// The directory asks clients to identify themselves.
	req.Header.Set("User-Agent", "WaxDeck")
	resp, err := l.radioClient().Do(req)
	if err != nil {
		return nil, &Error{Kind: KindDirectory, Msg: "the station directory could not be reached", Err: err}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, &Error{Kind: KindDirectory, Msg: fmt.Sprintf("the station directory answered status %d", resp.StatusCode)}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, &Error{Kind: KindDirectory, Msg: "the station directory could not be read", Err: err}
	}
	var raw []struct {
		Name        string `json:"name"`
		URL         string `json:"url"`
		URLResolved string `json:"url_resolved"`
		Homepage    string `json:"homepage"`
		Favicon     string `json:"favicon"`
		Tags        string `json:"tags"`
		Country     string `json:"country"`
		Codec       string `json:"codec"`
		Bitrate     int    `json:"bitrate"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, &Error{Kind: KindDirectory, Msg: "the station directory answered something unexpected", Err: err}
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
			Codec:       r.Codec,
			BitrateKbps: r.Bitrate,
		})
	}
	return out, nil
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
	logo, fetchErr := l.fetchRadioLogo(ctx, row.LogoURL)
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
		return RadioLogo{}, fmt.Errorf("the logo host answered status %d", resp.StatusCode)
	}
	declared, _, _ := strings.Cut(resp.Header.Get("Content-Type"), ";")
	mime, allowed := radioLogoMimes[strings.ToLower(strings.TrimSpace(declared))]
	if !allowed {
		return RadioLogo{}, fmt.Errorf("the logo host answered %q", declared)
	}
	// One byte past the cap, so a body at exactly the limit is served and
	// one over it is refused rather than silently truncated into a
	// corrupt image.
	body, err := io.ReadAll(io.LimitReader(resp.Body, radioLogoMaxBytes+1))
	if err != nil {
		return RadioLogo{}, err
	}
	if len(body) == 0 {
		return RadioLogo{}, errors.New("the logo host answered an empty body")
	}
	if len(body) > radioLogoMaxBytes {
		return RadioLogo{}, fmt.Errorf("the logo is larger than %d bytes", radioLogoMaxBytes)
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
		return RadioLogo{}, fmt.Errorf("the logo bytes are %q", sniffed)
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

// radioTitleFreshFor bounds how long an observed in-stream title
// stays reportable: metadata blocks recur every few seconds while a
// proxied listener is connected, so anything older means the stream
// closed and the title is stale.
const radioTitleFreshFor = 2 * time.Minute

// NoteRadioTitle records the in-stream ICY title the proxy just
// observed for a station; an empty title is the station clearing it.
func (l *Library) NoteRadioTitle(apiStationPID, title string) {
	l.radioTitlesMu.Lock()
	defer l.radioTitlesMu.Unlock()
	if title == "" {
		delete(l.radioTitles, apiStationPID)
		return
	}
	l.radioTitles[apiStationPID] = radioTitle{title: title, seenNS: time.Now().UnixNano()}
}

// RadioNowPlaying reports a station's last observed in-stream title
// while it is fresh; empty otherwise.
func (l *Library) RadioNowPlaying(apiStationPID string) string {
	l.radioTitlesMu.Lock()
	defer l.radioTitlesMu.Unlock()
	t, ok := l.radioTitles[apiStationPID]
	if !ok || time.Now().UnixNano()-t.seenNS > int64(radioTitleFreshFor) {
		return ""
	}
	return t.title
}

// radioTitle is one station's last observed in-stream title.
type radioTitle struct {
	title  string
	seenNS int64
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
