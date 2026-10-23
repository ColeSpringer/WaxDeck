package api

import (
	"errors"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The entry for a deletion says what became of the playlists, and for one
// that stopped part-way, that it did, whether the account was left
// disabled, and why - in the words of a refusal, never an internal
// fault's own text.
func TestUserDeleteDetailSaysWhatAStoppedDeletionHadDone(t *testing.T) {
	t.Parallel()
	done := service.AccountDeleted{
		PlaylistsTransferred: 2, PlaylistsDeleted: 1, PlaylistsFixed: 1, TransferredTo: "admin", LinksEnded: 3, Disabled: true,
	}

	whole := userDeleteDetail(done, nil)
	for k, want := range map[string]any{
		"playlistsTransferred": 2, "playlistsDeleted": 1, "playlistsFixed": 1, "transferredTo": "admin", "linksEnded": 3,
	} {
		if whole[k] != want {
			t.Errorf("detail[%s] = %v, want %v", k, whole[k], want)
		}
	}
	for _, k := range []string{"failed", "accountDisabled", "error"} {
		if _, has := whole[k]; has {
			t.Errorf("a finished deletion records %s: %v", k, whole)
		}
	}
	// A finished deletion always says how many links ended, none included;
	// the extras appear only when there is something to say.
	if plain := userDeleteDetail(service.AccountDeleted{PlaylistsDeleted: 1}, nil); len(plain) != 3 || plain["linksEnded"] != 0 {
		t.Errorf("a deletion that fixed and handed over nothing records %v, want the two counts and the links", plain)
	}

	internal := userDeleteDetail(done, errors.New(`open /var/lib/waxdeck/catalog.db: disk I/O error`))
	if internal["failed"] != true || internal["accountDisabled"] != true || internal["error"] != "internal error" {
		t.Errorf("detail = %v, want a failure that left the account disabled, in no words of the fault's own", internal)
	}
	if _, has := internal["linksEnded"]; has {
		t.Errorf("a deletion that stopped records the links it ended: %v", internal)
	}
	// What a retry did with the copies an earlier attempt left is named.
	dealt := userDeleteDetail(service.AccountDeleted{
		FixedCopiesRemoved: []string{"pl-01JZX5N8QW3F4V9T2B7KDAAAAA"}, FixedCopiesKept: []string{"pl-01JZX5N8QW3F4V9T2B7KDBBBBB"},
	}, nil)
	if !jsonEqual(dealt["fixedCopiesRemoved"], []string{"pl-01JZX5N8QW3F4V9T2B7KDAAAAA"}) ||
		!jsonEqual(dealt["fixedCopiesKept"], []string{"pl-01JZX5N8QW3F4V9T2B7KDBBBBB"}) {
		t.Errorf("detail = %v, want the copy removed and the copy kept, by pid", dealt)
	}
	if _, has := whole["fixedCopiesRemoved"]; has {
		t.Errorf("a deletion that dealt with no copy names some: %v", whole)
	}
	if _, has := whole["fixedCopiesKept"]; has {
		t.Errorf("a deletion that dealt with no copy names some: %v", whole)
	}
	// A failure that left a fixed copy of a playlist in the catalog names it.
	left := userDeleteDetail(done, leftCopyError{pid: "pl-01JZX5N8QW3F4V9T2B7KDAAAAA"})
	if left["fixedCopyLeft"] != "pl-01JZX5N8QW3F4V9T2B7KDAAAAA" || left["error"] != "internal error" {
		t.Errorf("detail = %v, want the copy that was left, and no words of the fault's own", left)
	}
	if _, has := internal["fixedCopyLeft"]; has {
		t.Errorf("a failure that left no copy names one: %v", internal)
	}
	refused := userDeleteDetail(service.AccountDeleted{}, &service.Error{Kind: service.KindConflict, Msg: "this is the last enabled administrator"})
	if refused["failed"] != true || refused["accountDisabled"] != false || refused["error"] != "this is the last enabled administrator" {
		t.Errorf("detail = %v, want the refusal's own sentence", refused)
	}
}

// leftCopyError is an error that says it left a fixed copy behind, as the
// service's failures of a handover do.
type leftCopyError struct{ pid string }

func (e leftCopyError) Error() string    { return "the catalog went away: " + e.pid }
func (e leftCopyError) LeftCopy() string { return e.pid }
