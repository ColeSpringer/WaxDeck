package api

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
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

// StreamItems builds absolute media URLs for a device endpoint.
// Renderers get the mp3 floor, the jukebox gets wav, cast devices get
// the derived shape. Multi-part books and, without the engine, span
// tracks are refused: partial support that loses positions is worse
// than a clear error.
func (r *ConnectResolver) StreamItems(ctx context.Context, userID string, entries []connect.QueueEntry, kind, base string, ttl time.Duration) ([]connect.MediaItem, error) {
	uc, err := r.Svc.UserCtxByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	force := ""
	switch kind {
	case connect.KindDLNA:
		force = "mp3"
	case connect.KindJukebox:
		force = "wav"
	}
	out := make([]connect.MediaItem, 0, len(entries))
	for _, e := range entries {
		part, err := r.Svc.ResolvePlayPart(ctx, uc, e.PID, 0)
		if err != nil {
			return nil, err
		}
		if part.MultiPart {
			return nil, connect.InvalidError{Msg: "multi-part audiobooks cannot play on this endpoint yet: " + e.PID}
		}
		// No ArtURL yet: the art endpoint authenticates by session,
		// which a cast device cannot present. A tokenized art URL is
		// recorded as deferred work.
		item := connect.MediaItem{
			PID:        e.PID,
			Title:      e.Title,
			Artist:     e.Artist,
			DurationMS: e.DurationMS,
		}
		if r.Bridge != nil {
			// The stored voice boost setting routes here exactly as it
			// does at play-info: a device endpoint has no local DSP, so
			// the engine applies it server side when the user asked.
			info, err := r.Bridge.PlayInfoFor(ctx, userID, e.PID, flow.PlayOptions{
				TTL:         ttl,
				ForceFormat: force,
				VoiceBoost:  r.Svc.EffectiveVoiceBoost(ctx, uc, e.PID),
			})
			if err != nil {
				return nil, err
			}
			item.URL = base + info.URL
			item.MimeType = info.MimeType
		} else {
			res, err := r.Svc.DirectPlayInfo(ctx, uc, e.PID, "")
			if err != nil {
				return nil, err
			}
			if res.HasSpan {
				return nil, connect.InvalidError{Msg: "this track is a window into a larger file and needs the streaming engine to cast: " + e.PID}
			}
			token, _ := r.Media.MintFor(userID, e.PID, ttl)
			item.URL = base + "/media/download?pid=" + url.QueryEscape(e.PID) +
				"&mt=" + url.QueryEscape(token) + "&id=" + url.QueryEscape(res.File.ETag)
			item.MimeType = res.File.MimeType
		}
		out = append(out, item)
	}
	return out, nil
}

// Timeline renders the queue as one gapless HLS stream when the engine
// supports timelines and every entry is a whole file. A nil result
// means "use StreamItems".
func (r *ConnectResolver) Timeline(ctx context.Context, userID string, entries []connect.QueueEntry, crossfade float64, base string) (*connect.TimelineMedia, error) {
	if r.Bridge == nil || !r.Bridge.TimelinesSupported() {
		return nil, nil
	}
	members := make([]flow.TimelineMember, 0, len(entries))
	for _, e := range entries {
		src, err := r.Svc.StreamSource(ctx, e.PID, "")
		if err != nil || src.Virtual {
			return nil, nil
		}
		members = append(members, flow.TimelineMember{PID: e.PID, Src: src})
	}
	res, err := r.Bridge.TimelineFor(ctx, userID, members, crossfade)
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
	entries := make([]PlaybackSessionEntry, 0, len(snap.Entries))
	for _, e := range snap.Entries {
		entry := PlaybackSessionEntry{Pid: e.PID, Title: e.Title}
		if e.Artist != "" {
			a := e.Artist
			entry.Artist = &a
		}
		if e.DurationMS > 0 {
			d := e.DurationMS
			entry.DurationMs = &d
		}
		entries = append(entries, entry)
	}
	out.Entries = &entries
	return out
}

