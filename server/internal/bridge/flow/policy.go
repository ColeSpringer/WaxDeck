package flow

import (
	"slices"

	"github.com/colespringer/waxflow/client"
)

// Source is what the format policy and proxy need to know about one
// resolvable item, provided by the service layer so this package never
// touches catalog types.
type Source struct {
	// Path is the containing file's absolute path on this host.
	Path string
	// Size and MTimeNS pin the file's identity for the id parameter.
	Size    int64
	MTimeNS int64
	// Virtual marks a CUE-backed span of a larger file; FromSample and
	// ToSample bound it (half-open, in source samples).
	Virtual    bool
	FromSample int64
	ToSample   int64
	// Codec and Container describe the source stream.
	Codec     string
	Container string
	// DurationMS is the item's duration (the span's for virtual tracks,
	// the resolved part's for multi-file books).
	DurationMS int64
	// SpokenWord marks podcast episodes and audiobooks: the content
	// voice boost is for.
	SpokenWord bool
	// IntegratedLUFS is the source's measured loudness when known (the
	// analysis cache); voice boost needs it to derive leveling gain.
	IntegratedLUFS *float64
}

// voiceTargetLUFS is the spoken-word leveling target. Streaming
// speech norms cluster around -16 LUFS; the true-peak limiter behind
// dynamics=voice makes overshooting safe.
const voiceTargetLUFS = -16.0

// VoiceBoostParams derives the DSP parameters for a requested voice
// boost: engaged only for spoken-word sources with measured loudness
// on a sidecar that ships the dynamics stage. The gain is the leveling
// delta to the target, clamped to the engaged ceiling.
func VoiceBoostParams(src Source, caps *client.Caps, want bool) (gainDB float64, applied bool) {
	if !want || !src.SpokenWord || src.IntegratedLUFS == nil || caps == nil {
		return 0, false
	}
	if !slices.Contains(caps.DSP.Dynamics, "voice") {
		return 0, false
	}
	gain := voiceTargetLUFS - *src.IntegratedLUFS
	ceiling := caps.DSP.GainMaxVoiceDB
	if ceiling <= 0 {
		ceiling = 24
	}
	if gain > ceiling {
		gain = ceiling
	}
	// Attenuation has no engaged floor worth clamping at speech levels.
	return gain, true
}

// Shape is the format policy's answer: the stream parameters to
// request and what the client should expect back.
type Shape struct {
	// Format is the format parameter (auto lets the ladder decide).
	Format string
	// MimeType is the expected response media type.
	MimeType string
	// Seekable reports whether byte ranges will work (direct play) as
	// opposed to time-based seeking via a fresh request.
	Seekable bool
}

// containerMime maps source containers to the media type a direct play
// of that container serves.
var containerMime = map[string]string{
	"flac": "audio/flac",
	"mp3":  "audio/mpeg",
	"wav":  "audio/wav",
	"aiff": "audio/aiff",
	"ogg":  "audio/ogg",
	"mp4":  "audio/mp4",
	"adts": "audio/aac",
	"mka":  "audio/x-matroska",
}

// formatMime maps explicitly requested output formats to the media
// type their default live container serves.
var formatMime = map[string]string{
	"flac": "audio/flac",
	"mp3":  "audio/mpeg",
	"opus": "audio/ogg",
	"aac":  "audio/mp4",
	"wav":  "audio/wav",
}

// lossless reports whether a codec can be transcoded without
// generation loss.
func lossless(codec string) bool {
	switch codec {
	case "pcm", "flac", "alac":
		return true
	}
	return false
}

// ShapeFor is the format policy, version zero: a pure function of the
// source and the sidecar's live capabilities. Whole files direct-play
// through the ladder (format auto). Virtual tracks must name a format:
// the source codec when the sidecar's cut supports it (zero-generation
// packet move), FLAC for lossless sources (no loss), and Opus (or the
// MP3 floor) for the lossy rest. An engaged voice boost is a DSP
// stage, so it forces a real encode: no direct play, no cut.
func ShapeFor(src Source, caps *client.Caps, voiceBoost bool) Shape {
	pick := func(format string) Shape {
		return Shape{Format: format, MimeType: formatMime[format], Seekable: false}
	}
	if voiceBoost {
		if hasOutput(caps, "opus") {
			return pick("opus")
		}
		return pick("mp3")
	}
	if !src.Virtual {
		mime := containerMime[src.Container]
		if mime == "" {
			mime = "application/octet-stream"
		}
		return Shape{Format: "auto", MimeType: mime, Seekable: true}
	}
	if slices.Contains(caps.Delivery.CutFormats, src.Codec) {
		return pick(src.Codec)
	}
	if lossless(src.Codec) {
		return pick("flac")
	}
	if hasOutput(caps, "opus") {
		return pick("opus")
	}
	return pick("mp3")
}

func hasOutput(caps *client.Caps, name string) bool {
	for _, o := range caps.Outputs {
		if o.Name == name {
			return true
		}
	}
	return false
}
