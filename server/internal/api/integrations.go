package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/httpcache"
	"github.com/colespringer/waxdeck/server/internal/pagetext"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// --- internet radio ---------------------------------------------------------------

func (s *Server) ListRadioStations(ctx context.Context, _ ListRadioStationsRequestObject) (ListRadioStationsResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	stations, err := s.svc.RadioStations(ctx)
	if err != nil {
		return nil, err
	}
	out := RadioStationList{Stations: make([]RadioStation, 0, len(stations))}
	for _, st := range stations {
		out.Stations = append(out.Stations, radioStationJSON(st))
	}
	return ListRadioStations200JSONResponse(out), nil
}

func (s *Server) CreateRadioStation(ctx context.Context, req CreateRadioStationRequestObject) (CreateRadioStationResponseObject, error) {
	if req.Body == nil {
		return CreateRadioStation400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	st, err := s.svc.CreateRadioStation(ctx, uc, radioEditFromWire(*req.Body))
	if err != nil {
		return nil, err
	}
	return CreateRadioStation201JSONResponse(radioStationJSON(st)), nil
}

func (s *Server) GetRadioStation(ctx context.Context, req GetRadioStationRequestObject) (GetRadioStationResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	st, err := s.svc.RadioStationByPID(ctx, req.Pid)
	if err != nil {
		return nil, err
	}
	return GetRadioStation200JSONResponse(radioStationJSON(st)), nil
}

func (s *Server) UpdateRadioStation(ctx context.Context, req UpdateRadioStationRequestObject) (UpdateRadioStationResponseObject, error) {
	if req.Body == nil {
		return UpdateRadioStation400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	st, err := s.svc.UpdateRadioStation(ctx, req.Pid, radioEditFromWire(*req.Body))
	if err != nil {
		return nil, err
	}
	return UpdateRadioStation200JSONResponse(radioStationJSON(st)), nil
}

func (s *Server) DeleteRadioStation(ctx context.Context, req DeleteRadioStationRequestObject) (DeleteRadioStationResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	if err := s.svc.DeleteRadioStation(ctx, req.Pid); err != nil {
		return nil, err
	}
	return DeleteRadioStation204Response{}, nil
}

func (s *Server) GetRadioPlayInfo(ctx context.Context, req GetRadioPlayInfoRequestObject) (GetRadioPlayInfoResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	station, err := s.svc.RadioStationByPID(ctx, req.Pid)
	if err != nil {
		return nil, err
	}
	token, _ := s.media.Mint(p.User.ID, req.Pid)
	out := RadioPlayInfo{
		Url: "/media/radio/" + url.PathEscape(req.Pid) + "?mt=" + url.QueryEscape(token),
	}
	// Read once and passed along, so the fields describe the same song:
	// the relay rewrites the title whenever the station announces one,
	// and a second read could land on the next track.
	if title, artURL := s.svc.RadioNowPlayingMeta(req.Pid); title != "" {
		out.NowPlaying = ptr(title)
		// One indexed read, and what keeps the heart honest across
		// devices: a save made on the phone fills the desktop's heart on
		// its next poll. Absent rather than false when nothing is kept,
		// which the contract says means the same thing.
		if savedPID := s.svc.RadioSavedPIDForNowPlaying(ctx, uc, station.Name, title); savedPID != "" {
			out.NowPlayingSaved = ptr(true)
			out.NowPlayingSavedPid = ptr(savedPID)
		}
		// Resolved against this caller's own visibility, since the pid
		// is going to be used to fetch cover art. Absent is the ordinary
		// answer and the client falls back to the rungs below.
		if pid := s.svc.RadioNowPlayingItem(ctx, uc, req.Pid, station.Name, title); pid != "" {
			out.NowPlayingItemPid = ptr(pid)
		} else if key, tryExternal := s.svc.EnsureRadioAnnouncedArt(artURL, title); key != "" {
			// The station's own answer, and the better one: it names the
			// picture for this exact broadcast, where an external lookup
			// guesses a release from a parsed title.
			out.NowPlayingArtKey = ptr(key)
		} else if tryExternal {
			// Only once the two rungs above have missed. Ensure starts
			// the lookup and answers the key for what is cached now, so
			// the poll that first sees a new title answers nothing and a
			// later one answers a key - it never waits on a paced third
			// party. tryExternal is false only while an announced fetch
			// is in flight, which is worth one poll's wait.
			if key := s.svc.EnsureRadioNowPlayingArt(station.Name, title); key != "" {
				out.NowPlayingArtKey = ptr(key)
			}
		}
	}
	return GetRadioPlayInfo200JSONResponse(out), nil
}

// radioLogoCacheControl is the freshness a station logo carries: the same
// as item artwork, because it is the same kind of thing - a picture
// behind a stable URL, cheap to revalidate and harmless to hold. No Vary
// beside it, unlike artwork: the station library is shared, so these
// bytes do not depend on who asked. Still private, because the request
// needs a session and a shared cache must not answer one without.
const radioLogoCacheControl = artCacheControl

// The logo response's hardening pair, and the one endpoint in this file
// that needs it: these bytes came from a host any account can name, and
// they are served from WaxDeck's own origin.
//
// The service is what makes the response safe - it serves only raster
// types, decided by sniffing the bytes rather than by trusting the host,
// so nothing that can carry script gets this far. These two make that
// hold even if it stops holding. `nosniff` stops a browser from deciding
// the body is really markup, and the policy neutralizes script and
// navigation for a document opened straight from this URL. Cheap, and
// exactly the layer that turns a future mistake in the type check from a
// stored-XSS hole into a broken image.
const (
	radioLogoNoSniff = "nosniff"
	radioLogoCSP     = "default-src 'none'; sandbox; style-src 'unsafe-inline'"
)

// radioStreamContentType is the type the stream proxy serves for a
// station's own, refusing the ones a browser would execute.
//
// A station names its type and the proxy relays it from this origin, so
// the executable families are replaced by the audio default rather than
// passed on: what a listener asked for is a stream, and a station that
// answers markup has already failed to be one.
func radioStreamContentType(declared string) string {
	essence, _, _ := strings.Cut(declared, ";")
	switch strings.ToLower(strings.TrimSpace(essence)) {
	case "", "text/html", "application/xhtml+xml", "image/svg+xml",
		"application/xml", "text/xml", "text/plain":
		return "audio/mpeg"
	}
	return declared
}

func (s *Server) GetRadioStationLogo(ctx context.Context, req GetRadioStationLogoRequestObject) (GetRadioStationLogoResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	logo, err := s.svc.RadioStationLogo(ctx, req.Pid)
	if err != nil {
		// Every way there is nothing to draw is a 404, including a station
		// that does not exist: the caller renders a monogram either way,
		// and the service has already collapsed the fetch failures.
		if service.KindOf(err) == service.KindNotFound {
			return GetRadioStationLogo404JSONResponse(errObj("not-found", "no logo for station "+req.Pid)), nil
		}
		return nil, err
	}
	cacheControl := radioLogoCacheControl
	if req.Params.IfNoneMatch != nil && httpcache.ETagMatches(*req.Params.IfNoneMatch, logo.ETag) {
		return GetRadioStationLogo304Response{Headers: GetRadioStationLogo304ResponseHeaders{
			ETag:         &logo.ETag,
			CacheControl: &cacheControl,
		}}, nil
	}
	noSniff, csp := radioLogoNoSniff, radioLogoCSP
	headers := GetRadioStationLogo200ResponseHeaders{
		ETag:                  &logo.ETag,
		CacheControl:          &cacheControl,
		XContentTypeOptions:   &noSniff,
		ContentSecurityPolicy: &csp,
	}
	body := bytes.NewReader(logo.Bytes)
	length := int64(len(logo.Bytes))
	// The service serves only these four, decided by sniffing the bytes,
	// so there is no branch here for a type that can carry script.
	switch logo.MimeType {
	case "image/png":
		return GetRadioStationLogo200ImagepngResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/webp":
		return GetRadioStationLogo200ImagewebpResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/gif":
		return GetRadioStationLogo200ImagegifResponse{Body: body, ContentLength: length, Headers: headers}, nil
	default:
		return GetRadioStationLogo200ImagejpegResponse{Body: body, ContentLength: length, Headers: headers}, nil
	}
}

func (s *Server) GetRadioNowPlayingArt(ctx context.Context, req GetRadioNowPlayingArtRequestObject) (GetRadioNowPlayingArtResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	art, err := s.svc.RadioNowPlayingArt(req.Params.V)
	if err != nil {
		// Same collapse as the logo: nothing announced, nothing parsed,
		// the rung off, the lookup not landed, upstream empty - the
		// client falls back the same way for all of them.
		if service.KindOf(err) == service.KindNotFound {
			return GetRadioNowPlayingArt404JSONResponse(errObj("not-found", "no now-playing artwork for station "+req.Pid)), nil
		}
		return nil, err
	}
	cacheControl := radioLogoCacheControl
	if req.Params.IfNoneMatch != nil && httpcache.ETagMatches(*req.Params.IfNoneMatch, art.ETag) {
		return GetRadioNowPlayingArt304Response{Headers: GetRadioNowPlayingArt304ResponseHeaders{
			ETag:         &art.ETag,
			CacheControl: &cacheControl,
		}}, nil
	}
	noSniff, csp := radioLogoNoSniff, radioLogoCSP
	headers := GetRadioNowPlayingArt200ResponseHeaders{
		ETag:                  &art.ETag,
		CacheControl:          &cacheControl,
		XContentTypeOptions:   &noSniff,
		ContentSecurityPolicy: &csp,
	}
	body := bytes.NewReader(art.Bytes)
	length := int64(len(art.Bytes))
	// Raster only, decided by sniffing the bytes upstream of here, so
	// there is no branch for a type that can carry script.
	switch art.MimeType {
	case "image/png":
		return GetRadioNowPlayingArt200ImagepngResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/webp":
		return GetRadioNowPlayingArt200ImagewebpResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/gif":
		return GetRadioNowPlayingArt200ImagegifResponse{Body: body, ContentLength: length, Headers: headers}, nil
	default:
		return GetRadioNowPlayingArt200ImagejpegResponse{Body: body, ContentLength: length, Headers: headers}, nil
	}
}

func (s *Server) ListRadioSavedSongs(ctx context.Context, req ListRadioSavedSongsRequestObject) (ListRadioSavedSongsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 50, 200)
	if !ok {
		return ListRadioSavedSongs400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 200"))}, nil
	}
	cursor := ""
	if req.Params.Cursor != nil {
		cursor = *req.Params.Cursor
	}
	page, err := s.svc.ListRadioSaved(ctx, uc, cursor, limit)
	if err != nil {
		return nil, err
	}
	out := RadioSavedSongPage{Songs: make([]RadioSavedSong, 0, len(page.Songs))}
	for _, sg := range page.Songs {
		out.Songs = append(out.Songs, radioSavedSongJSON(sg))
	}
	if page.Next != "" {
		out.NextCursor = ptr(page.Next)
	}
	return ListRadioSavedSongs200JSONResponse(out), nil
}

func (s *Server) SaveRadioSong(ctx context.Context, req SaveRadioSongRequestObject) (SaveRadioSongResponseObject, error) {
	if req.Body == nil {
		return SaveRadioSong400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	song, err := s.svc.SaveRadioSong(ctx, uc, req.Body.StationPid, req.Body.NowPlaying)
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			return SaveRadioSong409JSONResponse(errObj("conflict", err.Error())), nil
		}
		return nil, err
	}
	return SaveRadioSong201JSONResponse(radioSavedSongJSON(song)), nil
}

