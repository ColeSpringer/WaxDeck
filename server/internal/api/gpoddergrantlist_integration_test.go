package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/adapter/gpodder"
)

// A show a device alone holds stays followed through a withdrawal of the
// podcast grant, whatever that device's list says meanwhile: the account
// cannot see what it would be letting go of.
func TestAWithdrawnGrantKeepsADevicesOnlyHold(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	formerID, former := g.account(t, "former", g.musicLib, g.podcastLib)
	feedURL := g.feedURL(t)
	secret := decodeStatus[AppPasswordCreated](t, reqAs(t, g.h, http.MethodPost, "/api/v1/users/me/app-passwords", former,
		map[string]any{"label": "clients"}), 201, "minting an app password").Secret
	gp := httptest.NewServer(gpodder.New(g.h.svc, false, nil))
	t.Cleanup(gp.Close)
	put := func(body string) {
		t.Helper()
		req, _ := http.NewRequest(http.MethodPut, gp.URL+"/subscriptions/former/phone.txt", strings.NewReader(body))
		req.SetBasicAuth("former", secret)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("PUT = %d: %s", resp.StatusCode, raw)
		}
	}
	grant := func(libs ...string) {
		t.Helper()
		wantStatus(t, g.h.patchJSON(t, "/api/v1/users/"+formerID, map[string]any{
			"libraryAccess": map[string]any{"mode": "granted", "libraryPids": libs},
		}), 200, "setting the grant")
	}
	listed := func() int {
		t.Helper()
		return len(decode[SubscriptionPage](t, reqAs(t, g.h, http.MethodGet, "/api/v1/podcasts", former, nil)).Items)
	}

	put(feedURL + "\n")
	if n := listed(); n != 1 {
		t.Fatalf("the account follows %d shows after the phone's list, want the one", n)
	}
	grant(g.musicLib)
	put("")
	grant(g.musicLib, g.podcastLib)
	if n := listed(); n != 1 {
		t.Errorf("after the grant came back the account follows %d shows, want the one only the phone held", n)
	}
}
