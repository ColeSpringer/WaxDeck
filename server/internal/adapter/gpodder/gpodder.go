// Package gpodder is the gpodder.net API 2 compatibility surface:
// session login, device registry, subscription sync, and episode
// action sync, so podcast clients (AntennaPod is the reference) sync
// their subscription lists and playback positions against WaxDeck. It
// sits on the service layer like any first-party handler.
//
// Authentication on every endpoint is HTTP Basic with the WaxDeck
// username and an app password (the login password never works here),
// or the sessionid cookie the login endpoint, and any request signed with
// Basic, sets: an opaque token for a stored session that ends with its
// app password, its account, or a logout.
//
// Subscriptions are one list for the whole account, and every device
// reads all of it. A device's list is what it holds: an add holds a
// show, a full-list upload holds what it names and lets go of what it
// no longer names, and a show leaves the account only with its last
// hold, the WaxDeck apps holding what they subscribed to. An incremental
// remove is a deliberate unsubscribe and goes for the whole account. A
// device is told each show by the URL it last sent or was sent for it,
// else the one the account subscribed by.
package gpodder

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
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

// ServeHTTP keeps every answer out of shared caches: each is one
// account's, and any may carry a fresh session cookie.
func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
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
	u, _ := h.session(r)
	return u
}

// session is sessionUser answering the session too.
func (h *handler) session(r *http.Request) (*wdb.User, *wdb.GpodderSession) {
	u, s, err := h.svc.GpodderSession(r.Context(), cookieToken(r))
	if err != nil {
		h.log.Warn("gpodder session lookup", "err", err)
		return nil, nil
	}
	return u, s
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

// signIn is how a request authenticated: by the session its cookie names,
// or by the app password it was signed with.
type signIn struct {
	user        *wdb.User
	session     *wdb.GpodderSession
	appPassword string
}

// authenticate resolves the request to an account: a session cookie of
// the path's account, else HTTP Basic against app passwords. Either way
// the authenticated user must match the path username; mismatches answer
// exactly like bad credentials so the surface confirms no other account
// exists.
func (h *handler) authenticate(r *http.Request, pathUser string) (signIn, int, string) {
	if cookieToken(r) != "" {
		if u, s := h.session(r); sameUser(u, pathUser) {
			return signIn{user: u, session: s}, 0, ""
		}
	}
	if username, password, ok := r.BasicAuth(); ok {
		u, apID, err := h.svc.VerifyAppPasswordBasic(r.Context(), username, password)
		if err != nil || !sameUser(u, pathUser) {
			return signIn{}, http.StatusUnauthorized, "wrong username or password"
		}
		return signIn{user: u, appPassword: apID}, 0, ""
	}
	if cookieToken(r) != "" {
		return signIn{}, http.StatusUnauthorized, "session no longer valid"
	}
	return signIn{}, http.StatusUnauthorized, "authentication required"
}

// requireUser authenticates against the path username and builds the
// acting-user context, answering the error itself on failure. A request
// signed with Basic credentials is answered a session cookie as a login
// is, and a session it opened is renewed while the client keeps using it:
// gPodder's client sends the credentials only when challenged and answers
// three challenges in its life, so it signs in once and its cookie jar
// carries the session from there.
func (h *handler) requireUser(w http.ResponseWriter, r *http.Request, pathUser string) (*service.UserCtx, bool) {
	uc, _, ok := h.requireClient(w, r, pathUser)
	return uc, ok
}

// requireClient is requireUser that also answers the app password the
// request signed in with, directly or through the session its cookie names.
func (h *handler) requireClient(w http.ResponseWriter, r *http.Request, pathUser string) (*service.UserCtx, string, bool) {
	in, status, msg := h.authenticate(r, pathUser)
	if in.user == nil {
		h.fail(w, status, msg)
		return nil, "", false
	}
	appPassword := in.appPassword
	if in.session != nil {
		appPassword = in.session.AppPasswordID
	}
	var token string
	var expires time.Time
	var err error
	switch {
	case in.appPassword != "":
		token, expires, err = h.svc.GpodderOpenSession(r.Context(), in.user, in.appPassword)
	case in.session != nil:
		token, expires, err = h.svc.GpodderSessionUsed(r.Context(), in.session)
	}
	if err != nil {
		h.log.Warn("keeping a gpodder session", "err", err)
	} else if token != "" {
		h.setSession(w, token, expires)
	}
	uc, err := h.svc.UserCtx(r.Context(), in.user)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "resolving user failed")
		return nil, "", false
	}
	return uc, appPassword, true
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

