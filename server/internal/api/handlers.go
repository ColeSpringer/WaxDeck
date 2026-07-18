package api

import (
	"bytes"
	"context"
	cryptorand "crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"net/http"
	"net/url"
	"strings"
	"sync"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// Server implements StrictServerInterface over the library service and
// the WaxFlow bridge. Authentication is still the development stub (any
// credentials map to the built-in admin); real accounts arrive with the
// identity work.
type Server struct {
	Version string

	svc      *service.Library
	bridge   *flow.Bridge
	sessions sessionStore
}

// NewServer builds the API server. bridge may be nil when streaming is
// not configured; play-info then reports streaming unavailable while
// every catalog surface keeps working.
func NewServer(version string, svc *service.Library, bridge *flow.Bridge) *Server {
	s := &Server{Version: version, svc: svc, bridge: bridge}
	s.sessions.m = make(map[string]User)
	return s
}

// --- system ------------------------------------------------------------------

func (s *Server) GetHealth(ctx context.Context, _ GetHealthRequestObject) (GetHealthResponseObject, error) {
	return GetHealth200JSONResponse{
		Status:     "ok",
		Version:    s.Version,
		ApiVersion: 1,
	}, nil
}

// --- auth (development stub) ---------------------------------------------------

const sessionCookie = "waxdeck_session"

func (s *Server) Login(ctx context.Context, req LoginRequestObject) (LoginResponseObject, error) {
	if req.Body == nil || req.Body.Username == "" || req.Body.Password == "" {
		return Login400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "username and password are required"))}, nil
	}
	// Development stub: any non-empty credentials map to the built-in dev user.
	user := devUser(req.Body.Username)
	token := s.sessions.create(user)
	cookie := &http.Cookie{
		Name:     sessionCookie,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		// Secure is intentionally unset here so the plain-HTTP localhost demo
		// works. Real sessions will set Secure from deployment config whenever
		// the origin is HTTPS: the cookie must never ride cleartext in prod.
	}
	setCookie := cookie.String()
	return Login200JSONResponse{
		Body:    LoginResponse{User: user, Token: token},
		Headers: Login200ResponseHeaders{SetCookie: &setCookie},
	}, nil
}

func (s *Server) Logout(ctx context.Context, _ LogoutRequestObject) (LogoutResponseObject, error) {
	if token, ok := tokenFromContext(ctx); ok {
		s.sessions.revoke(token)
	}
	expired := &http.Cookie{
		Name:     sessionCookie,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   -1,
	}
	setCookie := expired.String()
	return Logout204Response{Headers: Logout204ResponseHeaders{SetCookie: &setCookie}}, nil
}

func (s *Server) GetSession(ctx context.Context, _ GetSessionRequestObject) (GetSessionResponseObject, error) {
	if user, ok := userFromContext(ctx); ok {
		return GetSession200JSONResponse{Authenticated: true, User: &user}, nil
	}
	return GetSession200JSONResponse{Authenticated: false}, nil
}

// --- library ---------------------------------------------------------------------

