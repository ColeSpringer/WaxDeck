package service

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"testing"

	"github.com/colespringer/waxbin/model"
)

func TestIdentifierValidators(t *testing.T) {
	t.Parallel()
	cases := []struct {
		field, value string
		ok           bool
	}{
		{"isrc", "USRC17607839", true},
		{"isrc", "usrc17607839", true},
		{"isrc", "US1AB2345678", true},  // registrant codes may carry digits
		{"isrc", "U51AB2345678", false}, // digit in the country code
		{"isrc", "USRC1760783", false},  // 11 chars
		{"isrc", "USRC1760783X", false}, // letter in the digit block
		{"isbn", "0306406152", true},
		{"isbn", "0-306-40615-2", true},
		{"isbn", "080442957X", true},
		{"isbn", "0306406153", false}, // bad ISBN-10 checksum
		{"isbn", "9780306406157", true},
		{"isbn", "978-0-306-40615-7", true},
		{"isbn", "9780306406158", false}, // bad ISBN-13 checksum
		{"isbn", "12345", false},
		{"asin", "B000002L5R", true},
		{"asin", "B000002L5", false},   // 9 chars
		{"asin", "B000002L5R2", false}, // 11 chars
		{"barcode", "12345670", true},
		{"barcode", "123456789012", true},
		{"barcode", "1234567890123", true},
		{"barcode", "12345678901234", true},
		{"barcode", "123456789", false}, // 9 digits
		{"barcode", "1234567a", false},  // non-digit
		{"mbid", "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d", true},
		{"mbid", "B10BBBFC-CF9E-42E0-BE17-E2C3E1D2600D", true},
		{"mbid", "b10bbbfc-cf9e-42e0-be17", false},
		{"mbid", "not-a-uuid", false},
		// The empty string always passes: it clears the field.
		{"isrc", "", true},
		{"isbn", "", true},
		{"mbid", "", true},
		// Non-identifier fields are never format-checked here.
		{"title", "anything at all", true},
	}
	for _, c := range cases {
		err := validateIdentifierField(c.field, c.value)
		if c.ok && err != nil {
			t.Errorf("%s=%q rejected: %v", c.field, c.value, err)
		}
		if !c.ok && err == nil {
			t.Errorf("%s=%q accepted, want rejection", c.field, c.value)
		}
	}
}

func TestValidateFieldEditsPerKind(t *testing.T) {
	t.Parallel()
	track := &model.ItemView{Kind: model.KindTrack}
	book := &model.ItemView{Kind: model.KindBook}
	episode := &model.ItemView{Kind: model.KindEpisode}

	if err := validateFieldEdits(track, map[string]string{"title": "T", "isrc": "USRC17607839"}, true); err != nil {
		t.Fatalf("track edit rejected: %v", err)
	}
	if err := validateFieldEdits(track, map[string]string{"narrator": "N"}, false); err == nil {
		t.Fatal("book field accepted on a track")
	}
	if err := validateFieldEdits(book, map[string]string{"narrator": "N", "isbn": "9780306406157"}, false); err != nil {
		t.Fatalf("book edit rejected: %v", err)
	}
	if err := validateFieldEdits(episode, map[string]string{"title": "T"}, false); err != nil {
		t.Fatalf("episode catalog edit rejected: %v", err)
	}
	// Episodes never write back to files.
	if err := validateFieldEdits(episode, map[string]string{"title": "T"}, true); err == nil {
		t.Fatal("episode write-back accepted")
	}
	if err := validateFieldEdits(track, nil, false); err == nil {
		t.Fatal("empty edit accepted")
	}
}

