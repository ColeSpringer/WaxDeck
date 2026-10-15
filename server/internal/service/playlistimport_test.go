package service

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

func TestParseDelimitedExportExportify(t *testing.T) {
	t.Parallel()
	payload := strings.Join([]string{
		`"Track URI","Track Name","Artist URI(s)","Artist Name(s)","Album URI","Album Name","Disc Number","Track Number","Track Duration (ms)","Explicit","Popularity","ISRC","Added At"`,
		`"spotify:track:1","Amber Waves","spotify:artist:1","Test Ensemble","spotify:album:1","Signal Garden","1","1","215000","false","41","USABC2400001","2024-01-01"`,
		`"spotify:track:2","Basalt Steps","spotify:artist:1","Test Ensemble, Guest Voice","spotify:album:1","Signal Garden","1","2","198500","false","37","USABC2400002","2024-01-02"`,
	}, "\n")
	refs, name, err := parseDelimitedExport(payload, ',')
	if err != nil {
		t.Fatal(err)
	}
	if name != "" {
		t.Fatalf("list name = %q, want empty (no playlist column)", name)
	}
	if len(refs) != 2 {
		t.Fatalf("entries = %d, want 2", len(refs))
	}
	first := refs[0]
	if first.Title != "Amber Waves" || first.Artist != "Test Ensemble" ||
		first.Album != "Signal Garden" || first.DurationMs != 215000 || first.ISRC != "USABC2400001" {
		t.Fatalf("first entry = %+v", first)
	}
	// A multi-artist cell parses intact: comma-carrying band names
	// must reach the resolver unharmed, and the primary-credit trim
	// runs only as a miss retry (retryMissesWithTrimmedArtist).
	if refs[1].Artist != "Test Ensemble, Guest Voice" {
		t.Fatalf("multi-artist cell = %q, want the full cell", refs[1].Artist)
	}
	if refs[1].DurationMs != 198500 {
		t.Fatalf("second duration = %d", refs[1].DurationMs)
	}
}

func TestParseDelimitedExportGoogleTakeout(t *testing.T) {
	t.Parallel()
	payload := strings.Join([]string{
		`Song Title,Album Title,Artist Name,Duration (ms),Rank,Removed`,
		`Cobalt Sky,Signal Garden,Test Ensemble,187000,1,`,
		`Delta Groove,Late Sets,Brass Nine,244000,2,`,
	}, "\n")
	refs, _, err := parseDelimitedExport(payload, ',')
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 2 {
		t.Fatalf("entries = %d, want 2", len(refs))
	}
	if refs[0].Title != "Cobalt Sky" || refs[0].Artist != "Test Ensemble" ||
		refs[0].Album != "Signal Garden" || refs[0].DurationMs != 187000 {
		t.Fatalf("first entry = %+v", refs[0])
	}
	if refs[1].Title != "Delta Groove" || refs[1].Artist != "Brass Nine" {
		t.Fatalf("second entry = %+v", refs[1])
	}
}

func TestParseDelimitedExportDurationPrecedence(t *testing.T) {
	t.Parallel()
	// A spreadsheet merge can carry both a clock-format Time column
	// and an exact Duration (ms) column; the milliseconds column must
	// win deterministically in either column order, and the clock
	// column fills in when the exact one is empty for a row.
	for _, payload := range []string{
		strings.Join([]string{
			`Track Name,Artist,Time,Duration (ms)`,
			`Cobalt Sky,Test Ensemble,3:35,215123`,
			`Delta Groove,Brass Nine,4:04,`,
		}, "\n"),
		strings.Join([]string{
			`Track Name,Artist,Duration (ms),Time`,
			`Cobalt Sky,Test Ensemble,215123,3:35`,
			`Delta Groove,Brass Nine,,4:04`,
		}, "\n"),
	} {
		refs, _, err := parseDelimitedExport(payload, ',')
		if err != nil {
			t.Fatal(err)
		}
		if len(refs) != 2 {
			t.Fatalf("entries = %d, want 2", len(refs))
		}
		if refs[0].DurationMs != 215123 {
			t.Fatalf("both-columns duration = %d, want the exact milliseconds", refs[0].DurationMs)
		}
		if refs[1].DurationMs != 244000 {
			t.Fatalf("clock-fallback duration = %d, want 4:04 parsed", refs[1].DurationMs)
		}
	}
}

