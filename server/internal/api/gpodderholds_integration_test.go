package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/adapter/gpodder"
)

// An unsubscribe through the API is the whole account's: it takes every
// gpodder device's hold on the show with it, so a device that adds the
// show again afterwards is its only holder and can let it go.
func TestAnUnsubscribeTakesEveryDevicesHold(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	gp := httptest.NewServer(gpodder.New(h.svc, false, nil))
	t.Cleanup(gp.Close)
	resp := h.postJSON(t, "/api/v1/users/me/app-passwords", map[string]any{"label": "gpodder"})
	if resp.StatusCode != 201 {
		t.Fatalf("app password status = %d", resp.StatusCode)
	}
	secret := decode[AppPasswordCreated](t, resp).Secret
	device := func(method, path, body string) {
		t.Helper()
		req, _ := http.NewRequest(method, gp.URL+path, strings.NewReader(body))
		req.SetBasicAuth("admin", secret)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("%s %s = %d", method, path, resp.StatusCode)
		}
	}

	device("POST", "/api/2/subscriptions/admin/phone.json", `{"add":["`+feed.feedURL()+`"],"remove":[]}`)
	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 200 {
		t.Fatalf("subscribing in the apps to what the phone added = %d, want 200", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show.Pid
	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/podcasts/"+show, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	del, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	wantStatus(t, del, 204, "unsubscribe")

	device("POST", "/api/2/subscriptions/admin/desk.json", `{"add":["`+feed.feedURL()+`"],"remove":[]}`)
	device("PUT", "/subscriptions/admin/desk.json", `[]`)
	if subs := decode[SubscriptionPage](t, get(t, h.ts, "/api/v1/podcasts", h.token)); len(subs.Items) != 0 {
		t.Fatalf("subscriptions after the desk let go = %+v, want none: the phone's hold went with the unsubscribe", subs.Items)
	}
}
