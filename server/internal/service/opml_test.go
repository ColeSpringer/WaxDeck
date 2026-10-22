package service

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// showsHost serves a distinct one-episode show at every /<name>.xml, and
// calls onAsk, when set, with each name asked for.
func showsHost(t *testing.T, onAsk func(name string)) *httptest.Server {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/"), ".xml")
		if onAsk != nil {
			onAsk(name)
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Show %[1]s</title>
<item><title>One</title><guid>%[1]s-1</guid></item></channel></rss>`, name)
	}))
	t.Cleanup(ts.Close)
	return ts
}

func openOpmlFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	return ctx, svc, uc
}

// A folder is stored as its segments, each trimmed, empty ones dropped,
// on every door that writes one; past 512 characters it is refused.
func TestAFolderIsNormalizedWhereverItIsWritten(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openOpmlFixture(t)
	host := showsHost(t, nil)
	for i, c := range []struct{ in, want string }{
		{"/News", "News"},
		{"News/", "News"},
		{"//a//b/", "a/b"},
		{" x / y ", "x/y"},
		{strings.Repeat("\u00e9", 512), strings.Repeat("\u00e9", 512)},
	} {
		sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: fmt.Sprintf("%s/n%d.xml", host.URL, i), Folder: c.in})
		if err != nil {
			t.Fatalf("subscribing with %q: %v", c.in, err)
		}
		if got := sub.Settings.Folder; got != c.want {
			t.Errorf("subscribed with %.20q: folder %.20q, want %.20q", c.in, got, c.want)
		}
	}

	huge := strings.Repeat("x/", 32000)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: host.URL + "/huge.xml", Folder: huge}); KindOf(err) != KindInvalid {
		t.Errorf("subscribing with a 64 KB folder: %v, want refused", err)
	}
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: host.URL + "/kept.xml", Folder: "Kept"})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(sub.Show.PID)
	settings := sub.Settings
	for _, folder := range []string{huge, strings.Repeat("\u00e9", 513)} {
		settings.Folder = folder
		if _, err := svc.PutSubscriptionSettings(ctx, uc, sub.Show.PID, settings); KindOf(err) != KindInvalid {
			t.Errorf("settings with a %d-byte folder: %v, want refused", len(folder), err)
		}
	}
	if row, err := svc.db.SubscriptionFor(ctx, uc.ID, string(bare)); err != nil || row.Folder != "Kept" {
		t.Errorf("folder after the refusals = %q (%v), want Kept", row.Folder, err)
	}
	for in, want := range map[string]string{"/Arts/": "Arts", " a // b ": "a/b"} {
		settings.Folder = in
		if put, err := svc.PutSubscriptionSettings(ctx, uc, sub.Show.PID, settings); err != nil || put.Settings.Folder != want {
			t.Errorf("settings with %q: folder %q (%v), want %q", in, put.Settings.Folder, err, want)
		}
	}
}

// storedFolders subscribes to one show per folder and stores each folder
// as it is given, the way a row written before folders were checked holds
// it.
func storedFolders(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, host string, folders []string) {
	t.Helper()
	for i, folder := range folders {
		sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: fmt.Sprintf("%s/f%d.xml", host, i)})
		if err != nil {
			t.Fatal(err)
		}
		_, bare, _ := parseAPIPID(sub.Show.PID)
		if _, err := svc.db.UpdateSubscriptionSettings(ctx, wdb.Subscription{
			UserID: uc.ID, ShowPID: string(bare), Folder: folder, UpdatedAtNS: 1,
		}); err != nil {
			t.Fatal(err)
		}
	}
}

// Whatever a stored folder holds, the export renders it as the folder it
// names, cut to the longest whole-segment prefix that fits, and drops no
// feed: a leading slash used to recurse until the stack ran out, a
// trailing one to lose the folder's feeds, and a long path to cost the
// square of its length.
func TestTheExportTakesAnyStoredFolder(t *testing.T) {
	t.Parallel()
	for _, c := range []struct{ name, stored, want string }{
		{"a leading slash", "/News", "News"},
		{"a trailing slash", "Arts/", "Arts"},
		{"a long path", strings.Repeat(strings.Repeat("y", 40)+"/", 100), strings.TrimSuffix(strings.Repeat(strings.Repeat("y", 40)+"/", 12), "/")},
		{"a deep path", strings.Repeat("x/", 4000), strings.TrimSuffix(strings.Repeat("x/", 16), "/")},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := openOpmlFixture(t)
			host := showsHost(t, nil)
			storedFolders(t, ctx, svc, uc, host.URL, []string{c.stored, "Other"})
			doc, err := svc.ExportOPML(ctx, uc)
			if err != nil {
				t.Fatal(err)
			}
			if len(doc) > 64<<10 {
				t.Fatalf("export = %d bytes", len(doc))
			}
			feeds, err := parseOpmlFeeds(doc)
			if err != nil {
				t.Fatal(err)
			}
			want := map[string]string{host.URL + "/f0.xml": c.want, host.URL + "/f1.xml": "Other"}
			if len(feeds) != len(want) {
				t.Errorf("exported %d feeds, want %d", len(feeds), len(want))
			}
			for _, f := range feeds {
				if w, ok := want[f.URL]; !ok || f.Folder != w {
					t.Errorf("%s exported under %.40q, want %.40q", f.URL, f.Folder, w)
				}
			}
		})
	}
}

// Folders that were always well formed export exactly as they did.
func TestTheNestedExportIsUnchanged(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openOpmlFixture(t)
	host := showsHost(t, nil)
	storedFolders(t, ctx, svc, uc, host.URL, []string{"News", "News/Tech", "", "Arts"})
	doc, err := svc.ExportOPML(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	want := `<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>WaxDeck subscriptions</title>
  </head>
  <body>
    <outline text="Arts" title="Arts">
      <outline text="Show f3" title="Show f3" type="rss" xmlUrl="HOST/f3.xml"></outline>
    </outline>
    <outline text="News" title="News">
      <outline text="Tech" title="Tech">
        <outline text="Show f1" title="Show f1" type="rss" xmlUrl="HOST/f1.xml"></outline>
      </outline>
      <outline text="Show f0" title="Show f0" type="rss" xmlUrl="HOST/f0.xml"></outline>
    </outline>
    <outline text="Show f2" title="Show f2" type="rss" xmlUrl="HOST/f2.xml"></outline>
  </body>
</opml>
`
	if got := string(doc); got != strings.ReplaceAll(want, "HOST", host.URL) {
		t.Errorf("export =\n%s\nwant\n%s", got, want)
	}
}

// An import fits each feed's folder the way a stored one is written,
// keeping the longest whole-segment prefix that fits rather than failing
// the feed, and needs the account's podcast permission before it reads a
// byte of the document.
func TestAnImportFitsItsFoldersAndAsksPermissionFirst(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openOpmlFixture(t)
	host := showsHost(t, nil)
	seg := strings.Repeat("s", 40)
	deep := strings.Repeat(`<outline text="`+seg+`">`, 300) + fmt.Sprintf(`<outline text="Deep" xmlUrl="%s/deep.xml"/>`, host.URL) +
		strings.Repeat(`</outline>`, 300)
	doc := fmt.Sprintf(`<?xml version="1.0"?><opml version="2.0"><body>
<outline title=" / News / "><outline text="Plain" xmlUrl="%[1]s/plain.xml"/></outline>
<outline text="%[2]s"><outline text="Long" xmlUrl="%[1]s/long.xml"/></outline>
%[3]s</body></opml>`, host.URL, strings.Repeat("y", 600), deep)
	entries, err := svc.ImportOPML(ctx, uc, []byte(doc))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"Show plain": "News",
		"Show long":  "",
		"Show deep":  strings.TrimSuffix(strings.Repeat(seg+"/", 12), "/"),
	}
	for _, e := range entries {
		if e.Err != "" {
			t.Errorf("%s failed: %s", e.FeedURL, e.Err)
			continue
		}
		_, bare, _ := parseAPIPID(e.PID)
		row, err := svc.db.SubscriptionFor(ctx, uc.ID, string(bare))
		if w, ok := want[e.Title]; err != nil || !ok || row.Folder != w {
			t.Errorf("%s under %.40q (%v), want %.40q", e.Title, row.Folder, err, w)
		}
	}
	if len(entries) != len(want) {
		t.Errorf("imported %d feeds, want %d", len(entries), len(want))
	}

	barred := *uc
	barred.ManagePodcasts = false
	for _, body := range []string{doc, "<opml><body><outline"} {
		if _, err := svc.ImportOPML(ctx, &barred, []byte(body)); KindOf(err) != KindForbidden {
			t.Errorf("an import without the permission: %v, want forbidden", err)
		}
	}
}

// One import takes at most 1,000 feeds and is refused whole past that,
// before any is subscribed.
func TestAnImportTakesAtMostAThousandFeeds(t *testing.T) {
	t.Parallel()
	var b strings.Builder
	b.WriteString(`<opml version="2.0"><body>`)
	for i := range 1001 {
		fmt.Fprintf(&b, `<outline text="f" xmlUrl="https://feeds.example/%d.xml"/>`, i)
	}
	b.WriteString(`</body></opml>`)
	feeds, err := parseOpmlFeeds([]byte(b.String()))
	if KindOf(err) != KindInvalid || !strings.Contains(err.Error(), "1000") {
		t.Fatalf("parsing 1001 feeds = %d feeds (%v), want a refusal naming the cap", len(feeds), err)
	}
}

// allocatedBy reports the bytes f allocates. The suite's parallel tests
// wait while a test that is not parallel runs, so the count is f's.
func allocatedBy(f func()) uint64 {
	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)
	f()
	runtime.ReadMemStats(&after)
	return after.TotalAlloc - before.TotalAlloc
}

// Reading a document costs memory in its size, not in the square of its
// depth: 9,990 nested folders used to allocate 841 MB, and 100,000 feeds
// under them three gigabytes.
func TestAnImportsMemoryIsBounded(t *testing.T) {
	deep := func(feeds int) []byte {
		var b strings.Builder
		b.WriteString(`<opml version="2.0"><body>`)
		b.WriteString(strings.Repeat(`<outline text="a">`, 9990))
		for i := range feeds {
			fmt.Fprintf(&b, `<outline xmlUrl="https://feeds.example/%d.xml"/>`, i)
		}
		b.WriteString(strings.Repeat(`</outline>`, 9990))
		b.WriteString(`</body></opml>`)
		return []byte(b.String())
	}
	for _, c := range []struct {
		name  string
		doc   func() []byte
		feeds int
	}{
		{"nested folders", func() []byte { return deep(1) }, 1},
		{"feeds under them", func() []byte { return deep(100_000) }, 0},
	} {
		t.Run(c.name, func(t *testing.T) {
			doc := c.doc()
			var feeds []opmlFeed
			var err error
			n := allocatedBy(func() { feeds, err = parseOpmlFeeds(doc) })
			if n > 32<<20 {
				t.Errorf("%d bytes allocated %d MB", len(doc), n>>20)
			}
			if c.feeds > 0 && (err != nil || len(feeds) != c.feeds) {
				t.Errorf("%d feeds (%v), want %d", len(feeds), err, c.feeds)
			}
			if c.feeds == 0 && KindOf(err) != KindInvalid {
				t.Errorf("%v, want refused", err)
			}
		})
	}
}

// A caller that stops waiting does not stop the import: every feed is
// still subscribed.
func TestAnImportOutlivesItsCaller(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openOpmlFixture(t)
	callCtx, hangUp := context.WithCancel(ctx)
	defer hangUp()
	host := showsHost(t, func(name string) {
		if name == "first" {
			hangUp()
		}
	})
	doc := fmt.Sprintf(`<opml version="2.0"><body><outline text="1" xmlUrl="%[1]s/first.xml"/>
<outline text="2" xmlUrl="%[1]s/second.xml"/><outline text="3" xmlUrl="%[1]s/third.xml"/></body></opml>`, host.URL)
	entries, err := svc.ImportOPML(callCtx, uc, []byte(doc))
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.Err != "" || e.PID == "" {
			t.Errorf("%s = %+v, want subscribed", e.FeedURL, e)
		}
	}
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 3 {
		t.Errorf("subscriptions = %d (%v), want 3", len(subs), err)
	}
}

// A folder holds at most 16 segments: the doors that write one refuse a
// deeper one, and an import or the export fits it to its first 16.
func TestAFolderIsAtMostSixteenDeep(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openOpmlFixture(t)
	host := showsHost(t, nil)
	deep := func(n int) string { return strings.TrimSuffix(strings.Repeat("d/", n), "/") }
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: host.URL + "/deep.xml", Folder: deep(17)}); KindOf(err) != KindInvalid {
		t.Errorf("subscribing 17 deep: %v, want refused", err)
	}
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: host.URL + "/deep.xml", Folder: deep(16)})
	if err != nil || sub.Settings.Folder != deep(16) {
		t.Fatalf("subscribing 16 deep = %q (%v), want kept", sub.Settings.Folder, err)
	}
	settings := sub.Settings
	settings.Folder = deep(17)
	if _, err := svc.PutSubscriptionSettings(ctx, uc, sub.Show.PID, settings); KindOf(err) != KindInvalid {
		t.Errorf("settings 17 deep: %v, want refused", err)
	}
	doc := fmt.Sprintf(`<opml version="2.0"><body>%s<outline text="Deeper" xmlUrl="%s/deeper.xml"/>%s</body></opml>`,
		strings.Repeat(`<outline text="d">`, 20), host.URL, strings.Repeat(`</outline>`, 20))
	entries, err := svc.ImportOPML(ctx, uc, []byte(doc))
	if err != nil || len(entries) != 1 || entries[0].Err != "" {
		t.Fatalf("import = %+v (%v)", entries, err)
	}
	_, bare, _ := parseAPIPID(entries[0].PID)
	if row, err := svc.db.SubscriptionFor(ctx, uc.ID, string(bare)); err != nil || row.Folder != deep(16) {
		t.Errorf("imported 20 deep under %q (%v), want the first 16", row.Folder, err)
	}
}

// The export of a thousand subscriptions, each in a distinct folder as
// deep and as long as a folder can be stored, stays under a fixed size and
// a fixed allocation: the segment cap is what bounds a path's depth, so
// the tree, the lines and the indentation all stay small.
func TestAThousandDeepFoldersExportSmall(t *testing.T) {
	for _, c := range []struct {
		name   string
		folder func(i int) string
	}{
		{"one-character segments", func(i int) string {
			return fmt.Sprintf("s%04d", i) + strings.Repeat("/x", 253)
		}},
		{"long segments", func(i int) string {
			seg := strings.Repeat("y", 30)
			return fmt.Sprintf("s%04d", i) + strings.Repeat("/"+seg, 15)
		}},
	} {
		t.Run(strings.ReplaceAll(c.name, " ", "_"), func(t *testing.T) {
			byFolder := map[string][]opmlFeed{}
			for i := range 1000 {
				folder := c.folder(i)
				byFolder[folder] = append(byFolder[folder], opmlFeed{
					URL: fmt.Sprintf("https://feeds.example/%d.xml", i), Title: fmt.Sprintf("Show %d", i), Folder: folder,
				})
			}
			var doc []byte
			var err error
			n := allocatedBy(func() { doc, err = renderOPML(byFolder) })
			if err != nil {
				t.Fatal(err)
			}
			t.Logf("%d bytes, %d bytes allocated", len(doc), n)
			if len(doc) > 4<<20 || n > 32<<20 {
				t.Errorf("a thousand deep folders export %d bytes and allocate %d MB", len(doc), n>>20)
			}
		})
	}
}

// The export writes at most the first 1,000 characters of a show's title,
// in both attributes that carry it.
func TestTheExportClipsLongTitles(t *testing.T) {
	t.Parallel()
	long := strings.Repeat("\u00e9", 5000)
	doc, err := renderOPML(map[string][]opmlFeed{
		"": {{URL: "https://feeds.example/long.xml", Title: long}},
	})
	if err != nil {
		t.Fatal(err)
	}
	clipped := strings.Repeat("\u00e9", 1000)
	if !strings.Contains(string(doc), `text="`+clipped+`" title="`+clipped+`" type="rss"`) {
		t.Errorf("export = %.200q..., want both attributes cut to 1000 characters", doc)
	}
	if len(doc) > 8<<10 {
		t.Errorf("export = %d bytes", len(doc))
	}
}
