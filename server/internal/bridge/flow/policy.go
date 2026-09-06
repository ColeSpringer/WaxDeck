package flow

import (
	"slices"
	"strings"

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
	// BitrateKbps is the source's bitrate in kilobits per second, when
	// known (zero otherwise) - the unit the catalog stores it in. A
	// bitrate cap reads it to leave a lossy direct play already inside
	// the cap alone.
	BitrateKbps int
	// DurationMS is the item's duration (the span's for virtual tracks,
	// the resolved part's for multi-file books).
	DurationMS int64
	// SpokenWord marks podcast episodes and audiobooks: the content
	// voice boost is for.
	SpokenWord bool
	// EssenceHash keys the analysis cache for the backing audio. The
	// resolver hands it out so a caller that wants loudness for content
	// StreamSource does not read it for (music, for timeline leveling)
	// can ask for it without resolving the item a second time.
	EssenceHash string
	// IntegratedLUFS and TruePeakDB are the source's measured loudness
	// when known (the analysis cache). Voice boost derives its leveling
	// gain from the first; timeline leveling reads both, because a gain
	// applied to a stream that is already near full scale clips.
	IntegratedLUFS *float64
	TruePeakDB     *float64
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

// replayGainTargetLUFS is the loudness a levelled queue is brought to.
// ReplayGain 2.0's reference is -18 LUFS, and a household stream that
// also plays podcasts at -16 sits close enough to it that a queue does
// not change loudness when the content changes.
const replayGainTargetLUFS = -18.0

// replayGainCeilingDBTP leaves a decibel of true-peak headroom, the
// ReplayGain convention: intersample peaks and a lossy re-encode both
// push the reconstructed waveform above what the samples measure.
const replayGainCeilingDBTP = -1.0

// replayGainMaxBoostDB bounds how far a quiet queue is lifted. The
// sidecar clamps requested positive gain at +12 for music anyway; the
// same bound here means the value in the signed URL is the value that
// plays, so a log line and a listener's ears agree.
const replayGainMaxBoostDB = 12.0

// TimelineGainDB derives the single gain a levelled timeline renders
// at, and whether there was anything to derive it from.
//
// One gain for the whole stream is not an approximation of per-track
// ReplayGain, it is the only thing a timeline can express: the members
// are rendered into one continuous stream and there is no seam at which
// a gain could change. That makes this an album gain over whatever the
// queue happens to be, so it is derived the way album gain is - from
// the program as a whole - by weighting each measured member's loudness
// by how long it plays.
//
// Members with no stored measurement are carried at the gain the
// measured ones produced rather than excluded from the stream, which is
// what an unanalyzed track in the middle of an analyzed album should
// do. A queue where nothing is measured levels nothing: false here
// means the mint asks for gain=off rather than for a number invented
// out of no data.
func TimelineGainDB(members []TimelineMember) (float64, bool) {
	var weighted, weight float64
	var peak *float64
	for _, m := range members {
		if p := m.Src.TruePeakDB; p != nil && (peak == nil || *p > *peak) {
			peak = p
		}
		if m.Src.IntegratedLUFS == nil {
			continue
		}
		// A member with no duration would drop out of a weighted mean
		// entirely; it counts as one unit instead, which is what an
		// unweighted mean would have done for every member.
		w := float64(m.Src.DurationMS)
		if w <= 0 {
			w = 1
		}
		weighted += *m.Src.IntegratedLUFS * w
		weight += w
	}
	if weight <= 0 {
		return 0, false
	}
	db := replayGainTargetLUFS - weighted/weight
	if db > replayGainMaxBoostDB {
		db = replayGainMaxBoostDB
	}
	// Clipping is the one failure a listener cannot undo by reaching for
	// the volume, so where a peak is known it wins over the target: a
	// quiet-but-peaky master is left where it is rather than squared
	// off. Only ever downward, so this can never turn a cut into more of
	// one. Where no peak was measured there is nothing to reason from
	// and the boost stands; the sidecar's limiter is the backstop.
	if peak != nil {
		if headroom := replayGainCeilingDBTP - *peak; db > headroom {
			db = headroom
		}
	}
	// A fraction of a decibel is not audible and would still cost the
	// whole queue a re-encode, so it counts as nothing to do.
	if db > -0.05 && db < 0.05 {
		return 0, false
	}
	return db, true
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
// of that container serves. Keys are NormalizeContainer's output - the
// stored labels are WaxLabel's names lowercased by the scan ("aac
// (adts)", "aifc", "matroska", "wavpack", "asf") - with the extension
// spellings kept beside them as belt.
var containerMime = map[string]string{
	"flac":     "audio/flac",
	"mp3":      "audio/mpeg",
	"wav":      "audio/wav",
	"aiff":     "audio/aiff",
	"aifc":     "audio/aiff",
	"ogg":      "audio/ogg",
	"opus":     "audio/ogg",
	"mp4":      "audio/mp4",
	"m4a":      "audio/mp4",
	"m4b":      "audio/mp4",
	"aac":      "audio/aac",
	"adts":     "audio/aac",
	"matroska": "audio/x-matroska",
	"mka":      "audio/x-matroska",
	"webm":     "audio/webm",
	"asf":      "audio/x-ms-wma",
	"wma":      "audio/x-ms-wma",
	"ape":      "audio/x-ape",
	"wavpack":  "audio/x-wavpack",
	"wv":       "audio/x-wavpack",
	"musepack": "audio/x-musepack",
	"mpc":      "audio/x-musepack",
	"mp+":      "audio/x-musepack",
	"mpga":     "audio/mpeg",
}

// NormalizeContainer folds a stored container label onto the family key
// the mime tables use: the first word, lowercased, so a composite probe
// label like "aac (adts)" lands on its family.
func NormalizeContainer(label string) string {
	key, _, _ := strings.Cut(strings.ToLower(strings.TrimSpace(label)), " ")
	return key
}

// ContainerMime answers the media type for a stored container label,
// application/octet-stream where nothing better is known. Never empty:
// real clients dereference content types without checking.
func ContainerMime(label string) string {
	if m, ok := containerMime[NormalizeContainer(label)]; ok {
		return m
	}
	return "application/octet-stream"
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

// canonicalMime folds the spellings devices use for one media type onto
// a single one, so comparing what a renderer advertised against what
// this server would send compares like with like. Renderers really do
// say `audio/x-flac` and `audio/mp3`, and a literal comparison would
// read those as unknown and drop a renderer that plays the format
// perfectly well down to the floor, which looks exactly like the bug
// negotiation is meant to fix.
var canonicalMime = map[string]string{
	"audio/x-flac":    "audio/flac",
	"audio/mp3":       "audio/mpeg",
	"audio/x-mp3":     "audio/mpeg",
	"audio/mpeg3":     "audio/mpeg",
	"audio/x-mpeg-3":  "audio/mpeg",
	"audio/m4a":       "audio/mp4",
	"audio/x-m4a":     "audio/mp4",
	"audio/mp4a-latm": "audio/mp4",
	"audio/x-aac":     "audio/aac",
	"audio/x-wav":     "audio/wav",
	"audio/wave":      "audio/wav",
	"audio/vnd.wave":  "audio/wav",
	"audio/x-aiff":    "audio/aiff",
	"application/ogg": "audio/ogg",
	"audio/vorbis":    "audio/ogg",
	// Not here, and it is a tempting mistake: `audio/L16` and
	// `audio/lpcm`, which DLNA renderers really do advertise, must not
	// fold onto `audio/wav`. L16 (RFC 2586, and DLNA's LPCM profile) is
	// headerless big-endian PCM; a WAV is a RIFF-headered little-endian
	// one. Serving a renderer that asked for L16 a WAV plays the 44-byte
	// header as audio and then every sample byte-swapped, which is a
	// click followed by static. The engine has no L16 output to serve
	// instead, and a renderer that advertises LPCM advertises mp3 too
	// (it is the DLNA audio baseline), so the floor is the right answer
	// for it rather than a missed opportunity.
}

// encodeTargets maps a canonical media type onto the engine output that
// produces it, for choosing what to transcode into. It is deliberately
// narrower than canonicalMime, and the omissions are the point:
//
//   - `audio/ogg` is absent. The engine's Opus output is Ogg-framed, but
//     `audio/ogg` from a renderer overwhelmingly means Vorbis on the
//     devices old enough to need negotiating with. Reading it as an offer
//     of Opus would hand silence to a renderer that told the truth. (It
//     still matches for a passthrough, where the type describes bytes
//     that already exist rather than a codec being requested.)
//   - `audio/aac` is absent. It names raw ADTS, and the engine's aac
//     output is MP4-framed, so a renderer that advertised only ADTS gets
//     the mp3 floor rather than a container it did not ask for.
var encodeTargets = map[string]string{
	"audio/flac": "flac",
	"audio/mpeg": "mp3",
	"audio/mp4":  "aac",
	"audio/wav":  "wav",
}

// losslessTargets and lossyTargets are the encode preference orders,
// best first, split by what the source is. A lossless source may go to
// a lossless target; a lossy one may not, because expanding an MP3 into
// FLAC multiplies the bytes and recovers nothing that was already lost.
//
// WAV is last in both, and that placement is deliberate rather than an
// ordering slip. It is lossless, so ranking it by quality would put it
// second, but it costs roughly 1.4 Mbit/s against 1 Mbit/s for the same
// audio as FLAC and a fifth of that for a lossy encode, over a LAN the
// device is sharing with everything else in the house, and a live PCM
// stream carries no length a renderer can seek against. It is here to
// keep a renderer that accepts nothing else playable at all -- the mp3
// floor would be a format such a device rejects -- not as something to
// prefer. That is also why it is in the lossy ladder despite the rule
// above: last resort beats silence.
var (
	losslessTargets = []string{"flac", "aac", "mp3", "wav"}
	lossyTargets    = []string{"aac", "mp3", "wav"}
)

// canonicalize folds a device's advertised media types into a lookup
// from the canonical spelling back to the device's own. A renderer may
// qualify a type with parameters (`audio/mp4; codecs=mp4a.40.2`); the
// base type is what names the format. The original spelling is kept
// because it is what has to be advertised back: a renderer that listed
// `audio/x-flac` and is handed a resource declaring `audio/flac` sees a
// type absent from its own sink, and the strict ones refuse the load.
func canonicalize(accepts []string) map[string]string {
	out := make(map[string]string, len(accepts))
	for _, mime := range accepts {
		base, _, _ := strings.Cut(strings.ToLower(strings.TrimSpace(mime)), ";")
		base = strings.TrimSpace(base)
		if base == "" {
			continue
		}
		canonical := base
		if c, ok := canonicalMime[base]; ok {
			canonical = c
		}
		// First spelling wins, so the answer does not depend on sink
		// order when a renderer lists two spellings of one type.
		if _, seen := out[canonical]; !seen {
			out[canonical] = mime
		}
	}
	return out
}

// DeviceFormat decides what to serve a device endpoint that told us
// which media types it accepts. floor is what to fall back to when the
// device said nothing usable (the caller's own policy, mp3 for
// renderers). It returns the engine format to force, empty meaning
// "force nothing" (serve the original bytes), plus the media type to
// advertise back, empty meaning "whatever the shape already says".
//
// The source and the shape are in hand on purpose, and the rules that
// need them are the whole reason this is not a set intersection:
//
//   - A device that already plays the source's own container gets the
//     original bytes. That is a seekable passthrough that spends no
//     transcode session and loses no quality, and forcing a format on it
//     (even the source's own) would engage the engine for nothing.
//   - Only a direct-play shape has original bytes to hand over. A
//     virtual track is a window into a larger file and an engaged voice
//     boost is a DSP stage: both are going through the engine already,
//     so answering "pass it through" for either would advertise the
//     source's own type for a stream the engine is about to re-encode.
//   - A lossy source is never re-encoded into a lossless target. A
//     renderer advertising FLAC is telling us what it can play, not what
//     it wants an MP3 inflated into.
func DeviceFormat(src Source, shape Shape, caps *client.Caps, accepts []string, floor string) (format, advertise string) {
	if caps == nil || len(accepts) == 0 {
		return floor, ""
	}
	wanted := canonicalize(accepts)
	if shape.Format == "auto" {
		if mime, ok := containerMime[NormalizeContainer(src.Container)]; ok {
			if c, ok := canonicalMime[mime]; ok {
				mime = c
			}
			if spelling, ok := wanted[mime]; ok {
				return "", spelling
			}
		}
	}
	// Reverse the accepted set onto engine formats, remembering which
	// spelling to advertise for each.
	encodable := make(map[string]string, len(wanted))
	for mime, spelling := range wanted {
		if f, ok := encodeTargets[mime]; ok {
			encodable[f] = spelling
		}
	}
	targets := lossyTargets
	if lossless(src.Codec) {
		targets = losslessTargets
	}
	for _, f := range targets {
		if spelling, ok := encodable[f]; ok && hasOutput(caps, f) {
			return f, spelling
		}
	}
	return floor, ""
}

// lossless reports whether a codec can be transcoded without
// generation loss. The labels are the scan's, which lowercases
// WaxLabel's own names and folds Monkey's Audio onto "ape".
func lossless(codec string) bool {
	switch codec {
	case "pcm", "flac", "alac", "wavpack", "ape":
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
		return Shape{Format: "auto", MimeType: ContainerMime(src.Container), Seekable: true}
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

// SameAsSource reports whether a forced format would produce exactly
// what the file already holds, so the engine has nothing to do and the
// original bytes can serve. It is deliberately narrow: only the pairs
// where one of this server's output names and the stored codec plus
// container describe the same bitstream in the same wrapper. Anything
// unrecognised, and any remux (aac in ADTS against the MP4-framed aac
// this engine emits), answers false and takes the encode path.
func SameAsSource(src Source, format string) bool {
	codec := strings.ToLower(strings.TrimSpace(src.Codec))
	container := NormalizeContainer(src.Container)
	switch format {
	case "mp3":
		return codec == "mp3" && container == "mp3"
	case "flac":
		return codec == "flac" && container == "flac"
	case "wav":
		return codec == "pcm" && container == "wav"
	case "opus":
		return codec == "opus" && (container == "ogg" || container == "opus")
	case "aac":
		return codec == "aac" && (container == "mp4" || container == "m4a" || container == "m4b")
	}
	return false
}

// MinStreamBitrateKbps and MaxStreamBitrateKbps bound a client bitrate
// cap: below the floor no codec speaks, above the ceiling a cap cannot
// beat direct play.
const (
	MinStreamBitrateKbps = 32
	MaxStreamBitrateKbps = 320
)

// CappedShape narrows a shape to a bitrate cap. A lossy direct play
// already at or below the cap streams unchanged - never transcode a
// 128k MP3 to satisfy a 320 cap, and an unknown bitrate counts as over
// the cap, never under it. Everything else becomes a real encode down
// to the cap: an encode already headed to a lossy format keeps it, the
// rest take the same lossy tail CUE cuts and voice boost get (Opus, or
// the MP3 floor). A capped shape is never seekable, which is also what
// routes it through session admission at fetch.
func CappedShape(src Source, caps *client.Caps, shape Shape, capKbps int) (Shape, bool) {
	if capKbps <= 0 {
		return shape, false
	}
	// Only a direct play is excused by the source's own bitrate: a shape
	// already headed for an encode (voice boost, a CUE cut) emits at the
	// engine's choosing, so the cap has to ride along regardless of what
	// the file on disk was.
	if shape.Seekable && !lossless(src.Codec) && src.BitrateKbps > 0 && src.BitrateKbps <= capKbps {
		return shape, false
	}
	format := shape.Format
	if !lossyBitrateFormats[format] {
		format = "mp3"
		if hasOutput(caps, "opus") {
			format = "opus"
		}
	}
	return Shape{Format: format, MimeType: formatMime[format], Seekable: false}, true
}
