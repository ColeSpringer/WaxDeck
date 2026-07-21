// Package testreceiver is an in-process fake Chromecast: a TLS
// listener speaking the real CASTV2 framing and namespaces, honest
// enough at the wire level that the castv2 driver cannot tell it from
// a device. Tests point a Device at it, drive playback through the
// driver, and assert on what arrived. Time is a mock clock the test
// steps, so positions are deterministic.
package testreceiver

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"fmt"
	"math/big"
	"net"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/cast/castv2"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// LoadRecord is one LOAD or QUEUE_LOAD as it arrived on the wire.
type LoadRecord struct {
	Queue              bool
	Items              []LoadedItem
	StartIndex         int
	CurrentTimeSeconds float64
	RepeatMode         string
}

// LoadedItem is one media entry of a load.
type LoadedItem struct {
	ContentID   string
	ContentType string
	StreamType  string
	Title       string
	Artist      string
	ArtURL      string
	Autoplay    bool
}

// mediaJSON mirrors the media object of LOAD and QUEUE_LOAD.
type mediaJSON struct {
	ContentID   string        `json:"contentId"`
	ContentType string        `json:"contentType"`
	StreamType  string        `json:"streamType"`
	Metadata    *metadataJSON `json:"metadata"`
}

type metadataJSON struct {
	MetadataType int    `json:"metadataType"`
	Title        string `json:"title"`
	Artist       string `json:"artist"`
	Images       []struct {
		URL string `json:"url"`
	} `json:"images"`
}

// request is the union of every field a sender request can carry.
type request struct {
	Type      string `json:"type"`
	RequestID int    `json:"requestId"`
	AppID     string `json:"appId"`
	Volume    *struct {
		Level *float64 `json:"level"`
		Muted *bool    `json:"muted"`
	} `json:"volume"`
	Media       *mediaJSON `json:"media"`
	Autoplay    *bool      `json:"autoplay"`
	CurrentTime *float64   `json:"currentTime"`
	Items       []struct {
		Media    mediaJSON `json:"media"`
		Autoplay bool      `json:"autoplay"`
	} `json:"items"`
	StartIndex     int    `json:"startIndex"`
	RepeatMode     string `json:"repeatMode"`
	MediaSessionID int    `json:"mediaSessionId"`
	ResumeState    string `json:"resumeState"`
}

// queueEntry is one loaded item with its receiver-assigned id.
type queueEntry struct {
	itemID int
	media  mediaJSON
}

// mediaState is the fake player. Positions derive from the mock
// clock: posBase is the playhead at clockBase, and PLAYING adds the
// clock delta since.
type mediaState struct {
	sessionID   int
	playerState string
	idleReason  string
	items       []queueEntry
	currentItem int
	posBase     float64
	clockBase   float64
}

// senderConn serializes writes to one sender, so replies and
// broadcasts interleave at frame granularity.
type senderConn struct {
	conn net.Conn
	mu   sync.Mutex
}

func (sc *senderConn) send(m castv2.Message) {
	sc.mu.Lock()
	defer sc.mu.Unlock()
	castv2.WriteMessage(sc.conn, m)
}

// Receiver is one fake device. All state sits behind mu; getters
// return copies.
type Receiver struct {
	ln     net.Listener
	group  *supervise.Group
	cancel context.CancelFunc

	mu       sync.Mutex
	conns    map[*senderConn]struct{}
	launched string
	volume   float64
	muted    bool
	clock    float64
	media    mediaState
	actions  []string
	loads    []LoadRecord
	lastSeek float64
}

const (
	transportID = "transport-1"
	sessionID   = "session-1"
)

