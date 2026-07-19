package waxtapsource

import (
	"context"
	"fmt"
	"io"
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

// Fetch downloads one video's audio and streams it to w. WaxTap lands the file
// atomically in WorkDir (remuxed to a clean container, with the configured
// SponsorBlock cut and embeds applied), provenance tags are stamped best-effort,
// and the bytes are then copied to w through the same tagged hasher WaxBin's
// HTTP provider uses. The temp file is always removed.
func (p *Provider) Fetch(ctx context.Context, req source.FetchRequest, w io.Writer) (*source.FetchResult, error) {
	const op = "waxtapsource.Fetch"

	// A FormatCopy remux muxes into the container named by the output path's
	// extension, so pick the extension from the same best-audio row the download
	// will select (aac lands in m4a, opus in webm).
	v, err := p.tap.Info(ctx, req.URL, waxtap.InfoBasic)
	if err != nil {
		return nil, err
	}
	ext := pickExtension(v.Formats)

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
			Transcode:      &waxtap.TranscodeSpec{Format: waxtap.FormatCopy},
			Cut:            cut,
			EmbedThumbnail: p.cfg.EmbedThumbnail,
			EmbedMetadata:  p.cfg.EmbedMetadata,
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
		ContentType: contentTypeFor(res.OutputFormat.Extension, path),
	}, nil
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

// pickExtension chooses the staging extension from the best-audio row the
// download facade would select (BestAudio with the stereo default under
// MinimizeLoss). It falls back to webm, WaxTap's own staging fallback, when
// selection fails or the row carries no extension.
func pickExtension(formats []waxtap.Format) string {
	idx, err := waxtap.BestAudio().WithChannels(waxtap.LayoutStereo).
		Select(formats, waxtap.MinimizeLoss(), waxtap.Target{})
	if err != nil || formats[idx].Extension == "" {
		return "webm"
	}
	return formats[idx].Extension
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
	case "ogg", "oga", "opus":
		return "audio/ogg"
	case "mp3":
		return "audio/mpeg"
	case "mka":
		return "audio/x-matroska"
	default:
		return "application/octet-stream"
	}
}