func TestParseDelimitedExportAppleMusicTSV(t *testing.T) {
	t.Parallel()
	payload := strings.Join([]string{
		"Name\tArtist\tAlbum\tTime",
		"Amber Waves\tTest Ensemble\tSignal Garden\t3:45",
		"Long Form\tTest Ensemble\tSignal Garden\t1:02:03",
	}, "\n")
	refs, _, err := parseDelimitedExport(payload, '\t')
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 2 {
		t.Fatalf("entries = %d, want 2", len(refs))
	}
	if refs[0].Title != "Amber Waves" || refs[0].Artist != "Test Ensemble" || refs[0].DurationMs != 225000 {
		t.Fatalf("first entry = %+v", refs[0])
	}
	if refs[1].DurationMs != 3723000 {
		t.Fatalf("h:mm:ss duration = %d, want 3723000", refs[1].DurationMs)
	}
}

func TestParseDelimitedExportGenericWithBOM(t *testing.T) {
	t.Parallel()
	payload := "\ufeffTitle,Artist,Album\n" +
		"Amber Waves,Test Ensemble,Signal Garden\n"
	refs, _, err := parseDelimitedExport(payload, ',')
	if err != nil {
		t.Fatalf("BOM-prefixed header did not parse: %v", err)
	}
	if len(refs) != 1 || refs[0].Title != "Amber Waves" || refs[0].Album != "Signal Garden" {
		t.Fatalf("entries = %+v", refs)
	}
}

func TestParseDelimitedExportSkipsMalformedRow(t *testing.T) {
	t.Parallel()
	// The stray short line mid-file (a spreadsheet round-trip artifact)
	// carries no title column and is skipped; rows after it still parse.
	payload := strings.Join([]string{
		`Artist,Album,Title`,
		`Test Ensemble,Signal Garden,Amber Waves`,
		`odd`,
		`Test Ensemble,Signal Garden,Basalt Steps`,
	}, "\n")
	refs, _, err := parseDelimitedExport(payload, ',')
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 2 || refs[0].Title != "Amber Waves" || refs[1].Title != "Basalt Steps" {
		t.Fatalf("entries = %+v, want the two well-formed rows", refs)
	}
}

func TestParseDelimitedExportPlaylistNameColumn(t *testing.T) {
	t.Parallel()
	payload := strings.Join([]string{
		`Playlist Name,Track Name,Artist Name`,
		`Road Tape,Amber Waves,Test Ensemble`,
		`Other Name,Basalt Steps,Test Ensemble`,
	}, "\n")
	refs, name, err := parseDelimitedExport(payload, ',')
	if err != nil {
		t.Fatal(err)
	}
	if name != "Road Tape" {
		t.Fatalf("list name = %q, want the first row's value", name)
	}
	if len(refs) != 2 {
		t.Fatalf("entries = %d, want 2", len(refs))
	}
}

func TestParseDelimitedExportRejectsBadShapes(t *testing.T) {
	t.Parallel()
	if _, _, err := parseDelimitedExport("", ','); err == nil {
		t.Fatal("empty payload parsed, want error")
	}
	if _, _, err := parseDelimitedExport("   \n\t", ','); err == nil {
		t.Fatal("blank payload parsed, want error")
	}
	noTitle := "Artist Name,Album Name\nTest Ensemble,Signal Garden\n"
	if _, _, err := parseDelimitedExport(noTitle, ','); err == nil {
		t.Fatal("export without a title column parsed, want error")
	}
}

func TestParseTextExport(t *testing.T) {
	t.Parallel()
	payload := strings.Join([]string{
		"# exported from a notes app",
		"Test Ensemble - Amber Waves",
		"Test Ensemble \u2013 Basalt Steps",
		"",
		"Cobalt Sky",
	}, "\n")
	refs, err := parseTextExport(payload)
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 3 {
		t.Fatalf("entries = %d, want 3 (comment and blank skipped)", len(refs))
	}
	if refs[0].Artist != "Test Ensemble" || refs[0].Title != "Amber Waves" {
		t.Fatalf("hyphen line = %+v", refs[0])
	}
	if refs[1].Artist != "Test Ensemble" || refs[1].Title != "Basalt Steps" {
		t.Fatalf("en-dash line = %+v", refs[1])
	}
	if refs[2].Artist != "" || refs[2].Title != "Cobalt Sky" {
		t.Fatalf("bare title line = %+v", refs[2])
	}
	// A comment-only payload is not a parse error; the import layer
	// refuses it for carrying no entries.
	if refs, err := parseTextExport("  \n# only a comment\n"); err != nil || len(refs) != 0 {
		t.Fatalf("comment-only payload = (%v, %v), want (empty, nil)", refs, err)
	}
	if _, err := parseTextExport("   \n\t"); err == nil {
		t.Fatal("blank payload parsed, want error")
	}
}

