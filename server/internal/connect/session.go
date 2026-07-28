package connect

import (
	"encoding/json"
	"time"
)

// Session authorities: who advances playback and whose position wins.
// Remote sessions are driven by the server; mirror sessions are driven
// by the playing client and mirrored here. Both are controlled the
// same way.
const (
	AuthorityRemote = "remote"
	AuthorityMirror = "mirror"
)

// QueueEntry is one queue member, hydrated for display.
type QueueEntry struct {
	PID        string
	Title      string
	Artist     string
	DurationMS int64
}

// TimelineBoundary places one queue entry on a minted timeline, in
// samples at the timeline's envelope rate.
type TimelineBoundary struct {
	PID             string
	OffsetSamples   int64
	DurationSamples int64
}

// TimelineMedia is a gapless rendering of a whole queue as one stream.
type TimelineMedia struct {
	Item         MediaItem
	EnvelopeRate int
	DurationMS   int64
	Boundaries   []TimelineBoundary
}

// queueState is a session's playback state. Position is an
// observation: PositionMS was true at PositionAt; snapshots
// extrapolate forward with Rate while Playing.
type queueState struct {
	Entries      []QueueEntry
	Index        int
	PositionMS   int64
	PositionAt   time.Time
	Playing      bool
	Rate         float64
	Volume       *float64
	Repeat       string
	Shuffle      bool
	QueueVersion int64
}

// session is the manager's in-memory record of one playback session.
type session struct {
	id         string
	ownerID    string
	ownerName  string
	endpointID string
	authority  string
	q          queueState

	// Remote plumbing: the live driver and, when the whole queue plays
	// as one stream, the timeline that maps positions.
	driver       Driver
	driverCancel func()
	timeline     *TimelineMedia

	createdAt time.Time
	updatedAt time.Time
	ended     bool
}

// Session is the public snapshot handed to the API layer and pushed to
// watchers. Position is already extrapolated to the snapshot instant.
type Session struct {
	ID           string
	EndpointID   string
	EndpointName string
	OwnerUserID  string
	OwnerName    string
	Authority    string
	Playing      bool
	Index        int
	PositionMS   int64
	PositionAt   time.Time
	Rate         float64
	Volume       *float64
	Repeat       string
	Shuffle      bool
	QueueVersion int64
	Entries      []QueueEntry
	Ended        bool
	UpdatedAt    time.Time
}

// EndedSession is one session's final state, read back from the
// history rows: the live map holds nothing once a session ends. It
// has no live half by construction — no `playing`, nothing to
// extrapolate, no queue version — because restoring one means
// starting a new session from this queue, not reviving this one.
type EndedSession struct {
	ID           string
	EndpointID   string
	EndpointName string
	Authority    string
	Index        int
	PositionMS   int64
	PositionAt   time.Time
	Rate         float64
	Repeat       string
	Shuffle      bool
	Entries      []QueueEntry
}

// extrapolate returns the position the observation implies at now.
func (q *queueState) extrapolate(now time.Time) int64 {
	if !q.Playing || q.PositionAt.IsZero() {
		return q.PositionMS
	}
	elapsed := now.Sub(q.PositionAt)
	if elapsed <= 0 {
		return q.PositionMS
	}
	rate := q.Rate
	if rate <= 0 {
		rate = 1
	}
	pos := q.PositionMS + int64(float64(elapsed.Milliseconds())*rate)
	if cur := q.currentDurationMS(); cur > 0 && pos > cur {
		pos = cur
	}
	return pos
}

func (q *queueState) currentDurationMS() int64 {
	if q.Index >= 0 && q.Index < len(q.Entries) {
		return q.Entries[q.Index].DurationMS
	}
	return 0
}

// persistedState is the JSON checkpoint written to playback_sessions.
type persistedState struct {
	Entries      []persistedEntry `json:"entries"`
	Index        int              `json:"index"`
	PositionMS   int64            `json:"positionMs"`
	Playing      bool             `json:"playing"`
	Rate         float64          `json:"rate"`
	Repeat       string           `json:"repeat,omitempty"`
	Shuffle      bool             `json:"shuffle,omitempty"`
	QueueVersion int64            `json:"queueVersion"`
}

type persistedEntry struct {
	PID        string `json:"pid"`
	Title      string `json:"title"`
	Artist     string `json:"artist,omitempty"`
	DurationMS int64  `json:"durationMs,omitempty"`
}

