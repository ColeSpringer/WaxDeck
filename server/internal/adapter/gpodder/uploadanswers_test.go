package gpodder

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// An upload never answers past what the uploader has read. AntennaPod
// downloads, then uploads its queue thirty actions at a time and keeps the
// last chunk's answer: a play another device stored between that download
// and the last chunk is in AntennaPod's next download, however long its
// chunks took.
func TestAChunkedUploadAnswersNoLaterThanItsDownload(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()
	e.subscribe("phone")
	e.actions("since=0")
	other := e.feed.URL + "/ep2.mp3"
	e.upload(playOf("tablet", feed, other, time.Now().UTC().Format(protocolTime), "0", "60", "600"))
	var last uploadAckJSON
	for chunk := range 3 {
		if chunk > 0 {
			time.Sleep(service.GpodderCursorLag/2 + 500*time.Millisecond)
		}
		last = e.upload(fmt.Sprintf(`{"podcast":%q,"episode":"%s/chunk-%d.mp3","action":"download","device":"phone"}`,
			feed, e.feed.URL, chunk))
	}
	if got := actionsFor(e.actions("since="+strconv.FormatInt(last.Timestamp, 10)), other); len(got) != 1 || got[0].Device != "tablet" {
		t.Errorf("the download from the last chunk's answer = %+v, want the tablet's play stored before it", got)
	}
}

// A subscription upload answers no later than its device's last delta: a
// change another device made after that read is in the device's next
// delta, however long after the read the upload came.
func TestASubscriptionUploadAnswersNoLaterThanItsDevicesRead(t *testing.T) {
	e := newEnv(t)
	resp, raw := e.call("POST", "/api/2/devices/alice/phone.json", `{"caption":"phone"}`, true)
	mustStatus(t, resp, raw, 200)
	read := e.changesSince("phone", 0)
	e.change("tablet", []string{e.feedURLOf(3)}, nil)
	time.Sleep(service.GpodderCursorLag + 1500*time.Millisecond)
	ack := e.change("phone", []string{e.feedURLOf(2)}, nil)
	if ack.Timestamp > read.Timestamp {
		t.Errorf("the upload answered %d, past the phone's last read at %d", ack.Timestamp, read.Timestamp)
	}
	if d := e.changesSince("phone", ack.Timestamp); !slices.Contains(d.Add, e.feedURLOf(3)) {
		t.Errorf("the phone's next delta = %+v, want the tablet's add made after its read", d)
	}
}

// An episodes upload answers no later than the downloads of the app
// password it signed in with, directly or through a session it opened: an
// app stuck downloading from a low point holds back its own uploads, never
// those of a device on another app password, which answer from that
// device's own reads.
func TestAnUploadAnswersFromItsOwnAppPasswordsReads(t *testing.T) {
	for _, how := range []string{"signed requests", "logins"} {
		t.Run(how, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			ap, err := e.svc.CreateAppPassword(e.ctx, e.uc, "laptop")
			if err != nil {
				t.Fatal(err)
			}
			// as sends requests as an app on one app password, signing
			// each, or carrying the cookie of its login, and answers the
			// timestamp each was answered.
			as := func(secret string) func(method, path, body string) int64 {
				var cookie *http.Cookie
				if how == "logins" {
					cookie = e.login("alice", secret)
				}
				return func(method, path, body string) int64 {
					t.Helper()
					req, _ := http.NewRequest(method, e.ts.URL+path, strings.NewReader(body))
					if cookie != nil {
						req.AddCookie(cookie)
					} else {
						req.SetBasicAuth("alice", secret)
					}
					resp, err := http.DefaultClient.Do(req)
					if err != nil {
						t.Fatal(err)
					}
					raw, _ := io.ReadAll(resp.Body)
					resp.Body.Close()
					mustStatus(t, resp, raw, 200)
					var answer struct {
						Timestamp int64 `json:"timestamp"`
					}
					if err := json.Unmarshal(raw, &answer); err != nil {
						t.Fatalf("%s %s answered %s: %v", method, path, raw, err)
					}
					return answer.Timestamp
				}
			}
			phone, laptop := as(e.secret), as(ap.Secret)
			upload := func(device string) string {
				return fmt.Sprintf(`[{"podcast":%q,"episode":"%s/ep1.mp3","action":"download","device":%q}]`,
					e.feedURL(), e.feed.URL, device)
			}
			stuck := phone("GET", "/api/2/episodes/alice.json?since=0", "")
			time.Sleep(1100 * time.Millisecond)
			read := laptop("GET", "/api/2/episodes/alice.json?since=0", "")
			if read <= stuck {
				t.Fatalf("the laptop's read answered %d, want past the phone's %d", read, stuck)
			}
			if got := laptop("POST", "/api/2/episodes/alice.json", upload("laptop")); got < read {
				t.Errorf("the laptop's upload answered %d, behind its own read at %d (the phone's answered %d)", got, read, stuck)
			}
			if got := phone("POST", "/api/2/episodes/alice.json", upload("phone")); got > stuck {
				t.Errorf("the phone's upload answered %d, past its own read at %d", got, stuck)
			}
		})
	}
}
