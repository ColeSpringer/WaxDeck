package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"net"
	"net/http"
	"net/url"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/connect"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/httpcache"
	"github.com/colespringer/waxdeck/server/internal/pagetext"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Server implements StrictServerInterface over the library service,
// the WaxFlow bridge, and the session manager.
type Server struct {
	Version string

	svc      *service.Library
	bridge   *flow.Bridge
	sessions *auth.Sessions
	oidc     *auth.OIDC
	limiter  *auth.RateLimiter
	// media mints and verifies the query-string tokens the offline
	// download endpoint uses (the streaming bridge holds its own
	// reference to the same instance).
	media *auth.MediaTokens
	log   logger
	// connect is the multi-device control core; nil only in tests
	// that exercise surfaces away from the player.
	connect *connect.Service
	// group supervises per-connection WebSocket writers.
	group *supervise.Group
	// bases are the advertise bases cast preflight reports.
	bases connect.Bases
	// cookieSecure marks session cookies Secure; set whenever the
	// deployed origin is HTTPS, never on the plain-HTTP LAN default.
	cookieSecure bool
	// publicBase is the externally reachable base URL; the OIDC
	// callback redirect URI derives from it.
	publicBase string
	// backups is the backup and staged-restore manager; nil in tests
	// that exercise other surfaces.
	backups *service.Backups
	// backupWake hands a claimed backup id to the supervised runner
	// loop in main; lossy sends never block a handler (the runner also
	// sweeps for claimed-but-unrun rows).
	backupWake chan string
	// shares mints and verifies the public share capability tokens; the
	// database stores no share secrets.
	shares *auth.ShareTokens
	// workerTokens authenticate external similarity workers on the
	// worker endpoints and the analysis audio route. Empty disables the
	// worker API.
	workerTokens []string
	// shareStreams caps concurrent anonymous streams per share so a
	// public link never becomes a bandwidth faucet.
	shareStreams shareStreamGate
	// relayStreams caps concurrent third-party relays per account, so
	// no one caller can pin goroutines and upstream sockets against
	// remote files this server does not control.
	relayStreams relayGate
	// uploads paces the upload surface per account, so a client that
	// has stopped waiting for its own answers cannot loop the server
	// through work the byte ceilings never see.
	uploads uploadGate
	// trusted is the reverse-proxy hop list the client-IP walk begins
	// from. Empty is today's behaviour exactly: the socket address, and
	// no header believed.
	trusted trustedProxies
}

// logger is the slice of slog the API layer uses (a seam tests can
// leave nil-safe via discard).
type logger interface {
	Info(msg string, args ...any)
	Warn(msg string, args ...any)
}

// Options carries the server's collaborators.
type Options struct {
	Service      *service.Library
	Bridge       *flow.Bridge
	Sessions     *auth.Sessions
	OIDC         *auth.OIDC
	Limiter      *auth.RateLimiter
	Media        *auth.MediaTokens
	Connect      *connect.Service
	Group        *supervise.Group
	Bases        connect.Bases
	Logger       logger
	CookieSecure bool
	PublicBase   string
	Backups      *service.Backups
	BackupWake   chan string
	Shares       *auth.ShareTokens
	WorkerTokens []string
	// TrustedProxies is the parsed WAXDECK_TRUSTED_PROXIES list. Empty
	// keeps the socket address authoritative.
	TrustedProxies trustedProxies
}

// NewServer builds the API server. Bridge may be nil when streaming is
// not configured; play-info then reports streaming unavailable while
// every catalog surface keeps working. OIDC may be nil when no provider
// is configured.
func NewServer(version string, opts Options) *Server {
	if opts.Limiter == nil {
		opts.Limiter = auth.NewRateLimiter()
	}
	if opts.Logger == nil {
		opts.Logger = discardLogger{}
	}
	if opts.Group == nil {
		opts.Group = supervise.NewGroup(nil)
	}
	return &Server{
		Version:      version,
		svc:          opts.Service,
		bridge:       opts.Bridge,
		sessions:     opts.Sessions,
		oidc:         opts.OIDC,
		limiter:      opts.Limiter,
		media:        opts.Media,
		connect:      opts.Connect,
		group:        opts.Group,
		bases:        opts.Bases,
		log:          opts.Logger,
		cookieSecure: opts.CookieSecure,
		publicBase:   opts.PublicBase,
		backups:      opts.Backups,
		backupWake:   opts.BackupWake,
		shares:       opts.Shares,
		workerTokens: opts.WorkerTokens,
		trusted:      opts.TrustedProxies,
	}
}

type discardLogger struct{}

func (discardLogger) Info(string, ...any) {}
func (discardLogger) Warn(string, ...any) {}

// --- system ------------------------------------------------------------------

func (s *Server) GetHealth(ctx context.Context, _ GetHealthRequestObject) (GetHealthResponseObject, error) {
	return GetHealth200JSONResponse{
		Status:     "ok",
		Version:    s.Version,
		ApiVersion: 1,
	}, nil
}

// --- auth ------------------------------------------------------------------------

const (
	sessionCookie = "waxdeck_session"
	csrfHeader    = "X-Csrf-Token"
)

// authFailureLog is the stable single-line auth-failure format the
// fail2ban recipe matches on; changing it breaks deployed jails.
const authFailureLog = "auth failure"

