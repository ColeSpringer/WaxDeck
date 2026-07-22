package api

import (
	"context"
	"fmt"
	"html"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

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
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if _, err := s.svc.RadioStationByPID(ctx, req.Pid); err != nil {
		return nil, err
	}
	token, _ := s.media.Mint(p.User.ID, req.Pid)
	out := RadioPlayInfo{
		Url: "/media/radio/" + url.PathEscape(req.Pid) + "?mt=" + url.QueryEscape(token),
	}
	if title := s.svc.RadioNowPlaying(req.Pid); title != "" {
		out.NowPlaying = ptr(title)
	}
	return GetRadioPlayInfo200JSONResponse(out), nil
}

func (s *Server) SearchRadioDirectory(ctx context.Context, req SearchRadioDirectoryRequestObject) (SearchRadioDirectoryResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	limit := 25
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	entries, err := s.svc.SearchRadioDirectory(ctx, req.Params.Query, limit)
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
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, streamURL, nil)
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
	ct := resp.Header.Get("Content-Type")
	if ct == "" {
		ct = "audio/mpeg"
	}
	w.Header().Set("Content-Type", ct)
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
	var segTitle string
	var segSince time.Time
	onBlock := func(block []byte) {
		title, ok := icyStreamTitle(block)
		if !ok {
			return
		}
		s.svc.NoteRadioTitle(pid, title)
		if title == segTitle {
			return
		}
		if segTitle != "" && time.Since(segSince) >= service.RadioScrobbleMinListen {
			s.svc.ScrobbleRadioPlay(r.Context(), user, pid, segTitle, segSince)
		}
		segTitle, segSince = title, time.Now()
	}
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if relay != nil {
				relay.feed(buf[:n], emit, onBlock)
			} else {
				emit(buf[:n])
			}
			if writeErr != nil {
				return
			}
			// Live audio wants low latency; flush every chunk.
			rc.Flush()
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
	username, err := s.svc.CompleteLastfmConnect(ctx, req.Params.State, req.Params.Token)
	if err != nil {
		msg := kindMessage(err, "the authorization could not be completed")
		page := scrobblePage("Last.fm connection failed", msg)
		if service.KindOf(err) == service.KindService {
			return LastfmCallback502TexthtmlResponse{Body: strings.NewReader(page), ContentLength: int64(len(page))}, nil
		}
		return LastfmCallback400TexthtmlResponse{Body: strings.NewReader(page), ContentLength: int64(len(page))}, nil
	}
	page := scrobblePage("Last.fm connected",
		"Connected as "+username+". You can close this window; WaxDeck delivers your scrobbles from here on.")
	return LastfmCallback200TexthtmlResponse{Body: strings.NewReader(page), ContentLength: int64(len(page))}, nil
}

// scrobblePage renders the tiny human-facing callback page. All values
// are escaped; the page carries no scripts.
func scrobblePage(title, body string) string {
	return "<!doctype html><html><head><meta charset=\"utf-8\"><title>" +
		html.EscapeString(title) + "</title></head><body style=\"font-family: sans-serif; max-width: 32em; margin: 4em auto;\"><h1>" +
		html.EscapeString(title) + "</h1><p>" + html.EscapeString(body) + "</p></body></html>"
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

func (s *Server) GetNotificationConfig(ctx context.Context, _ GetNotificationConfigRequestObject) (GetNotificationConfigResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return GetNotificationConfig403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	cfg, err := s.svc.NotificationSettings(ctx)
	if err != nil {
		return nil, err
	}
	return GetNotificationConfig200JSONResponse(notificationConfigJSON(cfg)), nil
}

func (s *Server) PutNotificationConfig(ctx context.Context, req PutNotificationConfigRequestObject) (PutNotificationConfigResponseObject, error) {
	if req.Body == nil {
		return PutNotificationConfig400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return PutNotificationConfig403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	targets := ""
	if req.Body.Targets != nil {
		targets = *req.Body.Targets
	}
	cfg, err := s.svc.PutNotificationSettings(ctx, req.Body.AppriseUrl, targets, req.Body.EnabledEvents)
	if err != nil {
		return nil, err
	}
	return PutNotificationConfig200JSONResponse(notificationConfigJSON(cfg)), nil
}

func (s *Server) TestNotifications(ctx context.Context, _ TestNotificationsRequestObject) (TestNotificationsResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return TestNotifications403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.svc.TestNotifications(ctx); err != nil {
		return nil, err
	}
	return TestNotifications202Response{}, nil
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

func notificationConfigJSON(cfg service.NotificationConfig) NotificationConfig {
	out := NotificationConfig{
		AppriseUrl:    cfg.AppriseURL,
		EnabledEvents: cfg.EnabledEvents,
		KnownEvents:   cfg.KnownEvents,
	}
	if cfg.Targets != "" {
		out.Targets = ptr(cfg.Targets)
	}
	return out
}
