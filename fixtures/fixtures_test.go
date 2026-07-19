package fixtures_test

import (
	"crypto/sha256"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxflow/audio"
	"github.com/colespringer/waxflow/codec"
	"github.com/colespringer/waxflow/container"
	"github.com/colespringer/waxflow/format"

	"github.com/colespringer/waxdeck/fixtures"
)

// wantCodecID maps fixture codecs to WaxFlow decoder identities.
var wantCodecID = map[fixtures.Codec]codec.ID{
	fixtures.CodecPCM:    codec.PCM,
	fixtures.CodecFLAC:   codec.FLAC,
	fixtures.CodecMP3:    codec.MP3,
	fixtures.CodecAAC:    codec.AACLC,
	fixtures.CodecALAC:   codec.ALAC,
	fixtures.CodecOpus:   codec.Opus,
	fixtures.CodecVorbis: codec.Vorbis,
}

// wantContainerName maps fixture containers to format registry names.
var wantContainerName = map[fixtures.Container]string{
	fixtures.ContainerWAV:      "wav",
	fixtures.ContainerAIFF:     "aiff",
	fixtures.ContainerFLAC:     "flac",
	fixtures.ContainerMP3:      "mp3",
	fixtures.ContainerMP4:      "mp4",
	fixtures.ContainerADTS:     "adts",
	fixtures.ContainerOgg:      "ogg",
	fixtures.ContainerMatroska: "mka",
}

// openFixture opens a generated file through WaxFlow's format registry.
func openFixture(t *testing.T, path string) format.Media {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { f.Close() })
	src, err := container.FileSource(f)
	if err != nil {
		t.Fatal(err)
	}
	med, err := format.Open(src, filepath.Ext(path), nil)
	if err != nil {
		t.Fatalf("format.Open(%s): %v", filepath.Base(path), err)
	}
	t.Cleanup(func() { med.Close() })
	return med
}

// decodeFrames pulls the whole stream and returns the decoded frame
// count; a mid-stream failure returns the frames decoded so far.
func decodeFrames(med format.Media) (int64, error) {
	f := med.Info().Default().Fmt
	buf := audio.Get(f, audio.StandardChunk)
	defer audio.Put(buf)
	var n int64
	for {
		err := med.ReadChunk(buf)
		if errors.Is(err, io.EOF) {
			return n, nil
		}
		if err != nil {
			return n, err
		}
		n += int64(buf.N)
	}
}

// verifySpec decodes path back through WaxFlow and asserts it matches
// the spec: right container, right codec, right shape, right length.
func verifySpec(t *testing.T, spec fixtures.Spec, path string) {
	t.Helper()
	med := openFixture(t, path)
	info := med.Info()
	track := info.Default()

	if want := wantContainerName[spec.Container]; info.Container != want {
		t.Errorf("container = %q, want %q", info.Container, want)
	}
	if want := wantCodecID[spec.Codec]; track.Codec != want {
		t.Errorf("codec = %q, want %q", track.Codec, want)
	}
	if track.Fmt.Channels != spec.Channels {
		t.Errorf("channels = %d, want %d", track.Fmt.Channels, spec.Channels)
	}
	wantRate := spec.SampleRate
	if spec.Codec == fixtures.CodecOpus {
		wantRate = 48000 // Opus always decodes at 48 kHz
	}
	if track.Fmt.Rate != wantRate {
		t.Errorf("rate = %d, want %d", track.Fmt.Rate, wantRate)
	}

	frames, err := decodeFrames(med)
	if err != nil {
		t.Fatalf("decoding: %v", err)
	}
	want := int64(spec.Duration * time.Duration(track.Fmt.Rate) / time.Second)
	// Lossy codec priming/padding (ADTS carries no gapless signaling at
	// all) stretches the decoded length a little; 15% covers it at 1 s.
	if tol := want * 15 / 100; frames < want-tol || frames > want+tol {
		t.Errorf("decoded %d frames, want %d +-%d", frames, want, tol)
	}
}

func TestDefaultLibrary(t *testing.T) {
	specs := fixtures.DefaultLibrary()
	dir := t.TempDir()
	paths, err := fixtures.Generate(dir, specs...)
	if err != nil {
		t.Fatal(err)
	}
	if len(paths) != len(specs) {
		t.Fatalf("got %d paths for %d specs", len(paths), len(specs))
	}
	for i, spec := range specs {
		if spec.Corrupt != fixtures.CorruptNone {
			continue // corrupt flavors are covered by TestCorrupt
		}
		t.Run(filepath.Base(paths[i]), func(t *testing.T) {
			verifySpec(t, spec, paths[i])
		})
	}
}

func TestConformanceMedia(t *testing.T) {
	specs := fixtures.ConformanceMedia()
	dir := t.TempDir()
	paths, err := fixtures.Generate(dir, specs...)
	if err != nil {
		t.Fatal(err)
	}
	if len(paths) != len(specs) {
		t.Fatalf("got %d paths for %d specs", len(paths), len(specs))
	}
	for i, spec := range specs {
		t.Run(filepath.Base(paths[i]), func(t *testing.T) {
			verifySpec(t, spec, paths[i])
		})
	}
}

func TestDeterministic(t *testing.T) {
	specs := fixtures.DefaultLibrary()
	dirA, dirB := t.TempDir(), t.TempDir()
	pathsA, err := fixtures.Generate(dirA, specs...)
	if err != nil {
		t.Fatal(err)
	}
	pathsB, err := fixtures.Generate(dirB, specs...)
	if err != nil {
		t.Fatal(err)
	}
	for i := range specs {
		a, err := os.ReadFile(pathsA[i])
		if err != nil {
			t.Fatal(err)
		}
		b, err := os.ReadFile(pathsB[i])
		if err != nil {
			t.Fatal(err)
		}
		if sha256.Sum256(a) != sha256.Sum256(b) {
			t.Errorf("%s: two generations differ (%d vs %d bytes)", filepath.Base(pathsA[i]), len(a), len(b))
		}
		if len(a) == 0 {
			t.Errorf("%s: empty file", filepath.Base(pathsA[i]))
		}
	}
}

