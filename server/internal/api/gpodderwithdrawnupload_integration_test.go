package api

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/adapter/gpodder"
)

// gpodderAck is a subscription upload's answer: the timestamp a client
// keeps as the since of its next read, and the URLs it is told to rewrite.
type gpodderAck struct {
	Timestamp  int64       `json:"timestamp"`
	UpdateURLs [][2]string `json:"update_urls"`
}

// waitOutTheSecond sleeps past the end of the current second, so a cursor
// read after it is a second later than any read before it.
func waitOutTheSecond() {
	time.Sleep(time.Until(time.Now().Truncate(time.Second).Add(time.Second + 10*time.Millisecond)))
}

// A client keeps an upload's answer as the since of its next read, so a
// subscription upload answers the place its device last read to, never
// the clock: what the other devices changed that this one has not read,
// before a withdrawal or after it, is still ahead of it. Episode uploads
// name no device, so one answers no later than what an episodes download
// of the account answered in the ten minutes before it, a withdrawal's
// answer included.
func TestAnUploadDuringAWithdrawnPodcastGrantAnswersTheDevicesLastRead(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	formerID, former := g.account(t, "former", g.musicLib, g.podcastLib)
	feedURL := g.feedURL(t)
	secret := decodeStatus[AppPasswordCreated](t, reqAs(t, g.h, http.MethodPost, "/api/v1/users/me/app-passwords", former,
		map[string]any{"label": "clients"}), 201, "minting an app password").Secret
	gp := httptest.NewServer(gpodder.New(g.h.svc, false, nil))
	t.Cleanup(gp.Close)
	call := func(method, path, body string) string {
		t.Helper()
		req, _ := http.NewRequest(method, gp.URL+path, strings.NewReader(body))
		req.SetBasicAuth("former", secret)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("%s %s = %d: %s", method, path, resp.StatusCode, raw)
		}
		return string(raw)
	}
	grant := func(libs ...string) {
		t.Helper()
		wantStatus(t, g.h.patchJSON(t, "/api/v1/users/"+formerID, map[string]any{
			"libraryAccess": map[string]any{"mode": "granted", "libraryPids": libs},
		}), 200, "setting the grant")
	}
	read := func(device string, since int64) gpodderReads {
		t.Helper()
		return readGpodder(t, call("GET", "/api/2/subscriptions/former/"+device+".json?since="+strconv.FormatInt(since, 10), ""))
	}
	upload := func(device string, add ...string) gpodderAck {
		t.Helper()
		body, _ := json.Marshal(map[string]any{"add": append([]string{}, add...), "remove": []string{}})
		var ack gpodderAck
		if err := json.Unmarshal([]byte(call("POST", "/api/2/subscriptions/former/"+device+".json", string(body))), &ack); err != nil {
			t.Fatal(err)
		}
		return ack
	}

	call("POST", "/api/2/devices/former/tablet.json", "{}")
	lastRead := read("tablet", 0).Timestamp
	if lastRead == 0 {
		t.Fatal("the tablet's first read answered 0, which would pass for a device that never read")
	}
	if ack := upload("phone", feedURL); len(ack.UpdateURLs) != 0 {
		t.Fatalf("the phone's add while granted was rewritten: %v", ack.UpdateURLs)
	}

	// The cursor is whole seconds: each wait keeps the clock from reading
	// what an earlier answer already said.
	waitOutTheSecond()
	uploaded := upload("tablet")
	if uploaded.Timestamp != lastRead {
		t.Errorf("an upload outside a withdrawal answered %d, want the tablet's last read at %d", uploaded.Timestamp, lastRead)
	}

	waitOutTheSecond()
	grant(g.musicLib)
	refused := upload("tablet", feedURL)
	if !slices.Equal(refused.UpdateURLs, [][2]string{{feedURL, ""}}) {
		t.Errorf("the tablet's add during the withdrawal = %v, want it refused as ever", refused.UpdateURLs)
	}
	if refused.Timestamp != lastRead {
		t.Errorf("the upload during the withdrawal answered %d, want the tablet's last read at %d", refused.Timestamp, lastRead)
	}
	if ack := upload("watch", feedURL); ack.Timestamp != 0 {
		t.Errorf("a device that never read was answered %d during the withdrawal, want 0", ack.Timestamp)
	}
	if held := readGpodder(t, call("GET", "/api/2/episodes/former.json?since="+strconv.FormatInt(lastRead, 10), "")); held.Timestamp != lastRead {
		t.Errorf("the episodes download during the withdrawal answered %d, want its since %d back", held.Timestamp, lastRead)
	}
	episodes := readGpodder(t, call("POST", "/api/2/episodes/former.json",
		`[{"podcast":"`+feedURL+`","episode":"https://cdn.example.com/e.mp3","device":"tablet","action":"download"}]`))
	if episodes.Timestamp > lastRead {
		t.Errorf("an episodes upload after a download held back at %d answered %d, want no later", lastRead, episodes.Timestamp)
	}

	// A read during the withdrawal is answered the since it came with, and
	// that is then the place the device keeps.
	if got := read("tablet", uploaded.Timestamp); got.Timestamp != uploaded.Timestamp || len(got.Add)+len(got.Remove) != 0 {
		t.Errorf("the tablet's read during the withdrawal = %+v, want nothing and its since %d back", got, uploaded.Timestamp)
	}
	if ack := upload("tablet", feedURL); ack.Timestamp != uploaded.Timestamp {
		t.Errorf("the upload after that read answered %d, want its since %d", ack.Timestamp, uploaded.Timestamp)
	}

	grant(g.musicLib, g.podcastLib)
	if got := read("tablet", refused.Timestamp); !slices.Equal(got.Add, []string{feedURL}) {
		t.Errorf("the delta from the withdrawn upload's answer = %+v, want the phone's add it had not read", got)
	}
	if ack := upload("tablet"); ack.Timestamp <= lastRead {
		t.Errorf("an upload once the grant returned answered %d, want past the read at %d", ack.Timestamp, lastRead)
	}
}
