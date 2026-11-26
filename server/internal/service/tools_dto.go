package service

import (
	"cmp"
	"encoding/json"
	"errors"
	"regexp"
	"strings"

	"github.com/colespringer/waxbin/scan"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// What a caller reads of a task: its failure with the operation names cut
// out, and the DTO.

// taskOpName is an operation name a library threads onto its errors: a
// dotted one ("jobs.Run", "meta.Writer.Apply") or a sibling's own.
var taskOpName = regexp.MustCompile(`^(?:[A-Za-z]\w*(?:\.\w+)+|waxtap|waxbin|waxflow|waxlabel|waxseal)$`)

// siblings are the libraries whose names begin their own operations'.
var siblings = map[string]bool{"waxtap": true, "waxbin": true, "waxflow": true, "waxlabel": true, "waxseal": true}

// namedEnds are the last parts that make a dotted name a file's or a
// host's, which say what failed: a file's extension or a domain's.
var namedEnds = map[string]bool{
	"jpg": true, "jpeg": true, "png": true, "gif": true, "webp": true, "bmp": true, "tif": true,
	"tiff": true, "avif": true, "heic": true, "svg": true, "cue": true, "lrc": true, "txt": true,
	"nfo": true, "json": true, "xml": true, "yaml": true, "yml": true, "m3u": true, "m3u8": true,
	"pls": true, "xspf": true, "log": true, "pdf": true, "epub": true, "sfv": true, "md5": true,
	"ffp": true, "accurip": true, "srt": true, "vtt": true, "zip": true, "rar": true, "7z": true,
	"tar": true, "gz": true, "part": true, "html": true, "htm": true, "csv": true,
	"com": true, "org": true, "net": true, "io": true, "fm": true, "dev": true, "app": true,
	"co": true, "uk": true, "de": true, "fr": true, "info": true, "tv": true, "me": true,
	"eu": true, "ca": true, "au": true, "nl": true, "jp": true,
}

// opName reports whether a part of a failure is an operation's name: a
// sibling's, or one shaped like it that names no file or host.
func opName(p string) bool {
	if !taskOpName.MatchString(p) {
		return false
	}
	first, _, dotted := strings.Cut(p, ".")
	if !dotted || siblings[first] {
		return true
	}
	return !scan.IsAudio(p) && !namedEnds[strings.ToLower(p[strings.LastIndexByte(p, '.')+1:])]
}

// taskFailureText is what a failed task records: a source refusal in the
// server's sentence for its reason, else the failure's own words, without
// the operation names a library threads onto it or the permanence marker.
// The server's paths stay for an administrator to read; taskFor cuts them
// for anyone else.
func taskFailureText(cause error) string {
	if s := refusalSentence(cause); s != "" {
		return s
	}
	s := waxDetail(cause)
	if s == "" {
		s = strings.TrimPrefix(cause.Error(), errToolPermanent.Error()+": ")
	}
	return withoutOpNames(s)
}

// refusalSentence is what the server says of a source's refusal: its
// sentence for the reason, or what a run said of it (how far a list got);
// the source's own words stay in the log. "" for any other failure.
func refusalSentence(cause error) string {
	var se *Error
	if !errors.As(cause, &se) || se.Kind != KindRefused {
		return ""
	}
	r, known := sourceReasons[se.Params["reason"]]
	if !known {
		return ""
	}
	return cmp.Or(se.Msg, r.sentence)
}

// taskFailureCode is a failure as a client words it: the API error code
// its classification answers, as an HTTP error's does, and the params it
// carries as a JSON object ("" for none).
func taskFailureCode(cause error) (code, params string) {
	if p := RefusalParams(cause); len(p) > 0 {
		params = marshalJSON(p)
	}
	return string(KindOf(cause)), params
}

// withoutOpNames drops the operation names leading s or any part of it
// after a ": ". A file's or a host's name reads like one ("part1.mp3:
// ...", "example.com: ...") and stays: it says what failed. The last
// part is the message itself.
func withoutOpNames(s string) string {
	parts := strings.Split(s, ": ")
	out := parts[:0]
	for i, p := range parts {
		if i < len(parts)-1 && opName(p) {
			continue
		}
		out = append(out, p)
	}
	return strings.Join(out, ": ")
}

// taskFor is a task as the caller may read it: its recorded failure
// names the server's paths, which only an administrator reads.
func (l *Tools) taskFor(uc *UserCtx, t wdb.ToolTask) ToolTaskDTO {
	dto := l.withActivity(toolTaskDTO(t))
	if !uc.Admin {
		dto.Error = l.Ingest.failureWords(dto.Error)
	}
	return dto
}

func toolTaskDTO(t wdb.ToolTask) ToolTaskDTO {
	var results []string
	if t.ResultPIDs != "" {
		_ = json.Unmarshal([]byte(t.ResultPIDs), &results)
	}
	var summary map[string]any
	if t.Summary != "" {
		_ = json.Unmarshal([]byte(t.Summary), &summary)
	}
	dto := ToolTaskDTO{
		ID: t.ID, Type: t.Type, State: t.State, ItemPID: t.ItemPID, ItemTitle: t.ItemTitle,
		ProgressPct: t.ProgressPct, Error: t.Error, ResultPIDs: results,
		Summary:     summary,
		CreatedAtNS: t.CreatedAtNS, FinishedAtNS: t.FinishedAtNS,
	}
	switch {
	case t.State == taskStateRunning && t.WaitReason != "":
		dto.WaitReason, dto.RetryAtNS = t.WaitReason, t.LeaseUntilNS
		dto.CancelRequested = t.CancelRequested
	case t.State == taskStateRunning:
		// What a wait said, kept for a run that never comes back, is no
		// news while the task runs.
		dto.Error = ""
		dto.CancelRequested = t.CancelRequested
	case t.State == taskStateFailed && t.ErrorCode != "":
		dto.ErrorCode = t.ErrorCode
		if t.ErrorParams != "" {
			_ = json.Unmarshal([]byte(t.ErrorParams), &dto.ErrorParams)
		}
	}
	if (t.Type == taskTypeBookMerge || t.Type == taskTypeBookSplit) && (t.State == taskStateRunning || t.State == taskStateParked) {
		// While the run's trash holds the book: from its trash to its new
		// files cataloged, or put back. Kept originals never went, and
		// sources gone from the trash for good are in it no longer.
		var p toolTaskParams
		if json.Unmarshal([]byte(t.Params), &p) == nil && !p.KeepOriginals && p.TrashFromNS != 0 && !p.Forward {
			switch p.Step {
			case toolStepTrashing, toolStepPlacing, toolStepUndoing:
				dto.BookInTrash = true
			}
		}
	}
	return dto
}
