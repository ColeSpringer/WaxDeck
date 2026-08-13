package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"
	"unicode/utf8"

	"github.com/coder/websocket"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/events"
)

// WebSocket timings. The subscribe deadline bounds a connection that
// upgrades and never speaks; the write deadline bounds a peer that
// stopped reading; pings keep intermediaries from reaping
// idle-but-live sockets. The outbound queue bounds a slow reader:
// invalidations cannot overflow (three flags), and command-bus frames
// are best-effort or answer-or-close, so a full queue means the
// connection is dead anyway.
const (
	wsSubscribeDeadline = 5 * time.Second
	wsWriteDeadline     = 10 * time.Second
	wsPingInterval      = 30 * time.Second
	wsOutboundQueue     = 64
	wsMaxFrameBytes     = 64 * 1024
)

// wsSubscribeFrame is the client's first frame. Cursors are opaque and
// unused by the transport: their validity is judged by the sync
// endpoints; their presence just prompts an immediate invalidate so a
// returning client pulls once.
type wsSubscribeFrame struct {
	CatalogSince string   `json:"catalogSince"`
	ServerSince  string   `json:"serverSince"`
	Topics       []string `json:"topics"`
}

// wsClientFrame is the union of every client-to-server frame after
// subscribe; Type discriminates. Shapes mirror the spec components.
type wsClientFrame struct {
	Type string `json:"type"`
	ID   string `json:"id"`

	// cmd
	SessionID  string   `json:"sessionId"`
	Verb       string   `json:"verb"`
	PositionMS *int64   `json:"positionMs"`
	Volume     *float64 `json:"volume"`
	Rate       *float64 `json:"rate"`
	ItemPids   []string `json:"itemPids"`
	Index      *int     `json:"index"`
	Repeat     string   `json:"repeat"`
	Shuffle    *bool    `json:"shuffle"`

	// register-endpoint
	Name          string `json:"name"`
	VolumeControl bool   `json:"volumeControl"`
	RateControl   bool   `json:"rateControl"`

	// cmd-result
	OK      *bool  `json:"ok"`
	Code    string `json:"code"`
	Message string `json:"message"`

	// session-report
	Playing bool `json:"playing"`

	// ping
	T *int64 `json:"t"`
}

type wsAckFrame struct {
	Type       string `json:"type"`
	ID         string `json:"id"`
	EndpointID string `json:"endpointId,omitempty"`
	Session    any    `json:"session,omitempty"`
}

type wsErrorFrame struct {
	Type    string            `json:"type"`
	ID      string            `json:"id,omitempty"`
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Params  map[string]string `json:"params,omitempty"`
}

type wsPongFrame struct {
	Type string `json:"type"`
	T    int64  `json:"t"`
	At   int64  `json:"at"`
}

