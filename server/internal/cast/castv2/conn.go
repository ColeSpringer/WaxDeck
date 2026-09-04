package castv2

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strconv"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Cast namespaces. Exported because the test receiver speaks them too.
const (
	NamespaceConnection = "urn:x-cast:com.google.cast.tp.connection"
	NamespaceHeartbeat  = "urn:x-cast:com.google.cast.tp.heartbeat"
	NamespaceReceiver   = "urn:x-cast:com.google.cast.receiver"
	NamespaceMedia      = "urn:x-cast:com.google.cast.media"
)

// DefaultMediaReceiverApp is the appId of Google's stock media
// receiver, present on every cast device.
const DefaultMediaReceiverApp = "CC1AD845"

const (
	castPort           = 8009
	senderID           = "sender-0"
	platformID         = "receiver-0"
	heartbeatInterval  = 5 * time.Second
	maxMissedPongs     = 3
	statusPollInterval = 5 * time.Second
	writeTimeout       = 5 * time.Second
)

// Player states and idle reasons the driver reads from MEDIA_STATUS.
const (
	stateIdle      = "IDLE"
	statePlaying   = "PLAYING"
	statePaused    = "PAUSED"
	stateBuffering = "BUFFERING"

	idleFinished  = "FINISHED"
	idleCancelled = "CANCELLED"
	idleError     = "ERROR"
)

// Logger is the two-level logging seam this package needs; slog.Logger
// satisfies it.
type Logger interface {
	Info(msg string, args ...any)
	Warn(msg string, args ...any)
}

type nopLogger struct{}

func (nopLogger) Info(string, ...any) {}
func (nopLogger) Warn(string, ...any) {}

// errConnClosed marks a deliberate teardown, so the event pump can
// tell Close from connection death.
var errConnClosed = errors.New("castv2: connection closed")

// tpPayload covers the connection and heartbeat namespaces, whose
// messages are a bare type.
type tpPayload struct {
	Type string `json:"type"`
}

// getStatusRequest works on both the receiver and media namespaces.
type getStatusRequest struct {
	Type      string `json:"type"`
	RequestID int    `json:"requestId"`
}

type launchRequest struct {
	Type      string `json:"type"`
	RequestID int    `json:"requestId"`
	AppID     string `json:"appId"`
}

type setVolumeRequest struct {
	Type      string      `json:"type"`
	RequestID int         `json:"requestId"`
	Volume    volumeLevel `json:"volume"`
}

type volumeLevel struct {
	Level float64 `json:"level"`
}

// receiverStatus is the status object of a RECEIVER_STATUS message.
type receiverStatus struct {
	Applications []receiverApp  `json:"applications"`
	Volume       receiverVolume `json:"volume"`
}

type receiverApp struct {
	AppID       string `json:"appId"`
	SessionID   string `json:"sessionId"`
	TransportID string `json:"transportId"`
	// DisplayName is the app's own name for itself, which is what a
	// person recognises the thing on their television by. Devices send
	// it; the app id is the fallback when one does not.
	DisplayName string `json:"displayName"`
	// IsIdleScreen marks the ambient app a device runs when nothing is
	// casting - Backdrop on a Chromecast, the photo screensaver on a
	// television. It is an application in the status like any other,
	// and reading it as one is reading an idle device as busy.
	IsIdleScreen bool `json:"isIdleScreen"`
}

type receiverVolume struct {
	Level *float64 `json:"level"`
	Muted *bool    `json:"muted"`
}

type receiverStatusMessage struct {
	Type      string         `json:"type"`
	RequestID int            `json:"requestId"`
	Status    receiverStatus `json:"status"`
}

// mediaInformation is the media object of LOAD and QUEUE_LOAD.
type mediaInformation struct {
	ContentID   string         `json:"contentId"`
	ContentType string         `json:"contentType"`
	StreamType  string         `json:"streamType"`
	Metadata    *mediaMetadata `json:"metadata,omitempty"`
}

// mediaMetadata with MetadataType 3 is MusicTrackMediaMetadata, which
// cast devices render on their own screens.
type mediaMetadata struct {
	MetadataType int          `json:"metadataType"`
	Title        string       `json:"title,omitempty"`
	Artist       string       `json:"artist,omitempty"`
	Images       []mediaImage `json:"images,omitempty"`
}

type mediaImage struct {
	URL string `json:"url"`
}

