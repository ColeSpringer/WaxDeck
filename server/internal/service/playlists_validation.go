package service

import (
	"context"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Checks on a playlist's wire inputs, the change events its edits fan out,
// and the offset cursor its in-memory lists page with.

// playlistVisibility validates the wire visibility; empty means
// private.
func playlistVisibility(v string) (model.PlaylistVisibility, error) {
	switch v {
	case "", string(model.VisibilityPrivate):
		return model.VisibilityPrivate, nil
	case string(model.VisibilityShared):
		return model.VisibilityShared, nil
	}
	return "", errInvalid("visibility must be private or shared")
}

// maxPlaylistName is the bound the contract declares on a playlist's
// name, in characters.
const maxPlaylistName = 200

// checkPlaylistName refuses a trimmed name past that bound.
func checkPlaylistName(name string) error {
	if utf8.RuneCountInString(name) > maxPlaylistName {
		return errInvalid(fmt.Sprintf("a playlist name may be at most %d characters", maxPlaylistName))
	}
	return nil
}

// emitPlaylistEvent appends playlist change events: always to the
// acting user, and to every other user when the playlist is (or was)
// shared, since shared playlists are visible to everyone. barePID is
// the bare catalog pid.
func (l *Playlists) emitPlaylistEvent(ctx context.Context, uc *UserCtx, shared bool, barePID string) {
	l.emitUserEvent(ctx, uc.ID, eventPlaylist, barePID)
	if shared {
		l.announcePlaylist(ctx, uc.ID, barePID)
	}
}

// announcePlaylist puts a playlist event on every account's stream but
// exceptID's.
func (l *Playlists) announcePlaylist(ctx context.Context, exceptID, barePID string) {
	err := l.db.EachUser(ctx, func(u *wdb.User) error {
		if u.ID != exceptID {
			l.emitUserEvent(ctx, u.ID, eventPlaylist, barePID)
		}
		return nil
	})
	if err != nil {
		l.log.Warn("fanning out playlist event", "err", err)
	}
}

// encodeOffsetCursor and decodeOffsetCursor page in-memory lists (a
// playlist's members, the playlist listing itself). The offset counts
// the entries the caller has been shown, and is opaque on the wire;
// positions inside one evaluation are what the contract promises.
//
// The prefix carries a version, retired the same way the scoped
// cursors' one is: bump it in the change that alters what the offset
// indexes into, and the old spelling stops parsing, so a cursor from
// before the change answers 400 instead of walking a shifted window.
// It went to o2 when the member listing's offset stopped indexing into
// the evaluation, members hidden from the caller included, and started
// counting what the caller was shown: a reader decoding it learned how
// many members it cannot see sit between the ones it can.
//
// Two surfaces mint these, and only one of them changed: the member
// listing above and the playlist listing itself. They share the prefix
// deliberately, because a second version constant is a second thing to
// remember to bump - but it means a bump for either 400s an in-flight
// scroll of both. The blast radius is one scroll, which is why that is
// the cheaper trade; whoever bumps it next should know they are
// retiring both.
const offsetCursorVersion = "o2:"

func encodeOffsetCursor(off int) string {
	return base64.RawURLEncoding.EncodeToString([]byte(offsetCursorVersion + strconv.Itoa(off)))
}

func decodeOffsetCursor(c string) (int, error) {
	if c == "" {
		return 0, nil
	}
	raw, err := base64.RawURLEncoding.DecodeString(c)
	if err != nil || !strings.HasPrefix(string(raw), offsetCursorVersion) {
		return 0, errInvalid("malformed cursor")
	}
	off, err := strconv.Atoi(strings.TrimPrefix(string(raw), offsetCursorVersion))
	if err != nil || off < 0 {
		return 0, errInvalid("malformed cursor")
	}
	return off, nil
}
