// Package fixtures synthesizes the tiny audio files WaxDeck's tests run
// against. The repository policy is "no binary media in git": every test
// asset is generated at test-setup from a Spec: a deterministic sine
// tone encoded through WaxFlow's own encoders and muxers. No external
// tools are involved. Output is byte-deterministic: the same Spec
// always yields the same file.
//
// Library use:
//
//	paths, err := fixtures.Generate(dir, fixtures.DefaultLibrary()...)
//
// CLI use:
//
//	go run ./cmd/fixturegen -out testdata/media
package fixtures

import (
	"context"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxflow"
	"github.com/colespringer/waxflow/container"
	"github.com/colespringer/waxlabel/tag"
)

// Codec names an audio codec a Spec can ask for.
type Codec string

const (
	CodecPCM    Codec = "pcm"
	CodecFLAC   Codec = "flac"
	CodecMP3    Codec = "mp3"
	CodecAAC    Codec = "aac"
	CodecALAC   Codec = "alac"
	CodecOpus   Codec = "opus"
	CodecVorbis Codec = "vorbis"
)

// Container names the file container a Spec's codec is muxed into.
type Container string

const (
	// ContainerDefault selects the codec's default container: WAV for
	// PCM, ADTS for AAC, MP4 for ALAC, Ogg for Opus and Vorbis, and
	// the codec's own stream form for FLAC and MP3.
	ContainerDefault  Container = ""
	ContainerWAV      Container = "wav"
	ContainerAIFF     Container = "aiff"
	ContainerFLAC     Container = "flac"
	ContainerMP3      Container = "mp3"
	ContainerMP4      Container = "mp4"
	ContainerADTS     Container = "adts"
	ContainerOgg      Container = "ogg"
	ContainerMatroska Container = "mka"
)

// Corruption selects a deliberately malformed flavor of a Spec, for
// robustness tests. Corrupt fixtures are synthesized like everything
// else; no binary media is vendored.
type Corruption string

const (
	// CorruptNone produces a valid file.
	CorruptNone Corruption = ""
	// CorruptTruncated produces the valid encode cut off at half its
	// length: headers survive, the stream ends mid-file.
	CorruptTruncated Corruption = "truncated"
	// CorruptGarbage produces deterministic junk bytes under the spec's
	// file extension: no valid magic, no parsable structure. Garbage
	// needs no encoder, so it never requires ffmpeg.
	CorruptGarbage Corruption = "garbage"
)

// Chapter is one chapter marker to embed where the container supports
// them (MP4 today).
type Chapter struct {
	Start time.Duration
	End   time.Duration
	Title string
}

// Spec describes one fixture file to synthesize.
type Spec struct {
	// Name overrides the generated file's base name (without the
	// extension). Empty derives a deterministic name from the fields.
	Name string
	// Codec selects the audio codec. Required.
	Codec Codec
	// Container selects the file container; ContainerDefault picks the
	// codec's native one.
	Container Container
	// Duration is the length of the synthesized tone, capped at
	// MaxDuration to keep fixtures tiny; 0 means 1 second.
	Duration time.Duration
	// LeadSilence prepends literal zero samples before the tone. Zero
	// means none; the output is then byte-identical to a spec without
	// the field. LeadSilence + Duration + TrailSilence must stay within
	// MaxDuration.
	LeadSilence time.Duration
	// TrailSilence appends literal zero samples after the tone. Zero
	// means none.
	TrailSilence time.Duration
	// SampleRate is in Hz; 0 means 44100 (48000 for Opus, which always
	// runs at 48 kHz anyway).
	SampleRate int
	// Channels is the channel count; 0 means 2 (stereo).
	Channels int
	// Corrupt selects a malformed flavor; the zero value is a valid file.
	Corrupt Corruption
	// Tags are metadata fields (TITLE, ARTIST, ...) embedded where the
	// container has a stream form for them. Keys are written in sorted
	// order so tagged output stays deterministic.
	Tags map[string]string
	// Chapters are chapter markers, embedded where the container
	// supports them.
	Chapters []Chapter
}

