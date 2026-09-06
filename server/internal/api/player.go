package api

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// ConnectResolver implements connect.MediaResolver over the service
// layer and the streaming bridge: queue hydration, device-fetchable
// stream URLs, and gapless timelines. Every path re-enforces the
// owning user's visibility.
type ConnectResolver struct {
	Svc    *service.Library
	Bridge *flow.Bridge
	Media  *auth.MediaTokens
}

// Entries hydrates queue entries, enforcing visibility per pid.
func (r *ConnectResolver) Entries(ctx context.Context, userID string, pids []string) ([]connect.QueueEntry, error) {
	entries, err := r.Svc.QueueEntries(ctx, userID, pids)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return nil, connect.ErrNotFound
		}
		return nil, err
	}
	return entries, nil
}

// delivery is what one endpoint's render needs beyond the queue
// itself: where its URLs hang off, how long the tokens on them have to
// live, and the format floor its kind imposes.
type delivery struct {
	base    string
	ttl     time.Duration
	force   string
	formats []string
}

// StreamItems builds absolute media URLs for a device endpoint. The
// jukebox gets wav, cast devices get the derived shape, and renderers
// get the best format they and the engine agree on, falling back to the
// mp3 floor. Without the engine, span tracks are refused: partial
// support that loses positions is worse than a clear error.
//
// A multi-file audiobook is one entry rendered as one item per part,
// because a device fetches whole files and steps through them itself.
// The session manager reads the parts back as one book from `Entry` and
// `PartStartMS`, so every position that crosses this boundary - what
// watchers see, what the listener resumes at - stays in book
// milliseconds.
func (r *ConnectResolver) StreamItems(ctx context.Context, userID string, entries []connect.QueueEntry, target connect.EndpointTarget, base string, ttl time.Duration) ([]connect.MediaItem, error) {
	uc, err := r.Svc.UserCtxByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	d := delivery{base: base, ttl: ttl}
	// formats is what the endpoint said it accepts, handed to the
	// bridge rather than resolved here: picking well needs the source
	// (whether the renderer already plays these bytes, whether the
	// source is lossy), and the bridge is where the source is resolved.
	// The jukebox declares nothing on purpose: it reads a wav preamble
	// off its input and fails on anything else, so there is nothing to
	// negotiate.
	switch target.Kind {
	case connect.KindDLNA:
		// mp3 is the floor rather than the answer: every renderer plays
		// it, so it is what a renderer that declared nothing (or nothing
		// the engine can produce) gets.
		d.force = "mp3"
		d.formats = target.Formats
	case connect.KindJukebox:
		d.force = "wav"
	}
	out := make([]connect.MediaItem, 0, len(entries))
	for i, e := range entries {
		art := ""
		if r.Media != nil {
			// The art token takes the ttl this call was handed, which
			// connect sizes to the whole queue's duration plus a margin.
			// A fresh mint with a hand-picked lifetime is the bug it
			// looks like the fix for: art would start 401-ing partway
			// into a long queue while the audio played on.
			//
			// Set unconditionally, exactly as the item read surface sets
			// `artUrl` unconditionally: whether art exists behind a pid
			// is only knowable by resolving it, which loads the whole
			// source image, and a queue load would pay that per entry to
			// learn something a 404 says for free. A renderer handed a
			// URL that 404s draws no art, which is what it would have
			// done without the URL.
			token, _ := r.Media.MintFor(userID, e.PID, ttl)
			art = base + mediaArtURL(e.PID, token, castArtSize)
		}
		// A multi-file audiobook lays out as one item per part,
		// resolved together: the item and the book are read once
		// between them however many parts there are.
		pieces, err := r.Svc.BookPieces(ctx, uc, e.PID)
		if err != nil {
			return nil, err
		}
		if len(pieces) == 0 {
			item, err := r.wholeItem(ctx, uc, userID, e, d)
			if err != nil {
				return nil, err
			}
			item.ArtURL, item.Entry = art, i
			out = append(out, item)
			continue
		}
		// Resolved once for the book rather than once per part: it is
		// the listener's setting for the book, not for a file in it.
		voiceBoost := r.Svc.EffectiveVoiceBoost(ctx, uc, e.PID)
		for _, piece := range pieces {
			item, err := r.partItem(ctx, userID, e, piece, d, voiceBoost)
			if err != nil {
				return nil, err
			}
			item.ArtURL, item.Entry = art, i
			out = append(out, item)
		}
	}
	return out, nil
}