// ServeWS upgrades the event channel and command bus. It runs behind
// AuthMiddleware (mounted on the mux with it), so a principal is
// always in context; the upgrade itself enforces same-origin for
// browser clients (the library's default rejects cross-origin upgrades
// and allows absent Origin headers, which is exactly the contract).
func (s *Server) ServeWS(hub *events.Hub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		p, ok := principalFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthenticated", "no valid session or token was presented")
			return
		}
		c, err := websocket.Accept(w, r, nil)
		if err != nil {
			// Accept already answered the request (bad handshake or
			// forbidden origin).
			return
		}
		defer c.Close(websocket.StatusInternalError, "closed")
		c.SetReadLimit(wsMaxFrameBytes)

		subCtx, cancel := context.WithTimeout(r.Context(), wsSubscribeDeadline)
		_, data, err := c.Read(subCtx)
		cancel()
		if err != nil {
			c.Close(websocket.StatusPolicyViolation, "no subscribe frame")
			return
		}
		var sub wsSubscribeFrame
		if err := json.Unmarshal(data, &sub); err != nil {
			c.Close(websocket.StatusPolicyViolation, "malformed subscribe frame")
			return
		}

		conn := hub.Register(p.User.ID, sub.Topics)
		defer hub.Unregister(conn)

		// A returning client (any cursor presented) gets one immediate
		// invalidate per subscribed topic: pulling is cheap and a no-op
		// when current, and it closes the offline gap without the
		// transport judging cursor validity.
		if sub.CatalogSince != "" {
			conn.Mark(events.TypeInvalidate, events.TopicCatalog)
		}
		if sub.ServerSince != "" {
			conn.Mark(events.TypeInvalidate, events.TopicUser)
		}

		// The writer goroutine owns every socket write; the read loop
		// (this goroutine) dispatches frames to the connect service.
		// The out queue drops best-effort frames when full and closes
		// the connection for must-deliver ones, which the enqueue
		// distinguishes by frame kind upstream.
		ctx, cancelAll := context.WithCancel(r.Context())
		defer cancelAll()
		// The read loop (this goroutine) is the connection's only
		// closer; the writer just stops on cancellation. Concurrent
		// Close would be safe (the library CAS-guards it), but a single
		// owner keeps the close status deterministic.
		out := make(chan any, wsOutboundQueue)
		s.group.GoOnce(ctx, "ws-writer", func(wctx context.Context) error {
			pings := time.NewTicker(wsPingInterval)
			defer pings.Stop()
			for {
				select {
				case <-wctx.Done():
					return nil
				case <-pings.C:
					if err := s.wsPing(wctx, c); err != nil {
						cancelAll()
						return nil
					}
				case <-conn.Wake():
					for _, f := range conn.TakePending() {
						if err := s.wsWrite(wctx, c, f); err != nil {
							cancelAll()
							return nil
						}
					}
				case v := <-out:
					if err := s.wsWrite(wctx, c, v); err != nil {
						cancelAll()
						return nil
					}
				}
			}
		})

		var link *connect.ClientLink
		if s.connect != nil {
			send := func(v any) bool {
				select {
				case out <- v:
					return true
				default:
					return false
				}
			}
			sessionID := ""
			if p.Session != nil {
				sessionID = p.Session.ID
			}
			deviceName := ""
			if p.Session != nil && p.Session.DeviceName != "" {
				deviceName = p.Session.DeviceName
			}
			link = connect.NewClientLink(p.User.ID, p.User.Username, sessionID, deviceName, send)
			defer s.connect.OnDisconnect(context.Background(), link)
		}

		for {
			_, data, err := c.Read(ctx)
			if err != nil {
				if ctx.Err() != nil {
					// A server-side end (shutdown, writer failure) says
					// goodbye properly; the deferred close is the
					// backstop for peer-initiated exits.
					c.Close(websocket.StatusNormalClosure, "")
				}
				return
			}
			s.dispatchWS(ctx, link, out, cancelAll, data)
		}
	}
}