// connectError maps connect errors onto typed responses; the bool is
// false for errors the caller should surface as 500.
func connectHTTP(err error) (status int, code, msg string, ok bool) {
	var inv connect.InvalidError
	switch {
	case errors.Is(err, connect.ErrNotFound):
		return http.StatusNotFound, "not-found", "no such endpoint or session is visible to you", true
	case errors.Is(err, connect.ErrEndpointOffline):
		return http.StatusConflict, "endpoint-offline", err.Error(), true
	case errors.Is(err, connect.ErrForbidden):
		return http.StatusForbidden, "forbidden", err.Error(), true
	case errors.Is(err, connect.ErrTimeout):
		return http.StatusConflict, "endpoint-offline", "the endpoint did not answer in time", true
	case errors.As(err, &inv):
		return http.StatusBadRequest, "invalid-request", inv.Msg, true
	}
	if service.KindOf(err) == service.KindNotFound {
		return http.StatusNotFound, "not-found", err.Error(), true
	}
	if service.KindOf(err) == service.KindConflict {
		return http.StatusConflict, "conflict", err.Error(), true
	}
	return 0, "", "", false
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

func (s *Server) CreatePlaybackSession(ctx context.Context, req CreatePlaybackSessionRequestObject) (CreatePlaybackSessionResponseObject, error) {
	_, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.connect == nil {
		return nil, errors.New("connect is not wired")
	}
	body := req.Body
	index := 0
	if body.Index != nil {
		index = *body.Index
	}
	var positionMS int64
	if body.PositionMs != nil {
		positionMS = *body.PositionMs
	}
	play := true
	if body.Play != nil {
		play = *body.Play
	}
	snap, err := s.connect.CreateSession(ctx, p.User.ID, p.User.Username, body.EndpointId, body.ItemPids, index, positionMS, play)
	if err != nil {
		if status, code, msg, ok := connectHTTP(err); ok {
			switch status {
			case http.StatusNotFound:
				return CreatePlaybackSession404JSONResponse{NotFoundJSONResponse(errObj(code, msg))}, nil
			case http.StatusConflict:
				return CreatePlaybackSession409JSONResponse{EndpointOfflineJSONResponse(errObj(code, msg))}, nil
			case http.StatusBadRequest:
				return CreatePlaybackSession400JSONResponse{InvalidRequestJSONResponse(errObj(code, msg))}, nil
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
		if status, code, msg, ok := connectHTTP(err); ok {
			switch status {
			case http.StatusNotFound:
				return TransferPlaybackSession404JSONResponse{NotFoundJSONResponse(errObj(code, msg))}, nil
			case http.StatusConflict:
				return TransferPlaybackSession409JSONResponse{EndpointOfflineJSONResponse(errObj(code, msg))}, nil
			case http.StatusBadRequest:
				return TransferPlaybackSession400JSONResponse{InvalidRequestJSONResponse(errObj(code, msg))}, nil
			case http.StatusForbidden:
				return TransferPlaybackSession404JSONResponse{NotFoundJSONResponse(errObj(code, msg))}, nil
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
	members := make([]flow.TimelineMember, 0, len(body.ItemPids))
	for _, pid := range body.ItemPids {
		if err := s.svc.VisibleItem(ctx, uc, pid); err != nil {
			return CreateQueueTimeline404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+pid))}, nil
		}
		src, err := s.svc.StreamSource(ctx, pid, "")
		if err != nil {
			return CreateQueueTimeline409JSONResponse{ConflictJSONResponse(errObj("conflict", "this item cannot join a timeline: "+pid))}, nil
		}
		if src.Virtual {
			return CreateQueueTimeline409JSONResponse{ConflictJSONResponse(errObj("conflict", "virtual tracks cannot join a timeline: "+pid))}, nil
		}
		members = append(members, flow.TimelineMember{PID: pid, Src: src})
	}
	res, err := s.bridge.TimelineFor(ctx, p.User.ID, members, crossfade)
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "crossfade") {
			return CreateQueueTimeline400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", msg))}, nil
		}
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

func (s *Server) GetCastPreflight(ctx context.Context, _ GetCastPreflightRequestObject) (GetCastPreflightResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	type candidate struct {
		base   string
		source string
	}
	var candidates []candidate
	if s.bases.Public != "" {
		candidates = append(candidates, candidate{base: s.bases.Public, source: "configured"})
	}
	if s.bases.LAN != "" && s.bases.LAN != s.bases.Public {
		candidates = append(candidates, candidate{base: s.bases.LAN, source: "detected"})
	}
	// The probes are independent and each waits up to its timeout;
	// they run concurrently so two dead bases cost one timeout, not
	// two stacked.
	out := GetCastPreflight200JSONResponse{Bases: make([]CastPreflightBase, len(candidates))}
	client := &http.Client{Timeout: 3 * time.Second}
	done := make(chan struct{}, len(candidates))
	for i, c := range candidates {
		s.group.GoOnce(ctx, "cast-preflight-probe", func(context.Context) error {
			defer func() { done <- struct{}{} }()
			entry := CastPreflightBase{Base: c.base, Source: c.source, Notes: []string{}}
			resp, err := client.Get(strings.TrimRight(c.base, "/") + "/api/v1/health")
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
			if u, err := url.Parse(c.base); err == nil {
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
			out.Bases[i] = entry
			return nil
		})
	}
	for range candidates {
		<-done
	}
	return out, nil
}
