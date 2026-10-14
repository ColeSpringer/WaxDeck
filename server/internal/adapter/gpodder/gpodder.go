// Package gpodder is the gpodder.net API 2 compatibility surface:
// session login, device registry, subscription sync, and episode
// action sync, so podcast clients (AntennaPod is the reference) sync
// their subscription lists and playback positions against WaxDeck. It
// sits on the service layer like any first-party handler.
//
// Authentication on every endpoint is HTTP Basic with the WaxDeck
// username and an app password (the login password never works here),
// or the sessionid cookie the login endpoint sets: an opaque token for a
// stored login that ends with its app password, its account, or a
// logout. Subscriptions in WaxDeck are user-global; device ids exist to
// annotate changes and satisfy the protocol's device registry, they
// never scope the subscription list itself.
package gpodder

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// sessionCookie is the cookie name gpodder clients expect.
const sessionCookie = "sessionid"

// maxBodyBytes bounds every request body this surface reads.
const maxBodyBytes = 8 << 20

// handler serves /api/2/ and /subscriptions/.
type handler struct {
	svc *service.Library
	// secure marks the cookie Secure, set whenever the server's own
	// session cookie is (WAXDECK_COOKIE_SECURE).
	secure bool
	log    *slog.Logger
	mux    *http.ServeMux
}

// New builds the adapter over the service; the handler routes both the
// /api/2/ and the /subscriptions/ prefixes internally.
func New(svc *service.Library, cookieSecure bool, logger *slog.Logger) http.Handler {
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}
	h := &handler{svc: svc, secure: cookieSecure, log: logger}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/2/auth/{user}/{op}", h.auth2)
	mux.HandleFunc("GET /api/2/devices/{userext}", h.devicesList)
	mux.HandleFunc("POST /api/2/devices/{user}/{devext}", h.deviceUpdate)
	mux.HandleFunc("GET /api/2/subscriptions/{user}/{devext}", h.subDeltaGet)
	mux.HandleFunc("POST /api/2/subscriptions/{user}/{devext}", h.subDeltaPost)
	mux.HandleFunc("GET /api/2/episodes/{userext}", h.episodesGet)
	mux.HandleFunc("POST /api/2/episodes/{userext}", h.episodesPost)
	mux.HandleFunc("GET /subscriptions/{userext}", h.subsUserGet)
	mux.HandleFunc("GET /subscriptions/{user}/{devext}", h.subsDeviceGet)
	mux.HandleFunc("PUT /subscriptions/{user}/{devext}", h.subsPut)
	h.mux = mux
	return h
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.mux.ServeHTTP(w, r)
}

// --- auth ----------------------------------------------------------------------

// cookieToken is the request's sessionid cookie value, "" when absent.
func cookieToken(r *http.Request) string {
	c, err := r.Cookie(sessionCookie)
	if err != nil {
		return ""
	}
	return c.Value
}

// sessionUser resolves the request's cookie to its account, nil when it
// names no live login.
func (h *handler) sessionUser(r *http.Request) *wdb.User {
	u, err := h.svc.GpodderSessionUser(r.Context(), cookieToken(r))
	if err != nil {
		h.log.Warn("gpodder session lookup", "err", err)
		return nil
	}
	return u
}

// setSession sets the cookie for a fresh login, offered for as long as
// the login itself lasts.
func (h *handler) setSession(w http.ResponseWriter, token string, expires time.Time) {
	http.SetCookie(w, &http.Cookie{
		Name: sessionCookie, Value: token, Path: "/", Expires: expires,
		HttpOnly: true, SameSite: http.SameSiteLaxMode, Secure: h.secure,
	})
}

func (h *handler) clearSession(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name: sessionCookie, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, Secure: h.secure,
	})
}

// sameUser compares an account with the path's username the way account
// lookup does: case-insensitively.
func sameUser(u *wdb.User, pathUser string) bool {
	return u != nil && strings.EqualFold(u.Username, pathUser)
}