// dispatchWS handles one client frame after subscribe. Answers ride
// the out queue; a full queue on an answer frame closes the connection
// (the contract answers every request exactly once, and a peer that
// cannot absorb 64 pending frames is not reading anyway).
func (s *Server) dispatchWS(ctx context.Context, link *connect.ClientLink, out chan any, cancel func(), data []byte) {
	enqueue := func(v any) {
		select {
		case out <- v:
		default:
			cancel()
		}
	}
	var f wsClientFrame
	if err := json.Unmarshal(data, &f); err != nil {
		enqueue(wsErrorFrame{Type: "error", Code: "invalid-request", Message: "malformed frame"})
		return
	}
	if s.connect == nil || link == nil {
		enqueue(wsErrorFrame{Type: "error", ID: f.ID, Code: "feature-unavailable", Message: "the player command bus is not available"})
		return
	}
	switch f.Type {
	case "ping":
		var t int64
		if f.T != nil {
			t = *f.T
		}
		enqueue(wsPongFrame{Type: "pong", T: t, At: time.Now().UnixMilli()})
	case "register-endpoint":
		if f.ID == "" {
			enqueue(wsErrorFrame{Type: "error", Code: "invalid-request", Message: "register-endpoint needs an id"})
			return
		}
		name := truncateRunesafe(f.Name, 128)
		endpointID := s.connect.HandleRegister(link, name, f.VolumeControl, f.RateControl)
		enqueue(wsAckFrame{Type: "ack", ID: f.ID, EndpointID: endpointID})
	case "cmd":
		if f.ID == "" || f.SessionID == "" || f.Verb == "" {
			enqueue(wsErrorFrame{Type: "error", ID: f.ID, Code: "invalid-request", Message: "cmd needs id, sessionId, and verb"})
			return
		}
		args := connect.CommandArgs{
			PositionMS: f.PositionMS,
			Volume:     f.Volume,
			Rate:       f.Rate,
			ItemPids:   f.ItemPids,
			Index:      f.Index,
			Repeat:     f.Repeat,
			Shuffle:    f.Shuffle,
		}
		snap, err := s.connect.HandleCommand(ctx, link, f.SessionID, f.Verb, args)
		if err != nil {
			enqueue(wsErrorFrame{Type: "error", ID: f.ID, Code: wsErrorCode(err), Message: err.Error(), Params: refusalParams(err)})
			return
		}
		ack := wsAckFrame{Type: "ack", ID: f.ID}
		if snap != nil {
			ack.Session = connect.WireSessionPayload(*snap, link.UserID, true)
		}
		enqueue(ack)
	case "cmd-result":
		// Deliberately no params: a client endpoint's code is
		// whitelisted before it reaches the wire, and an arbitrary map
		// from one would need the same treatment designed for it.
		ok := f.OK != nil && *f.OK
		s.connect.HandleCommandResult(f.ID, ok, f.Code, f.Message)
	case "session-report":
		rep := connect.SessionReport{
			Playing:    f.Playing,
			PositionMS: valueOrZero(f.PositionMS),
			Index:      indexOrZero(f.Index),
			Rate:       f.Rate,
			Volume:     f.Volume,
			ItemPids:   f.ItemPids,
			Repeat:     f.Repeat,
			Shuffle:    f.Shuffle,
		}
		if snap, answer := s.connect.HandleSessionReport(ctx, link, rep); answer && snap != nil {
			enqueue(connect.WireSessionFrame(*snap, link.UserID, true))
		}
	case "watch":
		snap, ok := s.connect.HandleWatch(link, f.SessionID)
		if !ok {
			enqueue(wsErrorFrame{Type: "error", ID: f.ID, Code: "not-found", Message: "no such session is visible to you"})
			return
		}
		if snap != nil {
			enqueue(connect.WireSessionFrame(*snap, link.UserID, true))
		}
	default:
		enqueue(wsErrorFrame{Type: "error", ID: f.ID, Code: "invalid-request", Message: "unknown frame type " + f.Type})
	}
}

// truncateRunesafe bounds a string to maxBytes without splitting a
// rune at the cut (a byte slice through a multibyte character would
// mojibake the display name).
func truncateRunesafe(v string, maxBytes int) string {
	if len(v) <= maxBytes {
		return v
	}
	cut := maxBytes
	for cut > 0 && !utf8.RuneStart(v[cut]) {
		cut--
	}
	return v[:cut]
}

func valueOrZero(v *int64) int64 {
	if v == nil {
		return 0
	}
	return *v
}

func indexOrZero(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}

// wsErrorCode maps connect errors onto the wire vocabulary. This is
// the seam the app's own control verbs come back through, so a
// refusal that arrived carrying a code leaves carrying the same one.
func wsErrorCode(err error) string {
	var inv connect.InvalidError
	switch {
	case errors.Is(err, connect.ErrNotFound):
		return "not-found"
	case errors.Is(err, connect.ErrEndpointOffline):
		return "endpoint-offline"
	case errors.Is(err, connect.ErrForbidden):
		return "forbidden"
	case errors.Is(err, connect.ErrTimeout):
		return "timeout"
	case errors.As(err, &inv):
		_, code := refusalStatus(inv.Code)
		return code
	default:
		return "invalid-request"
	}
}

// refusalParams is the machine detail behind a refusal, for the codes
// that cover more than one cause. Nil for everything else, which the
// frame's omitempty turns into an absent field, and nil for a code the
// whitelist rejected, for the reason connectHTTP withholds it there.
func refusalParams(err error) map[string]string {
	var inv connect.InvalidError
	if !errors.As(err, &inv) || len(inv.Params) == 0 {
		return nil
	}
	if _, code := refusalStatus(inv.Code); code != inv.Code {
		return nil
	}
	return inv.Params
}

func (s *Server) wsWrite(ctx context.Context, c *websocket.Conn, v any) error {
	wctx, cancel := context.WithTimeout(ctx, wsWriteDeadline)
	defer cancel()
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return c.Write(wctx, websocket.MessageText, data)
}

func (s *Server) wsPing(ctx context.Context, c *websocket.Conn) error {
	pctx, cancel := context.WithTimeout(ctx, wsWriteDeadline)
	defer cancel()
	return c.Ping(pctx)
}