// MaxDuration bounds a Spec's synthesized audio, silence included.
// Fixtures exist to be tiny; anything longer is a misuse this package
// refuses.
const MaxDuration = 10 * time.Second

// route describes how one codec+container pair is produced through
// WaxFlow's Transcode: the output format name and, where the pair is
// not the format's default form, the container override.
type route struct {
	ext     string
	format  string // WaxFlow TranscodeOptions.Format
	variant string // WaxFlow TranscodeOptions.Container override

	// Whether this route's muxer matches tag keys against a table of
	// canonical names (ID3 and MP4 do; a Vorbis comment block takes what
	// it is given). See canonicalTagKey.
	canonicalKeys bool
}

// routes is the supported codec/container matrix. The MP4 routes use
// WaxFlow's "progressive" container override: flat moov+mdat files its
// own format registry demuxes back, where the default MP4 form is
// fragmented CMAF.
var routes = map[Codec]map[Container]route{
	CodecPCM: {
		ContainerWAV:  {ext: "wav", format: "wav"},
		ContainerAIFF: {ext: "aiff", format: "aiff"},
	},
	CodecFLAC: {
		ContainerFLAC:     {ext: "flac", format: "flac"},
		ContainerMatroska: {ext: "mka", format: "flac", variant: "mka"},
	},
	CodecMP3: {
		ContainerMP3: {ext: "mp3", format: "mp3", canonicalKeys: true},
	},
	CodecAAC: {
		ContainerADTS: {ext: "aac", format: "aac", variant: "adts"},
		ContainerMP4:  {ext: "m4a", format: "aac", variant: "progressive", canonicalKeys: true},
	},
	CodecALAC: {
		ContainerMP4: {ext: "m4a", format: "alac", variant: "progressive", canonicalKeys: true},
	},
	CodecOpus: {
		ContainerOgg: {ext: "opus", format: "opus"},
	},
	CodecVorbis: {
		ContainerOgg: {ext: "ogg", format: "vorbis"},
	},
}

// defaultContainers maps each codec to its native container.
var defaultContainers = map[Codec]Container{
	CodecPCM:    ContainerWAV,
	CodecFLAC:   ContainerFLAC,
	CodecMP3:    ContainerMP3,
	CodecAAC:    ContainerADTS,
	CodecALAC:   ContainerMP4,
	CodecOpus:   ContainerOgg,
	CodecVorbis: ContainerOgg,
}

// withDefaults fills a Spec's zero values with the documented defaults.
func (s Spec) withDefaults() Spec {
	if s.Duration == 0 {
		s.Duration = time.Second
	}
	if s.Channels == 0 {
		s.Channels = 2
	}
	if s.SampleRate == 0 {
		if s.Codec == CodecOpus {
			s.SampleRate = 48000
		} else {
			s.SampleRate = 44100
		}
	}
	if s.Container == ContainerDefault {
		s.Container = defaultContainers[s.Codec]
	}
	return s
}

// route resolves the defaulted spec against the supported matrix.
func (s Spec) route() (route, error) {
	byContainer, ok := routes[s.Codec]
	if !ok {
		return route{}, fmt.Errorf("fixtures: unknown codec %q", s.Codec)
	}
	r, ok := byContainer[s.Container]
	if !ok {
		return route{}, fmt.Errorf("fixtures: codec %q has no %q container route", s.Codec, s.Container)
	}
	return r, nil
}

// validate rejects specs Generate cannot honor, before any work starts.
func (s Spec) validate() error {
	if _, err := s.route(); err != nil {
		return err
	}
	if s.Duration <= 0 || s.Duration > MaxDuration {
		return fmt.Errorf("fixtures: duration %v outside (0, %v]", s.Duration, MaxDuration)
	}
	if s.LeadSilence < 0 || s.TrailSilence < 0 {
		return fmt.Errorf("fixtures: negative silence (lead %v, trail %v)", s.LeadSilence, s.TrailSilence)
	}
	if total := s.LeadSilence + s.Duration + s.TrailSilence; total > MaxDuration {
		return fmt.Errorf("fixtures: total duration %v (silence included) exceeds %v", total, MaxDuration)
	}
	if s.SampleRate < 1 {
		return fmt.Errorf("fixtures: sample rate %d must be positive", s.SampleRate)
	}
	if s.Channels < 1 || s.Channels > 8 {
		return fmt.Errorf("fixtures: %d channels outside 1..8", s.Channels)
	}
	return nil
}