func TestValidateChapterList(t *testing.T) {
	t.Parallel()
	ok := []ChapterMark{
		{Index: 0, StartMS: 0, EndMS: 2000, Title: "One"},
		{Index: 1, StartMS: 2000, EndMS: 4000, Title: "Two"},
		{Index: 2, StartMS: 4000, Title: "Three"}, // open-ended final
	}
	if err := validateChapterList(ok); err != nil {
		t.Fatalf("valid chapters rejected: %v", err)
	}
	if err := validateChapterList(nil); err != nil {
		t.Fatalf("empty list rejected: %v", err)
	}
	bad := [][]ChapterMark{
		{{Index: 1, StartMS: 0}},                                         // index gap
		{{Index: 0, StartMS: -5}},                                        // negative start
		{{Index: 0, StartMS: 100, EndMS: 100}},                           // end not after start
		{{Index: 0, StartMS: 0}, {Index: 1, StartMS: 500}},               // open-ended non-final
		{{Index: 0, StartMS: 0, EndMS: 900}, {Index: 1, StartMS: 500}},   // overlap
		{{Index: 0, StartMS: 500, EndMS: 900}, {Index: 1, StartMS: 500}}, // equal starts
	}
	for i, chs := range bad {
		if err := validateChapterList(chs); err == nil {
			t.Errorf("bad chapter list %d accepted", i)
		}
	}
}