func (s *Server) ListItems(ctx context.Context, req ListItemsRequestObject) (ListItemsResponseObject, error) {
	// The generated binding enforces neither enum membership nor the
	// spec's limit bounds on query params, so both are checked here.
	if req.Params.MediaType != nil && !req.Params.MediaType.Valid() {
		return ListItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown mediaType"))}, nil
	}
	limit, ok := pageLimit(req.Params.Limit, 100, 500)
	if !ok {
		return ListItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	mediaType := ""
	if req.Params.MediaType != nil {
		mediaType = string(*req.Params.MediaType)
	}
	page, err := s.svc.Items(ctx, mediaType, deref(req.Params.Cursor), limit)
	if err != nil {
		if kind := service.KindOf(err); kind == service.KindInvalid {
			return ListItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return ListItems200JSONResponse(pageJSON(page)), nil
}

func (s *Server) BrowseList(ctx context.Context, req BrowseListRequestObject) (BrowseListResponseObject, error) {
	if !req.Params.List.Valid() {
		return BrowseList400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown list"))}, nil
	}
	limit, ok := pageLimit(req.Params.Limit, 100, 500)
	if !ok {
		return BrowseList400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	// An omitted seed on the random list gets a fresh one, returned on
	// the page so later pages keep the same shuffled order. Seed zero
	// would otherwise be a fixed order silently posing as a shuffle.
	seed := derefInt64(req.Params.Seed)
	if req.Params.List == Random && req.Params.Seed == nil {
		seed = rand.Int64()
	}
	page, err := s.svc.Browse(ctx, string(req.Params.List), seed, deref(req.Params.Cursor), limit)
	if err != nil {
		if kind := service.KindOf(err); kind == service.KindInvalid {
			return BrowseList400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := pageJSON(page)
	if req.Params.List == Random {
		out.Seed = &seed
	}
	return BrowseList200JSONResponse(out), nil
}

func (s *Server) Search(ctx context.Context, req SearchRequestObject) (SearchResponseObject, error) {
	if strings.TrimSpace(req.Params.Q) == "" {
		return Search400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "q is required"))}, nil
	}
	limit, ok := pageLimit(req.Params.Limit, 20, 100)
	if !ok {
		return Search400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 100"))}, nil
	}
	res, err := s.svc.Search(ctx, req.Params.Q, limit)
	if err != nil {
		return nil, err
	}
	conv := func(hits []service.SearchHit) []SearchHit {
		out := make([]SearchHit, 0, len(hits))
		for _, h := range hits {
			hit := SearchHit{Pid: h.PID, Kind: h.Kind, Title: h.Title}
			if h.Subtitle != "" {
				hit.Subtitle = ptr(h.Subtitle)
			}
			out = append(out, hit)
		}
		return out
	}
	return Search200JSONResponse{
		Query:     res.Query,
		Artists:   conv(res.Artists),
		Albums:    conv(res.Albums),
		Tracks:    conv(res.Tracks),
		Books:     conv(res.Books),
		Episodes:  conv(res.Episodes),
		Truncated: ptr(res.Truncated),
	}, nil
}

func (s *Server) GetItem(ctx context.Context, req GetItemRequestObject) (GetItemResponseObject, error) {
	d, err := s.svc.Item(ctx, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetItem404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetItem200JSONResponse(itemJSON(d)), nil
}

func (s *Server) GetItemArt(ctx context.Context, req GetItemArtRequestObject) (GetItemArtResponseObject, error) {
	size := 0
	if req.Params.Size != nil {
		size = *req.Params.Size
		if size < 16 || size > 2048 {
			return GetItemArt400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "size must be between 16 and 2048"))}, nil
		}
	}
	blob, err := s.svc.Art(ctx, req.Pid, size)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetItemArt404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no artwork for pid "+req.Pid))}, nil
		}
		return nil, err
	}
	// The validator is the source image hash scoped by the requested
	// size: same source, different thumbnail sizes, different bytes.
	etag := fmt.Sprintf("%q", fmt.Sprintf("%s-%d", blob.SourceHash, size))
	if req.Params.IfNoneMatch != nil && *req.Params.IfNoneMatch == etag {
		return GetItemArt304Response{}, nil
	}
	body := bytes.NewReader(blob.Bytes)
	length := int64(len(blob.Bytes))
	headers := GetItemArt200ResponseHeaders{ETag: &etag}
	switch blob.MimeType {
	case "image/png":
		return GetItemArt200ImagepngResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/webp":
		return GetItemArt200ImagewebpResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/gif":
		return GetItemArt200ImagegifResponse{Body: body, ContentLength: length, Headers: headers}, nil
	default:
		return GetItemArt200ImagejpegResponse{Body: body, ContentLength: length, Headers: headers}, nil
	}
}

func (s *Server) GetItemLyrics(ctx context.Context, req GetItemLyricsRequestObject) (GetItemLyricsResponseObject, error) {
	ly, err := s.svc.ItemLyrics(ctx, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetItemLyrics404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no lyrics for pid "+req.Pid))}, nil
		}
		return nil, err
	}
	out := Lyrics{Pid: ly.PID, Source: ly.Source}
	if len(ly.Synced) > 0 {
		lines := make([]SyncedLine, 0, len(ly.Synced))
		for _, l := range ly.Synced {
			lines = append(lines, SyncedLine{TimeMs: l.TimeMS, Text: l.Text})
		}
		out.Synced = &lines
	}
	if ly.Unsynced != "" {
		out.Unsynced = ptr(ly.Unsynced)
	}
	return GetItemLyrics200JSONResponse(out), nil
}

// --- admin -----------------------------------------------------------------------

func (s *Server) RescanLibrary(ctx context.Context, _ RescanLibraryRequestObject) (RescanLibraryResponseObject, error) {
	job, err := s.svc.Rescan(ctx)
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			return RescanLibrary409JSONResponse{ConflictJSONResponse(errObj("conflict", "a conflicting catalog job is already running"))}, nil
		}
		return nil, err
	}
	return RescanLibrary202JSONResponse(jobJSON(job)), nil
}

