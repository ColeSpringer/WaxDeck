package connect

import (
	"context"
	"crypto/rand"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// Endpoint is the registry's public view of one controllable output.
type Endpoint struct {
	ID            string
	Kind          string
	Name          string
	OwnerUserID   string
	Shared        bool
	Online        bool
	VolumeControl bool
	RateControl   bool
}

// Endpoint kinds.
const (
	KindClient  = "client"
	KindCast    = "cast"
	KindDLNA    = "dlna"
	KindJukebox = "jukebox"
)

// clientEndpoint is a registered first-party client: controllable over
// its WebSocket, visible only to its owner, alive while the connection
// is.
type clientEndpoint struct {
	meta Endpoint
	link *ClientLink
}

// deviceEndpoint is a server-driven output. Discovery keeps metadata
// fresh; the session manager dials a driver on demand.
type deviceEndpoint struct {
	meta      Endpoint
	deviceKey string
	dial      DialFunc
	lastSeen  time.Time
}

// Registry tracks every endpoint. Device endpoints persist their
// identity through the db so a rediscovered device keeps its pid.
type Registry struct {
	store *db.DB
	now   func() time.Time

	mu      sync.Mutex
	clients map[string]*clientEndpoint // endpoint id -> live client
	devices map[string]*deviceEndpoint // endpoint id -> device
}

// NewRegistry builds an empty registry over the endpoint table.
func NewRegistry(store *db.DB, now func() time.Time) *Registry {
	if now == nil {
		now = time.Now
	}
	return &Registry{
		store:   store,
		now:     now,
		clients: make(map[string]*clientEndpoint),
		devices: make(map[string]*deviceEndpoint),
	}
}

// RestorePersisted loads known device endpoints from the store as
// offline entries, so a restart lists them immediately (offline,
// undialable) instead of hiding them until the next discovery sweep
// re-announces. Discovery upserts replace these with live entries.
func (r *Registry) RestorePersisted(ctx context.Context) error {
	rows, err := r.store.ListPlayerEndpoints(ctx)
	if err != nil {
		return err
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, row := range rows {
		if _, live := r.devices[row.ID]; live {
			continue
		}
		r.devices[row.ID] = &deviceEndpoint{
			meta: Endpoint{
				ID:     row.ID,
				Kind:   row.Kind,
				Name:   row.Name,
				Shared: row.Shared,
				Online: false,
				// The capability flags every shipped device kind
				// carries; a live announce refreshes them.
				VolumeControl: true,
				RateControl:   false,
			},
			deviceKey: row.DeviceKey,
		}
	}
	return nil
}

// clientEndpointID derives a stable endpoint id from the device
// session id, so the same signed-in device keeps its endpoint identity
// across reconnects without another table.
func clientEndpointID(sessionID string) string {
	if rest, ok := strings.CutPrefix(sessionID, "se-"); ok {
		return "pe-" + rest
	}
	return "pe-" + sessionID
}

// newEndpointID mints a fresh endpoint pid for discovered devices.
func newEndpointID() string {
	return "pe-" + ulid.MustNew(ulid.Timestamp(time.Now()), rand.Reader).String()
}

// RegisterClient adds (or refreshes) the calling connection as a
// controllable client endpoint and returns its endpoint id. A second
// registration for the same device session replaces the first: one
// live endpoint per signed-in device.
func (r *Registry) RegisterClient(link *ClientLink, name string, volumeControl, rateControl bool) Endpoint {
	id := clientEndpointID(link.SessionID)
	if name == "" {
		name = link.DeviceName
	}
	if name == "" {
		name = "Client"
	}
	meta := Endpoint{
		ID:            id,
		Kind:          KindClient,
		Name:          name,
		OwnerUserID:   link.UserID,
		Shared:        false,
		Online:        true,
		VolumeControl: volumeControl,
		RateControl:   rateControl,
	}
	r.mu.Lock()
	r.clients[id] = &clientEndpoint{meta: meta, link: link}
	r.mu.Unlock()
	return meta
}

// UnregisterClient removes the connection's endpoint if it still owns
// it (a newer registration for the same device wins).
func (r *Registry) UnregisterClient(link *ClientLink) {
	id := clientEndpointID(link.SessionID)
	r.mu.Lock()
	if c, ok := r.clients[id]; ok && c.link == link {
		delete(r.clients, id)
	}
	r.mu.Unlock()
}

// UpsertDevice records a discovered device endpoint and returns its
// stable endpoint metadata. deviceKey is the device's own durable
// identity (cast device id, DLNA UDN, the jukebox output name).
func (r *Registry) UpsertDevice(ctx context.Context, kind, deviceKey, name, address string, volumeControl, rateControl bool, dial DialFunc) (Endpoint, error) {
	now := r.now()
	row, err := r.store.UpsertPlayerEndpoint(ctx, db.PlayerEndpointRow{
		ID:          newEndpointID(),
		Kind:        kind,
		DeviceKey:   deviceKey,
		Name:        name,
		Address:     address,
		Shared:      true,
		LastSeenNS:  now.UnixNano(),
		CreatedAtNS: now.UnixNano(),
	})
	if err != nil {
		return Endpoint{}, err
	}
	meta := Endpoint{
		ID:            row.ID,
		Kind:          kind,
		Name:          name,
		Shared:        true,
		Online:        true,
		VolumeControl: volumeControl,
		RateControl:   rateControl,
	}
	r.mu.Lock()
	r.devices[row.ID] = &deviceEndpoint{meta: meta, deviceKey: deviceKey, dial: dial, lastSeen: now}
	r.mu.Unlock()
	return meta, nil
}

// MarkDeviceOffline flips a device endpoint offline without forgetting
// it; the next discovery sweep brings it back.
func (r *Registry) MarkDeviceOffline(endpointID string) {
	r.mu.Lock()
	if d, ok := r.devices[endpointID]; ok {
		d.meta.Online = false
	}
	r.mu.Unlock()
}

// Visible returns the endpoints the user may see and control: their
// own client endpoints plus every shared device endpoint, devices
// first, then by name.
func (r *Registry) Visible(userID string) []Endpoint {
	r.mu.Lock()
	out := make([]Endpoint, 0, len(r.devices)+len(r.clients))
	for _, d := range r.devices {
		out = append(out, d.meta)
	}
	for _, c := range r.clients {
		if c.meta.OwnerUserID == userID {
			out = append(out, c.meta)
		}
	}
	r.mu.Unlock()
	sort.Slice(out, func(i, j int) bool {
		di, dj := out[i].Kind != KindClient, out[j].Kind != KindClient
		if di != dj {
			return di
		}
		if !strings.EqualFold(out[i].Name, out[j].Name) {
			return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
		}
		return out[i].ID < out[j].ID
	})
	return out
}

// Lookup returns endpoint metadata when the user may see it. The
// second result distinguishes "absent" from "not yours".
func (r *Registry) Lookup(userID, endpointID string) (Endpoint, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if d, ok := r.devices[endpointID]; ok {
		return d.meta, true
	}
	if c, ok := r.clients[endpointID]; ok && c.meta.OwnerUserID == userID {
		return c.meta, true
	}
	return Endpoint{}, false
}

// link returns the live connection behind a client endpoint.
func (r *Registry) link(endpointID string) (*ClientLink, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	c, ok := r.clients[endpointID]
	if !ok {
		return nil, false
	}
	return c.link, true
}

// dialer returns the DialFunc behind an online device endpoint. A
// restored-but-undiscovered endpoint has no dial yet and reads as
// offline.
func (r *Registry) dialer(endpointID string) (DialFunc, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	d, ok := r.devices[endpointID]
	if !ok || !d.meta.Online || d.dial == nil {
		return nil, false
	}
	return d.dial, true
}