// wholeItem renders one queue entry served as itself: a track, an
// episode, or a single-file book.
//
// This is where the awkward cases live, and they are all properties of
// a whole item: an episode whose audio was never fetched relays from
// the feed, and a track carved out of a larger file is refused where
// there is no engine to cut it. A book's parts are neither, which is
// why they take their own path.
func (r *ConnectResolver) wholeItem(ctx context.Context, uc *service.UserCtx, userID string, e connect.QueueEntry, d delivery) (connect.MediaItem, error) {
	item := connect.MediaItem{PID: e.PID, Title: e.Title, Artist: e.Artist, DurationMS: e.DurationMS}
	if r.Bridge != nil {
		// The stored voice boost setting routes here exactly as it does
		// at play-info: a device endpoint has no local DSP, so the
		// engine applies it server side when the user asked.
		info, err := r.Bridge.PlayInfoFor(ctx, userID, e.PID, flow.PlayOptions{
			TTL:           d.ttl,
			ForceFormat:   d.force,
			DeviceFormats: d.formats,
			VoiceBoost:    r.Svc.EffectiveVoiceBoost(ctx, uc, e.PID),
		})
		if err != nil {
			if u, mime, ok := r.enclosureItem(ctx, userID, e.PID, d.ttl, d.force, err); ok {
				item.URL, item.MimeType = d.base+u, mime
				return item, nil
			}
			return connect.MediaItem{}, err
		}
		item.URL, item.MimeType = d.base+info.URL, info.MimeType
		return item, nil
	}
	res, err := r.Svc.DirectPlayInfo(ctx, uc, e.PID, "")
	if err != nil {
		if u, mime, ok := r.enclosureItem(ctx, userID, e.PID, d.ttl, d.force, err); ok {
			item.URL, item.MimeType = d.base+u, mime
			return item, nil
		}
		return connect.MediaItem{}, err
	}
	if res.HasSpan {
		return connect.MediaItem{}, connect.InvalidError{
			Msg:    "this track is a window into a larger file and needs the streaming engine to cast: " + e.PID,
			Code:   "feature-unavailable",
			Params: map[string]string{"feature": "windowed-track", "pid": e.PID},
		}
	}
	item.URL = r.downloadURL(userID, e.PID, res.File.ETag, "", d)
	item.MimeType = res.File.MimeType
	return item, nil
}

// partItem renders one part of a multi-file audiobook from the
// resolution BookPieces already did: everything the mint reads is in
// the piece, so nothing here goes back to the catalog for it.
func (r *ConnectResolver) partItem(ctx context.Context, userID string, e connect.QueueEntry, piece service.PlayPiece, d delivery, voiceBoost bool) (connect.MediaItem, error) {
	item := connect.MediaItem{
		PID:         e.PID,
		Title:       e.Title,
		Artist:      e.Artist,
		DurationMS:  piece.Part.DurationMS,
		PartStartMS: piece.Part.StartMS,
	}
	if r.Bridge != nil {
		info, err := r.Bridge.PlayInfoForSource(ctx, userID, e.PID, piece.Src, flow.PlayOptions{
			TTL:           d.ttl,
			ForceFormat:   d.force,
			DeviceFormats: d.formats,
			FilePID:       piece.Part.FilePID,
			VoiceBoost:    voiceBoost,
		})
		if err != nil {
			return connect.MediaItem{}, err
		}
		item.URL, item.MimeType = d.base+info.URL, info.MimeType
		return item, nil
	}
	item.URL = r.downloadURL(userID, e.PID, piece.File.ETag, piece.Part.FilePID, d)
	item.MimeType = piece.File.MimeType
	return item, nil
}

// downloadURL builds the original-bytes URL a device fetches on a
// server running without the engine. filePID names one file of a
// multi-file book, the same selector play-info hangs on a download
// URL: the pid names the book, and this names the file inside it.
func (r *ConnectResolver) downloadURL(userID, pid, etag, filePID string, d delivery) string {
	token, _ := r.Media.MintFor(userID, pid, d.ttl)
	u := d.base + "/media/download?pid=" + url.QueryEscape(pid) +
		"&mt=" + url.QueryEscape(token) + "&id=" + url.QueryEscape(etag)
	if filePID != "" {
		u += "&f=" + url.QueryEscape(filePID)
	}
	return u
}