func (s *Server) GetJob(ctx context.Context, req GetJobRequestObject) (GetJobResponseObject, error) {
	job, err := s.svc.JobStatus(ctx, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetJob404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no job with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetJob200JSONResponse(jobJSON(job)), nil
}

// --- playback --------------------------------------------------------------------

func (s *Server) GetPlayInfo(ctx context.Context, req GetPlayInfoRequestObject) (GetPlayInfoResponseObject, error) {
	if s.bridge == nil {
		return nil, errStreamingUnavailable
	}
	// AuthMiddleware guarantees a user on this path; the guard covers a
	// future miswiring, not a reachable state.
	user, ok := userFromContext(ctx)
	if !ok {
		return GetPlayInfo401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no user in request context"))}, nil
	}
	info, err := s.bridge.PlayInfoFor(ctx, user.Id, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetPlayInfo404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetPlayInfo200JSONResponse{
		Pid:        req.Pid,
		Url:        info.URL,
		MimeType:   info.MimeType,
		DurationMs: info.DurationMS,
		Seekable:   info.Seekable,
		ExpiresAt:  info.ExpiresAt,
	}, nil
}

func (s *Server) GetPlayState(ctx context.Context, req GetPlayStateRequestObject) (GetPlayStateResponseObject, error) {
	st, err := s.svc.PlayState(ctx, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetPlayState404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	out := PlayState{
		Pid:        st.PID,
		PositionMs: st.PositionMS,
		Played:     st.Played,
		Finished:   st.Finished,
		PlayCount:  st.PlayCount,
		Starred:    st.Starred,
	}
	if !st.UpdatedAt.IsZero() {
		out.UpdatedAt = &st.UpdatedAt
	}
	return GetPlayState200JSONResponse(out), nil
}

func (s *Server) PutPlayState(ctx context.Context, req PutPlayStateRequestObject) (PutPlayStateResponseObject, error) {
	if req.Body == nil {
		return PutPlayState400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	err := s.svc.Checkpoint(ctx, req.Pid, req.Body.PositionMs)
	switch service.KindOf(err) {
	case "":
		return PutPlayState204Response{}, nil
	case service.KindNotFound:
		return PutPlayState404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
	case service.KindInvalid:
		return PutPlayState400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
}

func (s *Server) ReportListens(ctx context.Context, req ReportListensRequestObject) (ReportListensResponseObject, error) {
	if req.Body == nil || len(req.Body.Sessions) == 0 {
		return ReportListens400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "sessions must not be empty"))}, nil
	}
	if len(req.Body.Sessions) > 500 {
		return ReportListens400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "at most 500 sessions per report"))}, nil
	}
	// AuthMiddleware guarantees a user on this path; the guard covers a
	// future miswiring, not a reachable state.
	user, ok := userFromContext(ctx)
	if !ok {
		return ReportListens401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no user in request context"))}, nil
	}
	sessions := make([]service.ListenSession, 0, len(req.Body.Sessions))
	for _, in := range req.Body.Sessions {
		s := service.ListenSession{
			SessionID: in.SessionId,
			PID:       in.Pid,
			StartedAt: in.StartedAt,
			MsPlayed:  in.MsPlayed,
			Finished:  derefBool(in.Finished),
			Client:    deref(in.Client),
		}
		if in.Source != nil {
			s.Source = string(*in.Source)
		}
		sessions = append(sessions, s)
	}
	res, err := s.svc.IngestListens(ctx, user.Id, sessions)
	if err != nil {
		return nil, err
	}
	out := ListenIngestResult{Accepted: res.Accepted, Duplicates: res.Duplicates}
	if len(res.Rejected) > 0 {
		rej := make([]RejectedListen, 0, len(res.Rejected))
		for _, r := range res.Rejected {
			rej = append(rej, RejectedListen{SessionId: r.SessionID, Code: r.Code, Message: r.Message})
		}
		out.Rejected = &rej
	}
	return ReportListens200JSONResponse(out), nil
}

// --- DTO conversion ---------------------------------------------------------------

func pageJSON(p service.Page) ItemPage {
	out := ItemPage{Items: make([]ItemSummary, 0, len(p.Items))}
	for _, it := range p.Items {
		out.Items = append(out.Items, summaryJSON(it))
	}
	if p.Next != "" {
		out.NextCursor = ptr(p.Next)
	}
	return out
}

