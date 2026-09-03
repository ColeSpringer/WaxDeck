# fixtures

Test-media generator for WaxDeck. The repository policy is **no binary
media in git**: every audio file a test needs is synthesized at
test-setup from a `Spec`: a deterministic sine tone (440 Hz per
channel, times the channel index) encoded into the requested
codec/container through WaxFlow's own encoders and muxers. No external
tools are involved, and the same spec always produces the same bytes.

It is a Go module usable as a library and as a CLI.

## Library

```go
import "github.com/colespringer/waxdeck/fixtures"

// The full supported matrix.
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
go run ./cmd/fixturegen -out testdata/media                # codec/container matrix
go run ./cmd/fixturegen -out testdata/media -preset demo   # titled demo album
go run ./cmd/fixturegen -out testdata/media -preset all    # both
```

The written paths print to stdout, one per line. The demo preset
(`DemoLibrary()`) is a small tagged album with human-findable titles;
end-to-end harnesses scan it alongside the matrix.

## Coverage

| Route | Codec / container |
| --- | --- |
| Valid | PCM in WAV, PCM in AIFF, FLAC, FLAC in Matroska, MP3, AAC in ADTS, AAC in MP4, ALAC in MP4, Opus in Ogg, Vorbis in Ogg, HE-AAC in ADTS, HE-AAC in MP4, WavPack, Monkey's Audio |
| Corrupt | `CorruptTruncated` (valid encode cut at half), `CorruptGarbage` (deterministic junk bytes) |
| Vendored | Musepack SV8 with chapters, WMA with chapters |

The MP4 routes use WaxFlow's progressive container override, producing
flat moov+mdat files its format registry demuxes back; the default MP4
form is fragmented CMAF, which exists for streaming rather than for
files. HE-AAC is reached by naming the codec, since `.m4a` and `.aac`
resolve to plain AAC-LC.

WMA and Musepack are the one binary-media exception: WaxFlow decodes
both and encodes neither, so no `Spec` can synthesize them. Two samples
of a few KB each sit under `testdata/exotics/` and are served by
`Vendored(name)` (bytes) and `WriteVendored(dir, names...)` (files),
with `AllExotics` naming the set. Both carry chapters, which is the
decode path they exist to cover.

Tags are handed to WaxFlow's muxers verbatim, and a muxer now fails the
transcode on a tag block it cannot fit rather than dropping it. A `Spec`
over `MaxTagBytes` (48 KiB, Ogg's comment-header cap and the tightest
bound in play) is refused up front so the error names the fixture.

## Tests

`go test ./...` generates the library into temp dirs, decodes every
valid file back through WaxFlow's format registry (asserting container,
codec, rate, channels, and decoded length), checks byte-determinism
across two generations, and asserts the corrupt flavors fail the way
robustness tests rely on.
