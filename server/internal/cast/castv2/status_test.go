// Status-ordering tests are internal: what they pin is the order the
// pump reads observations in, which nothing outside the package sees.
package castv2

import (
	"slices"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/connect"
)

// TestPreLaunchStatusKeepsTheTransport pins the hazard the pump lives
// with. Every receiver status call before a launch answers with no
// application running, and the pump reads those answers after the
// launch has cached the transport - so reading one as the app going
// away strands every verb that follows with no media session, which
// is a device left playing a connection check.
func TestPreLaunchStatusKeepsTheTransport(t *testing.T) {
	d := &driver{events: make(chan connect.DriverEvent, 4)}
	d.transportID, d.sessionID, d.mediaSessionID, d.loaded = "transport-1", "session-1", 3, true
	d.transportSeq = 7

	d.handleStatus(statusUpdate{seq: 5, receiver: &receiverStatus{}})
	if d.transportID == "" || d.mediaSessionID == 0 || !d.loaded {
		t.Fatalf("a status from before the launch cleared the session: transport %q, media session %d, loaded %v",
			d.transportID, d.mediaSessionID, d.loaded)
	}

	// One the device sent afterwards is the app really going away.
	d.handleStatus(statusUpdate{seq: 8, receiver: &receiverStatus{}})
	if d.transportID != "" || d.mediaSessionID != 0 || d.loaded {
		t.Fatalf("a status from after the launch left the session standing: transport %q, media session %d, loaded %v",
			d.transportID, d.mediaSessionID, d.loaded)
	}
}

// TestPreLoadStatusKeepsTheMediaSession is the same hazard on the
// media side: a probe asks a running receiver what it is doing before
// it loads anything, and that answer names the session the load is
// about to replace. Folded in afterwards it retargets every verb at
// the old session - a STOP the device refuses, so the check it was
// silencing plays on.
func TestPreLoadStatusKeepsTheMediaSession(t *testing.T) {
	d := &driver{events: make(chan connect.DriverEvent, 4)}
	d.mediaSessionID, d.itemIDs, d.played, d.loadSeq = 9, []int{4, 5}, true, 7

	d.handleStatus(statusUpdate{seq: 5, media: &mediaStatus{
		MediaSessionID: 2,
		PlayerState:    stateIdle,
		IdleReason:     idleFinished,
		CurrentItemID:  1,
		Items:          []mediaQueueItem{{ItemID: 1}},
	}})
	if d.mediaSessionID != 9 || !slices.Equal(d.itemIDs, []int{4, 5}) {
		t.Errorf("a status from before the load took the session over: media session %d, items %v",
			d.mediaSessionID, d.itemIDs)
	}
	if len(d.events) != 0 {
		t.Errorf("a status from before the load was emitted as an observation of this one: %+v", <-d.events)
	}

	// One from after it is this session speaking.
	d.handleStatus(statusUpdate{seq: 8, media: &mediaStatus{MediaSessionID: 11, PlayerState: statePlaying}})
	if d.mediaSessionID != 11 {
		t.Errorf("media session = %d, want 11 from the status that followed the load", d.mediaSessionID)
	}
}

// TestDispatchStampsArrivalOrder: the read loop numbers observations
// as it reads them, hands a reply its own number rather than whatever
// the count has reached by the time the caller looks, and observed
// reports how far along the connection is.
func TestDispatchStampsArrivalOrder(t *testing.T) {
	waiter := make(chan inbound, 1)
	c := &conn{
		log:      nopLogger{},
		pending:  map[int]chan inbound{4: waiter},
		statuses: make(chan statusUpdate, 4),
	}
	if got := c.observed(); got != 0 {
		t.Fatalf("a fresh connection has observed %d messages, want 0", got)
	}

	c.dispatch(Message{Namespace: NamespaceReceiver,
		PayloadUTF8: `{"type":"RECEIVER_STATUS","requestId":4,"status":{"applications":[]}}`})
	c.dispatch(Message{Namespace: NamespaceMedia,
		PayloadUTF8: `{"type":"MEDIA_STATUS","requestId":0,"status":[{"playerState":"PLAYING"}]}`})

	select {
	case in := <-waiter:
		if in.seq != 1 {
			t.Errorf("the reply arrived carrying seq %d, want 1: its own place in the order", in.seq)
		}
	default:
		t.Error("the reply never reached the caller waiting on its requestId")
	}
	var seqs []uint64
	for len(c.statuses) > 0 {
		seqs = append(seqs, (<-c.statuses).seq)
	}
	if !slices.Equal(seqs, []uint64{1, 2}) {
		t.Errorf("status sequence = %v, want 1 then 2 in arrival order", seqs)
	}
	if got := c.observed(); got != 2 {
		t.Errorf("observed = %d after two messages, want 2", got)
	}
}