func (s *Server) DeleteRadioSavedSong(ctx context.Context, req DeleteRadioSavedSongRequestObject) (DeleteRadioSavedSongResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.RemoveRadioSaved(ctx, uc, req.Pid); err != nil {
		return nil, err
	}
	return DeleteRadioSavedSong204Response{}, nil
}

func (s *Server) GetRadioSavedSongArt(ctx context.Context, req GetRadioSavedSongArtRequestObject) (GetRadioSavedSongArtResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	art, err := s.svc.RadioSavedArt(ctx, uc, req.Pid)
	if err != nil {
		// No such row, another listener's row, or one saved with nothing
		// to copy: the client draws a monogram for all three.
		if service.KindOf(err) == service.KindNotFound {
			return GetRadioSavedSongArt404JSONResponse(errObj("not-found", "no artwork for saved song "+req.Pid)), nil
		}
		return nil, err
	}
	// Varied by the credential, unlike the station logo beside it: a
	// logo is shared library data and does not depend on who asked,
	// where a saved song is one listener's and answers 404 to everyone
	// else. A cache holding two credentials must not answer one from the
	// other's copy - the same rule item artwork follows.
	cacheControl, vary := radioLogoCacheControl, artVary
	if req.Params.IfNoneMatch != nil && httpcache.ETagMatches(*req.Params.IfNoneMatch, art.ETag) {
		return GetRadioSavedSongArt304Response{Headers: GetRadioSavedSongArt304ResponseHeaders{
			ETag:         &art.ETag,
			CacheControl: &cacheControl,
			Vary:         &vary,
		}}, nil
	}
	noSniff, csp := radioLogoNoSniff, radioLogoCSP
	headers := GetRadioSavedSongArt200ResponseHeaders{
		ETag:                  &art.ETag,
		CacheControl:          &cacheControl,
		Vary:                  &vary,
		XContentTypeOptions:   &noSniff,
		ContentSecurityPolicy: &csp,
	}
	body := bytes.NewReader(art.Bytes)
	length := int64(len(art.Bytes))
	// These bytes were snapshotted from a rung that had already decided
	// the type by sniffing them, so there is no branch here for a type
	// that can carry script.
	switch art.MimeType {
	case "image/png":
		return GetRadioSavedSongArt200ImagepngResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/webp":
		return GetRadioSavedSongArt200ImagewebpResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/gif":
		return GetRadioSavedSongArt200ImagegifResponse{Body: body, ContentLength: length, Headers: headers}, nil
	default:
		return GetRadioSavedSongArt200ImagejpegResponse{Body: body, ContentLength: length, Headers: headers}, nil
	}
}

