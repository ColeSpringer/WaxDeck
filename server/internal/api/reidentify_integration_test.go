package api

import (
	"context"
	"encoding/json"
	"maps"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/match"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// The editable identify query: the typed values reach the engine, the
// stored evidence keeps the files' own tags, and the override lives on
// the entry rather than in one run.

// recordingSource records what it was asked for and answers a fixed
// release, so a test can assert the query rather than the result.
type recordingSource struct {
	mu         sync.Mutex
	recordings []struct{ artist, title string }
	releases   []struct {
		artist, album string
		trackCount    int
	}
	answer []*match.Release
}

func (r *recordingSource) ReleaseByMBID(context.Context, string) (*match.Release, error) {
	return nil, nil
}

func (r *recordingSource) ReleasesByGroup(context.Context, string) ([]*match.Release, error) {
	return nil, nil
}

func (r *recordingSource) LookupFingerprint(context.Context, match.Fingerprint) ([]match.FingerprintHit, error) {
	return nil, nil
}

func (r *recordingSource) SearchReleases(_ context.Context, artist, album string, trackCount int) ([]*match.Release, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.releases = append(r.releases, struct {
		artist, album string
		trackCount    int
	}{artist, album, trackCount})
	return r.answer, nil
}

func (r *recordingSource) SearchRecordings(_ context.Context, artist, title string) ([]*match.Release, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.recordings = append(r.recordings, struct{ artist, title string }{artist, title})
	return r.answer, nil
}

func (r *recordingSource) recorded() (
	[]struct{ artist, title string },
	[]struct {
		artist, album string
		trackCount    int
	},
) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]struct{ artist, title string }{}, r.recordings...),
		append([]struct {
			artist, album string
			trackCount    int
		}{}, r.releases...)
}

func (r *recordingSource) reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.recordings = nil
	r.releases = nil
}

// looseTrack is the acquired-shaped file these tests upload: a channel
// artist and a descriptive title, which is the case the derivation
// misses and a typed query rescues.
func looseTrack(t *testing.T, name string) string {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: name, Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
		Tags: map[string]string{
			"TITLE":  "How Ya Livin' feat. Nas",
			"ARTIST": "Blue Room Records - Topic",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

func reidentifyHarness(t *testing.T, src *recordingSource) *harness {
	t.Helper()
	return newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = src
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
}

func TestReidentifySearchesTheTypedValues(t *testing.T) {
	t.Parallel()
	src := &recordingSource{}
	h := reidentifyHarness(t, src)

	up := uploadDeclaring(t, h, h.token, looseTrack(t, "loose"), nil)
	drainMatches(t, h)
	entryID := *up.ReviewEntryId

	// The derivation reads the descriptive title, which is exactly the
	// query that misses.
	recordings, _ := src.recorded()
	if len(recordings) != 1 || recordings[0].title != "How Ya Livin' feat. Nas" {
		t.Fatalf("first-pass recording searches = %+v", recordings)
	}
	src.reset()

	// The reviewer says what it actually is.
	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{"artist": "Nas", "album": "Stillmatic", "title": "How Ya Livin'"})
	if resp.StatusCode != 200 {
		t.Fatalf("re-identify status = %d", resp.StatusCode)
	}
	if entry := decode[ReviewEntry](t, resp); !entry.Identifying {
		t.Fatal("the re-identified entry should be identifying again")
	}
	drainMatches(t, h)

	recordings, releases := src.recorded()
	if len(releases) != 1 || releases[0].artist != "Nas" || releases[0].album != "Stillmatic" {
		t.Fatalf("release searches = %+v, want one for Nas / Stillmatic", releases)
	}
	// The album path now has something to key on, so the recording
	// search only runs because that path found nothing. Either way, what
	// it asks for must be the typed values.
	for _, r := range recordings {
		if r.artist != "Nas" || r.title != "How Ya Livin'" {
			t.Fatalf("recording search = %+v, want the typed values", r)
		}
	}

	// The stored evidence still reports the files' own tags: an override
	// changes what is searched for, never what the entry says it holds.
	detail := getReview(t, h, entryID)
	if got := detail.Tracks[0].Title; got != "How Ya Livin' feat. Nas" {
		t.Fatalf("stored track title = %q, want the file's own", got)
	}
	if detail.IdentifyOverride == nil || deref(detail.IdentifyOverride.Artist) != "Nas" ||
		deref(detail.IdentifyOverride.Album) != "Stillmatic" ||
		deref(detail.IdentifyOverride.Title) != "How Ya Livin'" {
		t.Fatalf("reported override = %+v", detail.IdentifyOverride)
	}
}

// The overlay writes copies: identifyEntry re-marshals the payload
// after the run, so an in-place one would replace the stored source
// tags with whatever was last searched for.
func TestReidentifyLeavesStoredTagsByteIdentical(t *testing.T) {
	t.Parallel()
	src := &recordingSource{}
	h := reidentifyHarness(t, src)

	up := uploadDeclaring(t, h, h.token, looseTrack(t, "tags"), nil)
	drainMatches(t, h)
	entryID := *up.ReviewEntryId

	before := storedTags(t, h, entryID)
	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{"artist": "Nas", "album": "Stillmatic", "title": "How Ya Livin'"})
	if resp.StatusCode != 200 {
		t.Fatalf("re-identify status = %d", resp.StatusCode)
	}
	drainMatches(t, h)

	after := storedTags(t, h, entryID)
	if !maps.Equal(before, after) {
		t.Fatalf("stored tags changed under an override:\nbefore %v\nafter  %v", before, after)
	}
}

