package db

import (
	"context"
	"testing"
)

func TestTimelineStashPrunesOnLoadAndPut(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	live := TimelineStash{Key: "live/flac~off~0", ID: "idlive", SignedMaster: "/hls/master.m3u8?sig=a", ExpiresAtNS: 2000}
	dead := TimelineStash{Key: "dead/flac~off~0", ID: "iddead", SignedMaster: "/hls/master.m3u8?sig=b", ExpiresAtNS: 500}
	for _, row := range []TimelineStash{live, dead} {
		if err := d.PutTimelineStash(ctx, row, 100); err != nil {
			t.Fatalf("put %s: %v", row.Key, err)
		}
	}

	// Load at a moment past one expiry drops that row and returns the
	// other. A server down past every stored expiry is the case this
	// covers: nothing has minted yet, so no other sweep has run.
	rows, err := d.LoadTimelineStash(ctx, 1000)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Key != "live/flac~off~0" || rows[0].SignedMaster != live.SignedMaster {
		t.Fatalf("load = %+v, want only the live row", rows)
	}
	if rows[0].ExpiresAtNS != live.ExpiresAtNS || rows[0].ID != live.ID {
		t.Fatalf("row = %+v, want %+v", rows[0], live)
	}

	// A mint sweeps too, so rows do not pile up across a long uptime.
	if err := d.PutTimelineStash(ctx, TimelineStash{Key: "next/aac~off~0", ID: "idnext", SignedMaster: "/c", ExpiresAtNS: 9000}, 3000); err != nil {
		t.Fatal(err)
	}
	rows, err = d.LoadTimelineStash(ctx, 3000)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Key != "next/aac~off~0" {
		t.Fatalf("load after the sweeping put = %+v, want only next", rows)
	}

	// Re-minting the same rendering replaces the signed URL rather than
	// conflicting: the digest is content-addressed, the signature is not.
	again := TimelineStash{Key: "next/aac~off~0", ID: "idother", SignedMaster: "/c2", ExpiresAtNS: 9500}
	if err := d.PutTimelineStash(ctx, again, 3000); err != nil {
		t.Fatal(err)
	}
	rows, _ = d.LoadTimelineStash(ctx, 3000)
	if len(rows) != 1 || rows[0].SignedMaster != "/c2" || rows[0].ExpiresAtNS != 9500 {
		t.Fatalf("re-mint = %+v, want the replaced row", rows)
	}
	// And so is the id: a re-mint passes the id it already holds, and
	// where it does not, memory had forgotten the row and the pid the
	// client is holding is the new one. Keeping the old id would strand
	// it across a restart, on a row this write just refreshed.
	if rows[0].ID != "idother" {
		t.Fatalf("re-mint left the row named %q", rows[0].ID)
	}

	if err := d.ForgetTimelineStash(ctx, "next/aac~off~0"); err != nil {
		t.Fatal(err)
	}
	if rows, _ = d.LoadTimelineStash(ctx, 3000); len(rows) != 0 {
		t.Fatalf("load after forget = %+v, want empty", rows)
	}
}

// Two renderings of one queue are two rows. The digest names the
// sources and the seams and nothing about the encoder, so a cast mint
// in AAC and a browser mint in FLAC over the same queue arrive with the
// same digest; keyed by digest alone the second would overwrite the
// first and hand one of the two a stream it cannot decode.
func TestTimelineStashHoldsRenderingsApart(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	for _, row := range []TimelineStash{
		{Key: "digest1/aac~off~0", ID: "idaac", SignedMaster: "/a", ExpiresAtNS: 9000},
		{Key: "digest1/flac~off~0", ID: "idflac", SignedMaster: "/f", ExpiresAtNS: 9000},
	} {
		if err := d.PutTimelineStash(ctx, row, 100); err != nil {
			t.Fatalf("put %s: %v", row.Key, err)
		}
	}
	rows, err := d.LoadTimelineStash(ctx, 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 {
		t.Fatalf("load = %+v, want both renderings", rows)
	}

	// And dropping one dead rendering leaves the other serving.
	if err := d.ForgetTimelineStash(ctx, "digest1/aac~off~0"); err != nil {
		t.Fatal(err)
	}
	rows, _ = d.LoadTimelineStash(ctx, 100)
	if len(rows) != 1 || rows[0].Key != "digest1/flac~off~0" {
		t.Fatalf("load after forget = %+v, want only the flac rendering", rows)
	}
}