// Timeline renders the queue as one gapless HLS stream when the engine
// supports timelines and every entry is a whole file. A nil result
// means "use StreamItems".
//
// A multi-file audiobook in the queue is one of the things that means
// it. Such a book is several files with a reading order, which a
// timeline has no way to carry: the boundary table places one member
// per entry. The queue then loads per item, and the music in it loses
// the seamless render until the book leaves - a queue mixing the two is
// rare, and its crossfade would be zeroed at the book anyway.
func (r *ConnectResolver) Timeline(ctx context.Context, userID string, entries []connect.QueueEntry, base string) (*connect.TimelineMedia, error) {
	if r.Bridge == nil || !r.Bridge.TimelinesSupported() {
		return nil, nil
	}
	// The session owner's, not the caller's: a household member with
	// permission to drive somebody else's cast session must not have
	// their own crossfade rewrite how it sounds mid-queue.
	prefs := r.Svc.PrefsForUser(ctx, userID)
	opts := flow.TimelineOptions{
		CrossfadeSeconds: prefs.CrossfadeSeconds,
		ReplayGain:       prefs.ReplayGain,
	}
	members := make([]flow.TimelineMember, 0, len(entries))
	for _, e := range entries {
		parts, err := r.Svc.BookParts(ctx, e.PID)
		if err != nil {
			return nil, err
		}
		if len(parts) > 0 {
			return nil, nil
		}
		src, err := r.Svc.StreamSource(ctx, e.PID, "")
		if err != nil {
			return nil, nil
		}
		if src.Virtual && !r.Bridge.TimelineMemberWindowsSupported() {
			// A carved track can join a gapless timeline only where the
			// sidecar takes member windows; otherwise fall back per item.
			return nil, nil
		}
		if opts.ReplayGain {
			r.Svc.FillLoudness(ctx, &src)
		}
		members = append(members, flow.TimelineMember{PID: e.PID, Src: src})
	}
	res, err := r.Bridge.TimelineFor(ctx, userID, members, opts)
	if err != nil {
		return nil, err
	}
	if res.JobPID != "" {
		// Measurement is running; the cast load falls back to per-item
		// URLs rather than waiting.
		return nil, nil
	}
	tm := &connect.TimelineMedia{
		Item: connect.MediaItem{
			URL:        base + res.URL,
			MimeType:   res.MimeType,
			DurationMS: res.DurationMS,
			Title:      "Queue",
		},
		EnvelopeRate: res.EnvelopeRate,
		DurationMS:   res.DurationMS,
	}
	if len(entries) > 0 {
		tm.Item.Title = entries[0].Title
		tm.Item.Artist = entries[0].Artist
	}
	for _, b := range res.Boundaries {
		tm.Boundaries = append(tm.Boundaries, connect.TimelineBoundary(b))
	}
	return tm, nil
}

// ConnectSink implements connect.ProgressSink over the service layer.
type ConnectSink struct {
	Svc *service.Library
}

func (s *ConnectSink) Progress(userID, pid string, positionMS int64) {
	s.Svc.PlayerProgress(userID, pid, positionMS)
}

func (s *ConnectSink) Checkpoint(ctx context.Context, userID, pid string, positionMS int64) {
	s.Svc.PlayerCheckpoint(ctx, userID, pid, positionMS)
}

func (s *ConnectSink) SetQueue(ctx context.Context, userID string, pids []string) {
	s.Svc.PlayerSetQueue(ctx, userID, pids)
}

func (s *ConnectSink) Listen(ctx context.Context, userID, pid string, msPlayed int64, startedAt time.Time) {
	s.Svc.PlayerListen(ctx, userID, pid, msPlayed, startedAt)
}

// --- REST handlers ---------------------------------------------------------------

// endpointJSON converts registry metadata for the caller.
func (s *Server) endpointJSON(userID string, ep connect.Endpoint) PlayerEndpoint {
	out := PlayerEndpoint{
		Id:            ep.ID,
		Kind:          ep.Kind,
		Name:          ep.Name,
		Online:        ep.Online,
		Shared:        ep.Shared,
		Mine:          ep.OwnerUserID == userID,
		VolumeControl: ep.VolumeControl,
		RateControl:   ep.RateControl,
	}
	if id := s.connect.ActiveSessionID(userID, ep.ID); id != "" {
		out.ActiveSessionId = &id
	}
	return out
}