// storedTags reads one entry's first track's tags straight out of the
// stored payload. The read surface strips them deliberately, and it is
// exactly the stripped half this test is about.
func storedTags(t *testing.T, h *harness, entryID string) map[string]string {
	t.Helper()
	row, err := h.store.ReviewEntryByID(context.Background(), entryID)
	if err != nil {
		t.Fatal(err)
	}
	var payload struct {
		Tracks []struct {
			Tags map[string]string `json:"tags"`
		} `json:"tracks"`
	}
	if err := json.Unmarshal([]byte(row.Payload), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Tracks) == 0 {
		t.Fatal("the entry holds no tracks")
	}
	return payload.Tracks[0].Tags
}

func TestReidentifyClearsTheOverrideWithAnEmptyBody(t *testing.T) {
	t.Parallel()
	src := &recordingSource{}
	h := reidentifyHarness(t, src)

	up := uploadDeclaring(t, h, h.token, looseTrack(t, "cleared"), nil)
	drainMatches(t, h)
	entryID := *up.ReviewEntryId

	postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{"artist": "Nas", "title": "How Ya Livin'"}).Body.Close()
	drainMatches(t, h)
	if getReview(t, h, entryID).IdentifyOverride == nil {
		t.Fatal("the override did not store")
	}

	src.reset()
	// Blank fields, not an absent body: both clear, and the whitespace
	// case is the one a text field actually produces.
	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{"artist": "  ", "title": ""})
	if resp.StatusCode != 200 {
		t.Fatalf("clearing status = %d", resp.StatusCode)
	}
	drainMatches(t, h)

	if o := getReview(t, h, entryID).IdentifyOverride; o != nil {
		t.Fatalf("override survived a blank body: %+v", o)
	}
	recordings, _ := src.recorded()
	if len(recordings) == 0 {
		t.Fatal("the cleared run searched for nothing at all")
	}
	for _, r := range recordings {
		if r.title != "How Ya Livin' feat. Nas" {
			t.Fatalf("cleared run searched %+v, want the derivation again", r)
		}
	}
}

