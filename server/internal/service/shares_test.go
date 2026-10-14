package service

import (
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

func TestShareCursorRoundTrip(t *testing.T) {
	t.Parallel()
	wantNS := int64(1753000000000000000)
	wantID := "01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	ns, id, err := decodeShareCursor(encodeShareCursor(wantNS, wantID))
	if err != nil || ns != wantNS || id != wantID {
		t.Fatalf("round trip = (%d, %q, %v), want (%d, %q, nil)", ns, id, err, wantNS, wantID)
	}
	// The empty cursor is the first page, never an error.
	if ns, id, err := decodeShareCursor(""); err != nil || ns != 0 || id != "" {
		t.Fatalf("empty cursor = (%d, %q, %v), want (0, \"\", nil)", ns, id, err)
	}
}

func TestShareCursorMalformed(t *testing.T) {
	t.Parallel()
	for _, bad := range []string{
		"nodot",             // no separator at all
		"%%%.someid",        // prefix is not base64url
		"!!!.",              // empty id and broken prefix
		"bm9jb2xvbg.someid", // prefix decodes but carries no ns:id pair
	} {
		if _, _, err := decodeShareCursor(bad); err == nil {
			t.Errorf("cursor %q decoded, want error", bad)
		}
	}
}

// TestShareAuditsCreationAndAnAdministratorsRevoke: a link serves under
// its owner's current reach, so the audit entry written when it was
// minted is the one durable record of what it published. An owner
// pulling their own link is routine; an administrator pulling someone
// else's is not.
func TestShareAuditsCreationAndAnAdministratorsRevoke(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, admin)[0]
	_, owner := shareOwner(t, ctx, svc, "publisher")
	entries := func(action string) []AuditEventDTO {
		t.Helper()
		page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: action}, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		return page.Events
	}

	mine, err := svc.CreateShare(ctx, owner, track, 0, true, 0)
	if err != nil {
		t.Fatal(err)
	}
	created := entries("share.create")
	if len(created) != 1 || created[0].TargetPID != mine.ID || created[0].ActorID != owner.ID ||
		created[0].Detail["targetPid"] != track || created[0].Detail["allowDownload"] != true {
		t.Fatalf("share.create entries = %+v", created)
	}
	if err := svc.RevokeShare(ctx, owner, mine.ID); err != nil {
		t.Fatal(err)
	}
	if got := entries("share.revoke"); len(got) != 0 {
		t.Errorf("an owner revoking their own link was audited: %+v", got)
	}

	theirs, err := svc.CreateShare(ctx, owner, track, 0, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RevokeShare(ctx, admin, theirs.ID); err != nil {
		t.Fatal(err)
	}
	revoked := entries("share.revoke")
	if len(revoked) != 1 || revoked[0].TargetPID != theirs.ID || revoked[0].ActorID != admin.ID {
		t.Errorf("share.revoke entries = %+v, want the administrator's revoke", revoked)
	}
}