// sessionJSON converts a session snapshot for the caller. REST always
// carries entries.
func sessionJSON(userID string, snap connect.Session) PlaybackSession {
	out := PlaybackSession{
		Id:           snap.ID,
		EndpointId:   snap.EndpointID,
		Mine:         snap.OwnerUserID == userID,
		Authority:    snap.Authority,
		Playing:      snap.Playing,
		Index:        snap.Index,
		PositionMs:   snap.PositionMS,
		PositionAt:   snap.PositionAt,
		Rate:         snap.Rate,
		QueueVersion: snap.QueueVersion,
		UpdatedAt:    snap.UpdatedAt,
	}
	if snap.EndpointName != "" {
		out.EndpointName = &snap.EndpointName
	}
	if !out.Mine && snap.OwnerName != "" {
		out.OwnerName = &snap.OwnerName
	}
	if snap.Volume != nil {
		out.Volume = snap.Volume
	}
	if snap.Repeat != "" {
		out.Repeat = &snap.Repeat
	}
	if snap.Shuffle {
		v := true
		out.Shuffle = &v
	}
	entries := queueEntriesJSON(snap.Entries)
	out.Entries = &entries
	return out
}

func queueEntriesJSON(in []connect.QueueEntry) []PlaybackSessionEntry {
	out := make([]PlaybackSessionEntry, 0, len(in))
	for _, e := range in {
		entry := PlaybackSessionEntry{Pid: e.PID, Title: e.Title}
		if e.Artist != "" {
			a := e.Artist
			entry.Artist = &a
		}
		if e.DurationMS > 0 {
			d := e.DurationMS
			entry.DurationMs = &d
		}
		out = append(out, entry)
	}
	return out
}

// endedSessionJSON converts one history row. Nothing here is a live
// value: no `mine` (the list is the caller's own by construction), no
// `playing`, no queue version.
func endedSessionJSON(e connect.EndedSession) PlaybackSessionHistoryEntry {
	out := PlaybackSessionHistoryEntry{
		Id:         e.ID,
		EndpointId: e.EndpointID,
		Authority:  e.Authority,
		Index:      e.Index,
		PositionMs: e.PositionMS,
		PositionAt: e.PositionAt,
		Rate:       e.Rate,
		Entries:    queueEntriesJSON(e.Entries),
	}
	if e.EndpointName != "" {
		out.EndpointName = &e.EndpointName
	}
	if e.Repeat != "" {
		out.Repeat = &e.Repeat
	}
	if e.Shuffle {
		v := true
		out.Shuffle = &v
	}
	return out
}

// connectHTTP maps connect errors onto typed responses; the bool is
// false for errors the caller should surface as 500. It answers the
// whole Error rather than its parts so a refusal's params ride out
// with it instead of needing a return value of their own.
func connectHTTP(err error) (status int, body Error, ok bool) {
	var inv connect.InvalidError
	switch {
	case errors.Is(err, connect.ErrNotFound):
		return http.StatusNotFound, errObj("not-found", "no such endpoint or session is visible to you"), true
	case errors.Is(err, connect.ErrEndpointOffline):
		return http.StatusConflict, errObj("endpoint-offline", err.Error()), true
	case errors.Is(err, connect.ErrEndpointBusy):
		// The server's to say, not an endpoint's, and so not routed
		// through the refusal whitelist: the device answered a question
		// about what it was doing and this is that answer.
		return http.StatusConflict, errObj("endpoint-busy", err.Error()), true
	case errors.Is(err, connect.ErrForbidden):
		return http.StatusForbidden, errObj("forbidden", err.Error()), true
	case errors.Is(err, connect.ErrTimeout):
		// `timeout`, not `endpoint-offline`: the endpoint is connected
		// and silent, and telling a controller to refresh the endpoint
		// list would send it looking for a departure that did not
		// happen. The socket has always said `timeout` here.
		return http.StatusConflict, errObj("timeout", "the endpoint did not answer in time"), true
	case errors.As(err, &inv):
		status, code := refusalStatus(inv.Code)
		body := errObj(code, inv.Msg)
		// Only where the code survived the whitelist: params keys are
		// documented per code, so a set minted for a rejected one would
		// arrive describing the `invalid-request` it degraded to, and
		// the whitelist is what it would be walking around.
		if len(inv.Params) > 0 && code == inv.Code {
			body.Params = &inv.Params
		}
		return status, body, true
	}
	if service.KindOf(err) == service.KindNotFound {
		return http.StatusNotFound, errObj("not-found", err.Error()), true
	}
	if service.KindOf(err) == service.KindConflict {
		return http.StatusConflict, errObj("conflict", err.Error()), true
	}
	return 0, Error{}, false
}

