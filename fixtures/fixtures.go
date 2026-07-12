// Package fixtures synthesizes the tiny audio files WaxDeck's tests run
// against. The repository policy is "no binary media in git": every test
// asset is generated at test-setup from a Spec: a deterministic sine
// tone encoded through WaxFlow's own encoders where they exist, and
// through a host ffmpeg for the formats they cannot produce (Vorbis,
// Matroska). Output is byte-deterministic: the same Spec always yields
// the same file.
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
	"maps"
	"math/rand/v2"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/colespringer/waxflow"
	"github.com/colespringer/waxflow/container"
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
	CodecVorbis Codec = "vorbis" // ffmpeg-only: WaxFlow decodes but does not encode Vorbis
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
	ContainerMatroska Container = "mka" // ffmpeg-only: WaxFlow demuxes but does not mux Matroska
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
	// Duration is the length of synthesized audio, capped at
	// MaxDuration to keep fixtures tiny; 0 means 1 second.
	Duration time.Duration
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

// MaxDuration bounds a Spec's synthesized audio. Fixtures exist to be
// tiny; anything longer is a misuse this package refuses.
const MaxDuration = 10 * time.Second

// route describes how one codec+container pair is produced: through
// WaxFlow's Transcode (format, variant) or through ffmpeg (ffArgs).
type route struct {
	ext     string
	format  string   // WaxFlow TranscodeOptions.Format
	variant string   // WaxFlow TranscodeOptions.Container override
	ffArgs  []string // ffmpeg codec+mux arguments; non-nil marks an ffmpeg route
	// ffAlt is a second ffmpeg argument set tried when ffArgs fails
	// (builds without libvorbis fall back to the built-in encoder).
	ffAlt []string
}

// routes is the supported codec/container matrix.
var routes = map[Codec]map[Container]route{
	CodecPCM: {
		ContainerWAV:  {ext: "wav", format: "wav"},
		ContainerAIFF: {ext: "aiff", format: "aiff"},
	},
	CodecFLAC: {
		ContainerFLAC: {ext: "flac", format: "flac"},
		ContainerMatroska: {
			ext:    "mka",
			ffArgs: []string{"-c:a", "flac", "-f", "matroska"},
		},
	},
	CodecMP3: {
		ContainerMP3: {ext: "mp3", format: "mp3"},
	},
	// WaxFlow's native MP4 output is fragmented, which its own demuxer
	// cannot read back (it reads progressive sample tables only), so
	// AAC's native route is the ADTS stream and the MP4 routes go
	// through ffmpeg's always-built-in aac/alac encoders to get
	// progressive, registry-decodable files.
	CodecAAC: {
		ContainerADTS: {ext: "aac", format: "aac", variant: "adts"},
		ContainerMP4: {
			ext:    "m4a",
			ffArgs: []string{"-c:a", "aac", "-f", "mp4"},
		},
	},
	CodecALAC: {
		ContainerMP4: {
			ext:    "m4a",
			ffArgs: []string{"-c:a", "alac", "-f", "mp4"},
		},
	},
	CodecOpus: {
		ContainerOgg: {ext: "opus", format: "opus"},
	},
	CodecVorbis: {
		ContainerOgg: {
			ext:    "ogg",
			ffArgs: []string{"-c:a", "libvorbis", "-f", "ogg"},
			ffAlt:  []string{"-c:a", "vorbis", "-strict", "-2", "-f", "ogg"},
		},
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
	if s.SampleRate < 1 {
		return fmt.Errorf("fixtures: sample rate %d must be positive", s.SampleRate)
	}
	if s.Channels < 1 || s.Channels > 8 {
		return fmt.Errorf("fixtures: %d channels outside 1..8", s.Channels)
	}
	return nil
}

// NeedsFFmpeg reports whether generating this spec shells out to ffmpeg:
// true only for what WaxFlow cannot produce itself (Vorbis, Matroska,
// progressive MP4), and never for garbage flavors, which need no
// encoder at all.
func (s Spec) NeedsFFmpeg() bool {
	r, err := s.withDefaults().route()
	return err == nil && r.ffArgs != nil && s.Corrupt != CorruptGarbage
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
		parts = append(parts,
			fmt.Sprintf("%dms", s.Duration.Milliseconds()),
			fmt.Sprintf("%dhz", s.SampleRate),
			fmt.Sprintf("%dch", s.Channels))
		base = strings.Join(parts, "-")
	}
	return base + "." + ext
}

// DefaultLibrary is the preset covering every codec/container pair
// WaxFlow both encodes natively and can decode back through its format
// registry (PCM in WAV and AIFF, FLAC, MP3, AAC in ADTS, and Opus), plus
// one truncated and one garbage flavor. Generating it never needs
// ffmpeg. Specs are fully spelled out (no zero-value defaults) so
// callers can read expected properties off them.
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
		full(CodecMP3, ContainerDefault, CorruptNone),
		full(CodecAAC, ContainerADTS, CorruptNone),
		full(CodecOpus, ContainerDefault, CorruptNone),
		full(CodecFLAC, ContainerDefault, CorruptTruncated),
		full(CodecFLAC, ContainerDefault, CorruptGarbage),
	}
}

// FFmpegLibrary is the preset covering formats WaxFlow decodes but
// cannot produce itself: Vorbis in Ogg, FLAC in Matroska, and AAC/ALAC
// in progressive MP4. Generating it requires ffmpeg on PATH; without
// one, Generate returns ErrNeedsFFmpeg and tests skip these specs.
func FFmpegLibrary() []Spec {
	sec := func(codec Codec, c Container) Spec {
		return Spec{Codec: codec, Container: c, Duration: time.Second, SampleRate: 44100, Channels: 2}
	}
	return []Spec{
		sec(CodecVorbis, ContainerOgg),
		sec(CodecFLAC, ContainerMatroska),
		sec(CodecAAC, ContainerMP4),
		sec(CodecALAC, ContainerMP4),
	}
}

// engine is the shared WaxFlow entry point; it is safe for concurrent use.
var engine = waxflow.New()

// Generate synthesizes each spec into dir (created if absent) and
// returns the written paths, in spec order. It stops at the first
// failure, returning the paths written so far alongside the error; a
// spec that needs an absent ffmpeg fails with an error matching
// ErrNeedsFFmpeg.
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
		r, _ := s.route() // validate already resolved it
		var err error
		data, err = s.render(r)
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

// render encodes the spec's synthesized tone into its target format:
// natively through WaxFlow's Transcode, or through ffmpeg for the
// formats WaxFlow cannot encode.
func (s Spec) render(r route) ([]byte, error) {
	wav, err := buildSourceWAV(s)
	if err != nil {
		return nil, err
	}
	if r.ffArgs != nil {
		return renderFFmpeg(wav, r)
	}
	dst := &memWriteSeeker{}
	opts := waxflow.TranscodeOptions{
		Format:    r.format,
		Container: r.variant,
		Tags:      containerTags(s.Tags),
		Chapters:  containerChapters(s.Chapters),
	}
	if _, err := engine.Transcode(context.Background(), container.BytesSource(wav), "wav", dst, opts); err != nil {
		return nil, err
	}
	return dst.b, nil
}

// containerTags converts the Spec's tag map to WaxFlow's slice form,
// sorted by key so tagged output stays deterministic.
func containerTags(m map[string]string) []container.Tag {
	if len(m) == 0 {
		return nil
	}
	tags := make([]container.Tag, 0, len(m))
	for _, k := range slices.Sorted(maps.Keys(m)) {
		tags = append(tags, container.Tag{Key: k, Value: m[k]})
	}
	return tags
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