// Filename is the deterministic base name Generate writes the spec to,
// extension included. An unsupported codec/container pair yields a
// ".bin" placeholder name; Generate rejects such specs with an error.
func (s Spec) Filename() string {
	s = s.withDefaults()
	ext := "bin"
	if r, err := s.route(); err == nil {
		ext = r.ext
	}
	base := s.Name
	if base == "" {
		parts := []string{string(s.Codec)}
		if s.Container != defaultContainers[s.Codec] {
			parts = append(parts, string(s.Container))
		}
		if s.Corrupt != CorruptNone {
			parts = append(parts, string(s.Corrupt))
		}
		parts = append(parts, fmt.Sprintf("%dms", s.Duration.Milliseconds()))
		if s.LeadSilence > 0 {
			parts = append(parts, fmt.Sprintf("lead%dms", s.LeadSilence.Milliseconds()))
		}
		if s.TrailSilence > 0 {
			parts = append(parts, fmt.Sprintf("trail%dms", s.TrailSilence.Milliseconds()))
		}
		parts = append(parts,
			fmt.Sprintf("%dhz", s.SampleRate),
			fmt.Sprintf("%dch", s.Channels))
		base = strings.Join(parts, "-")
	}
	return base + "." + ext
}

// DefaultLibrary is the preset covering the full supported
// codec/container matrix (PCM in WAV and AIFF, FLAC in its stream form
// and in Matroska, MP3, AAC in ADTS and MP4, ALAC in MP4, Opus in Ogg,
// and Vorbis in Ogg), plus one truncated and one garbage flavor. Specs
// are fully spelled out (no zero-value defaults) so callers can read
// expected properties off them.
func DefaultLibrary() []Spec {
	full := func(codec Codec, c Container, corrupt Corruption) Spec {
		rate := 44100
		if codec == CodecOpus {
			rate = 48000
		}
		if c == ContainerDefault {
			c = defaultContainers[codec]
		}
		return Spec{
			Codec:      codec,
			Container:  c,
			Duration:   time.Second,
			SampleRate: rate,
			Channels:   2,
			Corrupt:    corrupt,
		}
	}
	return []Spec{
		full(CodecPCM, ContainerWAV, CorruptNone),
		full(CodecPCM, ContainerAIFF, CorruptNone),
		full(CodecFLAC, ContainerDefault, CorruptNone),
		full(CodecFLAC, ContainerMatroska, CorruptNone),
		full(CodecMP3, ContainerDefault, CorruptNone),
		full(CodecAAC, ContainerADTS, CorruptNone),
		full(CodecAAC, ContainerMP4, CorruptNone),
		full(CodecALAC, ContainerMP4, CorruptNone),
		full(CodecOpus, ContainerDefault, CorruptNone),
		full(CodecVorbis, ContainerDefault, CorruptNone),
		full(CodecFLAC, ContainerDefault, CorruptTruncated),
		full(CodecFLAC, ContainerDefault, CorruptGarbage),
	}
}

