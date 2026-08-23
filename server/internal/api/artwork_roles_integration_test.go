package api

import (
	"strings"
	"testing"
)

// TestPodcastShowArtRoles confirms the art and art-roles endpoints accept a
// podcast-show (pc-) PID, which the spec promises for both but the prefix
// switch used to reject as not-found. art-roles answers 200 (its own-level
// slots, possibly empty) for a recognized entity, so it distinguishes a
// recognized show from the old unrecognized-prefix 404.
func TestPodcastShowArtRoles(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+show.Pid+"/art-roles", h.token),
		200, "podcast show art-roles")
}

// TestArtworkRolesAndLevelScope covers multi-slot artwork and the
// own-versus-inherited distinction: a front cover set on an item reads as
// its own; a back cover lands in its own slot without touching the front;
// the art-roles listing reports both slots with their pixel dimensions; each
// slot reads back its own image; clearing the front drops own-art while the
// back slot survives; and a bad role is rejected.
func TestArtworkRolesAndLevelScope(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	png := tinyPNG(t)

	// A front cover set on the item is its own (not inherited).
	resp := metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, png)
	wantStatus(t, resp, 200, "set front")
	meta := h.itemMeta(t, pid)
	if !meta.HasArtwork || !meta.HasOwnArtwork {
		t.Fatalf("after set front: hasArtwork=%v hasOwnArtwork=%v, want true/true",
			meta.HasArtwork, meta.HasOwnArtwork)
	}

	// A back cover lands in its own slot.
	resp = metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork?role=back", h.token, png)
	wantStatus(t, resp, 200, "set back")

	// A bad role on the write path is rejected up front.
	resp = metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork?role=bogus", h.token, png)
	wantStatus(t, resp, 400, "set bad role")

	// art-roles lists both own-level slots, with pixel dimensions.
	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	got := map[string]ArtRoleInfo{}
	for _, r := range roles.Roles {
		got[string(r.Role)] = r
	}
	if _, ok := got["front"]; !ok {
		t.Fatalf("art-roles missing front: %+v", roles.Roles)
	}
	if _, ok := got["back"]; !ok {
		t.Fatalf("art-roles missing back: %+v", roles.Roles)
	}
	if fr := got["front"]; fr.Width == nil || *fr.Width <= 0 || fr.Height == nil || *fr.Height <= 0 {
		t.Fatalf("front role missing dimensions: %+v", fr)
	}

	// Each slot reads back its own image; a bad role is rejected.
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+pid+"/art?role=back", h.token), 200, "read back")
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+pid+"/art?role=front", h.token), 200, "read front")
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+pid+"/art?role=bogus", h.token), 400, "bad role")

	// Clearing the front drops own-art; the back slot survives. The
	// front row itself stays, pinned and empty: the PUT above locked
	// the slot (the `lock` parameter defaults true) and a clear leaves
	// the pin as the caller set it, so what is left is the "no cover,
	// and do not refill it" state rather than a slot enrichment may
	// fill on its next pass.
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+pid+"/artwork"), 204, "clear front")
	if h.itemMeta(t, pid).HasOwnArtwork {
		t.Fatal("after clearing the front cover, hasOwnArtwork stayed true")
	}
	after := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	var front *ArtRoleInfo
	var backStill bool
	for i, r := range after.Roles {
		switch string(r.Role) {
		case "front":
			front = &after.Roles[i]
		case "back":
			backStill = true
		}
	}
	if front == nil {
		t.Fatalf("front slot lost its pin on a clear: %+v", after.Roles)
	}
	if deref(front.Format) != "" {
		t.Errorf("front slot kept an image through a clear: %+v", front)
	}
	if front.Locked == nil || !*front.Locked {
		t.Errorf("front slot came back unpinned, so the next enrichment refills it: %+v", front)
	}
	if !backStill {
		t.Fatalf("back slot lost when clearing front: %+v", after.Roles)
	}
}

// TestArtCacheHeaders pins the caching contract the client grids are
// built on. Before it, a warm two-hundred-cover grid spent a conditional
// GET per cover because the response carried a validator and no
// freshness at all. The 304 carries the same three headers as the body:
// a revalidated copy that learns nothing about its own freshness
// revalidates again on the next paint, which is the round trip this is
// here to remove.
func TestArtCacheHeaders(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, tinyPNG(t)),
		200, "set front")

	resp := getArt(t, h, "/api/v1/items/"+pid+"/art?size=256", "")
	etag := resp.Header.Get("ETag")
	cacheControl := resp.Header.Get("Cache-Control")
	vary := resp.Header.Get("Vary")
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("art status = %d, want 200", resp.StatusCode)
	}
	if etag == "" {
		t.Error("the art response carries no ETag")
	}
	if cacheControl != artCacheControl {
		t.Errorf("Cache-Control = %q, want %q", cacheControl, artCacheControl)
	}
	// Artwork follows the item's visibility, so a cache shared by two
	// accounts must key on the session and no shared cache may store it
	// at all.
	if vary != artVary {
		t.Errorf("Vary = %q, want %q", vary, artVary)
	}
	if !strings.HasPrefix(cacheControl, "private,") {
		t.Errorf("Cache-Control = %q, want it to start private", cacheControl)
	}

	again := getArt(t, h, "/api/v1/items/"+pid+"/art?size=256", etag)
	again.Body.Close()
	if again.StatusCode != 304 {
		t.Fatalf("If-None-Match status = %d, want 304", again.StatusCode)
	}
	if got := again.Header.Get("ETag"); got != etag {
		t.Errorf("304 ETag = %q, want the validator it was asked with (%q)", got, etag)
	}
	if got := again.Header.Get("Cache-Control"); got != artCacheControl {
		t.Errorf("304 Cache-Control = %q, want %q", got, artCacheControl)
	}
	if got := again.Header.Get("Vary"); got != artVary {
		t.Errorf("304 Vary = %q, want %q", got, artVary)
	}

	// The validator names the rung that answered, not the size that was
	// typed. Two requests that round to one rung are one picture and
	// share a validator; keying by the raw request instead would
	// survive a change to the ladder, so a browser holding pre-flip
	// bytes would revalidate into a 304 and keep the stale image for
	// as long as it held it.
	rounded := getArt(t, h, "/api/v1/items/"+pid+"/art?size=200", "")
	roundedETag := rounded.Header.Get("ETag")
	rounded.Body.Close()
	if !strings.HasSuffix(strings.TrimSuffix(roundedETag, `"`), "-256") {
		t.Errorf("ETag for size=200 = %q, want it keyed by the 256 rung", roundedETag)
	}
	sibling := getArt(t, h, "/api/v1/items/"+pid+"/art?size=250", "")
	siblingETag := sibling.Header.Get("ETag")
	sibling.Body.Close()
	if siblingETag != roundedETag {
		t.Errorf("size=250 ETag = %q, size=200 ETag = %q; one rung answers both",
			siblingETag, roundedETag)
	}
	// And the conditional request across the pair is honoured, which is
	// the behaviour the shared validator exists to buy.
	shared := getArt(t, h, "/api/v1/items/"+pid+"/art?size=250", roundedETag)
	shared.Body.Close()
	if shared.StatusCode != 304 {
		t.Errorf("If-None-Match across the rung status = %d, want 304", shared.StatusCode)
	}
}
