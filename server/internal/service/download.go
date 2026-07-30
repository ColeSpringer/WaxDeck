package service

import (
	"context"
	"fmt"
	"path/filepath"

	"github.com/colespringer/waxbin/model"
)

// DownloadFile is one downloadable backing file of an item: everything
// download-info reports and the download handler serves from.
type DownloadFile struct {
	FilePID  string
	Path     string
	FileName string
	MimeType string
	Size     int64
	MTimeNS  int64
	// DurationMS is this file's own duration, zero when the catalog does
	// not know it. It is what lets an offline client place a
	// book-timeline position in one part of a multi-file audiobook
	// without the server; for a carved item it is the containing file's,
	// and the span is the item's window inside it.
	DurationMS  int64
	EssenceHash string
	// ETag validates the exact file bytes (size plus mtime, which the
	// write-temp-then-rename discipline upstream makes a strong pair);
	// it changes on retag while EssenceHash does not.
	ETag string
}

// DownloadResolution is an item's complete download shape.
type DownloadResolution struct {
	Files       []DownloadFile
	SpanStartMS int64
	SpanEndMS   int64
	HasSpan     bool
}

// downloadMimes maps source containers to the media type the original
// bytes are served as; unknowns fall back to octet-stream (the bytes
// are still the bytes).
var downloadMimes = map[string]string{
	"flac": "audio/flac",
	"mp3":  "audio/mpeg",
	"wav":  "audio/wav",
	"aiff": "audio/aiff",
	"ogg":  "audio/ogg",
	"mp4":  "audio/mp4",
	"m4a":  "audio/mp4",
	"m4b":  "audio/mp4",
	"adts": "audio/aac",
	"mka":  "audio/x-matroska",
	"webm": "audio/webm",
	"wma":  "audio/x-ms-wma",
	"ape":  "audio/x-ape",
	"wv":   "audio/x-wavpack",
}

// DownloadInfo resolves the caller-visible item's original files for
// offline download: one per backing file in playback order, plus the
// playback window for items carved out of a larger file.
func (l *Library) DownloadInfo(ctx context.Context, uc *UserCtx, apiItemPID string) (DownloadResolution, error) {
	if !uc.Admin && !uc.Download {
		return DownloadResolution{}, &Error{Kind: KindForbidden, Msg: "this account cannot download originals"}
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return DownloadResolution{}, err
	}
	return l.downloadResolution(ctx, it)
}

// DownloadSource resolves one backing file for the download handler,
// which authenticates by media token (visibility was enforced at mint,
// exactly like streaming). filePID selects a part of a multi-file item;
// empty means the single backing file.
func (l *Library) DownloadSource(ctx context.Context, apiItemPID, filePID string) (DownloadFile, error) {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return DownloadFile{}, err
	}
	res, err := l.downloadResolution(ctx, it)
	if err != nil {
		return DownloadFile{}, err
	}
	if filePID == "" {
		if len(res.Files) != 1 {
			return DownloadFile{}, errInvalid("this item has multiple files; pass f")
		}
		return res.Files[0], nil
	}
	for _, f := range res.Files {
		if f.FilePID == filePID {
			return f, nil
		}
	}
	return DownloadFile{}, errNotFound("no such file for item " + apiItemPID)
}

func (l *Library) downloadResolution(ctx context.Context, it *model.ItemView) (DownloadResolution, error) {
	var out DownloadResolution
	if it.Kind == model.KindBook {
		bd, err := l.lib.Book(ctx, it.PID)
		if err != nil {
			return out, classify(err)
		}
		for _, part := range bd.Files {
			df, err := l.downloadFile(ctx, part.FilePID)
			if err != nil {
				return out, err
			}
			out.Files = append(out.Files, df)
		}
		if len(out.Files) > 0 {
			return out, nil
		}
		// A single-file book carries no parts list; fall through to the
		// item's own backing file.
	}
	loc, err := l.paths.Locate(ctx, it.PID)
	if err != nil {
		return out, classify(err)
	}
	df, err := l.downloadFile(ctx, loc.FilePID)
	if err != nil {
		return out, err
	}
	out.Files = []DownloadFile{df}
	if it.Virtual {
		out.HasSpan = true
		out.SpanStartMS, out.SpanEndMS = spanWindow(it)
	}
	return out, nil
}

// spanWindow reports a carved item's playback window with the sheet's
// open-ended last track closed by the item's own duration; the wire
// contracts promise a closed window, never the upstream 0 sentinel.
func spanWindow(it *model.ItemView) (startMS, endMS int64) {
	endMS = it.EndMS
	if endMS == 0 {
		endMS = it.StartMS + it.DurationMS
	}
	return it.StartMS, endMS
}

func (l *Library) downloadFile(ctx context.Context, filePID model.PID) (DownloadFile, error) {
	f, err := l.lib.File(ctx, filePID)
	if err != nil {
		return DownloadFile{}, classify(err)
	}
	mime := downloadMimes[f.Container]
	if mime == "" {
		mime = "application/octet-stream"
	}
	return DownloadFile{
		FilePID: string(f.PID),
		// The raw path bytes are the real filesystem name; DisplayPath
		// is lossy and only good for humans.
		Path:        string(f.Path),
		FileName:    filepath.Base(f.DisplayPath),
		MimeType:    mime,
		Size:        f.Size,
		MTimeNS:     f.MTimeNS,
		DurationMS:  f.DurationMS,
		EssenceHash: f.EssenceHash,
		ETag:        fmt.Sprintf("%d-%d", f.Size, f.MTimeNS),
	}, nil
}