// DemoLibrary is a small tagged album: one track per commonly streamed
// codec, titled so tests and humans can find them by name. End-to-end
// harnesses scan it alongside DefaultLibrary. Durations are distinct on
// purpose: a catalog's fingerprint dedup would otherwise merge these
// with the matrix files, which synthesize the same tone at the same
// length.
func DemoLibrary() []Spec {
	track := func(name, title string, codec Codec, d time.Duration) Spec {
		return Spec{
			Name:     name,
			Codec:    codec,
			Duration: d,
			Tags: map[string]string{
				"TITLE":  title,
				"ARTIST": "Fixture Artist",
				"ALBUM":  "Fixture Album",
			},
		}
	}
	return []Spec{
		track("alpha", "Alpha Song", CodecFLAC, 2*time.Second),
		track("bravo", "Bravo Song", CodecMP3, 2500*time.Millisecond),
		track("charlie", "Charlie Song", CodecOpus, 3*time.Second),
		track("delta", "Delta Song", CodecVorbis, 3500*time.Millisecond),
	}
}

// UploadSources is the manual-upload journey's source material: a
// two-track album plus a standalone single, whose artists, albums, and
// titles appear in no other preset, so an end-to-end import can assert
// them uniquely against the scanned library. The single is the
// declined-identify journey's own file - declining imports on arrival,
// so a file another upload test imports would race it for the
// destination and flag it as a duplicate. Durations are distinct from
// every other preset for the same fingerprint-dedup reason as
// DemoLibrary.
func UploadSources() []Spec {
	track := func(name, title, trackNo string, d time.Duration) Spec {
		return Spec{
			Name:     name,
			Codec:    CodecMP3,
			Duration: d,
			Tags: map[string]string{
				"TITLE":       title,
				"ARTIST":      "Courier North",
				"ALBUM":       "Paper Lanterns",
				"TRACKNUMBER": trackNo,
			},
		}
	}
	return []Spec{
		track("lantern-one", "Paper Lanterns", "1", 4200*time.Millisecond),
		track("lantern-two", "River Static", "2", 4700*time.Millisecond),
		{
			Name:     "sodium-sky",
			Codec:    CodecMP3,
			Duration: 5300 * time.Millisecond,
			Tags: map[string]string{
				"TITLE":       "Sodium Sky",
				"ARTIST":      "Night Transit",
				"ALBUM":       "Sodium Sky",
				"TRACKNUMBER": "1",
			},
		},
	}
}

// UploadFolderSources is the folder-pick journey's source material,
// which has to be its own album: the folder test and the file test run
// against one server, and reusing UploadSources would have each one
// importing the other's release and racing it for the destination.
// Distinct durations again, for the fingerprint-dedup reason.
//
// Written under a disc subdirectory by the e2e stack, so what the pick
// walks is a tree rather than a flat folder - which is the half of a
// folder upload a flat one would never prove.
func UploadFolderSources() []Spec {
	track := func(name, title, trackNo string, d time.Duration) Spec {
		return Spec{
			Name:     name,
			Codec:    CodecMP3,
			Duration: d,
			Tags: map[string]string{
				"TITLE":       title,
				"ARTIST":      "Tin Compass",
				"ALBUM":       "Harbour Lights",
				"TRACKNUMBER": trackNo,
			},
		}
	}
	return []Spec{
		track("harbour-one", "Harbour Lights", "1", 6100*time.Millisecond),
		track("harbour-two", "Breakwater", "2", 6600*time.Millisecond),
	}
}

// UploadWorkbenchSources is the release-workbench journey's own album,
// its own for the UploadFolderSources reason: that journey imports and
// then renames a release, and had it reused the lantern album its
// import would hold the destination the manual-upload journey's own
// import needs (the rename regroups the catalog but moves no files).
// Distinct durations, same fingerprint-dedup reason as everywhere.
func UploadWorkbenchSources() []Spec {
	track := func(name, title, trackNo string, d time.Duration) Spec {
		return Spec{
			Name:     name,
			Codec:    CodecMP3,
			Duration: d,
			Tags: map[string]string{
				"TITLE":       title,
				"ARTIST":      "Meridian Delay",
				"ALBUM":       "Tin Meridian",
				"TRACKNUMBER": trackNo,
			},
		}
	}
	return []Spec{
		track("meridian-one", "Tin Meridian", "1", 7100*time.Millisecond),
		track("meridian-two", "Ledger Lines", "2", 7600*time.Millisecond),
	}
}