func summaryJSON(it service.ItemSummary) ItemSummary {
	s := ItemSummary{
		Pid:        it.PID,
		MediaType:  MediaType(it.MediaType),
		Title:      it.Title,
		DurationMs: it.DurationMS,
		ArtUrl:     ptr("/api/v1/items/" + url.PathEscape(it.PID) + "/art"),
	}
	if it.Artist != "" {
		s.Artist = ptr(it.Artist)
	}
	if it.Album != "" {
		s.Album = ptr(it.Album)
	}
	return s
}

func itemJSON(d service.ItemDetail) Item {
	it := Item{
		Pid:        d.PID,
		MediaType:  MediaType(d.MediaType),
		Title:      d.Title,
		DurationMs: d.DurationMS,
		ArtUrl:     ptr("/api/v1/items/" + url.PathEscape(d.PID) + "/art"),
	}
	if d.Artist != "" {
		it.Artist = ptr(d.Artist)
	}
	if d.Album != "" {
		it.Album = ptr(d.Album)
	}
	if len(d.Genres) > 0 {
		it.Genres = &d.Genres
	}
	if d.Year != 0 {
		it.Year = ptr(d.Year)
	}
	if d.TrackNo != 0 {
		it.TrackNumber = ptr(d.TrackNo)
	}
	if d.DiscNo != 0 {
		it.DiscNumber = ptr(d.DiscNo)
	}
	if d.Codec != "" {
		it.Codec = ptr(d.Codec)
	}
	if d.Container != "" {
		it.Container = ptr(d.Container)
	}
	if d.SampleRate != 0 {
		it.SampleRate = ptr(d.SampleRate)
	}
	if d.Bitrate != 0 {
		it.Bitrate = ptr(d.Bitrate)
	}
	if !d.AddedAt.IsZero() {
		it.AddedAt = &d.AddedAt
	}
	return it
}

func jobJSON(j service.Job) Job {
	out := Job{Pid: j.PID, Kind: j.Kind, State: j.State}
	if j.Progress > 0 {
		out.Progress = ptr(j.Progress)
	}
	if j.Message != "" {
		out.Message = ptr(j.Message)
	}
	if j.Error != "" {
		out.Error = ptr(j.Error)
	}
	return out
}

// --- small helpers ----------------------------------------------------------------

func ptr[T any](v T) *T { return &v }

func deref(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

func derefBool(p *bool) bool { return p != nil && *p }

func derefInt64(p *int64) int64 {
	if p == nil {
		return 0
	}
	return *p
}

// pageLimit validates an optional limit param against [1, max],
// defaulting when absent.
func pageLimit(p *int, def, max int) (int, bool) {
	if p == nil {
		return def, true
	}
	if *p < 1 || *p > max {
		return 0, false
	}
	return *p, true
}

// errStreamingUnavailable reports play-info without a configured
// WaxFlow bridge. It reaches clients as a structured 500.
var errStreamingUnavailable = &service.Error{
	Kind: service.KindInternal,
	Msg:  "streaming is not configured on this server",
}

// --- auth middleware ------------------------------------------------------------

type ctxKey int

const (
	ctxUser ctxKey = iota
	ctxToken
)

// publicPaths are reachable without a session (per the spec's per-operation
// `security` overrides).
var publicPaths = map[string]bool{
	"/api/v1/health":       true,
	"/api/v1/auth/login":   true,
	"/api/v1/auth/session": true,
	"/api/v1/auth/logout":  true,
}

// AuthMiddleware resolves the session (cookie or bearer) into the request
// context and rejects unauthenticated calls to protected endpoints.
func (s *Server) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Try each presented credential in precedence order; a stale or
		// invalid bearer must not shadow a valid session cookie.
		for _, token := range authCandidates(r) {
			if user, ok := s.sessions.lookup(token); ok {
				ctx := context.WithValue(r.Context(), ctxUser, user)
				ctx = context.WithValue(ctx, ctxToken, token)
				r = r.WithContext(ctx)
				break
			}
		}
		if _, ok := userFromContext(r.Context()); !ok && !publicPaths[r.URL.Path] {
			writeError(w, http.StatusUnauthorized, "unauthenticated", "no valid session or token was presented")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// authCandidates returns the credential tokens to try, in precedence order:
// the bearer token (native clients) first, then the session cookie (web).
// Returning both lets the caller fall through a stale bearer to a good cookie.
func authCandidates(r *http.Request) []string {
	var tokens []string
	// The Authorization scheme name is case-insensitive (RFC 7235 section 2.1),
	// so accept "Bearer", "bearer", "BEARER", and other casings.
	if h := r.Header.Get("Authorization"); len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		tokens = append(tokens, h[7:])
	}
	if c, err := r.Cookie(sessionCookie); err == nil && c.Value != "" {
		tokens = append(tokens, c.Value)
	}
	return tokens
}

func userFromContext(ctx context.Context) (User, bool) {
	u, ok := ctx.Value(ctxUser).(User)
	return u, ok
}

func tokenFromContext(ctx context.Context) (string, bool) {
	t, ok := ctx.Value(ctxToken).(string)
	return t, ok
}

// writeError writes the spec's Error schema; used by the API middleware and by
// the strict handler's request/response error hooks in main.
func writeError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(Error{Code: code, Message: message})
}

