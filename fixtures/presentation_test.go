package fixtures_test

import (
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// The conformance presentations are the tone as the streaming engine
// renders one item for a player that plays HLS, in each format the suite
// plays: a master naming one variant, a VOD media playlist whose lengths
// add up to the tone's, an fMP4 init header and every segment it lists.
func TestConformancePresentations(t *testing.T) {
	tone := fixtures.ConformanceMedia()[0]
	out := t.TempDir()
	masters, err := fixtures.GenerateConformancePresentations(out)
	if err != nil {
		t.Fatal(err)
	}
	codecs := map[string]string{"opus": `CODECS="Opus"`, "flac": `CODECS="fLaC"`}
	if len(masters) != len(fixtures.ConformancePresentationFormats) {
		t.Fatalf("%d presentations, want one per format", len(masters))
	}
	for i, format := range fixtures.ConformancePresentationFormats {
		t.Run(format, func(t *testing.T) {
			dir := filepath.Join(out, fixtures.ConformancePresentationDir(format))
			if masters[i] != filepath.Join(dir, "master.m3u8") {
				t.Fatalf("master at %s, want %s", masters[i], filepath.Join(dir, "master.m3u8"))
			}
			verifyPresentation(t, dir, tone, codecs[format])
		})
	}
}

func verifyPresentation(t *testing.T, dir string, tone fixtures.Spec, codecs string) {
	t.Helper()
	read := func(name string) []byte {
		t.Helper()
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	m := string(read("master.m3u8"))
	if !strings.HasPrefix(m, "#EXTM3U\n") || !strings.Contains(m, "#EXT-X-STREAM-INF:BANDWIDTH=") ||
		!strings.Contains(m, codecs) || !strings.Contains(m, "\nmedia.m3u8\n") {
		t.Fatalf("master:\n%s", m)
	}
	media := string(read("media.m3u8"))
	for _, want := range []string{"#EXT-X-PLAYLIST-TYPE:VOD\n", `#EXT-X-MAP:URI="init.mp4"`, "#EXT-X-ENDLIST\n"} {
		if !strings.Contains(media, want) {
			t.Fatalf("media playlist lacks %q:\n%s", want, media)
		}
	}
	if init := read("init.mp4"); len(init) < 8 || string(init[4:8]) != "ftyp" {
		t.Fatalf("init header starts %q, want an ftyp box", init[:min(8, len(init))])
	}
	var total float64
	var segments int
	lines := strings.Split(media, "\n")
	for i, line := range lines {
		seconds, ok := strings.CutPrefix(line, "#EXTINF:")
		if !ok {
			continue
		}
		d, err := strconv.ParseFloat(strings.TrimSuffix(seconds, ","), 64)
		if err != nil {
			t.Fatalf("EXTINF %q: %v", line, err)
		}
		total += d
		segments++
		seg := read(lines[i+1])
		if len(seg) < 8 || (string(seg[4:8]) != "styp" && string(seg[4:8]) != "moof") {
			t.Fatalf("segment %s starts %q, want an fMP4 fragment", lines[i+1], seg[:min(8, len(seg))])
		}
	}
	if segments < 4 {
		t.Fatalf("%d segments, want the tone cut every two seconds", segments)
	}
	if want := tone.Duration.Seconds(); math.Abs(total-want) > 0.05 {
		t.Fatalf("segments add up to %.3f s, want the tone's %.3f", total, want)
	}
}