// ConformanceMedia returns the single tone the audio-engine conformance
// suite plays against real engines: long enough that mid-file seek
// targets are meaningfully far apart, still under the duration cap.
func ConformanceMedia() []Spec {
	return []Spec{{
		Name:       "conformance-tone",
		Codec:      CodecFLAC,
		Container:  ContainerFLAC,
		Duration:   8 * time.Second,
		SampleRate: 44100,
		Channels:   2,
	}}
}

// engine is the shared WaxFlow entry point; it is safe for concurrent use.
var engine = waxflow.New()

// Generate synthesizes each spec into dir (created if absent) and
// returns the written paths, in spec order. It stops at the first
// failure, returning the paths written so far alongside the error.
func Generate(dir string, specs ...Spec) ([]string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("fixtures: creating %s: %w", dir, err)
	}
	paths := make([]string, 0, len(specs))
	for _, spec := range specs {
		path, err := generateOne(dir, spec)
		if err != nil {
			return paths, fmt.Errorf("fixtures: generating %s: %w", spec.Filename(), err)
		}
		paths = append(paths, path)
	}
	return paths, nil
}

// generateOne renders one spec's bytes, applies any corruption, and
// writes the file.
func generateOne(dir string, spec Spec) (string, error) {
	s := spec.withDefaults()
	if err := s.validate(); err != nil {
		return "", err
	}
	var data []byte
	if s.Corrupt == CorruptGarbage {
		data = garbageBytes()
	} else {
		var err error
		data, err = s.renderCached()
		if err != nil {
			return "", err
		}
		if s.Corrupt == CorruptTruncated {
			data = data[:len(data)/2]
		}
	}
	path := filepath.Join(dir, s.Filename())
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return "", err
	}
	return path, nil
}

// renderCache memoizes rendered bytes per normalized spec for the life
// of the process. Encoding is the expensive half of a fixture (an
// integration suite synthesizes the same handful of files for hundreds
// of harnesses) and the package's own contract makes reuse sound: the
// same Spec always yields the same bytes. Bounded by MaxDuration times
// however many distinct specs a test binary uses. Values are shared,
// never mutated: corruption slices or replaces, and writing only reads.
var renderCache sync.Map // renderKey -> *renderOnce

type renderOnce struct {
	once sync.Once
	data []byte
	err  error
}

// renderCached returns the spec's rendered bytes, encoding them on the
// spec's first use in this process. The caller must treat the result
// as read-only.
func (s Spec) renderCached() ([]byte, error) {
	// Corruption is applied per call downstream, so flavors of one
	// spec share the clean encode.
	k := s
	k.Corrupt = CorruptNone
	// fmt prints map keys sorted, so the key is stable across runs and
	// covers every field render reads without naming them one by one.
	key := fmt.Sprintf("%#v", k)
	v, _ := renderCache.LoadOrStore(key, &renderOnce{})
	ro := v.(*renderOnce)
	ro.once.Do(func() {
		r, _ := s.route() // validate already resolved it
		ro.data, ro.err = s.render(r)
	})
	return ro.data, ro.err
}

// render encodes the spec's synthesized tone into its target format
// through WaxFlow's Transcode.
func (s Spec) render(r route) ([]byte, error) {
	wav, err := buildSourceWAV(s)
	if err != nil {
		return nil, err
	}
	dst := &memWriteSeeker{}
	opts := waxflow.TranscodeOptions{
		Format:    r.format,
		Container: r.variant,
		Tags:      containerTags(s.Tags, r),
		Chapters:  containerChapters(s.Chapters),
	}
	if _, err := engine.Transcode(context.Background(), container.BytesSource(wav), "wav", dst, opts); err != nil {
		return nil, err
	}
	return dst.b, nil
}

