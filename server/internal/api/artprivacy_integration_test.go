package api

import (
	"strings"
	"testing"
)

// TestPrivateFeedArtURLIsWithheld covers the one place a cover's
// provenance is somebody's credential.
//
// A feed cover's source URL is minted from the feed document and lives
// on the feed's host, so a credentialed show's channel image sits on
// the same tokenized path its feed does - the value `showDTO` already
// withholds, OPML export skips, shares refuse, and feed errors scrub.
// The art source is the newest way to ask for it, and it reaches four
// read paths at once (the show detail, an episode's item read, the
// art-roles read, and the `X-Art-Source-Url` header on the bytes), so
// the withholding lives under all four rather than at each.
//
// The rest of the attribution stays: what the caller loses is the
// address, not the fact that the picture came from the feed.
func TestPrivateFeedArtURLIsWithheld(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url":      fs.feedURL(),
		"username": "member",
		"password": "s3cret",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show

	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	// The feed URL itself is the rule this follows; if it ever stopped
	// being withheld the art URL would be the least of it.
	if got := deref(detail.FeedUrl); got != "" {
		t.Fatalf("a credentialed feed URL was reported at all: %q", got)
	}
	if detail.ArtSource == nil {
		t.Fatal("a private show reported no art source; the attribution is not the secret, the address is")
	}
	if detail.ArtSource.Source != "feed" {
		t.Errorf("show art source = %q, want feed", detail.ArtSource.Source)
	}
	if got := deref(detail.ArtSource.SourceUrl); got != "" {
		t.Errorf("a private show's cover reported its address: %q", got)
	}

	// The byte endpoint's header form of the same four values.
	res := get(t, h.ts, "/api/v1/items/"+show.Pid+"/art", h.token)
	defer res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("art status = %d", res.StatusCode)
	}
	if got := res.Header.Get("X-Art-Source"); got != "feed" {
		t.Errorf("X-Art-Source = %q, want feed", got)
	}
	if got := res.Header.Get("X-Art-Source-Url"); got != "" {
		t.Errorf("X-Art-Source-Url leaked a private feed's address: %q", got)
	}

	// The roles read, which is the path this rule reached last: it
	// reports each slot's own attribution rather than a resolve's, so
	// it took the stored URL straight out of the catalog while the mark
	// beside it withheld the same value.
	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+show.Pid+"/art-roles", h.token))
	front := artRoleNamed(t, roles, "front")
	if front.Source == nil || *front.Source != "feed" {
		t.Errorf("front role source = %v, want feed", front.Source)
	}
	if got := deref(front.SourceUrl); got != "" {
		t.Errorf("the front role reported a private feed's address: %q", got)
	}
}

// artRoleNamed picks one slot out of a roles read.
func artRoleNamed(t *testing.T, roles ArtRoles, role string) ArtRoleInfo {
	t.Helper()
	for _, r := range roles.Roles {
		if string(r.Role) == role {
			return r
		}
	}
	t.Fatalf("art-roles has no %s slot: %+v", role, roles.Roles)
	return ArtRoleInfo{}
}

// TestPublicFeedArtURLIsReported is the other half: withholding has to
// cost something, so a show nobody credentialed still cites where its
// picture came from. Without this the fix above could be "never report
// a feed URL" and pass.
func TestPublicFeedArtURLIsReported(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": fs.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show

	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if detail.ArtSource == nil {
		t.Fatal("a public show reported no art source")
	}
	if got := deref(detail.ArtSource.SourceUrl); !strings.HasSuffix(got, "/cover/a.png") {
		t.Errorf("show art sourceUrl = %q, want the feed's image", got)
	}
	res := get(t, h.ts, "/api/v1/items/"+show.Pid+"/art", h.token)
	defer res.Body.Close()
	if got := res.Header.Get("X-Art-Source-Url"); !strings.HasSuffix(got, "/cover/a.png") {
		t.Errorf("X-Art-Source-Url = %q, want the feed's image", got)
	}
	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+show.Pid+"/art-roles", h.token))
	front := artRoleNamed(t, roles, "front")
	if got := deref(front.SourceUrl); !strings.HasSuffix(got, "/cover/a.png") {
		t.Errorf("front role sourceUrl = %q, want the feed's image", got)
	}
}

// TestArtSourceURLDropsItsQuery is the redaction the acquisition block
// established, applied to the other value of the same kind: an art
// address goes out as scheme, host and path, because these reads answer
// everyone who can see the item and a signed cover URL carries its token
// in the query.
//
// It identifies where a picture came from; it is not a URL to re-fetch
// it by, and the contract says so.
func TestArtSourceURLDropsItsQuery(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)
	fs.imageRef.Store("/cover/a.png?token=s3cret&exp=1")
	fs.write(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": fs.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show

	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if detail.ArtSource == nil {
		t.Fatal("no art source on a public show")
	}
	for _, got := range []string{
		deref(detail.ArtSource.SourceUrl),
		func() string {
			roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+show.Pid+"/art-roles", h.token))
			return deref(artRoleNamed(t, roles, "front").SourceUrl)
		}(),
		func() string {
			res := get(t, h.ts, "/api/v1/items/"+show.Pid+"/art", h.token)
			defer res.Body.Close()
			return res.Header.Get("X-Art-Source-Url")
		}(),
	} {
		if got == "" {
			t.Error("the address was withheld entirely; a public show keeps its attribution")
			continue
		}
		if strings.Contains(got, "token") || strings.Contains(got, "?") {
			t.Errorf("art sourceUrl kept its query: %q", got)
		}
		if !strings.HasSuffix(got, "/cover/a.png") {
			t.Errorf("art sourceUrl = %q, want the path kept", got)
		}
	}
}
