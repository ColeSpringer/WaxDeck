package service

import (
	"context"
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