func TestReidentifyRefusesADecidedEntry(t *testing.T) {
	t.Parallel()
	src := &recordingSource{}
	h := reidentifyHarness(t, src)

	up := uploadDeclaring(t, h, h.token, looseTrack(t, "decided"), nil)
	drainMatches(t, h)
	entryID := *up.ReviewEntryId

	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/decide",
		map[string]any{"action": "skip"})
	if resp.StatusCode != 200 {
		t.Fatalf("skip status = %d", resp.StatusCode)
	}
	resp = postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{"artist": "Nas"})
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("re-identifying a decided entry = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestReidentifyIsInvisibleToOtherAccounts(t *testing.T) {
	t.Parallel()
	src := &recordingSource{}
	h := reidentifyHarness(t, src)

	up := uploadDeclaring(t, h, h.token, looseTrack(t, "mine"), nil)
	drainMatches(t, h)
	entryID := *up.ReviewEntryId

	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "stranger", "password": "long-enough-pw", "uploadEnabled": true,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	stranger := loginAs(t, h.ts, "stranger", "long-enough-pw").Token

	// Not-found rather than forbidden: an entry somebody else uploaded
	// reads as absent, which is what the rest of the surface answers.
	resp = postJSONAs(t, h, stranger, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{"artist": "Nas"})
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("a stranger's re-identify = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

// A re-identify is a change of mind, so the declined mark must clear.
// Reachable only on a declined submission still pending, which is one
// whose automatic import refused - here, a second copy.
func TestReidentifyClearsTheDeclinedMark(t *testing.T) {
	t.Parallel()
	src := &recordingSource{answer: obviousRelease()}
	h := reidentifyHarness(t, src)

	uploadDeclaring(t, h, h.token, looseTrack(t, "changed-mind"),
		map[string]any{"identify": false})
	up := uploadDeclaring(t, h, h.token, looseTrack(t, "changed-mind"),
		map[string]any{"identify": false})
	entryID := *up.ReviewEntryId
	d := getReview(t, h, entryID)
	if d.Status != "pending" {
		t.Fatalf("the second copy decided itself anyway: %q", d.Status)
	}
	if d.IdentifyDeclined == nil || !*d.IdentifyDeclined {
		t.Fatal("the submission should have declined")
	}

	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify", nil)
	if resp.StatusCode != 200 {
		t.Fatalf("re-identify status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	drainMatches(t, h)

	detail := getReview(t, h, entryID)
	if detail.IdentifyDeclined != nil {
		t.Fatalf("identifyDeclined survived a re-identify: %v", *detail.IdentifyDeclined)
	}
	if len(detail.Candidates) == 0 {
		t.Fatal("the re-identified entry found nothing; the queue was not entered")
	}
}

// A loose acquisition is the shape the parse is built for, so what it
// read is offered rather than making somebody retype what they see.
func TestAcquisitionSuggestsTheParsedQuery(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeAcquireSource{
		playlistURL: "https://tube.example/watch?v=lone",
		files:       map[string]string{},
	}
	paths, err := fixtures.Generate(media,
		fixtures.Spec{Name: "lone", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
			Tags: map[string]string{
				"TITLE":  "Nas - How Ya Livin' (Official Video)",
				"ARTIST": "Blue Room Records - Topic",
			}},
	)
	if err != nil {
		t.Fatal(err)
	}
	src.entries = []struct{ title, url string }{
		{"Nas - How Ya Livin'", "https://tube.example/watch?v=lone"},
	}
	src.files["https://tube.example/watch?v=lone"] = paths[0]

	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &recordingSource{}
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	})

	resp := postJSONAs(t, h, h.token, "/api/v1/acquisitions", map[string]any{
		"url": src.playlistURL, "mediaType": "music",
	})
	if resp.StatusCode != 202 {
		t.Fatalf("acquisition status = %d", resp.StatusCode)
	}
	task := decode[ToolTask](t, resp)
	drainTools(t, h)
	drainMatches(t, h)

	got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token))
	if got.ResultPids == nil || len(*got.ResultPids) != 1 {
		t.Fatalf("acquire task = %+v", got)
	}
	detail := getReview(t, h, (*got.ResultPids)[0])
	if detail.Suggested == nil {
		t.Fatal("a loose acquisition carried no suggestion")
	}
	if a := deref(detail.Suggested.Artist); a != "Nas" {
		t.Fatalf("suggested artist = %q, want the performer out of the title", a)
	}
	if title := deref(detail.Suggested.Title); title != "How Ya Livin'" {
		t.Fatalf("suggested title = %q, want the production note stripped", title)
	}
	if detail.Suggested.Album != nil {
		t.Fatalf("a loose track has no album to suggest; got %q", *detail.Suggested.Album)
	}
	// A suggestion, not a claim: the entry's own track still reports the
	// title the file carries.
	if got := detail.Tracks[0].Title; got != "Nas - How Ya Livin' (Official Video)" {
		t.Fatalf("stored track title = %q, want the file's own", got)
	}
}

// Uploads carry whatever tags the person curating them wrote, so there
// is nothing to guess and nothing is offered.
func TestUploadsCarryNoSuggestion(t *testing.T) {
	t.Parallel()
	h := reidentifyHarness(t, &recordingSource{})
	up := uploadDeclaring(t, h, h.token, looseTrack(t, "no-guess"), nil)
	drainMatches(t, h)
	if s := getReview(t, h, *up.ReviewEntryId).Suggested; s != nil {
		t.Fatalf("an upload was given a suggestion: %+v", s)
	}
}