// authenticate resolves the request to an account: HTTP Basic against
// app passwords, or the session cookie. Either way the authenticated
// user must match the path username; mismatches answer exactly like
// bad credentials so the surface confirms no other account exists.
func (h *handler) authenticate(r *http.Request, pathUser string) (*wdb.User, int, string) {
	if username, password, ok := r.BasicAuth(); ok {
		u, _, err := h.svc.VerifyAppPasswordBasic(r.Context(), username, password)
		if err != nil || !sameUser(u, pathUser) {
			return nil, http.StatusUnauthorized, "wrong username or password"
		}
		return u, 0, ""
	}
	if cookieToken(r) != "" {
		u := h.sessionUser(r)
		if !sameUser(u, pathUser) {
			return nil, http.StatusUnauthorized, "session no longer valid"
		}
		return u, 0, ""
	}
	return nil, http.StatusUnauthorized, "authentication required"
}

// requireUser authenticates against the path username and builds the
// acting-user context, answering the error itself on failure.
func (h *handler) requireUser(w http.ResponseWriter, r *http.Request, pathUser string) (*service.UserCtx, bool) {
	u, status, msg := h.authenticate(r, pathUser)
	if u == nil {
		h.fail(w, status, msg)
		return nil, false
	}
	uc, err := h.svc.UserCtx(r.Context(), u)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "resolving user failed")
		return nil, false
	}
	return uc, true
}

// --- session endpoints ----------------------------------------------------------

func (h *handler) auth2(w http.ResponseWriter, r *http.Request) {
	pathUser := r.PathValue("user")
	switch r.PathValue("op") {
	case "login.json":
		h.login(w, r, pathUser)
	case "logout.json":
		h.logout(w, r, pathUser)
	default:
		http.NotFound(w, r)
	}
}

// login opens a session from Basic credentials and sets its cookie. A
// live cookie for a different username is a 400 per the protocol, and a
// live cookie for the path username answers 200 without Basic
// credentials (pure cookie validation) and without a new cookie, so a
// cookie never extends itself.
func (h *handler) login(w http.ResponseWriter, r *http.Request, pathUser string) {
	cookieUser := h.sessionUser(r)
	if cookieUser != nil && !sameUser(cookieUser, pathUser) {
		h.fail(w, http.StatusBadRequest, "cookie does not match the request username")
		return
	}
	if username, password, ok := r.BasicAuth(); ok {
		u, token, expires, err := h.svc.GpodderLogin(r.Context(), pathUser, username, password)
		if err != nil || u == nil {
			h.fail(w, http.StatusUnauthorized, "wrong username or password")
			return
		}
		h.setSession(w, token, expires)
		h.writeJSON(w, struct{}{})
		return
	}
	if cookieUser != nil {
		h.writeJSON(w, struct{}{})
		return
	}
	h.fail(w, http.StatusUnauthorized, "authentication required")
}

// logout ends the session the cookie names and clears it. It answers 200
// whether or not a session was live; only a live cookie for a different
// username is an error (400), mirroring login.
func (h *handler) logout(w http.ResponseWriter, r *http.Request, pathUser string) {
	if u := h.sessionUser(r); u != nil && !sameUser(u, pathUser) {
		h.fail(w, http.StatusBadRequest, "cookie does not match the request username")
		return
	}
	if err := h.svc.GpodderLogout(r.Context(), cookieToken(r)); err != nil {
		h.fail(w, http.StatusInternalServerError, "ending the session failed")
		return
	}
	h.clearSession(w)
	h.writeJSON(w, struct{}{})
}

// --- devices ---------------------------------------------------------------------

// devicesList reports the user's registered devices. Subscriptions
// are user-global in WaxDeck (a device id only annotates changes), so
// every device reports the user's total synced-subscription count
// rather than a per-device one.
func (h *handler) devicesList(w http.ResponseWriter, r *http.Request) {
	user, ext := splitExt(r.PathValue("userext"))
	if ext != "json" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, user)
	if !ok {
		return
	}
	devs, err := h.svc.GpodderDevices(r.Context(), uc)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing devices failed")
		return
	}
	feeds, err := h.svc.GpodderFeedURLs(r.Context(), uc)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing subscriptions failed")
		return
	}
	out := make([]deviceJSON, 0, len(devs))
	for _, d := range devs {
		out = append(out, deviceJSON{
			ID: d.DeviceID, Caption: d.Caption, Type: d.Type,
			Subscriptions: len(feeds),
		})
	}
	h.writeJSON(w, out)
}