func (s *Server) ListPlayerEndpoints(ctx context.Context, _ ListPlayerEndpointsRequestObject) (ListPlayerEndpointsResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return ListPlayerEndpoints200JSONResponse{Endpoints: []PlayerEndpoint{}}, nil
	}
	eps := s.connect.Endpoints(p.User.ID)
	out := make([]PlayerEndpoint, 0, len(eps))
	for _, ep := range eps {
		out = append(out, s.endpointJSON(p.User.ID, ep))
	}
	return ListPlayerEndpoints200JSONResponse{Endpoints: out}, nil
}

func (s *Server) ListPlaybackSessions(ctx context.Context, _ ListPlaybackSessionsRequestObject) (ListPlaybackSessionsResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return ListPlaybackSessions200JSONResponse{Sessions: []PlaybackSession{}}, nil
	}
	snaps := s.connect.Sessions(p.User.ID)
	out := make([]PlaybackSession, 0, len(snaps))
	for _, snap := range snaps {
		out = append(out, sessionJSON(p.User.ID, snap))
	}
	return ListPlaybackSessions200JSONResponse{Sessions: out}, nil
}

func (s *Server) ListPlaybackSessionHistory(ctx context.Context, _ ListPlaybackSessionHistoryRequestObject) (ListPlaybackSessionHistoryResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return ListPlaybackSessionHistory200JSONResponse{Sessions: []PlaybackSessionHistoryEntry{}}, nil
	}
	ended, err := s.connect.SessionHistory(ctx, p.User.ID)
	if err != nil {
		return nil, err
	}
	out := make([]PlaybackSessionHistoryEntry, 0, len(ended))
	for _, e := range ended {
		out = append(out, endedSessionJSON(e))
	}
	return ListPlaybackSessionHistory200JSONResponse{Sessions: out}, nil
}

func (s *Server) CreatePlaybackSession(ctx context.Context, req CreatePlaybackSessionRequestObject) (CreatePlaybackSessionResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return nil, errors.New("connect is not wired")
	}
	body := req.Body
	create := connect.SessionRequest{
		EndpointID: body.EndpointId,
		PIDs:       body.ItemPids,
		Play:       true,
	}
	if body.Index != nil {
		create.Index = *body.Index
	}
	if body.PositionMs != nil {
		create.PositionMS = *body.PositionMs
	}
	if body.Play != nil {
		create.Play = *body.Play
	}
	create.Rate = body.Rate
	if body.Repeat != nil {
		create.Repeat = *body.Repeat
	}
	if body.Shuffle != nil {
		create.Shuffle = *body.Shuffle
	}
	if body.HandoffFrom != nil {
		create.HandoffFrom = *body.HandoffFrom
	}
	snap, err := s.connect.CreateSession(ctx, p.User.ID, p.User.Username, create)
	if err != nil {
		if status, body, ok := connectHTTP(err); ok {
			switch status {
			case http.StatusNotFound:
				return CreatePlaybackSession404JSONResponse{NotFoundJSONResponse(body)}, nil
			case http.StatusConflict:
				return CreatePlaybackSession409JSONResponse{PlaybackConflictJSONResponse(body)}, nil
			case http.StatusBadRequest:
				return CreatePlaybackSession400JSONResponse{InvalidRequestJSONResponse(body)}, nil
			case http.StatusForbidden:
				return CreatePlaybackSession403JSONResponse{ForbiddenJSONResponse(body)}, nil
			case http.StatusNotImplemented:
				return CreatePlaybackSession501JSONResponse{FeatureUnavailableJSONResponse(body)}, nil
			}
		}
		return nil, err
	}
	return CreatePlaybackSession201JSONResponse(sessionJSON(p.User.ID, snap)), nil
}

func (s *Server) GetPlaybackSession(ctx context.Context, req GetPlaybackSessionRequestObject) (GetPlaybackSessionResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return GetPlaybackSession404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such session"))}, nil
	}
	snap, err := s.connect.Session(p.User.ID, req.SessionId)
	if err != nil {
		return GetPlaybackSession404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such session is visible to you"))}, nil
	}
	return GetPlaybackSession200JSONResponse(sessionJSON(p.User.ID, snap)), nil
}

func (s *Server) DeletePlaybackSession(ctx context.Context, req DeletePlaybackSessionRequestObject) (DeletePlaybackSessionResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return DeletePlaybackSession404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such session"))}, nil
	}
	if err := s.connect.End(ctx, p.User.ID, req.SessionId); err != nil {
		return DeletePlaybackSession404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such session is visible to you"))}, nil
	}
	return DeletePlaybackSession204Response{}, nil
}