func TestWriteFileCrashSafe(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	path := filepath.Join(dir, "song.lrc")
	if err := writeFileCrashSafe(path, []byte("[00:01.000]Hello\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "[00:01.000]Hello\n" {
		t.Fatalf("content = %q", got)
	}
	// Overwrite replaces atomically and leaves no temp files behind.
	if err := writeFileCrashSafe(path, []byte("replaced\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(path); string(got) != "replaced\n" {
		t.Fatalf("overwrite content = %q", got)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("directory holds %d entries, want just the sidecar", len(entries))
	}
}

// A replaced sidecar keeps the mode it had; a new one takes its audio's,
// less any execute bit, so a player reading the library as another user
// reads the lyrics too; with neither, it is 0644.
func TestASidecarTakesTheModeOfWhatItSitsBeside(t *testing.T) {
	t.Parallel()
	if runtime.GOOS == "windows" {
		t.Skip("windows has no POSIX file modes")
	}
	dir := t.TempDir()
	audio := filepath.Join(dir, "song.flac")
	sidecar := filepath.Join(dir, "song.lrc")
	if err := os.WriteFile(audio, []byte("audio"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(audio, 0o755); err != nil {
		t.Fatal(err)
	}
	if got := sidecarMode(sidecar, audio); got != 0o644 {
		t.Errorf("beside a 0755 audio file = %o, want 0644", got)
	}
	if err := os.Chmod(audio, 0o664); err != nil {
		t.Fatal(err)
	}
	if got := sidecarMode(sidecar, audio); got != 0o664 {
		t.Errorf("beside a 0664 audio file = %o, want 0664", got)
	}
	if err := writeFileCrashSafe(sidecar, []byte("lyrics\n"), 0o640); err != nil {
		t.Fatal(err)
	}
	if st, err := os.Stat(sidecar); err != nil || st.Mode().Perm() != 0o640 {
		t.Fatalf("written sidecar mode = %v (%v), want 0640", st.Mode().Perm(), err)
	}
	if got := sidecarMode(sidecar, audio); got != 0o640 {
		t.Errorf("replacing a 0640 sidecar = %o, want its own 0640", got)
	}
	if got := sidecarMode(filepath.Join(dir, "none.lrc"), filepath.Join(dir, "none.flac")); got != 0o644 {
		t.Errorf("beside nothing = %o, want 0644", got)
	}
}

func TestGroupCredits(t *testing.T) {
	t.Parallel()
	rows := []model.Contributor{
		{Role: model.RoleProducer, Name: "Pat", Position: 0},
		{Role: model.RoleComposer, Name: "Clara", Position: 0},
		{Role: model.RoleProducer, Name: "Quinn", Position: 1},
	}
	out := groupCredits(rows)
	if len(out) != 2 {
		t.Fatalf("groups = %d, want 2", len(out))
	}
	if out[0].Role != "producer" || len(out[0].Names) != 2 || out[0].Names[1] != "Quinn" {
		t.Fatalf("producer group = %+v", out[0])
	}
	if out[1].Role != "composer" || len(out[1].Names) != 1 {
		t.Fatalf("composer group = %+v", out[1])
	}
}

func TestEditorScalarFieldsOverlay(t *testing.T) {
	t.Parallel()
	it := &model.ItemView{
		Kind: model.KindTrack, Title: "T", Artist: "A", Album: "L",
		Year: 2001, TrackNo: 3, Compilation: true,
	}
	prov := []model.FieldProvenance{
		{Field: "isrc", Value: "USRC17607839", Attribution: model.Attribution{Source: model.SourceUser}},
		{Field: "narrator", Value: "wrong kind"},  // off-vocabulary for a track
		{Field: "title", Value: "", Locked: true}, // lock-only row must not blank the view value
	}
	fields := editorScalarFields(it, prov)
	if fields["title"] != "T" || fields["year"] != "2001" || fields["track_no"] != "3" {
		t.Fatalf("view fields = %+v", fields)
	}
	if fields["compilation"] != "true" {
		t.Fatalf("compilation = %q", fields["compilation"])
	}
	if fields["isrc"] != "USRC17607839" {
		t.Fatalf("isrc overlay = %q", fields["isrc"])
	}
	if _, ok := fields["narrator"]; ok {
		t.Fatal("off-vocabulary provenance leaked into the fields map")
	}
	if _, ok := fields["album_artist"]; ok {
		t.Fatal("empty value was not omitted")
	}
}

func TestRedactedSourceURL(t *testing.T) {
	// The stored value is verbatim - a credentialed feed URL, a signed
	// link, a local path - and the read answers everyone who can see
	// the item, so anything that is not plainly shareable is dropped
	// rather than trimmed.
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain https survives", "https://feeds.example.test/show/ep-12.mp3", "https://feeds.example.test/show/ep-12.mp3"},
		{"http survives", "http://feeds.example.test/ep.mp3", "http://feeds.example.test/ep.mp3"},
		{"userinfo goes", "https://user:secret@feeds.example.test/ep.mp3", "https://feeds.example.test/ep.mp3"},
		{"query goes whole", "https://cdn.example.test/ep.mp3?token=abc&exp=1", "https://cdn.example.test/ep.mp3"},
		{"fragment goes", "https://cdn.example.test/ep.mp3#t=30", "https://cdn.example.test/ep.mp3"},
		{"scheme case folds", "HTTPS://cdn.example.test/ep.mp3", "https://cdn.example.test/ep.mp3"},
		{"file path is not emitted", "file:///srv/media/incoming/ep.mp3", ""},
		{"bare path is not emitted", "/srv/media/incoming/ep.mp3", ""},
		{"other schemes are not emitted", "s3://bucket/key", ""},
		{"hostless http is not emitted", "http:///ep.mp3", ""},
		{"empty stays empty", "", ""},
		{"unparseable is not emitted", "https://exa mple.test/\x7f", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := redactedSourceURL(tc.in); got != tc.want {
				t.Errorf("redactedSourceURL(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

// A section header and a bad timestamp are both skipped by line number,
// in words that fit either.
func TestSetItemLyricsReportsSkippedLines(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	apiPID, _ := fixtureTrackPID(t, ctx, svc, uc, "Flagged")
	out, err := svc.SetItemLyrics(ctx, uc, apiPID, "[Chorus]\n[9:99.99]bad\n[00:01.00]la la la\n", "", MetadataEditParams{})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"lrc line 1: no timed lyric, skipped", "lrc line 2: no timed lyric, skipped"}
	if !slices.Equal(out.Warnings, want) {
		t.Fatalf("warnings = %q, want %q", out.Warnings, want)
	}
}

// A piece a tool copies into the library takes the mode of the file it
// was cut from, not of its 0600 staging copy.
func TestACopiedToolPieceTakesItsOriginalsMode(t *testing.T) {
	t.Parallel()
	if runtime.GOOS == "windows" {
		t.Skip("no unix modes")
	}
	dir := t.TempDir()
	original := filepath.Join(dir, "book.m4b")
	piece := filepath.Join(t.TempDir(), "piece.m4b")
	if err := os.WriteFile(original, []byte("x"), 0o664); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(original, 0o664); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(piece, []byte("y"), 0o600); err != nil {
		t.Fatal(err)
	}
	dst := filepath.Join(dir, "Book", "01 - piece.m4b")
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := copyToolFile(piece, dst, fileModeBeside(original)); err != nil {
		t.Fatal(err)
	}
	if st, err := os.Stat(dst); err != nil || st.Mode().Perm() != 0o664 {
		t.Fatalf("copied piece mode = %v (%v), want the original's 0664", st.Mode().Perm(), err)
	}
}