func radioSavedSongJSON(s service.RadioSavedSong) RadioSavedSong {
	out := RadioSavedSong{
		Pid:         s.PID,
		NowPlaying:  s.NowPlaying,
		StationName: s.StationName,
		HeardAt:     s.HeardAt,
		HasArt:      s.HasArt,
	}
	if s.Artist != "" {
		out.Artist = ptr(s.Artist)
	}
	if s.Title != "" {
		out.Title = ptr(s.Title)
	}
	if s.StationPID != "" {
		out.StationPid = ptr(s.StationPID)
	}
	if s.InLibraryPID != "" {
		out.InLibraryPid = ptr(s.InLibraryPID)
	}
	return out
}

func (s *Server) SearchRadioDirectory(ctx context.Context, req SearchRadioDirectoryRequestObject) (SearchRadioDirectoryResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit := 25
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	// The caller is needed for their locale: the directory's own ranking
	// is by votes, which knows nothing about where the listener is.
	entries, err := s.svc.SearchRadioDirectory(ctx, uc, req.Params.Query, limit)
	if err != nil {
		return nil, err
	}
	out := RadioDirectoryResults{Entries: make([]RadioDirectoryEntry, 0, len(entries))}
	for _, e := range entries {
		w := RadioDirectoryEntry{Name: e.Name, StreamUrl: e.StreamURL}
		if e.HomepageURL != "" {
			w.HomepageUrl = ptr(e.HomepageURL)
		}
		if e.LogoURL != "" {
			w.LogoUrl = ptr(e.LogoURL)
		}
		if e.Tags != "" {
			w.Tags = ptr(e.Tags)
		}
		if e.Country != "" {
			w.Country = ptr(e.Country)
		}
		if e.Codec != "" {
			w.Codec = ptr(e.Codec)
		}
		if e.BitrateKbps > 0 {
			w.BitrateKbps = ptr(e.BitrateKbps)
		}
		out.Entries = append(out.Entries, w)
	}
	return SearchRadioDirectory200JSONResponse(out), nil
}