type loadRequest struct {
	Type        string           `json:"type"`
	RequestID   int              `json:"requestId"`
	Media       mediaInformation `json:"media"`
	CurrentTime float64          `json:"currentTime"`
	Autoplay    bool             `json:"autoplay"`
}

type queueLoadItem struct {
	Media    mediaInformation `json:"media"`
	Autoplay bool             `json:"autoplay"`
}

type queueLoadRequest struct {
	Type        string          `json:"type"`
	RequestID   int             `json:"requestId"`
	Items       []queueLoadItem `json:"items"`
	StartIndex  int             `json:"startIndex"`
	CurrentTime float64         `json:"currentTime"`
	RepeatMode  string          `json:"repeatMode"`
}

// mediaCommandRequest covers PLAY, PAUSE, and STOP.
type mediaCommandRequest struct {
	Type           string `json:"type"`
	RequestID      int    `json:"requestId"`
	MediaSessionID int    `json:"mediaSessionId"`
}

type seekRequest struct {
	Type           string  `json:"type"`
	RequestID      int     `json:"requestId"`
	MediaSessionID int     `json:"mediaSessionId"`
	CurrentTime    float64 `json:"currentTime"`
	ResumeState    string  `json:"resumeState"`
}

type mediaStatusMessage struct {
	Type      string        `json:"type"`
	RequestID int           `json:"requestId"`
	Status    []mediaStatus `json:"status"`
}

type mediaStatus struct {
	MediaSessionID int              `json:"mediaSessionId"`
	PlayerState    string           `json:"playerState"`
	CurrentTime    float64          `json:"currentTime"`
	IdleReason     string           `json:"idleReason"`
	CurrentItemID  int              `json:"currentItemId"`
	Items          []mediaQueueItem `json:"items"`
}

type mediaQueueItem struct {
	ItemID int              `json:"itemId"`
	Media  mediaInformation `json:"media"`
}

// statusUpdate is one parsed status broadcast, solicited or not.
// Exactly one field is set.
type statusUpdate struct {
	receiver *receiverStatus
	media    *mediaStatus
}

// conn is one live TLS channel to a cast device: framing, heartbeats,
// request correlation, and status fan-out. The supervised read loop
// owns the socket's read side; writers serialize on writeMu.
type conn struct {
	host string
	sock *tls.Conn
	log  Logger

	// runCtx outlives the dial context: the connection runs until
	// Close, and cancel stops the workers hanging off it.
	runCtx context.Context
	cancel context.CancelFunc

	writeMu sync.Mutex

	mu      sync.Mutex
	nextID  int
	pending map[int]chan json.RawMessage
	closed  bool
	deadErr error

	dead     chan struct{}
	statuses chan statusUpdate
}

// dialConn opens the TLS channel, sends the platform CONNECT, and
// starts the read loop under group. Cast devices present self-signed
// certificates by design, so verification is skipped: authorization
// comes from LAN possession plus the short-lived media tokens in the
// URLs the device is handed, and certificate trust would add nothing.
func dialConn(ctx context.Context, group *supervise.Group, log Logger, host string, port int) (*conn, error) {
	if log == nil {
		log = nopLogger{}
	}
	if port == 0 {
		port = castPort
	}
	dialer := &tls.Dialer{
		NetDialer: &net.Dialer{Timeout: 10 * time.Second},
		Config:    &tls.Config{InsecureSkipVerify: true},
	}
	addr := net.JoinHostPort(host, strconv.Itoa(port))
	raw, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("castv2: dialing %s: %w", addr, err)
	}
	runCtx, cancel := context.WithCancel(context.Background())
	c := &conn{
		host:     host,
		sock:     raw.(*tls.Conn),
		log:      log,
		runCtx:   runCtx,
		cancel:   cancel,
		pending:  make(map[int]chan json.RawMessage),
		dead:     make(chan struct{}),
		statuses: make(chan statusUpdate, 16),
	}
	if err := c.sendJSON(platformID, NamespaceConnection, tpPayload{Type: "CONNECT"}); err != nil {
		return nil, err
	}
	group.GoOnce(runCtx, "castv2-read-"+host, c.readLoop)
	return c, nil
}

// sendJSON marshals payload and writes one frame. A write deadline
// keeps a wedged device from blocking callers forever; a write failure
// kills the connection.
func (c *conn) sendJSON(dest, namespace string, payload any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("castv2: encoding %s payload: %w", namespace, err)
	}
	m := Message{SourceID: senderID, DestinationID: dest, Namespace: namespace, PayloadUTF8: string(body)}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	c.sock.SetWriteDeadline(time.Now().Add(writeTimeout))
	if err := WriteMessage(c.sock, m); err != nil {
		c.fail(err)
		return err
	}
	return nil
}