func (h *handler) deviceUpdate(w http.ResponseWriter, r *http.Request) {
	device, ext := splitExt(r.PathValue("devext"))
	if ext != "json" || device == "" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, r.PathValue("user"))
	if !ok {
		return
	}
	// Only supplied keys update; a missing key leaves the stored value
	// alone, which the upsert encodes as the empty string.
	var body struct {
		Caption *string `json:"caption"`
		Type    *string `json:"type"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&body); err != nil && !errors.Is(err, io.EOF) {
		h.fail(w, http.StatusBadRequest, "malformed body")
		return
	}
	caption, devType := "", ""
	if body.Caption != nil {
		caption = *body.Caption
	}
	if body.Type != nil && *body.Type != "" {
		devType = normalizeDeviceType(*body.Type)
	}
	if err := h.svc.GpodderUpsertDevice(r.Context(), uc, device, caption, devType); err != nil {
		h.fail(w, http.StatusInternalServerError, "storing device failed")
		return
	}
	h.writeJSON(w, struct{}{})
}

// --- subscription lists (the Simple API surface) ----------------------------------

func (h *handler) subsUserGet(w http.ResponseWriter, r *http.Request) {
	user, format := splitExt(r.PathValue("userext"))
	h.serveSubscriptionList(w, r, user, "", format)
}

func (h *handler) subsDeviceGet(w http.ResponseWriter, r *http.Request) {
	device, format := splitExt(r.PathValue("devext"))
	h.serveSubscriptionList(w, r, r.PathValue("user"), device, format)
}

func (h *handler) serveSubscriptionList(w http.ResponseWriter, r *http.Request, user, device, format string) {
	if !knownFormat(format) {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, user)
	if !ok {
		return
	}
	if device != "" {
		known, err := h.svc.GpodderDeviceExists(r.Context(), uc, device)
		if err != nil {
			h.fail(w, http.StatusInternalServerError, "checking device failed")
			return
		}
		if !known {
			h.fail(w, http.StatusNotFound, "unknown device")
			return
		}
	}
	// Private shows' feed URLs are deliberately included on this
	// surface; see GpodderFeedURLs for the rationale.
	urls, err := h.svc.GpodderFeedURLs(r.Context(), uc)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing subscriptions failed")
		return
	}
	switch format {
	case "json":
		h.writeJSON(w, urls)
	case "txt":
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		var b strings.Builder
		for _, u := range urls {
			b.WriteString(u)
			b.WriteByte('\n')
		}
		io.WriteString(w, b.String())
	case "opml":
		w.Header().Set("Content-Type", "text/xml; charset=utf-8")
		w.Write(renderOPML(urls))
	}
}

// subsPut is the full-list upload: the body carries the device's
// complete subscription list and the server diffs it against the
// user's current one. Failing feeds are logged and skipped rather
// than failing the upload; gpodder clients treat any non-200 as a
// full-sync failure and would retry the whole list forever.
func (h *handler) subsPut(w http.ResponseWriter, r *http.Request) {
	device, format := splitExt(r.PathValue("devext"))
	if !knownFormat(format) || device == "" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, r.PathValue("user"))
	if !ok {
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		h.fail(w, http.StatusBadRequest, "reading body failed")
		return
	}
	uploaded, err := parseSubscriptionList(body, format)
	if err != nil {
		h.fail(w, http.StatusBadRequest, "malformed subscription list")
		return
	}
	if err := h.svc.GpodderUpsertDevice(r.Context(), uc, device, "", ""); err != nil {
		h.fail(w, http.StatusInternalServerError, "storing device failed")
		return
	}
	current, err := h.svc.GpodderFeedURLs(r.Context(), uc)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing subscriptions failed")
		return
	}
	want := make(map[string]bool, len(uploaded))
	for _, raw := range uploaded {
		if s := sanitizeFeedURL(raw); s != "" {
			want[s] = true
		}
	}
	have := make(map[string]bool, len(current))
	for _, u := range current {
		have[u] = true
	}
	for u := range want {
		if !have[u] {
			if err := h.svc.GpodderSubscribe(r.Context(), uc, u, device); err != nil {
				h.log.Warn("gpodder subscribe", "url", u, "err", err)
			}
		}
	}
	for _, u := range current {
		if !want[u] {
			if err := h.svc.GpodderUnsubscribe(r.Context(), uc, u, device); err != nil {
				h.log.Warn("gpodder unsubscribe", "url", u, "err", err)
			}
		}
	}
	h.writeJSON(w, struct{}{})
}

// --- subscription deltas (the API 2 surface) ---------------------------------------

func (h *handler) subDeltaPost(w http.ResponseWriter, r *http.Request) {
	device, ext := splitExt(r.PathValue("devext"))
	if ext != "json" || device == "" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, r.PathValue("user"))
	if !ok {
		return
	}
	var body struct {
		Add    []string `json:"add"`
		Remove []string `json:"remove"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&body); err != nil {
		h.fail(w, http.StatusBadRequest, "malformed body")
		return
	}
	inAdd := make(map[string]bool, len(body.Add))
	for _, u := range body.Add {
		inAdd[u] = true
	}
	for _, u := range body.Remove {
		if inAdd[u] {
			h.fail(w, http.StatusBadRequest, "the same url is in add and remove")
			return
		}
	}
	if err := h.svc.GpodderUpsertDevice(r.Context(), uc, device, "", ""); err != nil {
		h.fail(w, http.StatusInternalServerError, "storing device failed")
		return
	}
	updates := make([][2]string, 0)
	apply := func(raw string, remove bool) {
		s := sanitizeFeedURL(raw)
		if s != raw {
			updates = append(updates, [2]string{raw, s})
		}
		if s == "" {
			return
		}
		var err error
		if remove {
			err = h.svc.GpodderUnsubscribe(r.Context(), uc, s, device)
		} else {
			err = h.svc.GpodderSubscribe(r.Context(), uc, s, device)
		}
		if err != nil {
			// Best effort, mirroring the full-list upload: a dead feed
			// must not wedge the client's sync loop.
			h.log.Warn("gpodder subscription change", "url", s, "remove", remove, "err", err)
		}
	}
	for _, u := range body.Add {
		apply(u, false)
	}
	for _, u := range body.Remove {
		apply(u, true)
	}
	h.writeJSON(w, uploadAckJSON{Timestamp: time.Now().Unix(), UpdateURLs: updates})
}