func (s *Server) TransferPlaybackSession(ctx context.Context, req TransferPlaybackSessionRequestObject) (TransferPlaybackSessionResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return TransferPlaybackSession404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such session"))}, nil
	}
	snap, err := s.connect.Transfer(ctx, p.User.ID, req.SessionId, req.Body.EndpointId)
	if err != nil {
		if status, body, ok := connectHTTP(err); ok {
			switch status {
			case http.StatusNotFound:
				return TransferPlaybackSession404JSONResponse{NotFoundJSONResponse(body)}, nil
			case http.StatusConflict:
				return TransferPlaybackSession409JSONResponse{PlaybackConflictJSONResponse(body)}, nil
			case http.StatusBadRequest:
				return TransferPlaybackSession400JSONResponse{InvalidRequestJSONResponse(body)}, nil
			case http.StatusForbidden:
				// A 403, not a 404 wearing a `forbidden` code: both
				// refusals here are about the target endpoint, and the
				// session the caller named is one they can see and
				// drive.
				return TransferPlaybackSession403JSONResponse{ForbiddenJSONResponse(body)}, nil
			case http.StatusNotImplemented:
				return TransferPlaybackSession501JSONResponse{FeatureUnavailableJSONResponse(body)}, nil
			}
		}
		return nil, err
	}
	return TransferPlaybackSession200JSONResponse(sessionJSON(p.User.ID, snap)), nil
}

func (s *Server) CreateQueueTimeline(ctx context.Context, req CreateQueueTimelineRequestObject) (CreateQueueTimelineResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.bridge == nil || !s.bridge.TimelinesSupported() {
		return CreateQueueTimeline501JSONResponse{FeatureUnavailableJSONResponse(errObj("feature-unavailable", "queue timelines need the streaming engine"))}, nil
	}
	body := req.Body
	crossfade := 0.0
	if body.CrossfadeSeconds != nil {
		crossfade = *body.CrossfadeSeconds
	}
	if crossfade < 0 || crossfade > 12 {
		return CreateQueueTimeline400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "crossfadeSeconds must be between 0 and 12"))}, nil
	}
	// The crossfade is the request's, since a caller minting its own
	// timeline is deciding this queue's presentation. Leveling is not on
	// the request at all: it says whether this listener wants a level
	// playing field, which is a fact about them and not about a queue.
	var formats []string
	if body.Formats != nil {
		formats = make([]string, 0, len(*body.Formats))
		for _, f := range *body.Formats {
			if !f.Valid() {
				return CreateQueueTimeline400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown timeline format "+string(f)))}, nil
			}
			formats = append(formats, string(f))
		}
	}
	opts := flow.TimelineOptions{
		CrossfadeSeconds: crossfade,
		ReplayGain:       s.svc.PrefsForUser(ctx, p.User.ID).ReplayGain,
		Formats:          formats,
	}
	members := make([]flow.TimelineMember, 0, len(body.ItemPids))
	for _, pid := range body.ItemPids {
		if err := s.svc.VisibleItem(ctx, uc, pid); err != nil {
			return CreateQueueTimeline404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+pid))}, nil
		}
		src, err := s.svc.StreamSource(ctx, pid, "")
		if err != nil {
			return CreateQueueTimeline409JSONResponse{ConflictJSONResponse(errObj("conflict", "this item cannot join a timeline: "+pid))}, nil
		}
		if src.Virtual && !s.bridge.TimelineMemberWindowsSupported() {
			return CreateQueueTimeline409JSONResponse{ConflictJSONResponse(errObj("conflict", "virtual tracks cannot join a timeline: "+pid))}, nil
		}
		if opts.ReplayGain {
			s.svc.FillLoudness(ctx, &src)
		}
		members = append(members, flow.TimelineMember{PID: pid, Src: src})
	}
	res, err := s.bridge.TimelineFor(ctx, p.User.ID, members, opts)
	if err != nil {
		if errors.Is(err, flow.ErrTranscodeLimited) {
			return CreateQueueTimeline429JSONResponse{TranscodeLimitedJSONResponse(errObj("transcode-limited",
				"the server's transcode session limit is reached; retry when a session ends"))}, nil
		}
		msg := err.Error()
		if strings.Contains(msg, "crossfade") {
			return CreateQueueTimeline400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", msg))}, nil
		}
		// The engine would not render this queue. Every member was
		// visible and resolvable, so this is not an internal fault: it
		// is the same "these items cannot join a timeline" the checks
		// above answer, discovered by the renderer rather than by us,
		// and a caller's move is the same either way - play per item.
		if errors.Is(err, flow.ErrTimelineUnrenderable) {
			return CreateQueueTimeline409JSONResponse{ConflictJSONResponse(errObj("conflict", msg))}, nil
		}
		// Everything else is the server being broken - the sidecar down,
		// a signature that would not sign - and belongs in the error
		// rate rather than in a refusal. Returned rather than worded,
		// because the wording would carry an internal host, port or
		// library path back to whoever asked.
		return nil, err
	}
	if res.JobPID != "" {
		state := "running"
		return CreateQueueTimeline202JSONResponse(Job{Pid: res.JobPID, Kind: "timeline", State: state}), nil
	}
	out := CreateQueueTimeline201JSONResponse{
		Url:          res.URL,
		MimeType:     res.MimeType,
		DurationMs:   res.DurationMS,
		ExpiresAt:    res.ExpiresAt,
		EnvelopeRate: res.EnvelopeRate,
	}
	if res.PID != "" {
		pid := res.PID
		out.Pid = &pid
	}
	if res.Format != "" {
		format := res.Format
		out.Format = &format
	}
	if res.CrossfadeSeconds > 0 {
		cf := res.CrossfadeSeconds
		out.CrossfadeSeconds = &cf
	}
	for _, b := range res.Boundaries {
		out.Boundaries = append(out.Boundaries, TimelineBoundary{
			Pid:             b.PID,
			OffsetSamples:   b.OffsetSamples,
			DurationSamples: b.DurationSamples,
		})
	}
	return out, nil
}