// ServeRadio proxies a station stream through this origin: the token
// authenticates the fetch, the guarded client refuses private
// destinations, ICY station headers pass through, and the body streams
// unbuffered for as long as both sides stay open. Token expiry never
// cuts an open stream; it only gates new opens. The proxy asks the
// station for in-stream ICY metadata, strips it from the audio, and
// records the current title for play-info to report.
func (s *Server) ServeRadio(w http.ResponseWriter, r *http.Request) {
	pid := r.PathValue("pid")
	user, err := s.media.Verify(r.URL.Query().Get("mt"), pid)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing or invalid media token")
		return
	}
	// Shared with the enclosure relay: the same account holding the same
	// kind of resource, counted once.
	release, ok := s.relayStreams.acquire(user)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited",
			"too many concurrent relayed streams for this account")
		return
	}
	defer release()
	streamURL, err := s.svc.RadioStreamSource(r.Context(), pid)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			writeError(w, http.StatusNotFound, "not-found", "no such station")
		case service.KindInvalid:
			writeError(w, http.StatusBadRequest, "invalid-request", kindMessage(err, "the station URL is not allowed"))
		default:
			writeError(w, http.StatusInternalServerError, "internal", "internal server error")
		}
		return
	}
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, streamURL, nil)
	if err != nil {
		writeError(w, http.StatusBadGateway, "service-unreachable", "the station could not be contacted")
		return
	}
	req.Header.Set("User-Agent", "WaxDeck")
	req.Header.Set("Icy-MetaData", "1")
	resp, err := s.svc.RadioHTTP().Do(req)
	if err != nil {
		writeError(w, http.StatusBadGateway, "service-unreachable", "the station could not be reached")
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		writeError(w, http.StatusBadGateway, "service-unreachable", fmt.Sprintf("the station answered status %d", resp.StatusCode))
		return
	}
	metaint, _ := strconv.Atoi(resp.Header.Get("Icy-Metaint"))
	// Some operators name their logo in the connect headers, which is a
	// better answer than the discovery walk and free to keep: this is
	// the one moment the station itself is talking to this server.
	s.svc.NoteRadioLogoHint(pid, strings.TrimSpace(resp.Header.Get("Icy-Logo")))
	// The station's own type, minus the ones that would make this origin
	// run a stranger's markup. The proxy serves an attacker-nameable host's
	// bytes from WaxDeck's origin, exactly as the logo endpoint does, and a
	// station answering text/html or an SVG here would be the same stored
	// XSS from the other door. Passed through rather than allowlisted
	// because the set of types real stations send is long and odd
	// (audio/aacp, application/ogg, audio/x-mpegurl) and refusing an
	// unfamiliar one would break playback to prevent nothing; what is
	// refused is only what a browser would execute. `nosniff` covers the
	// rest, so a mislabelled body cannot be re-decided into markup.
	ct := radioStreamContentType(resp.Header.Get("Content-Type"))
	w.Header().Set("Content-Type", ct)
	w.Header().Set("X-Content-Type-Options", radioLogoNoSniff)
	w.Header().Set("Cache-Control", "no-store")
	for name, vals := range resp.Header {
		lower := strings.ToLower(name)
		// icy-metaint is excluded: the metadata it announces is
		// consumed here, so clients get plain audio.
		if lower == "icy-metaint" {
			continue
		}
		if strings.HasPrefix(lower, "icy-") || lower == "ice-audio-info" {
			for _, v := range vals {
				w.Header().Add(name, v)
			}
		}
	}
	w.WriteHeader(http.StatusOK)
	rc := http.NewResponseController(w)
	buf := make([]byte, 32<<10)
	var relay *icyRelay
	if metaint > 0 {
		relay = newICYRelay(metaint)
	}
	var writeErr error
	emit := func(p []byte) {
		if writeErr != nil {
			return
		}
		_, writeErr = w.Write(p)
	}
	// Scrobbling rides the title transitions this listener actually
	// heard: a segment scrobbles only when its ENDING transition is
	// observed, so a never-changing pseudo-title scrobbles nothing and
	// the unfinished tail at disconnect stays off the record.
	seg := &radioSegment{
		now: time.Now,
		report: func(title string, since time.Time) {
			s.svc.ScrobbleRadioPlay(r.Context(), user, pid, title, since)
		},
	}
	onBlock := func(block []byte) {
		meta := icyMetaOf(block)
		// A spot is not a song, so its title and its banner are kept off
		// the face: an advertiser must not become what is playing, on
		// the lock screen or anywhere else. The break still ends the
		// song before it - see radioSegment for why that matters.
		if meta.ad {
			seg.close()
			return
		}
		// A block carrying only a URL is not an announcement. Stations
		// send these between songs, and treating one as a title change
		// would clear the song that is still playing.
		if !meta.titleOK {
			return
		}
		s.svc.NoteRadioMeta(pid, meta.title, meta.artURL)
		if meta.title == seg.title {
			return
		}
		seg.close()
		seg.start(meta.title)
	}
	// A station is not finite, so neither a size cap nor a rate floor
	// belongs here: both would eventually cut a healthy listen, which is
	// the one thing this endpoint exists to allow. The idle deadline is
	// the bound that survives that argument, since a station sending
	// nothing at all has stopped being a station and the socket is being
	// held for no audio.
	guard := newRelayGuard(relayLimits{idle: radioIdle}, cancel)
	defer guard.stop()
	for {
		n, readErr := resp.Body.Read(buf)
		// Noted before the write, and the write bracketed, so a listener
		// whose link cannot keep up with the station is never mistaken
		// for a station that stopped sending.
		if !guard.note(n) {
			// The one thing worth a line on this endpoint. A stream
			// ending is ordinary and logs nothing, either side of it -
			// but this is neither side, it is the server cutting a
			// listener off, and a station that goes quiet for a minute
			// while somebody is listening to it is a fact the operator
			// wants.
			relayed, elapsed := guard.stats()
			s.log.Warn("the station relay was cut short",
				"pid", pid, "reason", guard.reason(),
				"bytes", relayed, "elapsed", elapsed.Round(time.Second))
			return
		}
		if n > 0 {
			done := guard.writing()
			if relay != nil {
				relay.feed(buf[:n], emit, onBlock)
			} else {
				emit(buf[:n])
			}
			if writeErr == nil {
				// Live audio wants low latency; flush every chunk. Inside
				// the bracket with the write, since this is where a
				// listener who has stopped reading actually blocks.
				rc.Flush()
			}
			done()
			if writeErr != nil {
				return
			}
		}
		if readErr != nil {
			return
		}
	}
}

