package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/coder/websocket"

	"github.com/colespringer/waxdeck/server/internal/events"
)

// WebSocket event-channel timings. The subscribe deadline bounds a
// connection that upgrades and never speaks; the write deadline bounds
// a peer that stopped reading; pings keep intermediaries from reaping
// idle-but-live sockets.
const (
	wsSubscribeDeadline = 5 * time.Second
	wsWriteDeadline     = 10 * time.Second
	wsPingInterval      = 30 * time.Second
)

// wsSubscribeFrame is the client's one and only frame. Cursors are
// opaque and unused by the transport: their validity is judged by the
// sync endpoints; their presence just prompts an immediate invalidate
// so a returning client pulls once.
type wsSubscribeFrame struct {
	CatalogSince string   `json:"catalogSince"`
	ServerSince  string   `json:"serverSince"`
	Topics       []string `json:"topics"`
}

// ServeWS upgrades the event channel. It runs behind AuthMiddleware
// (mounted on the mux with it), so a principal is always in context;
// the upgrade itself enforces same-origin for browser clients (the
// library's default rejects cross-origin upgrades and allows absent
// Origin headers, which is exactly the contract).
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

		// CloseRead handles control frames and surfaces peer close by
		// canceling the returned context; this connection sends only.
		ctx := c.CloseRead(r.Context())
		pings := time.NewTicker(wsPingInterval)
		defer pings.Stop()
		for {
			select {
			case <-ctx.Done():
				c.Close(websocket.StatusNormalClosure, "")
				return
			case <-pings.C:
				if err := s.wsPing(ctx, c); err != nil {
					return
				}
			case <-conn.Wake():
				for _, f := range conn.TakePending() {
					if err := s.wsWrite(ctx, c, f); err != nil {
						return
					}
				}
			}
		}
	}
}

func (s *Server) wsWrite(ctx context.Context, c *websocket.Conn, f events.Frame) error {
	wctx, cancel := context.WithTimeout(ctx, wsWriteDeadline)
	defer cancel()
	data, err := json.Marshal(f)
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