// New starts a receiver on 127.0.0.1 with a fresh self-signed
// certificate, which is what a real device presents.
func New() (*Receiver, error) {
	cert, err := selfSignedCert()
	if err != nil {
		return nil, err
	}
	ln, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}})
	if err != nil {
		return nil, fmt.Errorf("testreceiver: listening: %w", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	r := &Receiver{
		ln:     ln,
		group:  supervise.NewGroup(nil),
		cancel: cancel,
		conns:  make(map[*senderConn]struct{}),
		volume: 1,
	}
	r.group.GoOnce(ctx, "testreceiver-accept", func(ctx context.Context) error {
		return r.acceptLoop(ctx)
	})
	return r, nil
}

// Start runs a receiver for one test and closes it on cleanup.
func Start(t *testing.T) *Receiver {
	t.Helper()
	r, err := New()
	if err != nil {
		t.Fatalf("starting test receiver: %v", err)
	}
	t.Cleanup(r.Close)
	return r
}

// Close stops the listener and every connection; safe to call twice.
func (r *Receiver) Close() {
	r.cancel()
	r.ln.Close()
	r.mu.Lock()
	for sc := range r.conns {
		sc.conn.Close()
	}
	r.mu.Unlock()
	r.group.Wait()
}

// Addr returns the listener's host:port for building a Device.
func (r *Receiver) Addr() string { return r.ln.Addr().String() }

// Device returns a castv2.Device pointing at this receiver.
func (r *Receiver) Device() castv2.Device {
	host, portStr, _ := net.SplitHostPort(r.Addr())
	port, _ := strconv.Atoi(portStr)
	return castv2.Device{Host: host, Port: port, Name: "Test Receiver", ID: "test-receiver-1"}
}

func (r *Receiver) acceptLoop(ctx context.Context) error {
	for {
		conn, err := r.ln.Accept()
		if err != nil {
			return nil // listener closed
		}
		sc := &senderConn{conn: conn}
		r.mu.Lock()
		r.conns[sc] = struct{}{}
		r.mu.Unlock()
		r.group.GoOnce(ctx, "testreceiver-conn", func(context.Context) error {
			defer func() {
				r.mu.Lock()
				delete(r.conns, sc)
				r.mu.Unlock()
				conn.Close()
			}()
			for {
				msg, err := castv2.ReadMessage(conn)
				if err != nil {
					return nil
				}
				r.handle(sc, msg)
			}
		})
	}
}

func (r *Receiver) handle(sc *senderConn, msg castv2.Message) {
	var req request
	if err := json.Unmarshal([]byte(msg.PayloadUTF8), &req); err != nil {
		return
	}
	switch msg.Namespace {
	case castv2.NamespaceConnection:
		// CONNECT and CLOSE take no reply.
	case castv2.NamespaceHeartbeat:
		if req.Type == "PING" {
			sc.send(reply(msg, castv2.NamespaceHeartbeat, `{"type":"PONG"}`))
		}
	case castv2.NamespaceReceiver:
		r.handleReceiver(sc, msg, req)
	case castv2.NamespaceMedia:
		r.handleMedia(sc, msg, req)
	}
}

// reply swaps source and destination for the answer to msg.
func reply(msg castv2.Message, namespace, payload string) castv2.Message {
	return castv2.Message{
		SourceID:      msg.DestinationID,
		DestinationID: msg.SourceID,
		Namespace:     namespace,
		PayloadUTF8:   payload,
	}
}

func (r *Receiver) handleReceiver(sc *senderConn, msg castv2.Message, req request) {
	r.mu.Lock()
	r.actions = append(r.actions, req.Type)
	switch req.Type {
	case "GET_STATUS":
	case "LAUNCH":
		r.launched = req.AppID
	case "SET_VOLUME":
		if req.Volume != nil {
			if req.Volume.Level != nil {
				r.volume = *req.Volume.Level
			}
			if req.Volume.Muted != nil {
				r.muted = *req.Volume.Muted
			}
		}
	default:
		r.mu.Unlock()
		return
	}
	payload := r.receiverStatusLocked(req.RequestID)
	r.mu.Unlock()
	sc.send(reply(msg, castv2.NamespaceReceiver, payload))
}

// receiverStatusLocked renders RECEIVER_STATUS; r.mu must be held.
func (r *Receiver) receiverStatusLocked(requestID int) string {
	status := map[string]any{
		"volume": map[string]any{"level": r.volume, "muted": r.muted, "controlType": "attenuation"},
	}
	if r.launched != "" {
		status["applications"] = []any{map[string]any{
			"appId":       r.launched,
			"sessionId":   sessionID,
			"transportId": transportID,
			"displayName": "Default Media Receiver",
			"statusText":  "Ready To Cast",
		}}
	}
	b, _ := json.Marshal(map[string]any{"type": "RECEIVER_STATUS", "requestId": requestID, "status": status})
	return string(b)
}

func (r *Receiver) handleMedia(sc *senderConn, msg castv2.Message, req request) {
	r.mu.Lock()
	r.actions = append(r.actions, req.Type)
	switch req.Type {
	case "LOAD":
		r.media.sessionID++
		var ct float64
		if req.CurrentTime != nil {
			ct = *req.CurrentTime
		}
		autoplay := req.Autoplay == nil || *req.Autoplay
		var m mediaJSON
		if req.Media != nil {
			m = *req.Media
		}
		r.media.items = []queueEntry{{itemID: 1, media: m}}
		r.media.currentItem = 1
		r.media.posBase = ct
		r.media.clockBase = r.clock
		r.media.idleReason = ""
		if autoplay {
			r.media.playerState = "PLAYING"
		} else {
			r.media.playerState = "PAUSED"
		}
		r.loads = append(r.loads, LoadRecord{
			Items:              []LoadedItem{loadedItem(m, autoplay)},
			CurrentTimeSeconds: ct,
		})
	case "QUEUE_LOAD":
		r.media.sessionID++
		var ct float64
		if req.CurrentTime != nil {
			ct = *req.CurrentTime
		}
		entries := make([]queueEntry, 0, len(req.Items))
		items := make([]LoadedItem, 0, len(req.Items))
		for i, it := range req.Items {
			entries = append(entries, queueEntry{itemID: i + 1, media: it.Media})
			items = append(items, loadedItem(it.Media, it.Autoplay))
		}
		idx := min(max(req.StartIndex, 0), len(entries)-1)
		r.media.items = entries
		r.media.currentItem = entries[idx].itemID
		r.media.posBase = ct
		r.media.clockBase = r.clock
		r.media.idleReason = ""
		r.media.playerState = "PLAYING"
		r.loads = append(r.loads, LoadRecord{
			Queue:              true,
			Items:              items,
			StartIndex:         req.StartIndex,
			CurrentTimeSeconds: ct,
			RepeatMode:         req.RepeatMode,
		})
	case "PLAY":
		r.media.posBase = r.currentTimeLocked()
		r.media.clockBase = r.clock
		r.media.playerState = "PLAYING"
	case "PAUSE":
		r.media.posBase = r.currentTimeLocked()
		r.media.playerState = "PAUSED"
	case "STOP":
		r.media.posBase = 0
		r.media.playerState = "IDLE"
		r.media.idleReason = "CANCELLED"
	case "SEEK":
		if req.CurrentTime != nil {
			r.lastSeek = *req.CurrentTime
			r.media.posBase = *req.CurrentTime
			r.media.clockBase = r.clock
		}
		switch req.ResumeState {
		case "PLAYBACK_START":
			r.media.playerState = "PLAYING"
		case "PLAYBACK_PAUSE":
			r.media.playerState = "PAUSED"
		}
	case "GET_STATUS":
	}
	payload := r.mediaStatusLocked(req.RequestID)
	r.mu.Unlock()
	sc.send(reply(msg, castv2.NamespaceMedia, payload))
}

func loadedItem(m mediaJSON, autoplay bool) LoadedItem {
	item := LoadedItem{
		ContentID:   m.ContentID,
		ContentType: m.ContentType,
		StreamType:  m.StreamType,
		Autoplay:    autoplay,
	}
	if m.Metadata != nil {
		item.Title = m.Metadata.Title
		item.Artist = m.Metadata.Artist
		if len(m.Metadata.Images) > 0 {
			item.ArtURL = m.Metadata.Images[0].URL
		}
	}
	return item
}

// currentTimeLocked is the playhead under the mock clock; r.mu held.
func (r *Receiver) currentTimeLocked() float64 {
	if r.media.playerState == "PLAYING" || r.media.playerState == "BUFFERING" {
		return r.media.posBase + (r.clock - r.media.clockBase)
	}
	return r.media.posBase
}

// mediaStatusLocked renders MEDIA_STATUS; r.mu must be held. Before
// any load the status array is empty, as on a real device.
func (r *Receiver) mediaStatusLocked(requestID int) string {
	statuses := []any{}
	if r.media.sessionID != 0 {
		status := map[string]any{
			"mediaSessionId":         r.media.sessionID,
			"playerState":            r.media.playerState,
			"currentTime":            r.currentTimeLocked(),
			"playbackRate":           1,
			"supportedMediaCommands": 274447,
			"volume":                 map[string]any{"level": 1, "muted": false},
		}
		if r.media.idleReason != "" {
			status["idleReason"] = r.media.idleReason
		}
		if r.media.currentItem != 0 {
			status["currentItemId"] = r.media.currentItem
		}
		if len(r.media.items) > 1 {
			items := make([]any, 0, len(r.media.items))
			for _, e := range r.media.items {
				items = append(items, map[string]any{"itemId": e.itemID, "media": e.media})
			}
			status["items"] = items
		}
		statuses = append(statuses, status)
	}
	b, _ := json.Marshal(map[string]any{"type": "MEDIA_STATUS", "requestId": requestID, "status": statuses})
	return string(b)
}

// broadcast pushes an unsolicited MEDIA_STATUS to every connection,
// the way a device announces state changes it made on its own.
func (r *Receiver) broadcast() {
	r.mu.Lock()
	payload := r.mediaStatusLocked(0)
	conns := make([]*senderConn, 0, len(r.conns))
	for sc := range r.conns {
		conns = append(conns, sc)
	}
	r.mu.Unlock()
	for _, sc := range conns {
		sc.send(castv2.Message{
			SourceID:      transportID,
			DestinationID: "*",
			Namespace:     castv2.NamespaceMedia,
			PayloadUTF8:   payload,
		})
	}
}

// FinishCurrent ends playback the way a real receiver does when the
// queue runs out: IDLE with idleReason FINISHED, broadcast to every
// connected sender.
func (r *Receiver) FinishCurrent() {
	r.mu.Lock()
	r.media.posBase = 0
	r.media.clockBase = r.clock
	r.media.playerState = "IDLE"
	r.media.idleReason = "FINISHED"
	r.media.currentItem = 0
	r.mu.Unlock()
	r.broadcast()
}

// Advance steps the mock clock: PLAYING positions move by seconds.
func (r *Receiver) Advance(seconds float64) {
	r.mu.Lock()
	r.clock += seconds
	r.mu.Unlock()
}

// PushStatus broadcasts an unsolicited MEDIA_STATUS so tests can force
// a position observation without waiting for the driver's poll.
func (r *Receiver) PushStatus() { r.broadcast() }

// LoadedItems returns the items of the most recent load.
func (r *Receiver) LoadedItems() []LoadedItem {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.loads) == 0 {
		return nil
	}
	last := r.loads[len(r.loads)-1]
	out := make([]LoadedItem, len(last.Items))
	copy(out, last.Items)
	return out
}

// Loads returns every load in arrival order.
func (r *Receiver) Loads() []LoadRecord {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]LoadRecord, len(r.loads))
	copy(out, r.loads)
	return out
}

// Actions returns every receiver and media request type in arrival
// order; heartbeats are not recorded.
func (r *Receiver) Actions() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]string, len(r.actions))
	copy(out, r.actions)
	return out
}

// LastSeekSeconds returns the target of the most recent SEEK.
func (r *Receiver) LastSeekSeconds() float64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.lastSeek
}

// VolumeLevel returns the device volume.
func (r *Receiver) VolumeLevel() float64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.volume
}

// PlayerState returns the current media player state.
func (r *Receiver) PlayerState() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.media.playerState
}

// LaunchedApp returns the appId of the running app, empty before
// LAUNCH.
func (r *Receiver) LaunchedApp() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.launched
}

// selfSignedCert mints the kind of throwaway certificate a real
// device presents.
func selfSignedCert() (tls.Certificate, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("testreceiver: generating key: %w", err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "testreceiver"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		IPAddresses:  []net.IP{net.IPv4(127, 0, 0, 1)},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("testreceiver: creating certificate: %w", err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}, nil
}