// Searched as typed: every part of the derivation that helps a
// machine-written title hurts a hand-written one.
func TestReidentifySearchesTypedValuesVerbatim(t *testing.T) {
	t.Parallel()
	src := &recordingSource{}
	h := reidentifyHarness(t, src)

	up := uploadDeclaring(t, h, h.token, looseTrack(t, "verbatim"), nil)
	drainMatches(t, h)
	entryID := *up.ReviewEntryId
	src.reset()

	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{
			"artist": "Benny Goodman",
			"title":  "Sing - Sing - Sing (Official Video)",
		})
	if resp.StatusCode != 200 {
		t.Fatalf("re-identify status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	drainMatches(t, h)

	recordings, _ := src.recorded()
	if len(recordings) == 0 {
		t.Fatal("the override ran no recording search")
	}
	for _, r := range recordings {
		if r.artist != "Benny Goodman" || r.title != "Sing - Sing - Sing (Official Video)" {
			t.Fatalf("recording search = %+v, want the typed values untouched", r)
		}
	}
}

// blockingSource holds the first search open until released, so a test
// can land a re-identify squarely inside the engine call.
type blockingSource struct {
	recordingSource
	entered chan struct{}
	release chan struct{}
	once    sync.Once
}

func (b *blockingSource) SearchRecordings(ctx context.Context, artist, title string) ([]*match.Release, error) {
	b.once.Do(func() {
		close(b.entered)
		<-b.release
	})
	return b.recordingSource.SearchRecordings(ctx, artist, title)
}

// A re-identify landing while the engine works must not be swallowed:
// the worker's full-row write would put its pre-typing payload back.
func TestReidentifyDuringAnInFlightRunIsNotLost(t *testing.T) {
	t.Parallel()
	src := &blockingSource{
		entered: make(chan struct{}),
		release: make(chan struct{}),
	}
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = src
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})

	up := uploadDeclaring(t, h, h.token, looseTrack(t, "in-flight"), nil)
	entryID := *up.ReviewEntryId

	// Drain on a goroutine of its own so the first run can park inside
	// the source while the test keeps working. No t.Fatal in here: that
	// is the test goroutine's alone.
	drained := make(chan struct{})
	go func() {
		defer close(drained)
		for l := 0; l < 100 && h.svc.DrainMatchQueue(context.Background()); l++ {
		}
	}()
	select {
	case <-src.entered:
	case <-time.After(20 * time.Second):
		t.Fatal("the identify worker never reached the source")
	}

	// Type a search while it is parked, then let the old run finish.
	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{"artist": "Nas", "title": "How Ya Livin'"})
	if resp.StatusCode != 200 {
		t.Fatalf("re-identify status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	close(src.release)
	select {
	case <-drained:
	case <-time.After(30 * time.Second):
		t.Fatal("the identify worker did not drain")
	}

	// The typed search survived, and it actually ran: the superseded
	// job retires and the new query takes its place, rather than the
	// entry being left identifying forever with nothing queued.
	detail := getReview(t, h, entryID)
	if detail.IdentifyOverride == nil || deref(detail.IdentifyOverride.Artist) != "Nas" {
		t.Fatalf("the typed search was lost: %+v", detail.IdentifyOverride)
	}
	if detail.Identifying {
		t.Fatal("the entry is still identifying; the superseded job was not re-queued")
	}
	recordings, _ := src.recorded()
	searchedTyped := false
	for _, r := range recordings {
		if r.artist == "Nas" {
			searchedTyped = true
		}
	}
	if !searchedTyped {
		t.Fatalf("the new query never reached the source: %+v", recordings)
	}
}

// A title names one track: on a unit of several the server ignores it,
// because scoring pairs files to release tracks by title.
func TestReidentifyIgnoresATrackTitleOnAMultiFileUnit(t *testing.T) {
	t.Parallel()
	src := &recordingSource{}
	h := reidentifyHarness(t, src)

	media := t.TempDir()
	paths, err := fixtures.Generate(media,
		batchTrackSpec("a", "Opening Tide", "Signal Test", "Cardinal Waves", "1", 3),
		batchTrackSpec("b", "Closing Tide", "Signal Test", "Cardinal Waves", "2", 4),
	)
	if err != nil {
		t.Fatal(err)
	}
	batch := createBatch(t, h, h.token, "album", "music")
	uploadBatchMember(t, h, h.token, paths[0], "music", batch.Id, "")
	uploadBatchMember(t, h, h.token, paths[1], "music", batch.Id, "")
	final := finalizeBatch(t, h, h.token, batch.Id)
	drainMatches(t, h)
	if len(final.ReviewEntryIds) != 1 {
		t.Fatalf("finalize opened %d entries, want one album", len(final.ReviewEntryIds))
	}
	entryID := final.ReviewEntryIds[0]
	src.reset()

	resp := postJSONAs(t, h, h.token, "/api/v1/review/queue/"+entryID+"/identify",
		map[string]any{
			"artist": "Cardinal Waves",
			"album":  "Neon Meridian",
			"title":  "Opening Tide",
		})
	if resp.StatusCode != 200 {
		t.Fatalf("re-identify status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	drainMatches(t, h)

	// The unit-wide corrections land.
	_, releases := src.recorded()
	if len(releases) == 0 || releases[0].album != "Neon Meridian" ||
		releases[0].artist != "Cardinal Waves" {
		t.Fatalf("release searches = %+v, want the typed artist and album", releases)
	}

	// The album search answered nothing, so the recording search runs
	// too - and each file must still key on its own title rather than
	// on one shared typed one.
	recordings, _ := src.recorded()
	if len(recordings) < 2 {
		t.Fatalf("recording searches = %+v, want one per file", recordings)
	}
	titles := map[string]bool{}
	for _, r := range recordings {
		titles[r.title] = true
	}
	if len(titles) != 2 || !titles["Opening Tide"] || !titles["Closing Tide"] {
		t.Fatalf("recording searches = %+v, want each file's own title", recordings)
	}
}