// fail marks the connection dead exactly once and closes the socket.
// Close passes nil so the driver can tell teardown from death.
func (c *conn) fail(err error) {
	c.mu.Lock()
	select {
	case <-c.dead:
		c.mu.Unlock()
		return
	default:
	}
	c.deadErr = err
	close(c.dead)
	c.mu.Unlock()
	c.cancel()
	c.sock.Close()
}

// Close tears the channel down; safe to call more than once.
func (c *conn) Close() error {
	c.mu.Lock()
	c.closed = true
	c.mu.Unlock()
	c.fail(nil)
	return nil
}

// deathErr reports why the connection ended.
func (c *conn) deathErr() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed || c.deadErr == nil {
		return errConnClosed
	}
	return c.deadErr
}

// readLoop owns the socket's read side: it answers pings, correlates
// replies, and fans out status broadcasts. Heartbeats piggyback on the
// read deadline so liveness needs no second goroutine: 5 seconds of
// silence sends a PING, and 3 unanswered PINGs (or any read error)
// kill the connection. Steady inbound traffic suppresses our PINGs,
// which is fine: traffic proves the liveness a PING would.
func (c *conn) readLoop(ctx context.Context) error {
	var unanswered int
	for {
		if ctx.Err() != nil {
			return nil
		}
		c.sock.SetReadDeadline(time.Now().Add(heartbeatInterval))
		msg, err := ReadMessage(c.sock)
		if err != nil {
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() {
				if unanswered >= maxMissedPongs {
					c.fail(fmt.Errorf("castv2: %s: %d heartbeats unanswered", c.host, unanswered))
					return nil
				}
				unanswered++
				if err := c.sendJSON(platformID, NamespaceHeartbeat, tpPayload{Type: "PING"}); err != nil {
					return nil
				}
				continue
			}
			c.fail(fmt.Errorf("castv2: %s: reading: %w", c.host, err))
			return nil
		}
		if msg.Namespace == NamespaceHeartbeat {
			var hb tpPayload
			if json.Unmarshal([]byte(msg.PayloadUTF8), &hb) == nil {
				switch hb.Type {
				case "PING":
					c.sendJSON(msg.SourceID, NamespaceHeartbeat, tpPayload{Type: "PONG"})
				case "PONG":
					unanswered = 0
				}
			}
			continue
		}
		c.dispatch(msg)
	}
}

// dispatch routes one non-heartbeat message: replies go to their
// waiting requester, and every status, solicited or not, goes to the
// status channel so the driver sees one stream of observations.
func (c *conn) dispatch(msg Message) {
	raw := json.RawMessage(msg.PayloadUTF8)
	var probe struct {
		Type      string `json:"type"`
		RequestID int    `json:"requestId"`
	}
	if err := json.Unmarshal(raw, &probe); err != nil {
		c.log.Warn("castv2: dropping unparseable payload", "host", c.host, "namespace", msg.Namespace)
		return
	}
	if probe.RequestID != 0 {
		c.mu.Lock()
		ch := c.pending[probe.RequestID]
		delete(c.pending, probe.RequestID)
		c.mu.Unlock()
		if ch != nil {
			ch <- raw
		}
	}
	switch probe.Type {
	case "RECEIVER_STATUS":
		var rs receiverStatusMessage
		if err := json.Unmarshal(raw, &rs); err == nil {
			c.pushStatus(statusUpdate{receiver: &rs.Status})
		}
	case "MEDIA_STATUS":
		var ms mediaStatusMessage
		if err := json.Unmarshal(raw, &ms); err == nil {
			for i := range ms.Status {
				c.pushStatus(statusUpdate{media: &ms.Status[i]})
			}
		}
	}
}

// pushStatus delivers to the status channel without ever blocking the
// read loop: when the consumer lags, the oldest observation is dropped
// in favor of newer absolute state.
func (c *conn) pushStatus(u statusUpdate) {
	for {
		select {
		case c.statuses <- u:
			return
		default:
		}
		select {
		case <-c.statuses:
		default:
		}
	}
}

