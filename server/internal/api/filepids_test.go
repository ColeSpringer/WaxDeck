package api

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A write-back's failures and issues name their files under the file
// prefix, as every pid the API gives wears its type's; one naming no
// file stays empty.
func TestWriteBackFilesWearTheFilePrefix(t *testing.T) {
	t.Parallel()
	const bare = "01JZX5N8QW3F4V9T2B7KDFILE00"
	fs := narrowedWriteBackFailuresJSON([]service.WriteBackFailureDTO{{FilePID: bare, Reason: "denied"}, {Reason: "no file"}})
	if fs[0].FilePid != "fl-"+bare || fs[1].FilePid != "" {
		t.Fatalf("failures = %+v, want the file prefixed and the fileless one empty", fs)
	}
	doc := itemMetadataJSON(service.ItemMetadataDTO{WriteBackIssues: []service.WriteBackIssueDTO{{FilePID: bare, Code: "tag-write-unsynced"}}})
	if doc.WriteBackIssues[0].FilePid != "fl-"+bare {
		t.Fatalf("issues = %+v, want the file prefixed", doc.WriteBackIssues)
	}
}

// An item's files are named under the file prefix, and the delete that
// takes them back refuses one without it.
func TestAnItemsFilePIDsWearTheFilePrefix(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	copyFixture(t, h.library, "alpha", filepath.Join(h.library, "copies"))
	h.rescanAndWait(t)
	pid := h.itemTitled(t, h.token, "Alpha Song").Pid
	files := h.itemFiles(t, h.token, pid)
	for _, f := range files {
		if !strings.HasPrefix(f.FilePid, "fl-") {
			t.Fatalf("files = %+v, want every file pid prefixed", files)
		}
	}
	cp := files[len(files)-1]
	dry := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/files/delete",
		map[string]any{"filePids": []string{cp.FilePid}, "dryRun": true}), 200, "plan the copy's delete")
	if len(dry.Entries) != 1 || dry.Entries[0].FileList == nil || (*dry.Entries[0].FileList)[0].FilePid != cp.FilePid {
		t.Fatalf("dry run = %+v, want the copy named by its pid", dry)
	}
	wantStatus(t, h.postJSON(t, "/api/v1/items/"+pid+"/files/delete",
		map[string]any{"filePids": []string{strings.TrimPrefix(cp.FilePid, "fl-")}, "dryRun": true}), 400, "a file pid without its prefix")
}
