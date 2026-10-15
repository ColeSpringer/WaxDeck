package api

import (
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxlabel/tag"
)

// alphaFile is the demo library's Alpha Song and its file.
func (h *harness) alphaFile(t *testing.T) (string, string) {
	t.Helper()
	pid := h.itemTitled(t, h.token, "Alpha Song").Pid
	return pid, *h.itemFiles(t, h.token, pid)[0].Path
}

// A custom tag set with writeBack reaches the file, and a clear with it
// strips it; a key the writer would store as another field refuses.
func TestACustomTagWithWriteBackReachesTheFile(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid, path := h.alphaFile(t)

	res := decodeStatus[TagEditResult](t, h.putJSON(t, "/api/v1/items/"+pid+"/tags/MOOD",
		map[string]any{"values": []string{"calm"}, "writeBack": true}), 200, "set MOOD")
	if res.Key != "MOOD" || res.WriteBackFailures != nil {
		t.Fatalf("result = %+v, want MOOD stored and written", res)
	}
	if got := tagOnDisk(t, path, tag.Key("MOOD")); got != "calm" {
		t.Fatalf("MOOD on disk = %q, want calm", got)
	}
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+pid+"/tags/YEAR",
		map[string]any{"values": []string{"1999"}, "writeBack": true}), 400, "YEAR with writeBack")

	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/items/"+pid+"/tags/MOOD?writeBack=true", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	wantStatus(t, resp, 204, "clear MOOD")
	if got := tagOnDisk(t, path, tag.Key("MOOD")); got != "" {
		t.Fatalf("MOOD on disk after the clear = %q, want none", got)
	}
}

// The release status and a draft's custom tags ride its writeBack.
func TestMetadataCommitWritesBackTagSetsAndReleaseStatus(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid, path := h.alphaFile(t)
	res := decodeStatus[MetadataCommitResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/metadata/commit", map[string]any{
		"tagSets": map[string][]string{"MOOD": {"bright"}}, "unofficial": true, "writeBack": true,
	}), 200, "commit")
	if res.WriteBackFailures != nil {
		t.Fatalf("commit = %+v, want every part written", res)
	}
	if got := tagOnDisk(t, path, tag.Key("MOOD")); got != "bright" {
		t.Fatalf("MOOD on disk = %q, want bright", got)
	}
	if got := tagOnDisk(t, path, tag.Key("RELEASESTATUS")); got != "unofficial" {
		t.Fatalf("release status on disk = %q, want unofficial", got)
	}
	decodeStatus[MetadataEditResult](t, h.putJSON(t, "/api/v1/items/"+pid+"/release-status",
		map[string]any{"unofficial": false, "writeBack": true}), 200, "clear the mark")
	if got := tagOnDisk(t, path, tag.Key("RELEASESTATUS")); got != "" {
		t.Fatalf("release status on disk after the clear = %q, want none", got)
	}
}

// Lyrics set with writeBack land in a sidecar that takes its audio's
// mode, and a clear with writeBack removes it, so a rescan cannot bring
// the lyrics back.
func TestClearingLyricsWithWriteBackRemovesTheSidecar(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid, path := h.alphaFile(t)
	if err := os.Chmod(path, 0o664); err != nil {
		t.Fatal(err)
	}
	decodeStatus[MetadataEditResult](t, h.putJSON(t, "/api/v1/items/"+pid+"/lyrics", map[string]any{
		"lrc": "[00:00.50]First line\n", "writeBack": true,
	}), 200, "set lyrics")
	sidecar := strings.TrimSuffix(path, filepath.Ext(path)) + ".lrc"
	st, err := os.Stat(sidecar)
	if err != nil {
		t.Fatalf("no sidecar written: %v", err)
	}
	if runtime.GOOS != "windows" && st.Mode().Perm() != 0o664 {
		t.Fatalf("sidecar mode = %v, want its audio's 0664", st.Mode().Perm())
	}

	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/items/"+pid+"/lyrics?writeBack=true", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	wantStatus(t, resp, 204, "clear lyrics")
	if _, err := os.Stat(sidecar); !os.IsNotExist(err) {
		t.Fatalf("sidecar still there (%v)", err)
	}
	h.rescanAndWaitWith(t, `{"force": true}`)
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+pid+"/lyrics", h.token), 404, "lyrics after a forced rescan")
}

// clearLyricsWritingBack clears an item's lyrics with writeBack.
func (h *harness) clearLyricsWritingBack(t *testing.T, pid string) {
	t.Helper()
	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/items/"+pid+"/lyrics?writeBack=true", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	wantStatus(t, resp, 204, "clear lyrics")
}

// A sidecar another audio file of the same name reads is that file's
// too, so clearing one item's lyrics leaves it; one only the item's own
// encodings share goes.
func TestClearingLyricsLeavesASidecarAnotherFileShares(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid, path := h.alphaFile(t)
	decodeStatus[MetadataEditResult](t, h.putJSON(t, "/api/v1/items/"+pid+"/lyrics", map[string]any{
		"lrc": "[00:00.50]First line\n", "writeBack": true,
	}), 200, "set lyrics")
	sidecar := strings.TrimSuffix(path, filepath.Ext(path)) + ".lrc"
	if _, err := fixtures.Generate(filepath.Dir(path), fixtures.Spec{
		Name: strings.TrimSuffix(filepath.Base(path), filepath.Ext(path)), Codec: fixtures.CodecMP3,
		Duration: 4 * time.Second, Tags: map[string]string{"TITLE": "Another Alpha"},
	}); err != nil {
		t.Fatal(err)
	}
	h.clearLyricsWritingBack(t, pid)
	if _, err := os.Stat(sidecar); err != nil {
		t.Fatalf("the shared sidecar went: %v", err)
	}

	both := twoEncodings(t, h)
	decodeStatus[MetadataEditResult](t, h.putJSON(t, "/api/v1/items/"+both+"/lyrics", map[string]any{
		"lrc": "[00:00.50]Both ways\n", "writeBack": true,
	}), 200, "set lyrics on two encodings")
	own := strings.TrimSuffix(*h.itemFiles(t, h.token, both)[0].Path, filepath.Ext(*h.itemFiles(t, h.token, both)[0].Path)) + ".lrc"
	if _, err := os.Stat(own); err != nil {
		t.Fatalf("no sidecar written: %v", err)
	}
	h.clearLyricsWritingBack(t, both)
	if _, err := os.Stat(own); !os.IsNotExist(err) {
		t.Fatalf("the item's own sidecar stayed (%v)", err)
	}
}
