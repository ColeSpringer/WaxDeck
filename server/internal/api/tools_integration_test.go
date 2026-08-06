package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// fakeToolJobStore is the fake sidecar's merge and split surface: it
// accepts the job bodies the bridge posts, synthesizes real audio for
// each output through the fixtures package, and serves the job document
// and result downloads. Analyze jobs are not its business and fall
// through to the static handling in newFakeFlowBridge.
type fakeToolJobStore struct {
	t   *testing.T
	dir string
	lib string

	mu   sync.Mutex
	seq  int
	jobs map[string][][]byte
}

func newFakeToolJobStore(t *testing.T, libraryDir string) *fakeToolJobStore {
	return &fakeToolJobStore{t: t, dir: t.TempDir(), lib: libraryDir, jobs: map[string][][]byte{}}
}

// handle serves the store's routes; false means the request belongs to
// the static fake.
func (s *fakeToolJobStore) handle(w http.ResponseWriter, r *http.Request) bool {
	if r.URL.Path == "/jobs" && r.Method == http.MethodPost {
		var req struct {
			Type   string   `json:"type"`
			Srcs   []string `json:"srcs"`
			Titles []string `json:"titles"`
			Format string   `json:"format"`
			Src    string   `json:"src"`
			Cuts   []int64  `json:"cuts"`
			Cue    string   `json:"cue"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			return false
		}
		switch req.Type {
		case "merge":
			s.createMerge(w, req.Srcs, req.Titles)
			return true
		case "split":
			s.createSplit(w, req.Format, req.Cuts, req.Cue)
			return true
		}
		return false
	}
	rest, ok := strings.CutPrefix(r.URL.Path, "/jobs/")
	if !ok {
		return false
	}
	id, tail, _ := strings.Cut(rest, "/")
	s.mu.Lock()
	outs, known := s.jobs[id]
	s.mu.Unlock()
	if !known {
		return false
	}
	switch {
	case tail == "":
		files := make([]map[string]any, 0, len(outs))
		for i, o := range outs {
			files = append(files, map[string]any{"file": fmt.Sprintf("out-%d", i), "bytes": len(o)})
		}
		json.NewEncoder(w).Encode(map[string]any{
			"schemaVersion": 2, "id": id, "state": "done",
			"progress": map[string]any{"percent": 100.0},
			"outputs":  files,
		})
		return true
	case strings.HasPrefix(tail, "result/"):
		idx, err := strconv.Atoi(strings.TrimPrefix(tail, "result/"))
		if err != nil || idx < 0 || idx >= len(outs) {
			http.NotFound(w, r)
			return true
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Content-Length", strconv.Itoa(len(outs[idx])))
		w.Write(outs[idx])
		return true
	}
	return false
}

func (s *fakeToolJobStore) nextID() (string, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	return fmt.Sprintf("tj%d", s.seq), s.seq
}

func (s *fakeToolJobStore) createMerge(w http.ResponseWriter, srcs, titles []string) {
	id, n := s.nextID()
	members := len(srcs)
	if members == 0 {
		http.Error(w, `{"code":"invalid-request","message":"srcs required"}`, http.StatusBadRequest)
		return
	}
	// Durations vary per job so no two fake outputs (or any library
	// fixture) share an audio essence.
	total := 8*time.Second + time.Duration(n)*90*time.Millisecond
	per := total / time.Duration(members)
	chapters := make([]fixtures.Chapter, 0, members)
	for i := 0; i < members; i++ {
		title := fmt.Sprintf("Chapter %d", i+1)
		if i < len(titles) && titles[i] != "" {
			title = titles[i]
		}
		chapters = append(chapters, fixtures.Chapter{
			Start: time.Duration(i) * per, End: time.Duration(i+1) * per, Title: title,
		})
	}
	data := s.render(fixtures.Spec{
		Name: "merge-" + id, Codec: fixtures.CodecAAC, Container: fixtures.ContainerMP4,
		Duration: total, Chapters: chapters,
	})
	s.finish(w, id, [][]byte{data})
}

func (s *fakeToolJobStore) createSplit(w http.ResponseWriter, format string, cuts []int64, cue string) {
	pieces := len(cuts) + 1
	if cue != "" {
		rel, ok := strings.CutPrefix(cue, "lib/")
		if !ok {
			http.Error(w, `{"code":"invalid-request","message":"bad cue ref"}`, http.StatusBadRequest)
			return
		}
		raw, err := os.ReadFile(filepath.Join(s.lib, filepath.FromSlash(rel)))
		if err != nil {
			http.Error(w, `{"code":"not-found","message":"cue sheet not found"}`, http.StatusBadRequest)
			return
		}
		pieces = strings.Count(string(raw), "TRACK ")
		if pieces == 0 {
			http.Error(w, `{"code":"invalid-request","message":"cue names no tracks"}`, http.StatusBadRequest)
			return
		}
	}
	id, n := s.nextID()
	codec, container := fixtures.CodecFLAC, fixtures.ContainerDefault
	switch format {
	case "aac":
		codec, container = fixtures.CodecAAC, fixtures.ContainerMP4
	case "mp3":
		codec, container = fixtures.CodecMP3, fixtures.ContainerDefault
	}
	outs := make([][]byte, 0, pieces)
	for i := 0; i < pieces; i++ {
		d := time.Duration(i+1)*1100*time.Millisecond + time.Duration(n)*70*time.Millisecond
		if d > 9500*time.Millisecond {
			d = 9500 * time.Millisecond
		}
		outs = append(outs, s.render(fixtures.Spec{
			Name: fmt.Sprintf("split-%s-%d", id, i), Codec: codec, Container: container, Duration: d,
		}))
	}
	s.finish(w, id, outs)
}

// render synthesizes one spec and returns its bytes; nil reports a
// failure (already recorded on t, never fatally: this runs on the fake
// server's goroutines).
func (s *fakeToolJobStore) render(spec fixtures.Spec) []byte {
	paths, err := fixtures.Generate(s.dir, spec)
	if err != nil {
		s.t.Errorf("fake tool job fixture: %v", err)
		return nil
	}
	data, err := os.ReadFile(paths[len(paths)-1])
	if err != nil {
		s.t.Errorf("fake tool job fixture read: %v", err)
		return nil
	}
	return data
}

func (s *fakeToolJobStore) finish(w http.ResponseWriter, id string, outs [][]byte) {
	for _, o := range outs {
		if o == nil {
			http.Error(w, `{"code":"internal","message":"fixture render failed"}`, http.StatusInternalServerError)
			return
		}
	}
	s.mu.Lock()
	s.jobs[id] = outs
	s.mu.Unlock()
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{"schemaVersion": 2, "id": id, "state": "queued"})
}

// newToolHarness is the standard harness with its library root managed,
// which the re-import side of every tool task needs.
func newToolHarness(t *testing.T) *harness {
	t.Helper()
	return newHarnessWith(t, func(cfg *service.Config) {
		cfg.Roots[0].Managed = true
	})
}

// drainToolTasks drives the tool worker the way main's supervised
// ticker would, until the queue reports idle.
func drainToolTasks(t *testing.T, h *harness) {
	t.Helper()
	deadline := time.Now().Add(90 * time.Second)
	for h.svc.DrainToolTasks(context.Background()) {
		if time.Now().After(deadline) {
			t.Fatal("tool tasks did not drain in time")
		}
	}
}

func (h *harness) toolTask(t *testing.T, id string) ToolTask {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/tools/tasks/"+id, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("get task status = %d", resp.StatusCode)
	}
	return decode[ToolTask](t, resp)
}

func TestBookMergeEndToEnd(t *testing.T) {
	h := newToolHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want 1", len(books.Items))
	}
	book := books.Items[0]

	// A mid-book resume point that must survive the merge unchanged:
	// multi-file book positions are book-timeline milliseconds already.
	resp := h.putJSON(t, "/api/v1/items/"+book.Pid+"/play-state", map[string]any{"positionMs": 4200})
	if resp.StatusCode != 200 && resp.StatusCode != 204 {
		t.Fatalf("checkpoint status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	resp = h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{
		"titles": []string{"One", "Two", "Three"},
	})
	if resp.StatusCode != 202 {
		t.Fatalf("merge status = %d", resp.StatusCode)
	}
	task := decode[ToolTask](t, resp)
	if !strings.HasPrefix(task.Id, "tk-") || task.Type != "book-merge" || task.State != "queued" {
		t.Fatalf("queued task = %+v", task)
	}

	drainToolTasks(t, h)
	done := h.toolTask(t, task.Id)
	if done.State != "done" {
		t.Fatalf("task state = %s (error: %v)", done.State, deref(done.Error))
	}
	if done.ResultPids == nil || len(*done.ResultPids) != 1 {
		t.Fatalf("resultPids = %v, want one", done.ResultPids)
	}
	newPid := (*done.ResultPids)[0]
	if !strings.HasPrefix(newPid, "bk-") {
		t.Fatalf("result pid = %q", newPid)
	}

	// The merged file replaces the parts. The catalog resolves the
	// import by the book's identity key, so the logical book (and its
	// pid) survives the merge; what changes is its shape: one backing
	// file where there were three, and chapter marks where there were
	// none.
	books = h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 || books.Items[0].Pid != newPid {
		t.Fatalf("post-merge audiobooks = %+v, want just %s", books.Items, newPid)
	}
	resp = get(t, h.ts, "/api/v1/books/"+newPid, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("book detail status = %d", resp.StatusCode)
	}
	detail := decode[BookDetail](t, resp)
	if len(detail.Parts) != 1 {
		t.Fatalf("merged parts = %d, want 1", len(detail.Parts))
	}
	if len(detail.Chapters) != 3 {
		t.Fatalf("merged chapters = %d, want 3", len(detail.Chapters))
	}
	if deref(detail.Chapters[0].Title) != "One" || deref(detail.Chapters[2].Title) != "Three" {
		t.Fatalf("chapter titles = %+v", detail.Chapters)
	}

	// The resume position carried over onto the merged timeline.
	resp = get(t, h.ts, "/api/v1/items/"+newPid+"/play-state", h.token)
	st := decode[PlayState](t, resp)
	if st.PositionMs != 4200 {
		t.Fatalf("carried position = %d, want 4200", st.PositionMs)
	}

	// A single-file book refuses to merge.
	resp = h.postJSON(t, "/api/v1/books/"+newPid+"/merge", map[string]any{})
	if resp.StatusCode != 409 {
		t.Fatalf("single-file merge status = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

	// The tooling is an administrator surface.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)
	resp = putJSON(t, h.ts, "/api/v1/items/"+newPid+"/play-state", sam.Token, map[string]any{"positionMs": 1})
	resp.Body.Close()
	resp = postJSON(t, h.ts.URL+"/api/v1/books/"+newPid+"/merge", sam.Token, `{}`)
	if resp.StatusCode != 403 {
		t.Fatalf("non-admin merge status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()

	// Task visibility: the admin's task log lists it; sam sees neither
	// the listing entry nor the task itself.
	resp = get(t, h.ts, "/api/v1/tools/tasks", h.token)
	page := decode[ToolTaskPage](t, resp)
	if len(page.Tasks) != 1 || page.Tasks[0].Id != task.Id {
		t.Fatalf("admin task log = %+v", page.Tasks)
	}
	resp = get(t, h.ts, "/api/v1/tools/tasks", sam.Token)
	if p := decode[ToolTaskPage](t, resp); len(p.Tasks) != 0 {
		t.Fatalf("sam task log = %+v, want empty", p.Tasks)
	}
	resp = get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, sam.Token)
	if resp.StatusCode != 404 {
		t.Fatalf("sam task read status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestBookSplitEndToEnd(t *testing.T) {
	h := newToolHarness(t)
	if _, err := fixtures.GenerateChapteredBook(h.library); err != nil {
		t.Fatal(err)
	}
	// A chapterless single-file book for the conflict case: an MP4/AAC
	// fixture renamed to the .m4b extension that classifies it.
	plainDir := filepath.Join(h.library, "Plain Author", "Plain Book")
	paths, err := fixtures.Generate(plainDir, fixtures.Spec{
		Name: "Plain Book", Codec: fixtures.CodecAAC, Container: fixtures.ContainerMP4,
		Duration: 9 * time.Second,
		Tags: map[string]string{
			"TITLE": "Plain Book", "ALBUM": "Plain Book",
			"ARTIST": "Plain Author", "ALBUMARTIST": "Plain Author",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	plain := strings.TrimSuffix(paths[0], filepath.Ext(paths[0])) + ".m4b"
	if err := os.Rename(paths[0], plain); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	books := h.items(t, "?mediaType=audiobook")
	var chaptered, chapterless string
	for _, it := range books.Items {
		switch it.Title {
		case "The Chaptered Fixture":
			chaptered = it.Pid
		case "Plain Book":
			chapterless = it.Pid
		}
	}
	if chaptered == "" || chapterless == "" {
		t.Fatalf("books = %+v", books.Items)
	}

	// A book without chapters answers conflict.
	resp := h.postJSON(t, "/api/v1/books/"+chapterless+"/split", map[string]any{})
	if resp.StatusCode != 409 {
		t.Fatalf("chapterless split status = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

	resp = h.putJSON(t, "/api/v1/items/"+chaptered+"/play-state", map[string]any{"positionMs": 3000})
	if resp.StatusCode != 200 && resp.StatusCode != 204 {
		t.Fatalf("checkpoint status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	resp = h.postJSON(t, "/api/v1/books/"+chaptered+"/split", map[string]any{})
	if resp.StatusCode != 202 {
		t.Fatalf("split status = %d", resp.StatusCode)
	}
	task := decode[ToolTask](t, resp)
	if task.Type != "book-split" {
		t.Fatalf("task = %+v", task)
	}

	drainToolTasks(t, h)
	done := h.toolTask(t, task.Id)
	if done.State != "done" {
		t.Fatalf("task state = %s (error: %v)", done.State, deref(done.Error))
	}
	if done.ResultPids == nil || len(*done.ResultPids) == 0 {
		t.Fatal("split produced no result pids")
	}
	newPid := (*done.ResultPids)[0]
	if !strings.HasPrefix(newPid, "bk-") {
		t.Fatalf("result pid = %q", newPid)
	}

	// The pieces re-imported as one multi-file book. The identity key
	// keeps the logical book stable across the split, so the proof is
	// its new shape: three backing parts where there was one file.
	books = h.items(t, "?mediaType=audiobook")
	pids := map[string]bool{}
	for _, it := range books.Items {
		pids[it.Pid] = true
	}
	if !pids[newPid] {
		t.Fatalf("post-split audiobooks = %+v", books.Items)
	}
	resp = get(t, h.ts, "/api/v1/books/"+newPid, h.token)
	detail := decode[BookDetail](t, resp)
	if len(detail.Parts) != 3 {
		t.Fatalf("split parts = %d, want 3 (one per chapter)", len(detail.Parts))
	}

	// The old single-file position is the same book-timeline number on
	// the new multi-file book.
	resp = get(t, h.ts, "/api/v1/items/"+newPid+"/play-state", h.token)
	st := decode[PlayState](t, resp)
	if st.PositionMs != 3000 {
		t.Fatalf("carried position = %d, want 3000", st.PositionMs)
	}
}

func TestCueSplitEndToEnd(t *testing.T) {
	h := newToolHarness(t)
	ripDir := filepath.Join(h.library, "Cue Artist", "Cue Album")
	if _, err := fixtures.Generate(ripDir, fixtures.Spec{
		Name: "Cue Album", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{
			"TITLE": "Cue Album", "ALBUM": "Cue Album",
			"ARTIST": "Cue Artist", "ALBUMARTIST": "Cue Artist",
		},
	}); err != nil {
		t.Fatal(err)
	}
	sheet := "PERFORMER \"Cue Artist\"\n" +
		"TITLE \"Cue Album\"\n" +
		"FILE \"Cue Album.flac\" WAVE\n" +
		"  TRACK 01 AUDIO\n" +
		"    TITLE \"Cue One\"\n" +
		"    PERFORMER \"Cue Artist\"\n" +
		"    INDEX 01 00:00:00\n" +
		"  TRACK 02 AUDIO\n" +
		"    TITLE \"Cue Two\"\n" +
		"    PERFORMER \"Cue Artist\"\n" +
		"    INDEX 01 00:03:00\n"
	if err := os.WriteFile(filepath.Join(ripDir, "Cue Album.cue"), []byte(sheet), 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	byTitle := map[string]ItemSummary{}
	for _, it := range h.items(t, "?mediaType=music").Items {
		byTitle[it.Title] = it
	}
	one, okOne := byTitle["Cue One"]
	two, okTwo := byTitle["Cue Two"]
	if !okOne || !okTwo {
		t.Fatalf("virtual cue tracks missing from the scan: %v", byTitle)
	}

	// A non-virtual track refuses the cue split.
	resp := h.postJSON(t, "/api/v1/items/"+byTitle["Alpha Song"].Pid+"/split-cue", map[string]any{})
	if resp.StatusCode != 409 {
		t.Fatalf("whole-file split-cue status = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

	// Track-level play state that must land on the matching piece.
	resp = h.putJSON(t, "/api/v1/items/"+two.Pid+"/play-state", map[string]any{"positionMs": 1500})
	if resp.StatusCode != 200 && resp.StatusCode != 204 {
		t.Fatalf("checkpoint status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	resp = h.postJSON(t, "/api/v1/items/"+one.Pid+"/split-cue", map[string]any{})
	if resp.StatusCode != 202 {
		t.Fatalf("split-cue status = %d", resp.StatusCode)
	}
	task := decode[ToolTask](t, resp)
	if task.Type != "cue-split" {
		t.Fatalf("task = %+v", task)
	}

	drainToolTasks(t, h)
	done := h.toolTask(t, task.Id)
	if done.State != "done" {
		t.Fatalf("task state = %s (error: %v)", done.State, deref(done.Error))
	}
	if done.ResultPids == nil || len(*done.ResultPids) != 2 {
		t.Fatalf("resultPids = %v, want two", done.ResultPids)
	}

	// The real files replaced the virtual carvings under the same titles,
	// the carvings left the listing, and per-track play state followed
	// each piece.
	//
	// Polled, because the task reporting done is not the listing carrying
	// the replacements: the drain returns when there is no more work, and
	// this read has come back without them. Asked by pid rather than by
	// title, because both pairs answer to the same two titles and the
	// swap is the whole question. resultPids are in sibling order, so [1]
	// is Cue Two's replacement.
	pieces := *done.ResultPids
	listed := map[string]ItemSummary{}
	deadline := time.Now().Add(30 * time.Second)
	for {
		listed = map[string]ItemSummary{}
		for _, it := range h.items(t, "?mediaType=music").Items {
			listed[it.Pid] = it
		}
		_, gotOne := listed[pieces[0]]
		_, gotTwo := listed[pieces[1]]
		_, keptOne := listed[one.Pid]
		_, keptTwo := listed[two.Pid]
		if gotOne && gotTwo && !keptOne && !keptTwo {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("split pieces %v never replaced the carvings %v in the listing: %v",
				pieces, []string{one.Pid, two.Pid}, listed)
		}
		time.Sleep(100 * time.Millisecond)
	}
	if got, want := listed[pieces[0]].Title, "Cue One"; got != want {
		t.Fatalf("piece %s title = %q, want %q", pieces[0], got, want)
	}
	if got, want := listed[pieces[1]].Title, "Cue Two"; got != want {
		t.Fatalf("piece %s title = %q, want %q", pieces[1], got, want)
	}

	// The carvings were retired: the shared rip is in the trash, which is
	// the one surface that does still name them (ADR-0048).
	trash := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
	retired := false
	for _, e := range trash {
		if strings.HasSuffix(e.Name, "Cue Album.flac") {
			retired = true
		}
	}
	if !retired {
		t.Fatalf("the shared rip was not trashed: %+v", trash)
	}

	resp = get(t, h.ts, "/api/v1/items/"+pieces[1]+"/play-state", h.token)
	st := decode[PlayState](t, resp)
	if st.PositionMs != 1500 {
		t.Fatalf("carried position = %d, want 1500", st.PositionMs)
	}

	// The rip and its sheet are gone from the album directory.
	entries, err := os.ReadDir(ripDir)
	if err == nil {
		for _, e := range entries {
			ext := strings.ToLower(filepath.Ext(e.Name()))
			if ext == ".cue" {
				t.Fatalf("cue sheet survived: %s", e.Name())
			}
		}
	}
}

func TestToolTaskDeleteAndClear(t *testing.T) {
	h := newHarnessDirect(t)
	ctx := context.Background()

	resp := get(t, h.ts, "/api/v1/auth/session", h.token)
	me := decode[SessionInfo](t, resp)
	if me.User == nil {
		t.Fatal("no session user")
	}

	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	seed := func(id, owner, state string) {
		t.Helper()
		if err := h.store.InsertToolTask(ctx, wdb.ToolTask{
			ID: id, Type: "acquire", State: state, UserID: owner,
			Params: "{}", ResultPIDs: "[]", CreatedAtNS: time.Now().UnixNano(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	const (
		adminDone = "tk-01JZX5N8QW3F4V9T2B7KDAD0NE"
		adminRun  = "tk-01JZX5N8QW3F4V9T2B7KDADRN1"
		samDone   = "tk-01JZX5N8QW3F4V9T2B7KDSMD0N"
	)
	seed(adminDone, me.User.Id, "done")
	seed(adminRun, me.User.Id, "running")
	seed(samDone, sam.User.Id, "done")

	// A non-admin cannot delete a row that is not theirs, and learns
	// nothing from trying: the answer is the read's.
	resp = reqAs(t, h, "DELETE", "/api/v1/tools/tasks/"+adminDone, sam.Token, nil)
	if resp.StatusCode != 404 {
		t.Fatalf("sam deleting admin task status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()

	// A task still running refuses: deleting a row out from under a
	// worker leases nothing back.
	resp = reqAs(t, h, "DELETE", "/api/v1/tools/tasks/"+adminRun, h.token, nil)
	if resp.StatusCode != 409 {
		t.Fatalf("running delete status = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

	// The owner deletes a finished row, and it is gone from the read.
	resp = reqAs(t, h, "DELETE", "/api/v1/tools/tasks/"+adminDone, h.token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("own delete status = %d, want 204", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/tools/tasks/"+adminDone, h.token)
	if resp.StatusCode != 404 {
		t.Fatalf("deleted task read status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()

	// An administrator may delete any finished row the listing shows.
	resp = reqAs(t, h, "DELETE", "/api/v1/tools/tasks/"+samDone, h.token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("admin deleting sam's task status = %d, want 204", resp.StatusCode)
	}
	resp.Body.Close()

	// A non-admin's sweep takes their own finished rows and nobody
	// else's; the admin's failed row survives it.
	seed("tk-01JZX5N8QW3F4V9T2B7KDADFL1", me.User.Id, "failed")
	seed("tk-01JZX5N8QW3F4V9T2B7KDSMD02", sam.User.Id, "done")
	resp = reqAs(t, h, "POST", "/api/v1/tools/tasks/clear-finished", sam.Token, nil)
	if got := decode[ToolTasksCleared](t, resp); got.Deleted != 1 {
		t.Fatalf("sam clear deleted = %d, want 1", got.Deleted)
	}
	page := decode[ToolTaskPage](t, get(t, h.ts, "/api/v1/tools/tasks", sam.Token))
	if len(page.Tasks) != 0 {
		t.Fatalf("sam's log after clear = %+v, want empty", page.Tasks)
	}

	// An administrator's sweep is as wide as the listing and the
	// per-row delete: everyone's finished rows go, the running one
	// stays.
	seed("tk-01JZX5N8QW3F4V9T2B7KDSMD03", sam.User.Id, "done")
	resp = reqAs(t, h, "POST", "/api/v1/tools/tasks/clear-finished", h.token, nil)
	if resp.StatusCode != 200 {
		t.Fatalf("clear status = %d", resp.StatusCode)
	}
	cleared := decode[ToolTasksCleared](t, resp)
	if cleared.Deleted != 2 {
		t.Fatalf("admin clear deleted = %d, want 2 (own failed + sam's done)", cleared.Deleted)
	}
	page = decode[ToolTaskPage](t, get(t, h.ts, "/api/v1/tools/tasks", h.token))
	ids := map[string]bool{}
	for _, task := range page.Tasks {
		ids[task.Id] = true
	}
	if len(ids) != 1 || !ids[adminRun] {
		t.Fatalf("after admin clear, tasks = %v", ids)
	}
}

func TestToolsUnavailableWithoutEngine(t *testing.T) {
	h := newHarnessDirect(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	book := h.items(t, "?mediaType=audiobook").Items[0]
	track := h.items(t, "?mediaType=music").Items[0]

	for _, path := range []string{
		"/api/v1/books/" + book.Pid + "/merge",
		"/api/v1/books/" + book.Pid + "/split",
		"/api/v1/items/" + track.Pid + "/split-cue",
	} {
		resp := h.postJSON(t, path, map[string]any{})
		if resp.StatusCode != 501 {
			t.Fatalf("%s status = %d, want 501", path, resp.StatusCode)
		}
		e := decode[Error](t, resp)
		if e.Code != "feature-unavailable" {
			t.Fatalf("%s error code = %q", path, e.Code)
		}
	}

	// The task log still answers, empty.
	resp := get(t, h.ts, "/api/v1/tools/tasks", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("task log status = %d", resp.StatusCode)
	}
	if page := decode[ToolTaskPage](t, resp); len(page.Tasks) != 0 {
		t.Fatalf("task log = %+v, want empty", page.Tasks)
	}
}