// containerTags converts the Spec's tag map to WaxFlow's slice form,
// sorted by key so tagged output stays deterministic.
//
// Spellings are folded onto their canonical key only for the routes
// whose muxers match on one. Everywhere else the caller's spelling is
// what goes in the file, because that is what a real encoder writes and
// imitating real files is the whole job here.
func containerTags(m map[string]string, r route) []container.Tag {
	if len(m) == 0 {
		return nil
	}
	tags := make([]container.Tag, 0, len(m))
	for k, v := range m {
		key := strings.ToUpper(k)
		if r.canonicalKeys {
			key = canonicalTagKey(key)
		}
		tags = append(tags, container.Tag{Key: key, Value: v})
	}
	slices.SortFunc(tags, func(a, b container.Tag) int {
		if c := strings.Compare(a.Key, b.Key); c != 0 {
			return c
		}
		return strings.Compare(a.Value, b.Value)
	})
	// Folding can bring two spellings onto one key - WaxLabel reads both
	// DATE and YEAR as RECORDINGDATE - and a muxer handed the same field
	// twice is not being asked a question it can answer. The sort above
	// makes which one survives deterministic rather than map order.
	return slices.CompactFunc(tags, func(a, b container.Tag) bool {
		return a.Key == b.Key
	})
}

// canonicalTagKey folds a caller's spelling onto the key the ID3 and MP4
// tables match on.
//
// Those two do raw key matching against tables that know only canonical
// names: an mpa muxer handed DATE writes no date frame at all, silently.
// A Vorbis comment block is written verbatim instead, and a reader's
// alias table picks DATE back up - so the same Spec produced a dated
// FLAC and an undated MP3, and every test comparing the two read that as
// a bug somewhere else. Folding everywhere would fix that by putting a
// RECORDINGDATE= in a FLAC, which no ripper writes.
//
// WaxLabel's own table, rather than a second one here: it is what reads
// these files back, so the two agree by construction.
func canonicalTagKey(key string) string {
	upper := strings.ToUpper(key)
	if canonical, ok := tag.AliasKey(upper); ok {
		return string(canonical)
	}
	return upper
}

// containerChapters converts the Spec's chapters to WaxFlow's form.
func containerChapters(cs []Chapter) []container.Chapter {
	if len(cs) == 0 {
		return nil
	}
	out := make([]container.Chapter, len(cs))
	for i, c := range cs {
		out[i] = container.Chapter{Start: c.Start, End: c.End, Title: c.Title}
	}
	return out
}

// garbageLen sizes a garbage fixture: enough to exercise sniffing and
// header parsing, small enough to stay trivial.
const garbageLen = 4096

// garbageBytes returns deterministic junk from a fixed-seed PCG. Bytes
// are masked to 0x00..0x7F so the MPEG sync word (which starts 0xFF and
// deliberately matches loosely) can never appear; the test suite pins
// that no registered container magic matches either.
func garbageBytes() []byte {
	rng := rand.New(rand.NewPCG(0x57617844, 0x6563646B)) // "WaxD", "ecdk"
	b := make([]byte, garbageLen)
	for i := range b {
		b[i] = byte(rng.Uint64()) & 0x7F
	}
	return b
}

// memWriteSeeker is an in-memory io.WriteSeeker for muxers that
// back-patch headers (AIFF, exact WAV sizes).
type memWriteSeeker struct {
	b   []byte
	pos int64
}

func (w *memWriteSeeker) Write(p []byte) (int, error) {
	if need := w.pos + int64(len(p)); need > int64(len(w.b)) {
		grown := make([]byte, need)
		copy(grown, w.b)
		w.b = grown
	}
	copy(w.b[w.pos:], p)
	w.pos += int64(len(p))
	return len(p), nil
}

func (w *memWriteSeeker) Seek(off int64, whence int) (int64, error) {
	switch whence {
	case io.SeekStart:
		w.pos = off
	case io.SeekCurrent:
		w.pos += off
	case io.SeekEnd:
		w.pos = int64(len(w.b)) + off
	default:
		return 0, fmt.Errorf("fixtures: bad seek whence %d", whence)
	}
	if w.pos < 0 {
		return 0, fmt.Errorf("fixtures: seek to negative offset %d", w.pos)
	}
	return w.pos, nil
}