func (s *Server) Login(ctx context.Context, req LoginRequestObject) (LoginResponseObject, error) {
	if req.Body == nil || req.Body.Username == "" || req.Body.Password == "" {
		return Login400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "username and password are required"))}, nil
	}
	ip := remoteIPFromContext(ctx)
	ipKey := "login-ip:" + ip
	acctKey := "login-acct:" + strings.ToLower(req.Body.Username)
	if !s.limiter.Allowed(ipKey) || !s.limiter.Allowed(acctKey) {
		return Login429JSONResponse{RateLimitedJSONResponse(errObj("rate-limited", "too many login attempts; retry later"))}, nil
	}
	user, err := s.svc.VerifyLocalLogin(ctx, req.Body.Username, req.Body.Password)
	if err != nil {
		return nil, err
	}
	if user == nil {
		s.limiter.Failure(ipKey)
		s.limiter.Failure(acctKey)
		s.log.Warn(authFailureLog, "user", req.Body.Username, "ip", ip)
		return Login401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "invalid credentials"))}, nil
	}
	s.limiter.Success(ipKey)
	s.limiter.Success(acctKey)

	// The kind keys on whether the client sent a label at all, not on
	// whether one survives the trim: a native client that pads or blanks
	// its name is still a device, and letting the trim decide would
	// quietly move it onto the web session's much shorter expiry.
	// Trimmed and capped rather than refused for storage, because a
	// sign-in must never fail over a label.
	kind := "web"
	if deref(req.Body.DeviceName) != "" {
		kind = "device"
	}
	deviceName := truncatedDeviceName(deref(req.Body.DeviceName))
	created, err := s.sessions.Create(ctx, user.ID, kind, deviceName, clientFromContext(ctx))
	if err != nil {
		return nil, err
	}
	setCookie := s.newSessionCookie(created.Token)
	return Login200JSONResponse{
		Body:    LoginResponse{User: userJSON(user), Token: created.Token, CsrfToken: created.CSRFToken},
		Headers: Login200ResponseHeaders{SetCookie: &setCookie},
	}, nil
}

func (s *Server) Logout(ctx context.Context, _ LogoutRequestObject) (LogoutResponseObject, error) {
	if p, ok := principalFromContext(ctx); ok {
		if err := s.sessions.Revoke(ctx, p.Session.ID); err != nil {
			s.log.Warn("revoking session at logout", "session", p.Session.ID, "err", err)
		}
	}
	setCookie := s.expiredSessionCookie()
	return Logout204Response{Headers: Logout204ResponseHeaders{SetCookie: &setCookie}}, nil
}

func (s *Server) GetSession(ctx context.Context, _ GetSessionRequestObject) (GetSessionResponseObject, error) {
	if p, ok := principalFromContext(ctx); ok {
		u := userJSON(p.User)
		return GetSession200JSONResponse{Authenticated: true, User: &u, CsrfToken: &p.Session.CSRFToken}, nil
	}
	return GetSession200JSONResponse{Authenticated: false}, nil
}

// sessionCookie renders the Set-Cookie value for a fresh session. The
// CSRF token is deliberately NOT a cookie: it lives in the session row
// server-side and reaches the SPA only through login and session
// bodies, which cross-origin pages cannot read. Mutating requests
// echo it in the X-CSRF-Token header (a synchronizer token, strictly
// stronger than cookie double-submit).
func (s *Server) newSessionCookie(token string) string {
	return (&http.Cookie{
		Name:     sessionCookie,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   s.cookieSecure,
	}).String()
}

func (s *Server) expiredSessionCookie() string {
	return (&http.Cookie{
		Name: sessionCookie, Value: "", Path: "/", HttpOnly: true,
		SameSite: http.SameSiteLaxMode, Secure: s.cookieSecure, MaxAge: -1,
	}).String()
}

