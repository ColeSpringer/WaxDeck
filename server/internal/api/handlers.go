package api

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

// Server implements StrictServerInterface with the development stubs:
// an in-memory session store and a tiny built-in catalog. Real account
// storage, WaxBin-backed browse, and the WaxFlow bridge arrive later.
type Server struct {
	Version string

	sessions sessionStore
	catalog  []Item
}

func NewServer(version string) *Server {
	s := &Server{
		Version: version,
		catalog: devCatalog(),
	}
	// Sort the immutable catalog by (title, pid) once, so browse just filters
	// and paginates it instead of re-sorting on every request.
	sort.Slice(s.catalog, func(i, j int) bool {
		if s.catalog[i].Title != s.catalog[j].Title {
			return s.catalog[i].Title < s.catalog[j].Title
		}
		return s.catalog[i].Pid < s.catalog[j].Pid
	})
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

// --- library (stub catalog) -----------------------------------------------------

func (s *Server) ListItems(ctx context.Context, req ListItemsRequestObject) (ListItemsResponseObject, error) {
	// Generated binding does not enforce enum membership on query params.
	if req.Params.MediaType != nil && !req.Params.MediaType.Valid() {
		return ListItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown mediaType"))}, nil
	}
	// The catalog is kept sorted by (title, pid) at construction, so this
	// filtered slice preserves that order (the keyset the cursor encodes).
	items := make([]Item, 0, len(s.catalog))
	for _, it := range s.catalog {
		if req.Params.MediaType != nil && it.MediaType != *req.Params.MediaType {
			continue
		}
		items = append(items, it)
	}

	start := 0
	if req.Params.Cursor != nil {
		title, pid, err := decodeCursor(*req.Params.Cursor)
		if err != nil {
			return ListItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "malformed cursor"))}, nil
		}
		start = sort.Search(len(items), func(i int) bool {
			if items[i].Title != title {
				return items[i].Title > title
			}
			return items[i].Pid > pid
		})
	}

	limit := 100
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	// The generated binding does not enforce the spec's min/max on limit, so
	// reject out-of-range values rather than computing invalid slice bounds.
	if limit < 1 || limit > 500 {
		return ListItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	end := min(start+limit, len(items))

	page := ItemPage{Items: make([]ItemSummary, 0, end-start)}
	for _, it := range items[start:end] {
		page.Items = append(page.Items, it.summary())
	}
	if end < len(items) {
		last := items[end-1]
		c := encodeCursor(last.Title, last.Pid)
		page.NextCursor = &c
	}
	return ListItems200JSONResponse(page), nil
}

func (s *Server) GetItem(ctx context.Context, req GetItemRequestObject) (GetItemResponseObject, error) {
	if it, ok := s.find(req.Pid); ok {
		return GetItem200JSONResponse(it), nil
	}
	return GetItem404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
}

func (s *Server) GetPlayInfo(ctx context.Context, req GetPlayInfoRequestObject) (GetPlayInfoResponseObject, error) {
	it, ok := s.find(req.Pid)
	if !ok {
		return GetPlayInfo404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
	}
	// Development stub: a well-formed response whose URL points at the
	// not-yet-implemented /media/stream. Real media tokens and the WaxFlow
	// bridge arrive later.
	return GetPlayInfo200JSONResponse{
		Pid:        it.Pid,
		Url:        fmt.Sprintf("/media/stream?pid=%s&mt=devstub", it.Pid),
		MimeType:   stubMime(it.MediaType),
		DurationMs: it.DurationMs,
		Seekable:   true,
		ExpiresAt:  time.Now().Add(15 * time.Minute).UTC(),
	}, nil
}

func (s *Server) find(pid string) (Item, bool) {
	for _, it := range s.catalog {
		if it.Pid == pid {
			return it, true
		}
	}
	return Item{}, false
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

// WriteError writes the spec's Error schema; used by the API middleware and by
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

// ResponseErrorHandler reports handler-returned errors as structured 500s.
func ResponseErrorHandler(w http.ResponseWriter, _ *http.Request, _ error) {
	writeError(w, http.StatusInternalServerError, "internal", "internal server error")
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
	if _, err := rand.Read(buf); err != nil {
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

// Cursors are opaque keyset positions: a uvarint title length, the title
// bytes, then the pid. Length-prefixing keeps the split unambiguous for any
// title content. A fixed delimiter would corrupt titles that contain it.
func encodeCursor(title, pid string) string {
	buf := binary.AppendUvarint(nil, uint64(len(title)))
	buf = append(buf, title...)
	buf = append(buf, pid...)
	return base64.RawURLEncoding.EncodeToString(buf)
}

func decodeCursor(c string) (title, pid string, err error) {
	raw, err := base64.RawURLEncoding.DecodeString(c)
	if err != nil {
		return "", "", err
	}
	titleLen, n := binary.Uvarint(raw)
	if n <= 0 || titleLen > uint64(len(raw)-n) {
		return "", "", fmt.Errorf("malformed cursor")
	}
	return string(raw[n : n+int(titleLen)]), string(raw[n+int(titleLen):]), nil
}

func stubMime(mt MediaType) string {
	switch mt {
	case Podcast:
		return "audio/mpeg"
	case Audiobook:
		return "audio/mp4"
	default:
		return "audio/flac"
	}
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

func devCatalog() []Item {
	str := func(s string) *string { return &s }
	num := func(n int) *int { return &n }
	added := time.Date(2026, 7, 11, 0, 0, 0, 0, time.UTC)
	return []Item{
		{
			Pid:         "tr-01JZWAXDECKDEVTRACK000000A",
			MediaType:   Music,
			Title:       "Prancing Pony Blues",
			Artist:      str("The Inn Keepers"),
			Album:       str("Songs From Bree"),
			DurationMs:  214000,
			Genres:      &[]string{"blues"},
			Year:        num(2024),
			TrackNumber: num(1),
			DiscNumber:  num(1),
			AddedAt:     &added,
		},
		{
			Pid:        "ep-01JZWAXDECKDEVEPISODE0000B",
			MediaType:  Podcast,
			Title:      "Second Breakfast, Explained",
			Artist:     str("Shire Radio"),
			Album:      str("Shire Radio Weekly"),
			DurationMs: 1861000,
			AddedAt:    &added,
		},
		{
			Pid:        "bk-01JZWAXDECKDEVBOOK000000C",
			MediaType:  Audiobook,
			Title:      "There And Back Again",
			Artist:     str("B. Baggins"),
			DurationMs: 39600000,
			Genres:     &[]string{"memoir"},
			AddedAt:    &added,
		},
	}
}

func (it Item) summary() ItemSummary {
	return ItemSummary{
		Pid:        it.Pid,
		MediaType:  it.MediaType,
		Title:      it.Title,
		Artist:     it.Artist,
		Album:      it.Album,
		DurationMs: it.DurationMs,
		ArtUrl:     it.ArtUrl,
	}
}