func TestSilencePadding(t *testing.T) {
	spec := fixtures.Spec{
		Codec:        fixtures.CodecFLAC,
		Container:    fixtures.ContainerFLAC,
		Duration:     time.Second,
		LeadSilence:  2 * time.Second,
		TrailSilence: time.Second,
		SampleRate:   44100,
		Channels:     2,
	}
	dir := t.TempDir()
	paths, err := fixtures.Generate(dir, spec)
	if err != nil {
		t.Fatal(err)
	}
	med := openFixture(t, paths[0])
	frames, err := decodeFrames(med)
	if err != nil {
		t.Fatalf("decoding: %v", err)
	}
	// FLAC is lossless: the decoded length is exactly the padded total.
	total := spec.LeadSilence + spec.Duration + spec.TrailSilence
	want := int64(total * time.Duration(spec.SampleRate) / time.Second)
	if frames != want {
		t.Errorf("decoded %d frames, want %d (2s lead + 1s tone + 1s trail)", frames, want)
	}
}

func TestSilencePaddingCapped(t *testing.T) {
	spec := fixtures.Spec{
		Codec:        fixtures.CodecFLAC,
		Duration:     8 * time.Second,
		LeadSilence:  2 * time.Second,
		TrailSilence: time.Second,
	}
	if _, err := fixtures.Generate(t.TempDir(), spec); err == nil {
		t.Error("Generate accepted 11s of padded audio over the 10s cap")
	}
}

func TestSilenceZeroBytesIdentical(t *testing.T) {
	// A spec with explicit zero silence must produce byte-identical
	// output to one that never mentions the fields.
	plain := fixtures.Spec{Name: "same", Codec: fixtures.CodecFLAC, Duration: time.Second}
	padded := plain
	padded.LeadSilence, padded.TrailSilence = 0, 0
	dirA, dirB := t.TempDir(), t.TempDir()
	pa, err := fixtures.Generate(dirA, plain)
	if err != nil {
		t.Fatal(err)
	}
	pb, err := fixtures.Generate(dirB, padded)
	if err != nil {
		t.Fatal(err)
	}
	a, _ := os.ReadFile(pa[0])
	b, _ := os.ReadFile(pb[0])
	if sha256.Sum256(a) != sha256.Sum256(b) {
		t.Error("zero-valued silence fields changed the output bytes")
	}
}

func TestCorrupt(t *testing.T) {
	base := fixtures.Spec{Codec: fixtures.CodecFLAC, Duration: time.Second, SampleRate: 44100, Channels: 2}
	truncated, garbage := base, base
	truncated.Corrupt = fixtures.CorruptTruncated
	garbage.Corrupt = fixtures.CorruptGarbage

	dir := t.TempDir()
	paths, err := fixtures.Generate(dir, truncated, garbage)
	if err != nil {
		t.Fatal(err)
	}

	t.Run("garbage", func(t *testing.T) {
		// Garbage must fail to open even with the extension hint a
		// server would pass along.
		raw, err := os.ReadFile(paths[1])
		if err != nil {
			t.Fatal(err)
		}
		if _, err := format.Open(container.BytesSource(raw), "flac", nil); err == nil {
			t.Error("format.Open succeeded on garbage bytes")
		}
	})

	t.Run("truncated", func(t *testing.T) {
		// The header half survives, so probing succeeds; a full decode
		// must either error out or come up short.
		med := openFixture(t, paths[0])
		want := int64(44100)
		frames, err := decodeFrames(med)
		if err == nil && frames >= want {
			t.Errorf("decoded %d of %d frames from a half-truncated file without error", frames, want)
		}
	})
}

func TestFilenames(t *testing.T) {
	cases := []struct {
		spec fixtures.Spec
		want string
	}{
		{fixtures.Spec{Codec: fixtures.CodecFLAC}, "flac-1000ms-44100hz-2ch.flac"},
		{fixtures.Spec{Codec: fixtures.CodecOpus}, "opus-1000ms-48000hz-2ch.opus"},
		{fixtures.Spec{Codec: fixtures.CodecAAC}, "aac-1000ms-44100hz-2ch.aac"},
		{fixtures.Spec{Codec: fixtures.CodecAAC, Container: fixtures.ContainerMP4}, "aac-mp4-1000ms-44100hz-2ch.m4a"},
		{fixtures.Spec{Codec: fixtures.CodecFLAC, Corrupt: fixtures.CorruptGarbage}, "flac-garbage-1000ms-44100hz-2ch.flac"},
		{fixtures.Spec{Name: "custom", Codec: fixtures.CodecMP3}, "custom.mp3"},
		{fixtures.Spec{Codec: fixtures.CodecMP3, Duration: 3 * time.Second, LeadSilence: 1500 * time.Millisecond, TrailSilence: time.Second},
			"mp3-3000ms-lead1500ms-trail1000ms-44100hz-2ch.mp3"},
	}
	for _, c := range cases {
		if got := c.spec.Filename(); got != c.want {
			t.Errorf("Filename() = %q, want %q", got, c.want)
		}
	}
	if strings.Contains(fixtures.Spec{Codec: "nope"}.Filename(), "flac") {
		t.Error("unsupported codec leaked a real extension")
	}
}