// devicesList reports the user's registered devices. Every device reads
// the whole account's list, so each reports the account's total.
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
	feeds, err := h.svc.GpodderFeedURLs(r.Context(), uc, "")
	if err != nil {
		h.failService(w, err, "listing subscriptions failed")
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
		h.failBody(w, err)
		return
	}
	caption, devType := "", ""
	if body.Caption != nil {
		caption = *body.Caption
	}
	if body.Type != nil && *body.Type != "" {
		devType = normalizeDeviceType(*body.Type)
	}
	if !h.upsertDevice(w, r, uc, device, caption, devType) {
		return
	}
	h.writeJSON(w, struct{}{})
}

// upsertDevice registers or updates a device, answering the error itself:
// a refused one (an id too long, an account at its device cap) is a 400.
func (h *handler) upsertDevice(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, device, caption, devType string) bool {
	err := h.svc.GpodderUpsertDevice(r.Context(), uc, device, caption, devType)
	switch {
	case err == nil:
		return true
	case service.KindOf(err) == service.KindInvalid:
		h.fail(w, http.StatusBadRequest, err.Error())
	default:
		h.fail(w, http.StatusInternalServerError, "storing device failed")
	}
	return false
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
	urls, err := h.svc.GpodderFeedURLs(r.Context(), uc, device)
	if err != nil {
		h.failService(w, err, "listing subscriptions failed")
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

// subsPut is the full-list upload: the body is the device's own list,
// which replaces what that device holds (see the package comment). A feed
// that cannot be added is parked or refused rather than failing the
// upload: gpodder clients treat any non-200 as a failed sync and would
// retry the whole list forever, and this call has no answer to carry a
// refusal in, so the account's inbox does.
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
		h.failBody(w, err)
		return
	}
	uploaded, err := parseSubscriptionList(body, format)
	if err != nil {
		h.fail(w, http.StatusBadRequest, "malformed subscription list")
		return
	}
	if len(uploaded) > maxUploadFeeds {
		h.fail(w, http.StatusRequestEntityTooLarge, fmt.Sprintf("a list carries at most %d feeds", maxUploadFeeds))
		return
	}
	if !h.upsertDevice(w, r, uc, device, "", "") {
		return
	}
	res, err := h.svc.GpodderReplaceDeviceList(r.Context(), uc, device, feedList(uploaded))
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "replacing the device list failed")
		return
	}
	counts := map[service.GpodderOutcome]int{}
	for _, outcome := range res.Outcomes {
		counts[outcome]++
	}
	// A list that let go of shows changed the account; parked and refused
	// feeds are asked for again on every sync, and the inbox records them.
	level := slog.LevelDebug
	if res.Released > 0 {
		level = slog.LevelInfo
	}
	if res.Released > 0 || counts[service.GpodderParked] > 0 || counts[service.GpodderRefused] > 0 {
		h.log.Log(r.Context(), level, "gpodder device list", "device", device, "released", res.Released,
			"parked", counts[service.GpodderParked], "refused", counts[service.GpodderRefused])
	}
	h.writeJSON(w, struct{}{})
}

// --- subscription deltas (the API 2 surface) ---------------------------------------