// --- scrobbling -------------------------------------------------------------------

func (s *Server) ListScrobblers(ctx context.Context, _ ListScrobblersRequestObject) (ListScrobblersResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.svc.ListScrobblers(ctx, uc)
	if err != nil {
		return nil, err
	}
	out := ScrobblerList{Scrobblers: make([]Scrobbler, 0, len(rows))}
	for _, sc := range rows {
		out.Scrobblers = append(out.Scrobblers, scrobblerJSON(sc))
	}
	return ListScrobblers200JSONResponse(out), nil
}

func (s *Server) ConnectListenBrainz(ctx context.Context, req ConnectListenBrainzRequestObject) (ConnectListenBrainzResponseObject, error) {
	if req.Body == nil {
		return ConnectListenBrainz400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	apiURL := ""
	if req.Body.ApiUrl != nil {
		apiURL = *req.Body.ApiUrl
	}
	sc, err := s.svc.ConnectListenBrainz(ctx, uc, req.Body.Token, apiURL)
	if err != nil {
		return nil, err
	}
	return ConnectListenBrainz200JSONResponse(scrobblerJSON(sc)), nil
}

func (s *Server) DisconnectListenBrainz(ctx context.Context, _ DisconnectListenBrainzRequestObject) (DisconnectListenBrainzResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DisconnectScrobbler(ctx, uc, service.ScrobblerListenBrainz); err != nil {
		return nil, err
	}
	return DisconnectListenBrainz204Response{}, nil
}

func (s *Server) DisconnectLastfm(ctx context.Context, _ DisconnectLastfmRequestObject) (DisconnectLastfmResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DisconnectScrobbler(ctx, uc, service.ScrobblerLastfm); err != nil {
		return nil, err
	}
	return DisconnectLastfm204Response{}, nil
}

func (s *Server) StartLastfmConnect(ctx context.Context, _ StartLastfmConnectRequestObject) (StartLastfmConnectResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	callback := strings.TrimSuffix(s.publicBase, "/") + "/api/v1/scrobble/lastfm/callback"
	authURL, err := s.svc.StartLastfmConnect(ctx, uc, callback)
	if err != nil {
		return nil, err
	}
	return StartLastfmConnect200JSONResponse(LastfmConnectStart{AuthUrl: authURL}), nil
}

func (s *Server) LastfmCallback(ctx context.Context, req LastfmCallbackRequestObject) (LastfmCallbackResponseObject, error) {
	loc := pageStringsFromContext(ctx)
	username, err := s.svc.CompleteLastfmConnect(ctx, req.Params.State, req.Params.Token)
	if err != nil {
		// A message the service carried up is a diagnostic and shows in
		// its own English; the localized sentence is what stands in when
		// there is none.
		msg := kindMessage(err, loc.LastfmFailedBody)
		page := scrobblePage(loc, loc.LastfmFailedTitle, msg)
		if service.KindOf(err) == service.KindService {
			return LastfmCallback502TexthtmlResponse{Body: strings.NewReader(page), ContentLength: int64(len(page))}, nil
		}
		return LastfmCallback400TexthtmlResponse{Body: strings.NewReader(page), ContentLength: int64(len(page))}, nil
	}
	page := scrobblePage(loc, loc.LastfmConnectedTitle, fmt.Sprintf(loc.LastfmConnectedBody, username))
	return LastfmCallback200TexthtmlResponse{Body: strings.NewReader(page), ContentLength: int64(len(page))}, nil
}

// scrobblePageTmpl is the tiny human-facing callback page. A template
// rather than concatenation so escaping is the default rather than a
// call somebody has to remember; the page carries no scripts.
var scrobblePageTmpl = template.Must(template.New("scrobble").Parse(
	`<!doctype html><html lang="{{.Lang}}"><head><meta charset="utf-8"><title>{{.Title}}</title></head>` +
		`<body style="font-family: sans-serif; max-width: 32em; margin: 4em auto;">` +
		`<h1>{{.Title}}</h1><p>{{.Body}}</p></body></html>`))

func scrobblePage(loc *pagetext.Strings, title, body string) string {
	var b strings.Builder
	_ = scrobblePageTmpl.Execute(&b, struct{ Lang, Title, Body string }{loc.Lang, title, body})
	return b.String()
}

// --- push registrations -----------------------------------------------------------

func (s *Server) ListPushRegistrations(ctx context.Context, _ ListPushRegistrationsRequestObject) (ListPushRegistrationsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.svc.PushRegistrations(ctx, uc)
	if err != nil {
		return nil, err
	}
	out := PushRegistrationList{Registrations: make([]PushRegistration, 0, len(rows))}
	for _, r := range rows {
		out.Registrations = append(out.Registrations, pushRegistrationJSON(r))
	}
	return ListPushRegistrations200JSONResponse(out), nil
}

func (s *Server) CreatePushRegistration(ctx context.Context, req CreatePushRegistrationRequestObject) (CreatePushRegistrationResponseObject, error) {
	if req.Body == nil {
		return CreatePushRegistration400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	label := ""
	if req.Body.Label != nil {
		label = *req.Body.Label
	}
	reg, created, err := s.svc.RegisterPushEndpoint(ctx, uc, req.Body.Endpoint, label)
	if err != nil {
		return nil, err
	}
	if created {
		return CreatePushRegistration201JSONResponse(pushRegistrationJSON(reg)), nil
	}
	return CreatePushRegistration200JSONResponse(pushRegistrationJSON(reg)), nil
}

func (s *Server) DeletePushRegistration(ctx context.Context, req DeletePushRegistrationRequestObject) (DeletePushRegistrationResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DeletePushRegistration(ctx, uc, req.RegistrationId); err != nil {
		return nil, err
	}
	return DeletePushRegistration204Response{}, nil
}

func (s *Server) DeleteAllPushRegistrations(ctx context.Context, _ DeleteAllPushRegistrationsRequestObject) (DeleteAllPushRegistrationsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DeleteAllPushRegistrations(ctx, uc); err != nil {
		return nil, err
	}
	return DeleteAllPushRegistrations204Response{}, nil
}

// --- notifications ----------------------------------------------------------------

func (s *Server) ListNotificationEvents(ctx context.Context, _ ListNotificationEventsRequestObject) (ListNotificationEventsResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	events := s.svc.NotifyEvents()
	out := NotificationEventList{Events: make([]NotificationEvent, 0, len(events))}
	for _, e := range events {
		out.Events = append(out.Events, NotificationEvent{
			Name:        e.Name,
			Scope:       NotificationScope(e.Scope),
			Description: e.Description,
		})
	}
	return ListNotificationEvents200JSONResponse(out), nil
}

func (s *Server) ListServerNotificationTargets(ctx context.Context, _ ListServerNotificationTargetsRequestObject) (ListServerNotificationTargetsResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return ListServerNotificationTargets403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	rows, err := s.svc.ListServerNotificationTargets(ctx)
	if err != nil {
		return nil, err
	}
	return ListServerNotificationTargets200JSONResponse(notificationTargetListJSON(rows)), nil
}

func (s *Server) CreateServerNotificationTarget(ctx context.Context, req CreateServerNotificationTargetRequestObject) (CreateServerNotificationTargetResponseObject, error) {
	if req.Body == nil {
		return CreateServerNotificationTarget400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return CreateServerNotificationTarget403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	in, err := notificationTargetInputFromWire(string(req.Body.Kind), req.Body.Label, req.Body.Config, req.Body.EnabledEvents)
	if err != nil {
		return nil, err
	}
	created, err := s.svc.CreateServerNotificationTarget(ctx, in)
	if err != nil {
		return nil, err
	}
	return CreateServerNotificationTarget201JSONResponse(notificationTargetJSON(created)), nil
}

func (s *Server) UpdateServerNotificationTarget(ctx context.Context, req UpdateServerNotificationTargetRequestObject) (UpdateServerNotificationTargetResponseObject, error) {
	if req.Body == nil {
		return UpdateServerNotificationTarget400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return UpdateServerNotificationTarget403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	in, err := notificationTargetInputFromWire("", req.Body.Label, req.Body.Config, req.Body.EnabledEvents)
	if err != nil {
		return nil, err
	}
	updated, err := s.svc.UpdateServerNotificationTarget(ctx, req.TargetId, in)
	if err != nil {
		return nil, err
	}
	return UpdateServerNotificationTarget200JSONResponse(notificationTargetJSON(updated)), nil
}

func (s *Server) DeleteServerNotificationTarget(ctx context.Context, req DeleteServerNotificationTargetRequestObject) (DeleteServerNotificationTargetResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return DeleteServerNotificationTarget403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.svc.DeleteServerNotificationTarget(ctx, req.TargetId); err != nil {
		return nil, err
	}
	return DeleteServerNotificationTarget204Response{}, nil
}

func (s *Server) TestServerNotificationTarget(ctx context.Context, req TestServerNotificationTargetRequestObject) (TestServerNotificationTargetResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return TestServerNotificationTarget403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.svc.TestServerNotificationTarget(ctx, req.TargetId); err != nil {
		return nil, err
	}
	return TestServerNotificationTarget202Response{}, nil
}

func (s *Server) ListMyNotificationTargets(ctx context.Context, _ ListMyNotificationTargetsRequestObject) (ListMyNotificationTargetsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.svc.ListMyNotificationTargets(ctx, uc)
	if err != nil {
		return nil, err
	}
	return ListMyNotificationTargets200JSONResponse(notificationTargetListJSON(rows)), nil
}

func (s *Server) CreateMyNotificationTarget(ctx context.Context, req CreateMyNotificationTargetRequestObject) (CreateMyNotificationTargetResponseObject, error) {
	if req.Body == nil {
		return CreateMyNotificationTarget400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	in, err := notificationTargetInputFromWire(string(req.Body.Kind), req.Body.Label, req.Body.Config, req.Body.EnabledEvents)
	if err != nil {
		return nil, err
	}
	created, err := s.svc.CreateMyNotificationTarget(ctx, uc, in)
	if err != nil {
		return nil, err
	}
	return CreateMyNotificationTarget201JSONResponse(notificationTargetJSON(created)), nil
}

func (s *Server) UpdateMyNotificationTarget(ctx context.Context, req UpdateMyNotificationTargetRequestObject) (UpdateMyNotificationTargetResponseObject, error) {
	if req.Body == nil {
		return UpdateMyNotificationTarget400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	in, err := notificationTargetInputFromWire("", req.Body.Label, req.Body.Config, req.Body.EnabledEvents)
	if err != nil {
		return nil, err
	}
	updated, err := s.svc.UpdateMyNotificationTarget(ctx, uc, req.TargetId, in)
	if err != nil {
		return nil, err
	}
	return UpdateMyNotificationTarget200JSONResponse(notificationTargetJSON(updated)), nil
}

func (s *Server) DeleteMyNotificationTarget(ctx context.Context, req DeleteMyNotificationTargetRequestObject) (DeleteMyNotificationTargetResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DeleteMyNotificationTarget(ctx, uc, req.TargetId); err != nil {
		return nil, err
	}
	return DeleteMyNotificationTarget204Response{}, nil
}

func (s *Server) TestMyNotificationTarget(ctx context.Context, req TestMyNotificationTargetRequestObject) (TestMyNotificationTargetResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.TestMyNotificationTarget(ctx, uc, req.TargetId); err != nil {
		return nil, err
	}
	return TestMyNotificationTarget202Response{}, nil
}

// --- wire conversion --------------------------------------------------------------

func radioStationJSON(st service.RadioStation) RadioStation {
	out := RadioStation{
		Pid:       st.PID,
		Name:      st.Name,
		StreamUrl: st.StreamURL,
		CreatedAt: st.CreatedAt,
	}
	if st.HomepageURL != "" {
		out.HomepageUrl = ptr(st.HomepageURL)
	}
	if st.LogoURL != "" {
		out.LogoUrl = ptr(st.LogoURL)
	}
	return out
}

func radioEditFromWire(e RadioStationEdit) service.RadioStationEdit {
	out := service.RadioStationEdit{Name: e.Name, StreamURL: e.StreamUrl}
	if e.HomepageUrl != nil {
		out.HomepageURL = *e.HomepageUrl
	}
	if e.LogoUrl != nil {
		out.LogoURL = *e.LogoUrl
	}
	return out
}

func scrobblerJSON(sc service.Scrobbler) Scrobbler {
	out := Scrobbler{Service: sc.Service, Available: sc.Available, Connected: sc.Connected}
	if sc.Username != "" {
		out.Username = ptr(sc.Username)
	}
	if sc.APIURL != "" {
		out.ApiUrl = ptr(sc.APIURL)
	}
	if !sc.LastSuccessAt.IsZero() {
		out.LastSuccessAt = ptr(sc.LastSuccessAt)
	}
	if sc.LastError != "" {
		out.LastError = ptr(sc.LastError)
		out.LastErrorAt = ptr(sc.LastErrorAt)
	}
	return out
}

func pushRegistrationJSON(r service.PushRegistration) PushRegistration {
	out := PushRegistration{Pid: r.PID, Endpoint: r.Endpoint, CreatedAt: r.CreatedAt}
	if r.Label != "" {
		out.Label = ptr(r.Label)
	}
	return out
}

// notificationTargetInputFromWire converts one create or update body.
// The free-form config object round-trips through JSON so the service
// and providers see the raw document; kind is empty on updates (fixed
// at creation, resolved from the stored row).
func notificationTargetInputFromWire(kind string, label *string, config map[string]interface{}, events []string) (service.NotificationTargetInput, error) {
	raw, err := json.Marshal(config)
	if err != nil {
		return service.NotificationTargetInput{}, &service.Error{Kind: service.KindInvalid, Msg: "config is not a valid document"}
	}
	in := service.NotificationTargetInput{
		Kind:          kind,
		Config:        json.RawMessage(raw),
		EnabledEvents: events,
	}
	if label != nil {
		in.Label = *label
	}
	return in, nil
}

func notificationTargetListJSON(rows []service.NotificationTarget) NotificationTargetList {
	out := NotificationTargetList{Targets: make([]NotificationTarget, 0, len(rows))}
	for _, r := range rows {
		out.Targets = append(out.Targets, notificationTargetJSON(r))
	}
	return out
}

func notificationTargetJSON(t service.NotificationTarget) NotificationTarget {
	config := map[string]interface{}{}
	// The service hands the opened document; an unreadable one already
	// degraded to {} there.
	_ = json.Unmarshal(t.Config, &config)
	out := NotificationTarget{
		Pid:           t.PID,
		Kind:          NotificationTargetKind(t.Kind),
		Scope:         NotificationScope(t.Scope),
		Config:        config,
		EnabledEvents: t.EnabledEvents,
		CreatedAt:     t.CreatedAt,
	}
	if t.Label != "" {
		out.Label = ptr(t.Label)
	}
	if !t.LastSuccessAt.IsZero() {
		out.LastSuccessAt = ptr(t.LastSuccessAt)
	}
	if t.LastError != "" {
		out.LastError = ptr(t.LastError)
		out.LastErrorAt = ptr(t.LastErrorAt)
	}
	return out
}