// ReleaseQueueTimeline hands a listener's transcode slot back the
// moment they stop, rather than the minute later the idle sweep would.
// A server with no engine has nothing to release, which is the same
// answer an id it never minted gets.
func (s *Server) ReleaseQueueTimeline(ctx context.Context, req ReleaseQueueTimelineRequestObject) (ReleaseQueueTimelineResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	id := strings.TrimPrefix(req.Pid, "tl-")
	if s.bridge == nil || !s.bridge.ReleaseTimeline(p.User.ID, id) {
		return ReleaseQueueTimeline404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no live timeline with pid "+req.Pid))}, nil
	}
	return ReleaseQueueTimeline204Response{}, nil
}

func (s *Server) GetCastPreflight(ctx context.Context, _ GetCastPreflightRequestObject) (GetCastPreflightResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	var bases []string
	if s.bases.Public != "" {
		bases = append(bases, s.bases.Public)
	}
	if s.bases.LAN != "" && s.bases.LAN != s.bases.Public {
		bases = append(bases, s.bases.LAN)
	}
	return GetCastPreflight200JSONResponse{Bases: s.reachability(ctx, bases)}, nil
}

// baseSource says where a candidate advertise base came from, in the
// vocabulary the preflight schema documents.
func (s *Server) baseSource(base string) string {
	switch base {
	case s.bases.Public:
		return "configured"
	case s.bases.LAN:
		return "detected"
	case s.bases.Loopback:
		return "loopback"
	}
	return "unknown"
}

// reachability builds one server-side verdict per base: whether this
// server can fetch itself through the address, plus the plain-language
// caveats a device would run into.
//
// The fetches are independent and each waits up to its timeout, so
// they run concurrently: two dead bases cost one timeout rather than
// two stacked.
func (s *Server) reachability(ctx context.Context, bases []string) []CastPreflightBase {
	out := make([]CastPreflightBase, len(bases))
	client := &http.Client{Timeout: 3 * time.Second}
	done := make(chan struct{}, len(bases))
	for i, base := range bases {
		// The bool matters: a cancelled context makes GoOnce refuse to
		// spawn, and a worker that never runs never signals - so
		// ignoring it is a handler that waits forever on a request
		// nobody is listening to any more.
		if !s.group.GoOnce(ctx, "cast-preflight-probe", func(context.Context) error {
			defer func() { done <- struct{}{} }()
			entry := CastPreflightBase{Base: base, Source: s.baseSource(base), Notes: []string{}}
			resp, err := client.Get(strings.TrimRight(base, "/") + "/api/v1/health")
			if err != nil {
				entry.Reachable = false
				entry.Notes = append(entry.Notes, "the server could not reach itself through this address: "+err.Error())
			} else {
				resp.Body.Close()
				entry.Reachable = resp.StatusCode == http.StatusOK
				if !entry.Reachable {
					entry.Notes = append(entry.Notes, fmt.Sprintf("this address answered status %d instead of the health check", resp.StatusCode))
				}
			}
			if u, err := url.Parse(base); err == nil {
				if u.Scheme == "https" {
					entry.Notes = append(entry.Notes, "cast devices require a publicly trusted certificate for HTTPS addresses; private or self-signed authorities fail silently")
				} else {
					entry.Notes = append(entry.Notes, "plain HTTP needs no TLS setup; the default cast receiver plays it out of the box")
				}
				host := u.Hostname()
				if host != "" && net.ParseIP(host) == nil && u.Scheme != "https" {
					entry.Notes = append(entry.Notes, "the device must resolve this name itself; many cast devices ignore LAN DNS, so an IP address is more reliable")
				}
			}
			out[i] = entry
			return nil
		}) {
			out[i] = CastPreflightBase{
				Base:      base,
				Source:    s.baseSource(base),
				Reachable: false,
				Notes:     []string{"the check was cancelled before this address was tried"},
			}
			done <- struct{}{}
		}
	}
	for range bases {
		<-done
	}
	return out
}

