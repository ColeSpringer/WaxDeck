package waxtapsource

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/colespringer/waxbin/identity"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"
	waxtap "github.com/colespringer/waxtap/v3"
)

// Fetch downloads one video's audio and streams it to w, copying the source's
// highest-quality audio without re-encoding. WaxTap lands the file atomically in
// WorkDir (remuxed to a clean container, with the configured SponsorBlock cut
// and embeds applied), provenance tags are stamped best-effort, and the bytes
// are then copied to w through the same tagged hasher WaxBin's HTTP provider
// uses. The temp file is always removed.
func (p *Provider) Fetch(ctx context.Context, req source.FetchRequest, w io.Writer) (*source.FetchResult, error) {
	return p.fetch(ctx, req, w, "")
}

// FetchFormat downloads honoring a preferred output format. An empty format (or
// "best") copies the source's highest-quality audio; "opus", "mp3", "m4a", and
// "flac" transcode to that container. It satisfies the acquisition path's
// optional format capability.
func (p *Provider) FetchFormat(ctx context.Context, req source.FetchRequest, w io.Writer, format string) (*source.FetchResult, error) {
	return p.fetch(ctx, req, w, format)
}

func (p *Provider) fetch(ctx context.Context, req source.FetchRequest, w io.Writer, format string) (*source.FetchResult, error) {
	const op = "waxtapsource.Fetch"

	// A FormatCopy remux muxes into the container named by the output path's
	// extension, so pick the extension from the same best-audio row the download
	// will select. The raw YouTube container (Opus-in-WebM) is remuxed, losslessly,
	// into the codec's recognized picture-capable container instead (Ogg-Opus),
	// which both the catalog imports and cover art can be embedded into. A
	// requested transcode names its own container (opus, mp3, m4a, flac).
	v, err := p.tap.Info(ctx, req.URL, waxtap.InfoBasic)
	if err != nil {
		return nil, err
	}
	tspec, ext := transcodeFor(format, v.Formats)

	tmp, err := os.CreateTemp(p.cfg.WorkDir, "fetch-*."+ext)
	if err != nil {
		return nil, waxerr.Wrap(waxerr.CodeIO, op, err)
	}
	path := tmp.Name()
	if err := tmp.Close(); err != nil {
		_ = os.Remove(path)
		return nil, waxerr.Wrap(waxerr.CodeIO, op, err)
	}
	defer os.Remove(path)

	var cut *waxtap.CutSpec
	if len(p.categories) > 0 {
		cut = &waxtap.CutSpec{SponsorBlock: p.categories}
	}
	res, err := p.tap.Download(ctx, waxtap.Request{
		URL: req.URL,
		ProcessSpec: waxtap.ProcessSpec{
			Output:         waxtap.ToFile(path),
			Transcode:      &tspec,
			Cut:            cut,
			EmbedThumbnail: p.cfg.EmbedThumbnail,
			EmbedMetadata:  p.cfg.EmbedMetadata,
			Events:         p.warningEvents(ctx, req.URL),
		},
	})
	if err != nil {
		return nil, err
	}

	info, err := os.Stat(path)
	if err != nil {
		return nil, waxerr.Wrap(waxerr.CodeIO, op, err)
	}
	if req.MaxBytes > 0 && info.Size() > req.MaxBytes {
		// Mirrors the shape of WaxBin's HTTP provider over-size refusal.
		return nil, waxerr.New(waxerr.CodeInvalid, op,
			fmt.Sprintf("download from %s exceeds %d-byte limit", req.URL, req.MaxBytes))
	}

	videoID := res.VideoID
	if videoID == "" {
		videoID = v.ID
	}
	p.stampProvenance(ctx, path, req.URL, videoID)

	f, err := os.Open(path)
	if err != nil {
		return nil, waxerr.Wrap(waxerr.CodeIO, op, err)
	}
	defer f.Close()
	hasher, finalize := identity.StreamHasher()
	n, err := io.Copy(io.MultiWriter(w, hasher), f)
	if err != nil {
		return nil, waxerr.Wrap(waxerr.CodeIO, op, err)
	}
	return &source.FetchResult{
		Bytes:       n,
		ContentHash: finalize(),
		// ext is the container the file was actually muxed into (FormatCopy writes
		// the output path's container), so it names the delivered content exactly.
		ContentType: contentTypeFor(ext, path),
	}, nil
}

// recoveredWarnings are the WaxTap conditions that resolved themselves: the
// delivered audio is still what was asked for, so they are context rather than a
// problem. Everything else, including a code a later WaxTap adds, describes a
// degraded delivery and warns.
var recoveredWarnings = map[waxtap.WarningCode]bool{
	waxtap.WarnSponsorBlockEmpty:  true, // nothing matched, so nothing to cut
	waxtap.WarnURLReResolved:      true, // the signed URL expired and was re-signed
	waxtap.WarnRateLimitedRetried: true,
	waxtap.WarnThrottled:          true,
	waxtap.WarnWebContextRetry:    true, // the attested context was capped; a fresh one worked
	waxtap.WarnSessionRotated:     true, // googlevideo capped the identity; a fresh one worked
}

