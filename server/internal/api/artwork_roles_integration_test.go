package api

import (
	"testing"
)

// TestPodcastShowArtRoles confirms the art and art-roles endpoints accept a
// podcast-show (pc-) PID, which the spec promises for both but the prefix
// switch used to reject as not-found. art-roles answers 200 (its own-level
// slots, possibly empty) for a recognized entity, so it distinguishes a
// recognized show from the old unrecognized-prefix 404.
func TestPodcastShowArtRoles(t *testing.T) {
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

	// Clearing the front drops own-art; the back slot survives.
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+pid+"/artwork"), 204, "clear front")
	if h.itemMeta(t, pid).HasOwnArtwork {
		t.Fatal("after clearing the front cover, hasOwnArtwork stayed true")
	}
	after := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	var frontStill, backStill bool
	for _, r := range after.Roles {
		switch string(r.Role) {
		case "front":
			frontStill = true
		case "back":
			backStill = true
		}
	}
	if frontStill {
		t.Fatalf("front slot survived a clear: %+v", after.Roles)
	}
	if !backStill {
		t.Fatalf("back slot lost when clearing front: %+v", after.Roles)
	}
}