// probeTokenTTL covers a whole probe run - every base, each with its
// own wait - and the slack a device takes to actually fetch.
const probeTokenTTL = 5 * time.Minute

// probeMimeFor picks how to describe the probe to the endpoint about
// to fetch it.
//
// Renderers refuse a resource whose type is absent from the sink they
// advertised, and they disagree about how to spell wav, so a renderer
// that named one of its spellings is handed that one - the same
// courtesy the stream resolver pays a declared format. A renderer that
// declared nothing, or nothing wav-shaped, gets the plain type: it may
// still take it, and where it does not the fault it answers with says
// so in the verdict.
func probeMimeFor(target connect.EndpointTarget) string {
	for _, f := range target.Formats {
		switch strings.ToLower(strings.TrimSpace(f)) {
		case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave":
			return f
		}
	}
	return "audio/wav"
}

// ProbeCastEndpoint is the device half of the connection check: the
// device fetches a second of silence through each advertise base and
// says what happened, which is the failure mode a server checking
// itself is blind to.
func (s *Server) ProbeCastEndpoint(ctx context.Context, req ProbeCastEndpointRequestObject) (ProbeCastEndpointResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return ProbeCastEndpoint404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such endpoint or session is visible to you"))}, nil
	}
	if s.media == nil {
		return nil, errors.New("media tokens are not configured on this server")
	}
	// One token for the whole run: it names the probe rather than any
	// item, so it opens nothing in the library whichever base the
	// device fetches it from. Each address gets its own marker on the
	// URL, so a request arriving back here says which one the device
	// could reach.
	token, _ := s.media.MintFor(p.User.ID, probePID, probeTokenTTL)
	s.probes.begin(token)
	defer s.probes.end(token)
	markers := map[string]string{}
	media := connect.ProbeMedia{
		Item: func(target connect.EndpointTarget, base string) connect.MediaItem {
			marker := strconv.Itoa(len(markers))
			markers[base] = marker
			return connect.MediaItem{
				PID:        probePID,
				URL:        base + mediaProbeURL(token, marker),
				MimeType:   probeMimeFor(target),
				Title:      "WaxDeck connection check",
				DurationMS: probeSeconds * 1000,
			}
		},
		Fetched: func(base string) bool { return s.probes.fetched(token, markers[base]) },
	}
	res, err := s.connect.Probe(ctx, p.User.ID, req.EndpointId, media)
	if err != nil {
		if status, body, ok := connectHTTP(err); ok {
			switch status {
			case http.StatusNotFound:
				return ProbeCastEndpoint404JSONResponse{NotFoundJSONResponse(body)}, nil
			case http.StatusForbidden:
				return ProbeCastEndpoint403JSONResponse{ForbiddenJSONResponse(body)}, nil
			case http.StatusConflict:
				return ProbeCastEndpoint409JSONResponse{PlaybackConflictJSONResponse(body)}, nil
			}
		}
		return nil, err
	}
	// The bases the device was actually tried against, in that order,
	// each carrying the server-side row beside the device's verdict:
	// one row saying both halves is what makes an answer readable.
	bases := make([]string, len(res.Bases))
	for i, v := range res.Bases {
		bases[i] = v.Base
	}
	out := ProbeCastEndpoint200JSONResponse{
		EndpointId: res.EndpointID,
		Name:       res.Name,
		Kind:       res.Kind,
		Bases:      s.reachability(ctx, bases),
	}
	for i, v := range res.Bases {
		verdict := CastDeviceVerdict{Verdict: v.Verdict, LatencyMs: v.LatencyMS}
		if v.Detail != "" {
			verdict.Detail = &v.Detail
		}
		out.Bases[i].Device = &verdict
	}
	return out, nil
}
