# fixtures

Test-media generator for WaxDeck. The repository policy is **no binary
media in git**: every audio file a test needs is synthesized at
test-setup from a `Spec`: a deterministic sine tone (440 Hz per
channel, times the channel index) encoded into the requested
codec/container. The same spec always produces the same bytes.

It is a Go module usable as a library and as a CLI.

## Library

```go
import "github.com/colespringer/waxdeck/fixtures"

// Everything WaxFlow encodes natively (no ffmpeg needed).
paths, err := fixtures.Generate(dir, fixtures.DefaultLibrary()...)

// One custom file.
paths, err = fixtures.Generate(dir, fixtures.Spec{
    Codec:      fixtures.CodecFLAC,
    Duration:   2 * time.Second,
    SampleRate: 48000,
    Channels:   1,
    Tags:       map[string]string{"TITLE": "Fixture"},
})
```

`Spec` fields: `Codec`, `Container` (empty picks the codec's default),
`Duration` (default 1 s, capped at 10 s), `SampleRate` (default 44100;
Opus 48000), `Channels` (default 2), `Corrupt`, `Tags`, `Chapters`,
`Name`. `Spec.Filename()` is the deterministic name `Generate` writes.

## CLI

```sh
go run ./cmd/fixturegen -out testdata/media              # default preset
go run ./cmd/fixturegen -out testdata/media -preset all  # + ffmpeg formats
```

Presets: `default` (native only), `ffmpeg`, `all`. The written paths
print to stdout, one per line.

## Coverage

| Route | Codec / container | Produced by |
| --- | --- | --- |
| Native | PCM in WAV, PCM in AIFF, FLAC, MP3, AAC in ADTS, Opus in Ogg | WaxFlow encoders + muxers |
| ffmpeg | Vorbis in Ogg, FLAC in Matroska, AAC in MP4, ALAC in MP4 | host `ffmpeg` |
| Corrupt | `CorruptTruncated` (valid encode cut at half), `CorruptGarbage` (deterministic junk bytes) | synthesized |

The MP4 routes go through ffmpeg because WaxFlow's native MP4 output is
fragmented, which its own format registry cannot demux back (it reads
progressive sample tables only). ALAC-in-fMP4 native output, and the
vendored WMA/APE/WavPack samples the plan of record mentions, are
deferred for now.

ffmpeg is **never hard-required**: it is looked up on `PATH` at
runtime. Specs that need it fail with an error matching
`fixtures.ErrNeedsFFmpeg` when it is absent, and tests skip them
(`fixtures.FFmpegAvailable()` / `Spec.NeedsFFmpeg()` let callers filter
up front). `DefaultLibrary()` never needs it.

## Tests

`go test ./...` generates the libraries into temp dirs, decodes every
valid file back through WaxFlow's format registry (asserting container,
codec, rate, channels, and decoded length), checks byte-determinism
across two generations, and asserts the corrupt flavors fail the way
robustness tests rely on. It passes with or without ffmpeg installed.
