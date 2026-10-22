package service

import (
	"fmt"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// An episode's format does not change when it is fetched: whatever
// spelling its feed declares, an unfetched episode reports the container
// and type the catalog then reports for the file, read off real files.
func TestAnUnfetchedEpisodeReportsTheFormatAFetchedCopyWould(t *testing.T) {
	t.Parallel()
	families := []struct {
		spec     fixtures.Spec
		declared []string
	}{
		{fixtures.Spec{Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3},
			[]string{"audio/mpeg", "audio/mp3", "audio/x-mp3", "audio/mpeg3", "audio/x-mpeg-3", "audio/x-mpeg", "audio/mpga", "application/mpeg"}},
		{fixtures.Spec{Codec: fixtures.CodecAAC, Container: fixtures.ContainerMP4},
			[]string{"audio/mp4", "audio/x-m4a", "audio/m4a", "audio/mp4a-latm", "application/mp4", "audio/x-m4b", "video/mp4", "video/x-m4v", "video/quicktime"}},
		{fixtures.Spec{Codec: fixtures.CodecAAC, Container: fixtures.ContainerADTS},
			[]string{"audio/aac", "audio/x-aac", "audio/aacp"}},
		{fixtures.Spec{Codec: fixtures.CodecVorbis, Container: fixtures.ContainerOgg},
			[]string{"audio/ogg", "application/ogg", "audio/vorbis"}},
		{fixtures.Spec{Codec: fixtures.CodecOpus, Container: fixtures.ContainerOgg},
			[]string{"audio/opus"}},
		{fixtures.Spec{Codec: fixtures.CodecFLAC, Container: fixtures.ContainerFLAC},
			[]string{"audio/flac", "audio/x-flac"}},
		{fixtures.Spec{Codec: fixtures.CodecPCM, Container: fixtures.ContainerWAV},
			[]string{"audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave"}},
		{fixtures.Spec{Codec: fixtures.CodecPCM, Container: fixtures.ContainerAIFF},
			[]string{"audio/aiff", "audio/x-aiff"}},
		{fixtures.Spec{Codec: fixtures.CodecFLAC, Container: fixtures.ContainerMatroska},
			[]string{"audio/x-matroska", "video/x-matroska"}},
	}
	// Each family's first spelling once more, for the copy that is fetched.
	var declared []string
	for _, fam := range families {
		declared = append(declared, fam.declared[0])
		declared = append(declared, fam.declared...)
	}
	feed := &stubFeed{kind: model.SourceRSS, n: len(declared), prefix: "Format",
		enclosure: func(i int) (string, string) {
			return fmt.Sprintf("https://cdn.example/format-%03d", i), declared[i]
		}}
	f := openStubFeeds(t, feed)
	sub := f.subscribe(t, "https://feeds.example/formats", "rss")
	byTitle := map[string]EpisodeSummary{}
	read := func() {
		t.Helper()
		rows, _, err := f.svc.Episodes(f.ctx, f.uc, sub.Show.PID, "", len(declared))
		if err != nil || len(rows) != len(declared) {
			t.Fatalf("episodes = %d (%v), want %d", len(rows), err, len(declared))
		}
		for _, r := range rows {
			byTitle[r.Title] = r
		}
	}
	read()
	i := 0
	for _, fam := range families {
		spec := fam.spec
		spec.Name, spec.Duration = fmt.Sprintf("format-%d", i), time.Second
		paths, err := fixtures.Generate(t.TempDir(), spec)
		if err != nil {
			t.Fatal(err)
		}
		_, bare, _ := parseAPIPID(byTitle[fmt.Sprintf("Format %03d", i)].PID)
		if _, err := f.svc.lib.Podcasts().ImportEpisodeFile(f.ctx, bare, paths[0], false); err != nil {
			t.Fatal(err)
		}
		i += 1 + len(fam.declared)
	}
	read()
	i = 0
	for _, fam := range families {
		fetched := byTitle[fmt.Sprintf("Format %03d", i)]
		if !fetched.Downloaded || fetched.Container == "" {
			t.Fatalf("the %s copy = %+v, want it fetched with a container", fam.declared[0], fetched)
		}
		for j, spelling := range fam.declared {
			got := byTitle[fmt.Sprintf("Format %03d", i+1+j)]
			if got.Downloaded {
				t.Fatalf("the %s episode is fetched", spelling)
			}
			if got.Container != fetched.Container || got.MimeType != fetched.MimeType {
				t.Errorf("declared %s: container %q, type %q; the fetched copy reads %q, %q",
					spelling, got.Container, got.MimeType, fetched.Container, fetched.MimeType)
			}
		}
		i += 1 + len(fam.declared)
	}
}

// The spellings with no file to make here map to the label the catalog
// stores for such a file, typed as a fetched one is; one the table does
// not know keeps the type its feed declared, with no container.
func TestEpisodeFormatOfTheRarerSpellings(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		declared, container string
	}{
		{"audio/webm", "webm"},
		{"video/webm", "webm"},
		{"audio/x-ms-wma", "asf"},
	} {
		ep := &model.Episode{EnclosureURL: "https://cdn.example/ep", EnclosureType: c.declared}
		container, mimeType := episodeFormat(ep, "")
		if container != c.container || mimeType != flow.ContainerMime(c.container) {
			t.Errorf("declared %s = %q, %q; want %q, %q", c.declared, container, mimeType, c.container, flow.ContainerMime(c.container))
		}
	}
	ep := &model.Episode{EnclosureURL: "https://cdn.example/ep", EnclosureType: "audio/x-ape"}
	if container, mimeType := episodeFormat(ep, ""); container != "" || mimeType != "audio/x-ape" {
		t.Errorf("an unknown audio spelling = %q, %q; want no container and the declared type", container, mimeType)
	}
}
