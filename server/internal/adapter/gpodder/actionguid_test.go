package gpodder

import (
	"fmt"
	"testing"
)

// An uploaded action's guid is read and not kept, so one that is not a
// string costs the guid, never the action.
func TestAnUploadedActionWithAMistypedGuidIsKept(t *testing.T) {
	e := newEnv(t)
	host := linkedFeeds(t)
	e.subscribeFirstParty(host + "/open")
	for i, guid := range []string{`7`, `{"id":7}`, `["open-1"]`, `true`} {
		up := fmt.Sprintf(`[{"podcast":%q,"episode":%q,"guid":%s,"action":"play","device":"phone","timestamp":"2026-01-01T00:00:%02d","started":0,"position":100,"total":600}]`,
			host+"/open", host+"/two.mp3?src=rss", guid, i)
		resp, raw := e.call("POST", "/api/2/episodes/alice.json", up, true)
		mustStatus(t, resp, raw, 200)
	}
	kept := 0
	for _, a := range e.actions("since=0").Actions {
		if a.Device == "phone" {
			kept++
		}
	}
	if kept != 4 {
		t.Errorf("kept %d of the four actions whose guid was not a string, want all", kept)
	}
}