// warningEvents returns the hook that surfaces a download's non-fatal conditions.
// WaxTap reports them instead of failing, so without this a SponsorBlock outage,
// an untagged embed, or a WaxSeal session googlevideo capped all look exactly like
// a clean acquisition.
//
// It reads the event stream rather than Result.Warnings because the Result only
// carries them on success: waxtap copies the accumulated warnings onto the Result
// when the job finishes, and a failed download has no Result to copy them onto.
// That drops them from the run whose warnings explain the failure, which is the
// one worth reading. Nothing is lost by the switch, since both places waxtap
// records a warning emit the same StageWarning event.
//
// The message tracks the level rather than naming WaxTap's "warning" both times:
// a recovery and a degraded delivery are different events, and anything grouping
// by message text would otherwise read every routine retry as a problem. The code
// attribute is what joins the two back together.
//
// Callbacks run synchronously on the worker, so this stays a log line and ignores
// every other stage.
func (p *Provider) warningEvents(ctx context.Context, url string) func(waxtap.Event) {
	return func(e waxtap.Event) {
		if e.Stage != waxtap.StageWarning || e.Warning == nil {
			return
		}
		level, msg := slog.LevelWarn, "youtube download degraded"
		if recoveredWarnings[e.Warning.Code] {
			level, msg = slog.LevelInfo, "youtube download recovered"
		}
		p.log.Log(ctx, level, msg, "url", url, "code", e.Warning.Code.String(), "detail", e.Warning.Detail)
	}
}

// stampProvenance writes SOURCE_URL/SOURCE_ID/ACQUISITION_DATE tags onto the
// downloaded file with WaxLabel. Provenance is best effort: a container WaxLabel
// cannot parse or write is logged and the download proceeds untagged.
func (p *Provider) stampProvenance(ctx context.Context, path, sourceURL, videoID string) {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		p.log.Warn("provenance stamp skipped: parse failed", "path", path, "err", err)
		return
	}
	plan, err := doc.Edit().
		Set(tag.SourceURL, sourceURL).
		Set(tag.SourceID, videoID).
		Set(tag.AcquisitionDate, time.Now().UTC().Format(time.RFC3339)).
		Prepare()
	if err != nil {
		p.log.Warn("provenance stamp skipped: prepare failed", "path", path, "err", err)
		return
	}
	if _, _, err := plan.Execute(ctx, waxlabel.SaveBack()); err != nil {
		p.log.Warn("provenance stamp skipped: write failed", "path", path, "err", err)
	}
}

// transcodeFor maps a caller's format preference to the WaxTap transcode spec
// and the delivered container extension. An empty or unrecognized preference is
// the lossless best-audio copy, whose container the codec decides; a named
// format transcodes into its own recognized, picture-capable container.
func transcodeFor(format string, formats []waxtap.Format) (waxtap.TranscodeSpec, string) {
	switch strings.ToLower(strings.TrimSpace(format)) {
	case "opus":
		return waxtap.TranscodeSpec{Format: waxtap.FormatOpus}, "opus"
	case "mp3":
		return waxtap.TranscodeSpec{Format: waxtap.FormatMP3}, "mp3"
	case "m4a", "aac":
		return waxtap.TranscodeSpec{Format: waxtap.FormatAAC}, "m4a"
	case "flac":
		return waxtap.TranscodeSpec{Format: waxtap.FormatFLAC}, "flac"
	default:
		return waxtap.TranscodeSpec{Format: waxtap.FormatCopy}, stagingExtension(formats)
	}
}

// stagingExtension chooses the delivered container from the best-audio row the
// download will select (BestAudio with the stereo default under MinimizeLoss,
// mirroring the Download defaults so the extension names the codec the copy
// carries). The container has to satisfy two consumers the raw YouTube container
// does not: the catalog imports only known audio extensions (no .webm/.mka), and
// cover art embeds only into a picture-capable container. So the selected codec
// is remuxed, losslessly, into its recognized picture-capable native container.
// YouTube's best audio is Opus, so Ogg-Opus is the fallback when selection
// cannot name a codec.
func stagingExtension(formats []waxtap.Format) string {
	idx, err := waxtap.BestAudio().WithChannels(waxtap.LayoutStereo).
		Select(formats, waxtap.MinimizeLoss(), waxtap.Target{})
	if err != nil {
		return "opus"
	}
	return containerExtForCodec(formats[idx].Codec, formats[idx].Extension)
}

// containerExtForCodec maps a normalized codec id to the recognized,
// picture-capable container extension WaxDeck stages it in: Opus and Vorbis to
// Ogg, AAC to m4a, MP3 and FLAC to their own. It falls back to the row's native
// extension when that is already a recognized audio container, else to Ogg-Opus.
func containerExtForCodec(codec, native string) string {
	c := strings.ToLower(codec)
	switch {
	case strings.HasPrefix(c, "opus"):
		return "opus"
	case strings.HasPrefix(c, "vorbis"):
		return "ogg"
	// mp4a.40.34 is MP3 carried in an MP4 descriptor, so it is caught before the
	// general mp4a (AAC, any profile) case below.
	case c == "mp4a.40.34", strings.HasPrefix(c, "mp3"):
		return "mp3"
	case strings.HasPrefix(c, "mp4a"), strings.HasPrefix(c, "aac"):
		return "m4a"
	case strings.HasPrefix(c, "flac"):
		return "flac"
	}
	switch strings.ToLower(native) {
	case "m4a", "mp3", "ogg", "oga", "opus", "flac", "aac", "wav", "aiff", "aif":
		return strings.ToLower(native)
	}
	return "opus"
}

// contentTypeFor maps the delivered container to a media type, preferring the
// result's output format extension and falling back to the file extension.
func contentTypeFor(ext, path string) string {
	if ext == "" {
		ext = strings.TrimPrefix(filepath.Ext(path), ".")
	}
	switch strings.ToLower(ext) {
	case "m4a", "mp4", "m4b":
		return "audio/mp4"
	case "aac":
		return "audio/aac"
	case "webm":
		return "audio/webm"
	case "opus":
		return "audio/opus"
	case "ogg", "oga":
		return "audio/ogg"
	case "mp3":
		return "audio/mpeg"
	case "flac":
		return "audio/flac"
	case "mka":
		return "audio/x-matroska"
	default:
		return "application/octet-stream"
	}
}
