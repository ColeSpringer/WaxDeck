package api

import (
	"encoding/json"
	"io"
	"net/url"
	"testing"
)

// historyPage reads one page of the organize history as the wire has it.
func historyPage(t *testing.T, h *harness, query url.Values) ([]string, string) {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/organize/history?"+query.Encode(), h.token)
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		t.Fatalf("history %s = %d (%s)", query.Encode(), resp.StatusCode, body)
	}
	var page struct {
		Batches []struct {
			JobPid string `json:"jobPid"`
		} `json:"batches"`
		NextCursor string `json:"nextCursor"`
	}
	if err := json.Unmarshal(body, &page); err != nil {
		t.Fatal(err)
	}
	var pids []string
	for _, b := range page.Batches {
		pids = append(pids, b.JobPid)
	}
	return pids, page.NextCursor
}

// The organize history pages as every list does, cursor in and
// nextCursor out, so a run older than a page is still reached: three
// runs at two a page are two pages, newest first, the last without a
// cursor. A page the runs left fill exactly is the last too, with no
// cursor to an empty one.
func TestTheOrganizeHistoryPages(t *testing.T) {
	t.Parallel()
	h := newManagedHarness(t)
	run := decodeStatus[OrganizeReport](t, h.postJSON(t, "/api/v1/organize/apply", map[string]any{}), 200, "apply")
	undo := decodeStatus[OrganizeReport](t, h.postJSON(t, "/api/v1/organize/undo",
		map[string]any{"jobPid": run.JobPid}), 200, "undo")
	redo := decodeStatus[OrganizeReport](t, h.postJSON(t, "/api/v1/organize/undo",
		map[string]any{"jobPid": undo.JobPid}), 200, "undo the undo")

	first, next := historyPage(t, h, url.Values{"limit": {"2"}})
	if len(first) != 2 || first[0] != redo.JobPid || first[1] != undo.JobPid || next == "" {
		t.Fatalf("first page = %v (next %q), want the two newest and a cursor", first, next)
	}
	second, last := historyPage(t, h, url.Values{"limit": {"2"}, "cursor": {next}})
	if len(second) != 1 || second[0] != run.JobPid || last != "" {
		t.Fatalf("second page = %v (next %q), want the oldest run and no cursor", second, last)
	}
	if exact, after := historyPage(t, h, url.Values{"limit": {"1"}, "cursor": {next}}); len(exact) != 1 || after != "" {
		t.Fatalf("a last page of one at one a page = %v (next %q), want no cursor", exact, after)
	}
	if every, after := historyPage(t, h, url.Values{"limit": {"3"}}); len(every) != 3 || after != "" {
		t.Fatalf("three runs at three a page = %v (next %q), want one page and no cursor", every, after)
	}
	resp := get(t, h.ts, "/api/v1/organize/history?cursor=not-a-cursor", h.token)
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Errorf("a bad cursor = %d, want 400", resp.StatusCode)
	}
}