// userJSON renders the self view of an account. uploadEnabled and
// managePodcasts are the effective rights (administrators always hold
// them), so every client surface gates its affordances off these
// fields.
func userJSON(u *wdb.User) User {
	out := User{Id: u.ID, Username: u.Username, Roles: u.Roles}
	if u.DisplayName != "" {
		out.DisplayName = ptr(u.DisplayName)
	}
	out.UploadEnabled = u.UploadEnabled
	manage := service.PermissionsOf(u).ManagePodcasts
	for _, r := range u.Roles {
		if r == "admin" {
			out.UploadEnabled = true
			manage = true
		}
	}
	out.ManagePodcasts = ptr(manage)
	return out
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	filter := itemFilterOf(req.Params.MediaType, req.Params.Facet, req.Params.FacetKey)
	page, err := s.svc.Items(ctx, uc, filter, deref(req.Params.Cursor), limit)
	if err != nil {
		if kind := service.KindOf(err); kind == service.KindInvalid {
			return ListItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return ListItems200JSONResponse(pageJSON(page)), nil
}

func (s *Server) ListFacets(ctx context.Context, req ListFacetsRequestObject) (ListFacetsResponseObject, error) {
	limit, ok := pageLimit(req.Params.Limit, 100, 500)
	if !ok {
		return ListFacets400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	sort := ""
	if req.Params.Sort != nil {
		sort = string(*req.Params.Sort)
	}
	order, err := service.ParseFacetSort(sort)
	if err != nil {
		return ListFacets400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	}
	facet := ""
	if req.Params.Facet != nil {
		facet = string(*req.Params.Facet)
	}
	page, err := s.svc.Facets(ctx, uc, service.FacetQuery{
		Dimension: string(req.Params.Dimension),
		Order:     order,
		Cursor:    deref(req.Params.Cursor),
		StartsAt:  deref(req.Params.StartsAt),
		Facet:     facet,
		FacetKey:  deref(req.Params.FacetKey),
		Limit:     limit,
	})
	if err != nil {
		if kind := service.KindOf(err); kind == service.KindInvalid {
			return ListFacets400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := FacetPage{
		Dimension: BrowseDimension(page.Dimension),
		Buckets:   make([]FacetBucket, 0, len(page.Buckets)),
	}
	for _, b := range page.Buckets {
		bucket := FacetBucket{Key: b.Key, Label: b.Label, Count: b.Count}
		if b.EntityPID != "" {
			bucket.EntityPid = &b.EntityPID
		}
		if b.Unknown {
			unknown := true
			bucket.Unknown = &unknown
		}
		// Empty only on the unknown bucket, which has no rail row.
		if b.Letter != "" {
			bucket.Letter = &b.Letter
		}
		out.Buckets = append(out.Buckets, bucket)
	}
	if page.Next != "" {
		out.NextCursor = &page.Next
	}
	return ListFacets200JSONResponse(out), nil
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
	// Not when a cursor came with it: minting one there would refuse the
	// cursor for a difference the caller never made, and the contract
	// says to send back the seed the first page answered with.
	seed := derefInt64(req.Params.Seed)
	if req.Params.List == Random && req.Params.Seed == nil && req.Params.Cursor == nil {
		seed = rand.Int64()
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	filter := itemFilterOf(req.Params.MediaType, req.Params.Facet, req.Params.FacetKey)
	page, err := s.svc.Browse(ctx, uc, string(req.Params.List), filter, seed, deref(req.Params.Cursor), limit)
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	res, err := s.svc.Search(ctx, uc, req.Params.Q, limit)
	if err != nil {
		return nil, err
	}
	return Search200JSONResponse{
		Query:     res.Query,
		Artists:   searchHitsJSON(res.Artists),
		Albums:    searchHitsJSON(res.Albums),
		Tracks:    searchHitsJSON(res.Tracks),
		Books:     searchHitsJSON(res.Books),
		Episodes:  searchHitsJSON(res.Episodes),
		Truncated: ptr(res.Truncated),
	}, nil
}

func (s *Server) ResolveEntities(ctx context.Context, req ResolveEntitiesRequestObject) (ResolveEntitiesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return ResolveEntities400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	cards, departed, err := s.svc.EntityCards(ctx, uc, req.Body.Pids)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ResolveEntities400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := EntityCardList{Entities: make([]EntityCard, 0, len(cards))}
	if len(departed) > 0 {
		out.Departed = &departed
	}
	for _, c := range cards {
		card := EntityCard{
			Pid:   c.PID,
			Kind:  EntityCardKind(c.Kind),
			Title: c.Title,
		}
		if c.Artist != "" {
			card.Artist = ptr(c.Artist)
		}
		if c.Year != 0 {
			card.Year = ptr(c.Year)
		}
		card.ItemCount = c.ItemCount
		out.Entities = append(out.Entities, card)
	}
	return ResolveEntities200JSONResponse(out), nil
}

func (s *Server) GetAlbum(ctx context.Context, req GetAlbumRequestObject) (GetAlbumResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	d, err := s.svc.Album(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetAlbum404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no album with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetAlbum200JSONResponse(albumJSON(d)), nil
}

// albumJSON omits every empty identity field. Most releases carry none of
// the five, and a header that draws a row per absent value would be
// mostly blank labels.
func albumJSON(d service.AlbumDetail) AlbumDetail {
	out := AlbumDetail{Pid: d.PID, Title: d.Title}
	for _, f := range []struct {
		value string
		into  **string
	}{
		{d.SortKey, &out.SortKey},
		{d.MBID, &out.Mbid},
		{d.ReleaseGroupPID, &out.ReleaseGroupPid},
		{d.Barcode, &out.Barcode},
		{d.Label, &out.Label},
		{d.CatalogNumber, &out.CatalogNumber},
		{d.Media, &out.Media},
		{d.Country, &out.Country},
	} {
		if f.value != "" {
			*f.into = ptr(f.value)
		}
	}
	if d.Year != 0 {
		out.Year = ptr(d.Year)
	}
	if d.ItemCount != 0 {
		out.ItemCount = ptr(d.ItemCount)
	}
	if d.TotalDurationMS != 0 {
		out.TotalDurationMs = ptr(d.TotalDurationMS)
	}
	out.ArtSource = artSourceJSON(d.ArtSource)
	return out
}

func (s *Server) GetItem(ctx context.Context, req GetItemRequestObject) (GetItemResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	d, err := s.svc.Item(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetItem404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetItem200JSONResponse(itemJSON(d)), nil
}

// Artwork is the one response worth caching hard: the bytes for a pid
// and size never change without the ETag changing, and a grid asks for
// two hundred of them at once. A day of freshness with a week of
// stale-while-revalidate turns a warm grid from two hundred conditional
// GETs into none. It stays private and varies by the credential
// presented because artwork follows the item's visibility: this endpoint
// takes a session cookie or a bearer token, and a cache shared by two of
// either must not answer one from the other's copy. No immutable: the
// URL names a pid and a size, not the bytes, so a replaced cover reuses
// it (which is what the ignored `v` parameter is for).
const (
	artCacheControl = "private, max-age=86400, stale-while-revalidate=604800"
	artVary         = "Cookie, Authorization"
	// maxArtHeaderURL bounds the fetch URL echoed as a response header.
	// Generous for a real cover address, well under where an
	// intermediary's own header limits begin.
	maxArtHeaderURL = 2048
	// minArtSize is the smallest box a client may name. Below the
	// ladder's bottom rung rather than on it - a size in here rounds up
	// to that rung - so it is a number of its own rather than one of the
	// service's art sizes, and it is the spec's `minimum` for the same
	// parameter.
	minArtSize = 16
)

// maxUnscaledArtBytes bounds what a request that asked for a thumbnail
// may be answered with when the picture could not be scaled.
//
// The resolver answers a sized request with the original whenever it
// could not measure the source - after BMP and TIFF became first-class,
// that means AVIF, HEIC, and bytes nothing could read. A source it did
// measure never lands here: one larger than the rung comes back scaled,
// and one already inside the rung is the picture the caller asked for,
// however many bytes it is. For an unmeasurable cover a little over the
// bound the original is the right answer; for a large one it is not,
// because a caller asking for a 64-pixel tile is asking for something
// small and nothing here can paint these bytes anyway. Well above any
// real thumbnail at the 2048-pixel ceiling and far below the 16 MiB an
// upload may be.
//
// The rung and not the raw request is what the picture is measured
// against, because the rung is what the resolver answered at: a request
// for 600 is served the 768 derivative, and reading a 700-pixel answer
// against the 600 that was typed would refuse bytes that are exactly
// what was asked for.
//
// Applied on this endpoint alone. `Art` also answers the Subsonic
// adapter, whose clients have no designed placeholder to fall back to,
// and the radio snapshot, which already applies a cap of its own; the
// tokenized cast endpoint stamps a size into every URL it mints, so
// refusing there would leave a renderer no way to ask for the picture at
// all.
const maxUnscaledArtBytes = 2 << 20

// artTooBigForSize reports whether a sized request was answered with an
// original bigger than a thumbnail slot has any business holding: one
// never measured, or one the thumbnailer failed on and the resolver fell
// back to whole. A request that asked for no size is never refused (the
// resolver leaves Box zero for one), and neither is a source already
// within the rung that answered.
//
// It reads the size off the blob rather than taking the request, so a
// caller cannot hand it a number the resolve did not round to.
func artTooBigForSize(blob service.ArtBlob) bool {
	return blob.Box > 0 && len(blob.Bytes) > maxUnscaledArtBytes &&
		(blob.Width == 0 && blob.Height == 0 ||
			blob.Width > blob.Box || blob.Height > blob.Box)
}

// artHeaderValues renders one resolved cover's provenance as the four
// response headers, for the 200 and the 304 alike.
func artHeaderValues(src service.ArtSourceDTO) (source, provider, sourceURL, level *string) {
	source = ptr(src.Source)
	if src.Provider != "" {
		provider = ptr(src.Provider)
	}
	// The one header value that came off somebody else's network.
	// net/http neutralizes the newlines, so this is the length: a
	// multi-kilobyte header is where proxies start dropping the
	// response, and losing the cover to caption it would be a poor
	// trade. Omitted rather than truncated, because half a URL is not a
	// shorter URL.
	if url := src.SourceURL; url != "" && len(url) <= maxArtHeaderURL {
		sourceURL = ptr(url)
	}
	if src.Level != "" {
		level = ptr(src.Level)
	}
	return source, provider, sourceURL, level
}

func (s *Server) GetItemArt(ctx context.Context, req GetItemArtRequestObject) (GetItemArtResponseObject, error) {
	size := 0
	if req.Params.Size != nil {
		size = *req.Params.Size
		// The ceiling is the ladder's top rung: past it a request is
		// asking for an enlargement. The floor sits below the bottom
		// rung and rounds up onto it, which is why it is a number of its
		// own. The spec carries the same pair as schema bounds; this is
		// what a client that ignores them meets.
		if size < minArtSize || size > service.ArtSizeMax {
			return GetItemArt400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", fmt.Sprintf("size must be between %d and %d", minArtSize, service.ArtSizeMax)))}, nil
		}
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	blob, err := s.svc.Art(ctx, uc, req.Pid, enumStr(req.Params.Role), size)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return GetItemArt404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no artwork for pid "+req.Pid))}, nil
		case service.KindInvalid:
			return GetItemArt400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	// A thumbnail slot is not where an unscaled original belongs; see
	// maxUnscaledArtBytes. Before the validator, so a caller cannot
	// revalidate its way into the bytes this refuses.
	if artTooBigForSize(blob) {
		return GetItemArt404JSONResponse{NotFoundJSONResponse(errObj("not-found",
			"no thumbnail of that size for pid "+req.Pid))}, nil
	}
	// The validator is the source image hash scoped by the rung that
	// answered: same source, different rungs, different bytes. Scoping
	// it by the raw request instead would survive a change to the
	// ladder - the same URL would answer new bytes under the validator
	// the old ones were cached with, and a browser holding the old copy
	// would revalidate into a 304 and keep it indefinitely.
	etag := fmt.Sprintf("%q", fmt.Sprintf("%s-%d", blob.SourceHash, blob.Box))
	cacheControl, vary := artCacheControl, artVary
	if req.Params.IfNoneMatch != nil && httpcache.ETagMatches(*req.Params.IfNoneMatch, etag) {
		// A 304 repeats the validator and the freshness the body would
		// have carried; without them the cached copy stays as stale as
		// it was and revalidates again on the next paint. It repeats the
		// provenance too: the validator addresses the bytes, and a cover
		// can be re-attributed without them changing, so a bare 304
		// would pin a caller to the old origin for as long as it held
		// the picture.
		h := GetItemArt304ResponseHeaders{
			ETag:         &etag,
			CacheControl: &cacheControl,
			Vary:         &vary,
		}
		if src := blob.Source; src.Attributed() {
			h.XArtSource, h.XArtProvider, h.XArtSourceUrl, h.XArtLevel = artHeaderValues(src)
		}
		return GetItemArt304Response{Headers: h}, nil
	}
	body := bytes.NewReader(blob.Bytes)
	length := int64(len(blob.Bytes))
	noSniff, csp := service.ArtNoSniff, service.ArtCSP
	headers := GetItemArt200ResponseHeaders{
		ETag:                  &etag,
		CacheControl:          &cacheControl,
		Vary:                  &vary,
		XContentTypeOptions:   &noSniff,
		ContentSecurityPolicy: &csp,
	}
	// The provenance of the bytes being served, for a consumer that has
	// only this response to read. WaxDeck's own clients take the same
	// four values off the JSON reads: a browser hands an `<img>` caller
	// no access to response headers, so this form cannot reach the web.
	if src := blob.Source; src.Attributed() {
		headers.XArtSource, headers.XArtProvider, headers.XArtSourceUrl, headers.XArtLevel = artHeaderValues(src)
	}
	// One variant per type the response declares; a stored format outside
	// the set (a provider-named oddball) falls to jpeg, which the
	// response documents.
	switch blob.MimeType {
	case "image/png":
		return GetItemArt200ImagepngResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/webp":
		return GetItemArt200ImagewebpResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/gif":
		return GetItemArt200ImagegifResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/bmp":
		return GetItemArt200ImagebmpResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/tiff":
		return GetItemArt200ImagetiffResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/avif":
		return GetItemArt200ImageavifResponse{Body: body, ContentLength: length, Headers: headers}, nil
	case "image/heic":
		return GetItemArt200ImageheicResponse{Body: body, ContentLength: length, Headers: headers}, nil
	default:
		return GetItemArt200ImagejpegResponse{Body: body, ContentLength: length, Headers: headers}, nil
	}
}

func (s *Server) GetItemArtRoles(ctx context.Context, req GetItemArtRolesRequestObject) (GetItemArtRolesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	infos, err := s.svc.ItemArtRoles(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetItemArtRoles404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no artwork for pid "+req.Pid))}, nil
		}
		return nil, err
	}
	out := ArtRoles{
		Roles:     make([]ArtRoleInfo, 0, len(infos.Roles)),
		ArtSource: artSourceJSON(infos.ArtSource),
	}
	for _, i := range infos.Roles {
		info := ArtRoleInfo{
			Role:   ArtRole(i.Role),
			Width:  ptr(i.Width),
			Height: ptr(i.Height),
			Locked: ptr(i.Locked),
		}
		if i.Format != "" {
			info.Format = ptr(i.Format)
		}
		if i.Source != "" {
			info.Source = ptr(i.Source)
		}
		if i.Provider != "" {
			info.Provider = ptr(i.Provider)
		}
		if i.SourceURL != "" {
			info.SourceUrl = ptr(i.SourceURL)
		}
		if !i.UpdatedAt.IsZero() {
			info.UpdatedAt = ptr(i.UpdatedAt)
		}
		out.Roles = append(out.Roles, info)
	}
	return GetItemArtRoles200JSONResponse(out), nil
}

// artSourceJSON renders a picture's provenance, or nothing when the
// store holds none. Absent is the signal a surface reads as "draw no
// mark"; an object with an empty source would ask every caller to make
// the same emptiness check twice.
func artSourceJSON(a service.ArtSourceDTO) *ArtSource {
	if !a.Attributed() {
		return nil
	}
	out := &ArtSource{Source: a.Source}
	if a.Provider != "" {
		out.Provider = ptr(a.Provider)
	}
	if a.SourceURL != "" {
		out.SourceUrl = ptr(a.SourceURL)
	}
	if a.Level != "" {
		out.Level = ptr(a.Level)
	}
	if a.Derived {
		out.Derived = ptr(true)
	}
	if !a.UpdatedAt.IsZero() {
		out.UpdatedAt = ptr(a.UpdatedAt)
	}
	return out
}

func (s *Server) GetItemLyrics(ctx context.Context, req GetItemLyricsRequestObject) (GetItemLyricsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	ly, err := s.svc.ItemLyrics(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetItemLyrics404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no lyrics for pid "+req.Pid))}, nil
		}
		return nil, err
	}
	out := Lyrics{Pid: ly.PID, Source: ly.Source}
	if ly.Provider != "" {
		out.Provider = ptr(ly.Provider)
	}
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
	if p, ok := principalFromContext(ctx); !ok || !p.IsAdmin() {
		return RescanLibrary403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	job, err := s.svc.Rescan(ctx)
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			return RescanLibrary409JSONResponse{ConflictJSONResponse(errObj("conflict", "a conflicting catalog job is already running"))}, nil
		}
		return nil, err
	}
	return RescanLibrary202JSONResponse(jobJSON(job)), nil
}

func (s *Server) AnalyzeLibrary(ctx context.Context, _ AnalyzeLibraryRequestObject) (AnalyzeLibraryResponseObject, error) {
	if p, ok := principalFromContext(ctx); !ok || !p.IsAdmin() {
		return AnalyzeLibrary403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	job, err := s.svc.Analyze(ctx)
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			// Narrower prose than the rescan twin's: analysis takes its
			// own scope lease, so the only thing it can collide with is
			// another analyze pass. Telling an administrator that some
			// unnamed catalog job is in the way would send them looking
			// at the scan.
			return AnalyzeLibrary409JSONResponse{ConflictJSONResponse(errObj("conflict", "the analyze pass is already running"))}, nil
		}
		return nil, err
	}
	return AnalyzeLibrary202JSONResponse(jobJSON(job)), nil
}

func (s *Server) GetJob(ctx context.Context, req GetJobRequestObject) (GetJobResponseObject, error) {
	// Timeline-measurement jobs live in the bridge, not the catalog;
	// they answer here so one job surface covers both.
	if s.bridge != nil {
		if state, ok := s.bridge.TimelineJob(ctx, req.Pid); ok {
			return GetJob200JSONResponse(Job{Pid: req.Pid, Kind: "timeline", State: state}), nil
		}
	}
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
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	// Visibility gates the mint: an item outside the caller's libraries
	// must not yield a stream URL.
	if err := s.svc.VisibleItem(ctx, uc, req.Pid); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetPlayInfo404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}

	// Multi-file books resolve one part per call, selected by the
	// book-timeline position.
	var positionMS int64
	if req.Params.PositionMs != nil {
		positionMS = *req.Params.PositionMs
	}
	part, err := s.svc.ResolvePlayPart(ctx, uc, req.Pid, positionMS)
	if err != nil {
		return nil, err
	}

	maxKbps := 0
	if req.Params.MaxBitrateKbps != nil {
		maxKbps = *req.Params.MaxBitrateKbps
		if maxKbps < flow.MinStreamBitrateKbps || maxKbps > flow.MaxStreamBitrateKbps {
			return GetPlayInfo400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request",
				fmt.Sprintf("maxBitrateKbps must be between %d and %d", flow.MinStreamBitrateKbps, flow.MaxStreamBitrateKbps)))}, nil
		}
	}

	// Without the streaming engine the original bytes serve directly:
	// ranged, untranscoded, through the same token-authenticated
	// endpoint downloads use. Span items ride whole with the window in
	// the response; DSP (voice boost) is simply unavailable.
	if s.bridge == nil {
		if s.media == nil {
			return nil, errStreamingUnavailable
		}
		res, err := s.svc.DirectPlayInfo(ctx, uc, req.Pid, part.FilePID)
		if err != nil {
			if out, ok := s.enclosurePlayInfo(ctx, uc.ID, req.Pid, err); ok {
				return out, nil
			}
			switch service.KindOf(err) {
			case service.KindNotFound:
				return GetPlayInfo404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
			case service.KindConflict:
				return GetPlayInfo409JSONResponse(errObj("conflict", err.Error())), nil
			}
			return nil, err
		}
		token, exp := s.media.Mint(p.User.ID, req.Pid)
		u := "/media/download?pid=" + url.QueryEscape(req.Pid) +
			"&mt=" + url.QueryEscape(token) + "&id=" + url.QueryEscape(res.File.ETag)
		if part.FilePID != "" {
			u += "&f=" + url.QueryEscape(part.FilePID)
		}
		out := GetPlayInfo200JSONResponse{
			Pid:        req.Pid,
			Url:        u,
			MimeType:   res.File.MimeType,
			DurationMs: res.DurationMS,
			Seekable:   true,
			ExpiresAt:  exp,
		}
		if res.HasSpan {
			out.SpanStartMs = &res.SpanStartMS
			out.SpanEndMs = &res.SpanEndMS
		}
		if part.MultiPart {
			out.PartIndex = &part.Index
			out.PartCount = &part.Count
			out.PartStartMs = &part.StartMS
		}
		return out, nil
	}

	// Voice boost precedence is resolved here, at mint time: an explicit
	// parameter wins, an absent one falls back to the caller's stored
	// setting for the show or book.
	boost := false
	if req.Params.VoiceBoost != nil {
		boost = *req.Params.VoiceBoost
	} else {
		boost = s.svc.EffectiveVoiceBoost(ctx, uc, req.Pid)
	}

	info, err := s.bridge.PlayInfoFor(ctx, uc.ID, req.Pid, flow.PlayOptions{
		FilePID:        part.FilePID,
		VoiceBoost:     boost,
		MaxBitrateKbps: maxKbps,
	})
	if err != nil {
		if out, ok := s.enclosurePlayInfo(ctx, uc.ID, req.Pid, err); ok {
			return out, nil
		}
		switch service.KindOf(err) {
		case service.KindNotFound:
			return GetPlayInfo404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindConflict:
			return GetPlayInfo409JSONResponse(errObj("conflict", err.Error())), nil
		}
		return nil, err
	}
	out := GetPlayInfo200JSONResponse{
		Pid:        req.Pid,
		Url:        info.URL,
		MimeType:   info.MimeType,
		DurationMs: info.DurationMS,
		Seekable:   info.Seekable,
		ExpiresAt:  info.ExpiresAt,
	}
	if info.VoiceBoost {
		vb := true
		out.VoiceBoost = &vb
	}
	if info.AppliedBitrateKbps > 0 {
		out.AppliedBitrateKbps = &info.AppliedBitrateKbps
	}
	if part.MultiPart {
		out.PartIndex = &part.Index
		out.PartCount = &part.Count
		out.PartStartMs = &part.StartMS
	}
	return out, nil
}

func (s *Server) GetPlayState(ctx context.Context, req GetPlayStateRequestObject) (GetPlayStateResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	st, err := s.svc.PlayState(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetPlayState404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetPlayState200JSONResponse(playStateJSON(st)), nil
}

// searchHitsJSON projects service search hits onto the wire shape, the
// entity summary every hit-shaped surface shares.
func searchHitsJSON(hits []service.SearchHit) []SearchHit {
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

func playStateJSON(st service.PlayState) PlayState {
	out := PlayState{
		Pid:        st.PID,
		PositionMs: st.PositionMS,
		Played:     st.Played,
		Finished:   st.Finished,
		PlayCount:  st.PlayCount,
		Starred:    st.Starred,
		Rating:     st.Rating,
	}
	if !st.UpdatedAt.IsZero() {
		out.UpdatedAt = &st.UpdatedAt
	}
	return out
}

func (s *Server) PutPlayState(ctx context.Context, req PutPlayStateRequestObject) (PutPlayStateResponseObject, error) {
	if req.Body == nil {
		return PutPlayState400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	// A skipped replay is still a 204: the winning state is already in
	// the caller's event stream, so there is nothing to report.
	_, err = s.svc.Checkpoint(ctx, uc, req.Pid, req.Body.PositionMs, req.Body.RecordedAt)
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	sessions := make([]service.ListenSession, 0, len(req.Body.Sessions))
	for _, in := range req.Body.Sessions {
		s := service.ListenSession{
			SessionID: in.SessionId,
			PID:       in.Pid,
			StartedAt: in.StartedAt,
			MsPlayed:  in.MsPlayed,
			SkippedMs: derefInt64(in.SkippedMs),
			Finished:  derefBool(in.Finished),
			Client:    deref(in.Client),
		}
		if in.Source != nil {
			s.Source = string(*in.Source)
		}
		sessions = append(sessions, s)
	}
	res, err := s.svc.IngestListens(ctx, uc, sessions)
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
	if it.ArtistPID != "" {
		s.ArtistPid = ptr(it.ArtistPID)
	}
	if it.AlbumPID != "" {
		s.AlbumPid = ptr(it.AlbumPID)
	}
	if it.TrackNo > 0 {
		s.TrackNumber = ptr(it.TrackNo)
	}
	if it.DiscNo > 0 {
		s.DiscNumber = ptr(it.DiscNo)
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
	if d.ArtistPID != "" {
		it.ArtistPid = ptr(d.ArtistPID)
	}
	if d.AlbumPID != "" {
		it.AlbumPid = ptr(d.AlbumPID)
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
	it.ArtSource = artSourceJSON(d.ArtSource)
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

func derefFloat(p *float64) float64 {
	if p == nil {
		return 0
	}
	return *p
}

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
	ctxPrincipal ctxKey = iota
	ctxRemoteIP
	ctxClient
	// The raw header, unparsed: only the handful of handlers that
	// render HTML negotiate it, and they are strict-server methods with
	// no *http.Request to read it from themselves.
	ctxAcceptLanguage
	// What the request declared its body to be, for the one handler
	// that has to refuse an over-large one before reading it. Same
	// reason as the header above: a strict-server method is handed a
	// reader, never the request that carried it.
	ctxContentLength
)

// publicPaths are reachable without a session (per the spec's per-operation
// `security` overrides). They are also exempt from CSRF proof.
var publicPaths = map[string]bool{
	"/api/v1/health":              true,
	"/api/v1/auth/login":          true,
	"/api/v1/auth/session":        true,
	"/api/v1/auth/logout":         true,
	"/api/v1/auth/bootstrap":      true,
	"/api/v1/auth/signup":         true,
	"/api/v1/auth/oidc/providers": true,
	"/api/v1/auth/oidc/start":     true,
	"/api/v1/auth/oidc/callback":  true,
	"/api/v1/auth/oidc/exchange":  true,
	// The Last.fm redirect target authenticates by its one-time state,
	// never by a session: the approving browser tab may not carry one.
	"/api/v1/scrobble/lastfm/callback": true,
}

// pageVaryPaths answer HTML whose words follow Accept-Language. Set
// here because their generated response types expose no header hook,
// and needed because not every answer is single-use: a server with no
// OIDC configured renders the same 200 for the same bare URL, with no
// Cache-Control to stop a shared cache handing it to the next reader in
// the wrong language. The share page sets its own.
var pageVaryPaths = map[string]bool{
	"/api/v1/auth/oidc/callback":       true,
	"/api/v1/scrobble/lastfm/callback": true,
}

// AuthMiddleware resolves the session (cookie or bearer) into the
// request context, rejects unauthenticated calls to protected
// endpoints, and demands CSRF proof for cookie-authenticated
// mutations. Request metadata (source IP, user agent) rides the
// context for the login and device paths.
func (s *Server) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(r.Context(), ctxRemoteIP, s.trusted.clientIP(r))
		ctx = context.WithValue(ctx, ctxClient, clientHint(r))
		ctx = context.WithValue(ctx, ctxAcceptLanguage, r.Header.Get("Accept-Language"))
		ctx = context.WithValue(ctx, ctxContentLength, r.ContentLength)
		if pageVaryPaths[r.URL.Path] {
			w.Header().Set("Vary", "Accept-Language")
		}

		// Worker endpoints take the worker token and nothing else: they
		// ignore library visibility, so a user session must never open
		// them, and the worker token opens nothing else.
		if workerPaths[r.URL.Path] {
			if !s.workerAuthorized(r) {
				writeError(w, http.StatusUnauthorized, "unauthenticated", "a worker token is required")
				return
			}
			ctx = context.WithValue(ctx, ctxWorkerKey{}, true)
			next.ServeHTTP(w, r.WithContext(ctx))
			return
		}

		// Try each presented credential in precedence order; a stale or
		// invalid bearer must not shadow a valid session cookie.
		var principal *auth.Principal
		for _, cand := range authCandidates(r) {
			p, err := s.sessions.Lookup(ctx, cand.token)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "internal", "session lookup failed")
				return
			}
			if p != nil {
				p.FromCookie = cand.fromCookie
				principal = p
				break
			}
		}
		if principal != nil {
			ctx = context.WithValue(ctx, ctxPrincipal, principal)
		} else if !publicPaths[r.URL.Path] {
			writeError(w, http.StatusUnauthorized, "unauthenticated", "no valid session or token was presented")
			return
		}

		// Cookie-borne credentials ride on every browser request, so a
		// mutation needs proof the SPA itself sent it: the session's CSRF
		// token echoed in a header, which a cross-site page cannot set.
		if principal != nil && principal.FromCookie && mutatingMethod(r.Method) && !publicPaths[r.URL.Path] {
			if r.Header.Get(csrfHeader) != principal.Session.CSRFToken {
				writeError(w, http.StatusForbidden, "forbidden", "missing or wrong CSRF token")
				return
			}
		}
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func mutatingMethod(m string) bool {
	switch m {
	case http.MethodGet, http.MethodHead, http.MethodOptions:
		return false
	}
	return true
}

type credential struct {
	token      string
	fromCookie bool
}

// authCandidates returns the credentials to try, in precedence order:
// the bearer token (native clients) first, then the session cookie
// (web). Returning both lets the caller fall through a stale bearer to
// a good cookie.
func authCandidates(r *http.Request) []credential {
	var out []credential
	// The Authorization scheme name is case-insensitive (RFC 7235 section 2.1),
	// so accept "Bearer", "bearer", "BEARER", and other casings.
	if h := r.Header.Get("Authorization"); len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		out = append(out, credential{token: h[7:]})
	}
	if c, err := r.Cookie(sessionCookie); err == nil && c.Value != "" {
		out = append(out, credential{token: c.Value, fromCookie: true})
	}
	return out
}

// remoteIP is the connection's source address, and nothing else. What
// the limiter actually counts goes through trustedProxies.clientIP,
// which starts here and only believes a forwarded header when this
// address is a hop the operator configured.
func remoteIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// clientHint is the compact client label stored with a session; see
// summarizeClient for what it does with a browser's user agent and why.
func clientHint(r *http.Request) string {
	return summarizeClient(r.Header.Get("User-Agent"))
}

func principalFromContext(ctx context.Context) (*auth.Principal, bool) {
	p, ok := ctx.Value(ctxPrincipal).(*auth.Principal)
	return p, ok
}

func remoteIPFromContext(ctx context.Context) string {
	ip, _ := ctx.Value(ctxRemoteIP).(string)
	return ip
}

// declaredBodyBytes is what the request said it was sending, or -1
// when it said nothing (a chunked body).
func declaredBodyBytes(ctx context.Context) int64 {
	n, ok := ctx.Value(ctxContentLength).(int64)
	if !ok {
		return -1
	}
	return n
}

func clientFromContext(ctx context.Context) string {
	c, _ := ctx.Value(ctxClient).(string)
	return c
}

// pageStringsFromContext is the words for a rendered HTML page, in the
// reader's language where the server has them. Only the page handlers
// call it: the JSON API answers developer English whatever the browser
// asked for, which is what keeps the backend out of translation.
func pageStringsFromContext(ctx context.Context) *pagetext.Strings {
	header, _ := ctx.Value(ctxAcceptLanguage).(string)
	return pagetext.For(pagetext.Negotiate(header))
}

// requireUserCtx resolves the principal into the service-layer user
// context. AuthMiddleware guarantees a principal on protected paths;
// the error covers a future miswiring, not a reachable state.
func (s *Server) requireUserCtx(ctx context.Context) (*service.UserCtx, *auth.Principal, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return nil, nil, &service.Error{Kind: service.KindInternal, Msg: "no principal in request context"}
	}
	uc, err := s.svc.UserCtx(ctx, p.User)
	if err != nil {
		return nil, nil, err
	}
	return uc, p, nil
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
	case service.KindCatalogBusy:
		writeError(w, http.StatusConflict, "catalog-busy", kindMessage(err, "another catalog job holds the file-mutation scope; retry shortly"))
	case service.KindGone:
		writeError(w, http.StatusGone, "sync-reset", kindMessage(err, "re-mirror from a fresh snapshot"))
	case service.KindForbidden:
		writeError(w, http.StatusForbidden, "forbidden", kindMessage(err, "not allowed"))
	case service.KindUnsupported:
		writeError(w, http.StatusNotImplemented, "source-unavailable", kindMessage(err, "this server is not running the needed integration"))
	case service.KindUpstream:
		writeError(w, http.StatusBadGateway, "feed-unreachable", kindMessage(err, "the upstream feed could not be fetched"))
	case service.KindDirectory:
		writeError(w, http.StatusBadGateway, "directory-unavailable", kindMessage(err, "the external directory could not be reached"))
	case service.KindService:
		writeError(w, http.StatusBadGateway, "service-unreachable", kindMessage(err, "an external service could not be reached"))
	case service.KindQuota:
		writeError(w, http.StatusRequestEntityTooLarge, "quota-exceeded", kindMessage(err, "the upload would exceed your storage quota"))
	case service.KindStorageFull:
		writeError(w, http.StatusInsufficientStorage, "storage-full", kindMessage(err, "the server has no room to stage this"))
	case service.KindLocked:
		writeError(w, http.StatusConflict, "field-locked", kindMessage(err, "the field is locked; pass force to override"))
	case service.KindFormat:
		writeError(w, http.StatusUnsupportedMediaType, "unsupported-format", kindMessage(err, "the file's format is not accepted"))
	case service.KindDRM:
		writeError(w, http.StatusUnsupportedMediaType, "drm-protected", kindMessage(err, "the file is DRM-encrypted and can never play"))
	case service.KindFeature:
		writeError(w, http.StatusNotImplemented, "feature-unavailable", kindMessage(err, "this server is not running the needed capability"))
	case service.KindReadOnly:
		writeError(w, http.StatusConflict, "read-only", kindMessage(err, "the target library is read-only"))
	case service.KindTranscodeLimit:
		writeError(w, http.StatusTooManyRequests, "transcode-limited", kindMessage(err, "the transcode session limit is reached"))
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

// --- helpers ----------------------------------------------------------------------

func errObj(code, message string) Error {
	return Error{Code: code, Message: message}
}

// itemFilterOf maps the media-type and facet parameters the item listing
// and the discovery lists both take. Keyed on facet alone: an absent
// facetKey drills the dimension's unknown bucket rather than reading as
// no filter.
func itemFilterOf(mediaType *MediaType, facet *BrowseDimension, facetKey *string) service.ItemFilter {
	out := service.ItemFilter{}
	if mediaType != nil {
		out.MediaType = string(*mediaType)
	}
	if facet != nil {
		out.Facet, out.FacetKey = string(*facet), deref(facetKey)
	}
	return out
}