func (s *session) persisted() string {
	ps := persistedState{
		Index:        s.q.Index,
		PositionMS:   s.q.PositionMS,
		Playing:      s.q.Playing,
		Rate:         s.q.Rate,
		Repeat:       s.q.Repeat,
		Shuffle:      s.q.Shuffle,
		QueueVersion: s.q.QueueVersion,
	}
	for _, e := range s.q.Entries {
		ps.Entries = append(ps.Entries, persistedEntry(e))
	}
	data, err := json.Marshal(ps)
	if err != nil {
		return "{}"
	}
	return string(data)
}

// Wire frames the connect package originates. Shapes mirror the spec
// components (PlaybackSession, WsSessionFrame, WsEndpointCommandFrame);
// the api package owns the client-to-server halves.

type wireEntry struct {
	PID        string `json:"pid"`
	Title      string `json:"title"`
	Artist     string `json:"artist,omitempty"`
	DurationMS int64  `json:"durationMs,omitempty"`
}

type wireSession struct {
	ID           string      `json:"id"`
	EndpointID   string      `json:"endpointId"`
	EndpointName string      `json:"endpointName,omitempty"`
	Mine         bool        `json:"mine"`
	OwnerName    string      `json:"ownerName,omitempty"`
	Authority    string      `json:"authority"`
	Playing      bool        `json:"playing"`
	Index        int         `json:"index"`
	PositionMS   int64       `json:"positionMs"`
	PositionAt   string      `json:"positionAt"`
	Rate         float64     `json:"rate"`
	Volume       *float64    `json:"volume,omitempty"`
	Repeat       string      `json:"repeat,omitempty"`
	Shuffle      bool        `json:"shuffle,omitempty"`
	QueueVersion int64       `json:"queueVersion"`
	Entries      []wireEntry `json:"entries,omitempty"`
	Ended        bool        `json:"ended,omitempty"`
	UpdatedAt    string      `json:"updatedAt"`
}

type wireSessionFrame struct {
	Type    string      `json:"type"`
	Session wireSession `json:"session"`
}

type wireEndpointCommand struct {
	Type       string   `json:"type"`
	ID         string   `json:"id"`
	SessionID  string   `json:"sessionId"`
	Verb       string   `json:"verb"`
	ItemPids   []string `json:"itemPids,omitempty"`
	Index      *int     `json:"index,omitempty"`
	PositionMS *int64   `json:"positionMs,omitempty"`
	Play       *bool    `json:"play,omitempty"`
	Volume     *float64 `json:"volume,omitempty"`
	Rate       *float64 `json:"rate,omitempty"`
	Repeat     string   `json:"repeat,omitempty"`
	Shuffle    *bool    `json:"shuffle,omitempty"`
}

// WireSessionPayload converts a snapshot into the wire session object
// (the PlaybackSession schema) for one receiver, without the frame
// envelope; acks embed it directly.
func WireSessionPayload(s Session, forUserID string, withEntries bool) any {
	frame := WireSessionFrame(s, forUserID, withEntries).(wireSessionFrame)
	return frame.Session
}

// WireSessionFrame converts a snapshot into a session frame for one
// receiver: Mine is receiver-relative, OwnerName shows only on
// sessions the receiver does not own, and entries ride only when
// withEntries (the first frame of a watch and queue changes).
func WireSessionFrame(s Session, forUserID string, withEntries bool) any {
	ws := wireSession{
		ID:           s.ID,
		EndpointID:   s.EndpointID,
		EndpointName: s.EndpointName,
		Mine:         s.OwnerUserID == forUserID,
		Authority:    s.Authority,
		Playing:      s.Playing,
		Index:        s.Index,
		PositionMS:   s.PositionMS,
		PositionAt:   s.PositionAt.UTC().Format("2006-01-02T15:04:05.000Z07:00"),
		Rate:         s.Rate,
		Volume:       s.Volume,
		Repeat:       s.Repeat,
		Shuffle:      s.Shuffle,
		QueueVersion: s.QueueVersion,
		Ended:        s.Ended,
		UpdatedAt:    s.UpdatedAt.UTC().Format("2006-01-02T15:04:05.000Z07:00"),
	}
	if !ws.Mine {
		ws.OwnerName = s.OwnerName
	}
	if withEntries {
		ws.Entries = make([]wireEntry, 0, len(s.Entries))
		for _, e := range s.Entries {
			ws.Entries = append(ws.Entries, wireEntry(e))
		}
	}
	return wireSessionFrame{Type: "session", Session: ws}
}