// RequestErrorHandler adapts strict-server binding failures (bad params, bad
// bodies) to the structured Error schema.
func RequestErrorHandler(w http.ResponseWriter, _ *http.Request, err error) {
	writeError(w, http.StatusBadRequest, "invalid-request", err.Error())
}

// ResponseErrorHandler reports handler-returned errors as structured
// responses: catalog maintenance as the typed 503 clients render as a
// banner, everything else as an opaque 500. Handlers map expected kinds
// to typed responses themselves; the not-found and invalid fallbacks
// here keep the status honest when one slips through.
func ResponseErrorHandler(w http.ResponseWriter, _ *http.Request, err error) {
	switch service.KindOf(err) {
	case service.KindMaintenance:
		writeError(w, http.StatusServiceUnavailable, "catalog-maintenance",
			"the catalog is temporarily under maintenance; retry shortly")
	case service.KindNotFound:
		writeError(w, http.StatusNotFound, "not-found", kindMessage(err, "not found"))
	case service.KindInvalid:
		writeError(w, http.StatusBadRequest, "invalid-request", kindMessage(err, "invalid request"))
	case service.KindConflict:
		writeError(w, http.StatusConflict, "conflict", kindMessage(err, "a conflicting operation is running"))
	default:
		var se *service.Error
		if errors.As(err, &se) && se.Msg != "" && se.Kind == service.KindInternal {
			writeError(w, http.StatusInternalServerError, "internal", se.Msg)
			return
		}
		writeError(w, http.StatusInternalServerError, "internal", "internal server error")
	}
}

// kindMessage returns the service error's own message when it carries
// one, else fallback. Only the service's Msg is surfaced, never a
// wrapped error's text, which may name internals.
func kindMessage(err error, fallback string) string {
	var se *service.Error
	if errors.As(err, &se) && se.Msg != "" {
		return se.Msg
	}
	return fallback
}

// --- session store (in-memory stub) ----------------------------------------------

// maxStubSessions bounds the in-memory session map. The development stub has
// no session expiry, so this cap is the only thing preventing unbounded
// growth. Real session lifecycle (TTL, persistence, revocation) arrives with
// identity work.
const maxStubSessions = 4096

type sessionStore struct {
	mu sync.RWMutex
	m  map[string]User
}

func (st *sessionStore) create(u User) string {
	buf := make([]byte, 32)
	if _, err := cryptorand.Read(buf); err != nil {
		panic(err) // crypto/rand failure is not recoverable
	}
	token := base64.RawURLEncoding.EncodeToString(buf)
	st.mu.Lock()
	defer st.mu.Unlock()
	st.m[token] = u
	// Evict an existing entry when over the cap so the map cannot grow without
	// bound. Map iteration order makes the victim effectively arbitrary, which
	// is acceptable for a stub backstop that normal use never reaches.
	if len(st.m) > maxStubSessions {
		for k := range st.m {
			if k != token {
				delete(st.m, k)
				break
			}
		}
	}
	return token
}

func (st *sessionStore) lookup(token string) (User, bool) {
	st.mu.RLock()
	defer st.mu.RUnlock()
	u, ok := st.m[token]
	return u, ok
}

func (st *sessionStore) revoke(token string) {
	st.mu.Lock()
	defer st.mu.Unlock()
	delete(st.m, token)
}

// --- helpers & dev data ------------------------------------------------------------

func errObj(code, message string) Error {
	return Error{Code: code, Message: message}
}

func devUser(username string) User {
	name := "Development User"
	return User{
		Id:          "us-01JZWAXDECKDEVUSER00000000",
		Username:    username,
		DisplayName: &name,
		Roles:       []string{"admin"},
	}
}