func TestParseClockDuration(t *testing.T) {
	t.Parallel()
	cases := []struct {
		in   string
		want int64
	}{
		{"3:45", 225000},
		{"1:02:03", 3723000},
		{"245", 245000},
		{"0:07", 7000},
		{"", 0},
		{"abc", 0},
		{"-5", 0},
		{"1:2:3:4", 0},
		{"3:-1", 0},
		{"3:xx", 0},
	}
	for _, c := range cases {
		if got := parseClockDuration(c.in); got != c.want {
			t.Errorf("parseClockDuration(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestFirstArtist(t *testing.T) {
	t.Parallel()
	cases := []struct {
		in, want string
	}{
		{"A; B", "A"},
		{"A, B", "A"},
		{"A feat. B", "A"},
		{"A ft. B", "A"},
		{"Solo Artist", "Solo Artist"},
		{"  padded  ", "padded"},
		{"", ""},
	}
	for _, c := range cases {
		if got := firstArtist(c.in); got != c.want {
			t.Errorf("firstArtist(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// TestResolveReachableFallsThroughToTheRetry: a first-pass match the
// caller cannot see is a miss inside that pass, so the trimmed-artist
// retry still runs and finds the copy they can.
func TestResolveReachableFallsThroughToTheRetry(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{
		extra: func(t *testing.T, libDir string) {
			if _, err := fixtures.Generate(filepath.Join(libDir, "guest"), fixtures.Spec{
				Name: "guest", Codec: fixtures.CodecFLAC, Duration: 4 * time.Second,
				Tags: map[string]string{
					"TITLE": "Amber Waves", "ARTIST": "Test Ensemble, Guest", "ALBUM": "Guest Spots",
				},
			}); err != nil {
				t.Fatal(err)
			}
		},
	})
	var guest, plain string
	page, err := svc.Items(ctx, uc, ItemFilter{}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range page.Items {
		switch {
		case it.Title == "Amber Waves" && it.Artist == "Test Ensemble, Guest":
			guest = it.PID
		case it.Title == "Amber Waves":
			plain = it.PID
		}
	}
	if guest == "" || plain == "" {
		t.Fatalf("fixture copies: guest %q plain %q", guest, plain)
	}
	if _, err := svc.SetItemTag(ctx, uc, guest, "MOOD", []string{"calm"}, MetadataEditParams{Lock: false, Force: false}); err != nil {
		t.Fatal(err)
	}
	in := PlaylistImportInput{Source: "text", Payload: "Test Ensemble, Guest - Amber Waves\n"}

	out, err := svc.ImportStreamingPlaylist(ctx, uc, in)
	if err != nil {
		t.Fatal(err)
	}
	if got := memberPIDs(t, ctx, svc, uc, out.PlaylistPID); !samePIDs(got, []string{guest}) {
		t.Fatalf("unrestricted import holds %v, want the credited copy %s", got, guest)
	}

	kid := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: "MOOD", Value: "calm"}},
	}
	out, err = svc.ImportStreamingPlaylist(ctx, kid, in)
	if err != nil {
		t.Fatal(err)
	}
	if out.Resolved != 1 {
		t.Fatalf("restricted import = %+v, want the retry's match", out)
	}
	if got := memberPIDs(t, ctx, svc, kid, out.PlaylistPID); !samePIDs(got, []string{plain}) {
		t.Errorf("restricted import holds %v, want the copy they can see %s", got, plain)
	}
}

// TestPairRefsRefusesAListThatMoved: the portable export pairs the
// catalog's positional refs with a member read by position, so a list
// that changed between the two reads must refuse rather than hand a
// reader the ref of a member they cannot see.
func TestPairRefsRefusesAListThatMoved(t *testing.T) {
	t.Parallel()
	l := &Library{}
	f := memberFilter{uc: &UserCtx{Admin: true, AllLibraries: true, Explicit: true}, subs: l.newSubscriptionFilter(nil)}
	view := func(pid, title string, state model.ItemState) *model.ItemView {
		return &model.ItemView{PID: model.PID(pid), Kind: model.KindTrack, Title: title, DurationMS: 1000, State: state}
	}
	ref := func(title string) model.PortableRef {
		return model.PortableRef{Kind: model.KindTrack, Title: title, DurationMS: 1000}
	}
	live, gone := view("a", "Alpha", model.StatePresent), view("b", "Bravo", model.StateArchived)

	out, ok := l.pairRefs(t.Context(), f, []*model.ItemView{live, gone}, []model.PortableRef{ref("Alpha"), ref("Bravo")})
	if !ok || len(out) != 1 || out[0].Title != "Alpha" {
		t.Errorf("aligned lists = %+v (%v), want Alpha's ref alone", out, ok)
	}
	if _, ok := l.pairRefs(t.Context(), f, []*model.ItemView{live, gone}, []model.PortableRef{ref("Bravo"), ref("Alpha")}); ok {
		t.Error("a reordered list paired")
	}
	if _, ok := l.pairRefs(t.Context(), f, []*model.ItemView{live}, []model.PortableRef{ref("Alpha"), ref("Bravo")}); ok {
		t.Error("lists of different lengths paired")
	}
}