func (h *handler) subDeltaGet(w http.ResponseWriter, r *http.Request) {
	device, ext := splitExt(r.PathValue("devext"))
	if ext != "json" || device == "" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, r.PathValue("user"))
	if !ok {
		return
	}
	since, ok2 := parseSince(r.URL.Query().Get("since"))
	if !ok2 {
		h.fail(w, http.StatusBadRequest, "malformed since")
		return
	}
	events, err := h.svc.GpodderSubChangesSince(r.Context(), uc, since)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing changes failed")
		return
	}
	// Collapse per feed URL: the latest action since the cursor is the
	// state worth reporting; intermediate flip-flops carry nothing.
	latest := make(map[string]string, len(events))
	var order []string
	var maxTS int64
	for _, ev := range events {
		if _, seen := latest[ev.FeedURL]; !seen {
			order = append(order, ev.FeedURL)
		}
		latest[ev.FeedURL] = ev.Action
		if ev.TsSec > maxTS {
			maxTS = ev.TsSec
		}
	}
	out := subDeltaJSON{Add: []string{}, Remove: []string{}}
	for _, u := range order {
		if latest[u] == "add" {
			out.Add = append(out.Add, u)
		} else {
			out.Remove = append(out.Remove, u)
		}
	}
	out.Timestamp = maxTS
	if out.Timestamp == 0 {
		out.Timestamp = time.Now().Unix()
	}
	h.writeJSON(w, out)
}

// --- episode actions ---------------------------------------------------------------

