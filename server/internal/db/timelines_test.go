package db

import (
	"context"
	"testing"
)

func TestTimelineStashPrunesOnLoadAndPut(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	live := TimelineStash{Digest: "live", SignedMaster: "/hls/master.m3u8?sig=a", ExpiresAtNS: 2000}
	dead := TimelineStash{Digest: "dead", SignedMaster: "/hls/master.m3u8?sig=b", ExpiresAtNS: 500}
	for _, row := range []TimelineStash{live, dead} {
		if err := d.PutTimelineStash(ctx, row, 100); err != nil {
			t.Fatalf("put %s: %v", row.Digest, err)
		}
	}

	// Load at a moment past one expiry drops that row and returns the
	// other. A server down past every stored expiry is the case this
	// covers: nothing has minted yet, so no other sweep has run.
	rows, err := d.LoadTimelineStash(ctx, 1000)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Digest != "live" || rows[0].SignedMaster != live.SignedMaster {
		t.Fatalf("load = %+v, want only the live row", rows)
	}
	if rows[0].ExpiresAtNS != live.ExpiresAtNS {
		t.Fatalf("expiry = %d, want %d", rows[0].ExpiresAtNS, live.ExpiresAtNS)
	}

	// A mint sweeps too, so rows do not pile up across a long uptime.
	if err := d.PutTimelineStash(ctx, TimelineStash{Digest: "next", SignedMaster: "/c", ExpiresAtNS: 9000}, 3000); err != nil {
		t.Fatal(err)
	}
	rows, err = d.LoadTimelineStash(ctx, 3000)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Digest != "next" {
		t.Fatalf("load after the sweeping put = %+v, want only next", rows)
	}

	// Re-minting the same digest replaces the signed URL rather than
	// conflicting: the digest is content-addressed, the signature is not.
	again := TimelineStash{Digest: "next", SignedMaster: "/c2", ExpiresAtNS: 9500}
	if err := d.PutTimelineStash(ctx, again, 3000); err != nil {
		t.Fatal(err)
	}
	rows, _ = d.LoadTimelineStash(ctx, 3000)
	if len(rows) != 1 || rows[0].SignedMaster != "/c2" || rows[0].ExpiresAtNS != 9500 {
		t.Fatalf("re-mint = %+v, want the replaced row", rows)
	}

	if err := d.ForgetTimelineStash(ctx, "next"); err != nil {
		t.Fatal(err)
	}
	if rows, _ = d.LoadTimelineStash(ctx, 3000); len(rows) != 0 {
		t.Fatalf("load after forget = %+v, want empty", rows)
	}
}