func (h *handler) subDeltaPost(w http.ResponseWriter, r *http.Request) {
	arrived := time.Now()
	device, ext := splitExt(r.PathValue("devext"))
	if ext != "json" || device == "" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, ok := h.requireUser(w, r, r.PathValue("user"))
	if !ok {
		return
	}
	// As of the upload's arrival, before its own work, which can wait on
	// the writer or fetch feeds for a while: a client keeps it as the since
	// of its next delta, which must still carry what changed meanwhile.
	timestamp, err := h.svc.GpodderUploadCursor(r.Context(), uc, device, arrived)
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "reading the device's place failed")
		return
	}
	var body struct {
		Add    []string `json:"add"`
		Remove []string `json:"remove"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&body); err != nil {
		h.failBody(w, err)
		return
	}
	if len(body.Add)+len(body.Remove) > maxUploadFeeds {
		h.fail(w, http.StatusRequestEntityTooLarge, fmt.Sprintf("a change carries at most %d feeds", maxUploadFeeds))
		return
	}
	// Compared trimmed and sanitized, as the service acts on them.
	acted := func(raw string) string { return cmp.Or(sanitizeFeedURL(raw), raw) }
	inAdd := make(map[string]bool, len(body.Add))
	for _, u := range body.Add {
		inAdd[acted(u)] = true
	}
	for _, u := range body.Remove {
		if inAdd[acted(u)] {
			h.fail(w, http.StatusBadRequest, "the same url is in add and remove")
			return
		}
	}
	if !h.upsertDevice(w, r, uc, device, "", "") {
		return
	}
	outcomes, err := h.svc.GpodderApplyChanges(r.Context(), uc, device, feedList(body.Add), feedList(body.Remove))
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "applying subscription changes failed")
		return
	}
	// A URL this server will not take, malformed or refused, is answered
	// as "", the protocol's way of saying to drop it, and a rewritten one
	// as what it became. A parked one is answered as it was sent: it is
	// still being tried.
	updates := make([][2]string, 0)
	answer := func(raw string, add bool) {
		s := sanitizeFeedURL(raw)
		switch {
		case s != "" && add && outcomes[s] == service.GpodderRefused:
			updates = append(updates, [2]string{raw, ""})
		case s != raw:
			updates = append(updates, [2]string{raw, s})
		}
	}
	for _, raw := range body.Add {
		answer(raw, true)
	}
	for _, raw := range body.Remove {
		answer(raw, false)
	}
	h.writeJSON(w, uploadAckJSON{Timestamp: timestamp, UpdateURLs: updates})
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
	h.svc.GpodderSeeDevice(r.Context(), uc, device)
	events, cursor, err := h.svc.GpodderSubChangesSince(r.Context(), uc, device, since)
	if err == nil {
		err = h.svc.GpodderRememberRead(r.Context(), uc, device, cursor)
	}
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing changes failed")
		return
	}
	// The service says each URL once, with its show's latest change.
	out := subDeltaJSON{Add: []string{}, Remove: []string{}}
	for _, ev := range events {
		if ev.Action == "add" {
			out.Add = append(out.Add, ev.FeedURL)
		} else {
			out.Remove = append(out.Remove, ev.FeedURL)
		}
	}
	// The cursor trails the clock and every change still in flight, so a
	// change stamped before the read and committed after it is in the next
	// delta.
	out.Timestamp = cursor
	h.writeJSON(w, out)
}

// --- episode actions ---------------------------------------------------------------

// validActions is the protocol's action vocabulary.
var validActions = map[string]bool{
	"download": true, "play": true, "delete": true, "new": true, "flattr": true,
}

func (h *handler) episodesPost(w http.ResponseWriter, r *http.Request) {
	arrived := time.Now()
	user, ext := splitExt(r.PathValue("userext"))
	if ext != "json" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, appPassword, ok := h.requireClient(w, r, user)
	if !ok {
		return
	}
	// As of the upload's arrival, for the same reason as a subscription
	// upload's.
	timestamp := h.svc.GpodderEpisodesUploadCursor(uc, appPassword, arrived)
	var actions []json.RawMessage
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&actions); err != nil {
		h.failBody(w, err)
		return
	}
	if len(actions) > maxUploadActions {
		h.fail(w, http.StatusRequestEntityTooLarge, fmt.Sprintf("an upload carries at most %d actions", maxUploadActions))
		return
	}
	// A client sends a batch until it is answered, so one action that
	// cannot be kept, a field of the wrong type included, must not refuse
	// the rest: it is skipped.
	rows := make([]wdb.GpodderAction, 0, len(actions))
	for _, raw := range actions {
		var a episodeActionJSON
		if json.Unmarshal(raw, &a) != nil {
			continue
		}
		if row, ok := storedAction(a); ok {
			rows = append(rows, row)
		}
	}
	if skipped := len(actions) - len(rows); skipped > 0 {
		h.log.Info("gpodder episode actions skipped", "skipped", skipped, "kept", len(rows))
	}
	if err := h.svc.GpodderRecordActions(r.Context(), uc, rows); err != nil {
		h.fail(w, http.StatusInternalServerError, "storing episode actions failed")
		return
	}
	h.writeJSON(w, uploadAckJSON{Timestamp: timestamp, UpdateURLs: [][2]string{}})
}

// storedAction is an uploaded action as the log keeps it; false for one
// it cannot keep: one naming no feed, episode or action of the protocol's,
// a field longer than the log keeps, this server's own device, a time no
// action can have, or numbers no play can have. A client reads each one
// back, gPodder's mygpoclient refusing whatever the protocol does not
// allow.
func storedAction(a episodeActionJSON) (wdb.GpodderAction, bool) {
	a.Action = strings.ToLower(a.Action)
	if a.Podcast == "" || a.Episode == "" || !validActions[a.Action] ||
		len(a.Podcast) > maxURLLen || len(a.Episode) > maxURLLen || len(a.Device) > service.GpodderMaxDeviceIDLen ||
		a.Device == service.GpodderOwnDevice || !plausiblePlay(a) {
		return wdb.GpodderAction{}, false
	}
	ts, err := service.NormalizeGpodderTime(a.Timestamp)
	if err != nil {
		return wdb.GpodderAction{}, false
	}
	return wdb.GpodderAction{
		PodcastURL: a.Podcast, EpisodeURL: a.Episode, DeviceID: a.Device,
		Action: a.Action, ActionTS: ts,
		StartedSec: a.Started, PositionSec: a.Position, TotalSec: a.Total,
	}, true
}

// plausiblePlay reports whether an action's numbers are a play's that an
// episode can have: only a play carries a start, position or length, a
// play its start or length only beside its position, none negative or
// past maxPlaySeconds, and a position no further than a length given.
func plausiblePlay(a episodeActionJSON) bool {
	switch {
	case a.Action != "play" && (a.Started != nil || a.Position != nil || a.Total != nil):
		return false
	case a.Position == nil && (a.Started != nil || a.Total != nil):
		return false
	}
	for _, n := range []*int64{a.Started, a.Position, a.Total} {
		if n != nil && (*n < 0 || *n > maxPlaySeconds) {
			return false
		}
	}
	return a.Position == nil || a.Total == nil || *a.Position <= *a.Total
}

func (h *handler) episodesGet(w http.ResponseWriter, r *http.Request) {
	user, ext := splitExt(r.PathValue("userext"))
	if ext != "json" {
		h.fail(w, http.StatusBadRequest, "unknown format")
		return
	}
	uc, appPassword, ok := h.requireClient(w, r, user)
	if !ok {
		return
	}
	q := r.URL.Query()
	since, ok2 := parseSince(q.Get("since"))
	if !ok2 {
		h.fail(w, http.StatusBadRequest, "malformed since")
		return
	}
	rows, cursor, err := h.svc.GpodderActionsSince(r.Context(), uc, appPassword, since, q.Get("podcast"), q.Get("device"))
	if err != nil {
		h.fail(w, http.StatusInternalServerError, "listing episode actions failed")
		return
	}
	aggregated := q.Get("aggregated") == "true" || q.Get("aggregated") == "1"
	out := actionsPageJSON{Actions: []episodeActionJSON{}, Timestamp: cursor}
	index := make(map[string]int)
	for _, a := range rows {
		j := actionJSON(a)
		if aggregated {
			// An episode keeps its action of the latest time, and of two at
			// one time the later upload's, rows coming oldest first. The
			// protocol's times share one layout, so they compare as text. A
			// private show's episodes go by their guids as well as their
			// bare links, which two of them can share.
			key := a.EpisodeURL + "\x00" + a.GUID
			if i, seen := index[key]; seen {
				if a.ActionTS >= out.Actions[i].Timestamp {
					out.Actions[i] = j
				}
				continue
			}
			index[key] = len(out.Actions)
		}
		out.Actions = append(out.Actions, j)
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

// failBody answers a body that could not be read: 413 for one over the
// limit, which retrying as it is cannot cure, else 400.
func (h *handler) failBody(w http.ResponseWriter, err error) {
	var tooBig *http.MaxBytesError
	if errors.As(err, &tooBig) {
		h.fail(w, http.StatusRequestEntityTooLarge, "request body too large")
		return
	}
	h.fail(w, http.StatusBadRequest, "malformed body")
}

// failService answers a service's failure: 503 while the catalog is in a
// hand-off, as the REST surface answers, so a client tries again rather
// than reading an answer, else a 500 saying what failed.
func (h *handler) failService(w http.ResponseWriter, err error, msg string) {
	if service.KindOf(err) == service.KindMaintenance {
		h.fail(w, http.StatusServiceUnavailable, "the catalog is under maintenance; retry shortly")
		return
	}
	h.fail(w, http.StatusInternalServerError, msg)
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