// validActions is the protocol's action vocabulary.
var validActions = map[string]bool{
	"download": true, "play": true, "delete": true, "new": true, "flattr": true,
}

func (h *handler) episodesPost(w http.ResponseWriter, r *http.Request) {
	user, ext := splitExt(r.PathValue("userext"))
	if ext != "json" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, user)
	if !ok {
		return
	}
	var actions []episodeActionJSON
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&actions); err != nil {
		h.fail(w, http.StatusBadRequest, "malformed body")
		return
	}
	// Validate the whole batch before storing any of it: a bad entry
	// rejects the request so the client never half-syncs silently.
	for i := range actions {
		actions[i].Action = strings.ToLower(actions[i].Action)
		if actions[i].Podcast == "" || actions[i].Episode == "" || !validActions[actions[i].Action] {
			h.fail(w, http.StatusBadRequest, "invalid episode action")
			return
		}
	}
	now := time.Now().Unix()
	for _, a := range actions {
		err := h.svc.GpodderAppendAction(r.Context(), uc, wdb.GpodderAction{
			PodcastURL: a.Podcast, EpisodeURL: a.Episode, DeviceID: a.Device,
			Action: a.Action, ActionTS: a.Timestamp,
			StartedSec: a.Started, PositionSec: a.Position, TotalSec: a.Total,
			UploadedSec: now,
		})
		if err != nil {
			h.fail(w, http.StatusInternalServerError, "storing episode action failed")
			return
		}
		if a.Action == "play" && a.Position != nil {
			// Positions flow through to WaxDeck playback state so a
			// gpodder client's progress survives into first-party
			// clients. Best effort: unknown feeds and episodes never
			// fail the batch.
			if err := h.svc.GpodderApplyPlay(r.Context(), uc, a.Podcast, a.Episode, a.Position, a.Total, a.Timestamp); err != nil {
				h.log.Warn("gpodder play write-through", "episode", a.Episode, "err", err)
			}
		}
	}
	h.writeJSON(w, uploadAckJSON{Timestamp: now, UpdateURLs: [][2]string{}})
}

func (h *handler) episodesGet(w http.ResponseWriter, r *http.Request) {
	user, ext := splitExt(r.PathValue("userext"))
	if ext != "json" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, user)
	if !ok {
		return
	}
	q := r.URL.Query()
	since, ok2 := parseSince(q.Get("since"))
	if !ok2 {
		h.fail(w, http.StatusBadRequest, "malformed since")
		return
	}
	rows, err := h.svc.GpodderActionsSince(r.Context(), uc, since, q.Get("podcast"), q.Get("device"))
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing episode actions failed")
		return
	}
	aggregated := q.Get("aggregated") == "true" || q.Get("aggregated") == "1"
	out := actionsPageJSON{Actions: []episodeActionJSON{}}
	var maxUploaded int64
	index := make(map[string]int)
	for _, a := range rows {
		if a.UploadedSec > maxUploaded {
			maxUploaded = a.UploadedSec
		}
		j := actionJSON(a)
		if aggregated {
			// Rows arrive oldest first, so replacing in place keeps
			// only the newest action per episode URL.
			if i, seen := index[a.EpisodeURL]; seen {
				out.Actions[i] = j
				continue
			}
			index[a.EpisodeURL] = len(out.Actions)
		}
		out.Actions = append(out.Actions, j)
	}
	out.Timestamp = maxUploaded
	if out.Timestamp == 0 {
		out.Timestamp = time.Now().Unix()
	}
	h.writeJSON(w, out)
}

// --- response plumbing ---------------------------------------------------------------

func (h *handler) writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		h.log.Warn("writing gpodder response", "err", err)
	}
}

// fail answers a plain status code; gpodder clients only check the
// status. A 401 carries the Basic challenge so clients that wait for
// one send credentials.
func (h *handler) fail(w http.ResponseWriter, status int, msg string) {
	if status == http.StatusUnauthorized {
		w.Header().Set("WWW-Authenticate", `Basic realm="WaxDeck gpodder API"`)
	}
	http.Error(w, msg, status)
}