// roundTrip sends one request and waits for the reply correlated by
// requestId.
func (c *conn) roundTrip(ctx context.Context, dest, namespace string, build func(requestID int) any) (json.RawMessage, error) {
	ch := make(chan json.RawMessage, 1)
	c.mu.Lock()
	c.nextID++
	id := c.nextID
	c.pending[id] = ch
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
	}()
	if err := c.sendJSON(dest, namespace, build(id)); err != nil {
		return nil, err
	}
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-c.dead:
		return nil, c.deathErr()
	case raw := <-ch:
		return raw, nil
	}
}

// failureTypes are reply types that mean the device refused a request.
var failureTypes = map[string]bool{
	"LAUNCH_ERROR":         true,
	"LOAD_FAILED":          true,
	"LOAD_CANCELLED":       true,
	"INVALID_REQUEST":      true,
	"INVALID_PLAYER_STATE": true,
	"ERROR":                true,
}

// replyError turns a refusal reply into an error, nil otherwise.
func replyError(raw json.RawMessage) error {
	var probe struct {
		Type   string `json:"type"`
		Reason string `json:"reason"`
	}
	if err := json.Unmarshal(raw, &probe); err != nil {
		return fmt.Errorf("castv2: decoding reply: %w", err)
	}
	if !failureTypes[probe.Type] {
		return nil
	}
	if probe.Reason != "" {
		return fmt.Errorf("castv2: device refused request: %s (%s)", probe.Type, probe.Reason)
	}
	return fmt.Errorf("castv2: device refused request: %s", probe.Type)
}

// decodeReceiverStatus validates and unpacks a receiver reply.
func decodeReceiverStatus(raw json.RawMessage) (*receiverStatus, error) {
	if err := replyError(raw); err != nil {
		return nil, err
	}
	var msg receiverStatusMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		return nil, fmt.Errorf("castv2: decoding receiver status: %w", err)
	}
	return &msg.Status, nil
}

// getReceiverStatus asks the platform for its running apps and volume.
func (c *conn) getReceiverStatus(ctx context.Context) (*receiverStatus, error) {
	raw, err := c.roundTrip(ctx, platformID, NamespaceReceiver, func(id int) any {
		return getStatusRequest{Type: "GET_STATUS", RequestID: id}
	})
	if err != nil {
		return nil, err
	}
	return decodeReceiverStatus(raw)
}

// launch starts an app on the device.
func (c *conn) launch(ctx context.Context, appID string) (*receiverStatus, error) {
	raw, err := c.roundTrip(ctx, platformID, NamespaceReceiver, func(id int) any {
		return launchRequest{Type: "LAUNCH", RequestID: id, AppID: appID}
	})
	if err != nil {
		return nil, err
	}
	return decodeReceiverStatus(raw)
}

// setVolume sets the device volume; volume is a platform concern, not
// a media session one.
func (c *conn) setVolume(ctx context.Context, level float64) error {
	raw, err := c.roundTrip(ctx, platformID, NamespaceReceiver, func(id int) any {
		return setVolumeRequest{Type: "SET_VOLUME", RequestID: id, Volume: volumeLevel{Level: level}}
	})
	if err != nil {
		return err
	}
	_, err = decodeReceiverStatus(raw)
	return err
}

// connectTransport opens the virtual connection to a running app; the
// device drops media messages from senders that skipped this.
func (c *conn) connectTransport(transportID string) error {
	return c.sendJSON(transportID, NamespaceConnection, tpPayload{Type: "CONNECT"})
}

// mediaCall runs one media namespace round trip and returns the first
// status of the MEDIA_STATUS reply (nil when the reply carries none).
func (c *conn) mediaCall(ctx context.Context, dest string, build func(requestID int) any) (*mediaStatus, error) {
	raw, err := c.roundTrip(ctx, dest, NamespaceMedia, build)
	if err != nil {
		return nil, err
	}
	if err := replyError(raw); err != nil {
		return nil, err
	}
	var msg mediaStatusMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		return nil, fmt.Errorf("castv2: decoding media status: %w", err)
	}
	if len(msg.Status) == 0 {
		return nil, nil
	}
	return &msg.Status[0], nil
}

// pollMediaStatus fires a GET_STATUS without waiting for the reply,
// which comes back through the status channel like any broadcast, so
// the event pump never blocks on the device.
func (c *conn) pollMediaStatus(dest string) error {
	c.mu.Lock()
	c.nextID++
	id := c.nextID
	c.mu.Unlock()
	return c.sendJSON(dest, NamespaceMedia, getStatusRequest{Type: "GET_STATUS", RequestID: id})
}
