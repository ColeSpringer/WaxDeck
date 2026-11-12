package service

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"
)

// ExportPlaylistM3U renders the members of a playlist this caller can
// see as an M3U8 document, in the catalog's own format byte for byte so
// its importer reads the document back. Written here rather than by
// ExportM3U8, which writes every stored member for whoever asks.
func (l *Playlists) ExportPlaylistM3U(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (string, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return "", err
	}
	members, err := l.members(ctx, pl)
	if err != nil {
		return "", err
	}
	f, err := l.withTagVerdicts(ctx, l.newMemberFilter(uc, pl), members)
	if err != nil {
		return "", err
	}
	fold := strings.NewReplacer("\r", " ", "\n", " ")
	var buf bytes.Buffer
	buf.WriteString("#EXTM3U\n")
	for _, it := range members {
		if !l.memberVisible(ctx, f, it) {
			continue
		}
		// A line-based format cannot carry a path with a line break.
		if strings.ContainsAny(it.DisplayPath, "\r\n") {
			return "", errInvalid("item path contains a newline and cannot be written to M3U8: " + itemAPIPID(it))
		}
		fmt.Fprintf(&buf, "#EXTINF:%d,%s - %s\n%s\n", it.DurationMS/1000,
			fold.Replace(it.Artist), fold.Replace(it.Title), it.DisplayPath)
	}
	return buf.String(), nil
}

// ImportPlaylistM3U creates a static playlist from an M3U8 document.
func (l *Playlists) ImportPlaylistM3U(ctx context.Context, uc *UserCtx, name, visibility, content string) (M3uImportOutcome, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return M3uImportOutcome{}, errInvalid("a playlist needs a name")
	}
	if err := checkPlaylistName(name); err != nil {
		return M3uImportOutcome{}, err
	}
	vis, err := playlistVisibility(visibility)
	if err != nil {
		return M3uImportOutcome{}, err
	}
	owner := model.PID(uc.CatalogPID)
	if err := l.lib.Playlists().CheckImport(ctx, name, owner, vis); err != nil {
		return M3uImportOutcome{}, classify(err)
	}
	lines, err := l.resolveM3U(ctx, uc, content)
	if err != nil {
		return M3uImportOutcome{}, err
	}
	out := M3uImportOutcome{}
	var keep []model.PID
	for _, ln := range lines {
		switch ln.outcome {
		case M3uUnmatched:
			out.Unmatched++
			out.UnmatchedPaths = append(out.UnmatchedPaths, ln.path)
		case M3uMatched:
			keep = append(keep, ln.item.PID)
		}
	}
	pid, err := l.createStaticWith(ctx, name, owner, vis, keep)
	if err != nil {
		return M3uImportOutcome{}, err
	}
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		return M3uImportOutcome{}, classify(err)
	}
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	out.Playlist = l.dto(ctx, uc, pl, true, nil)
	out.Matched = len(keep)
	return out, nil
}

// PreviewPlaylistM3U reports how an M3U8 document would import for the
// caller, line by line, and writes nothing.
func (l *Playlists) PreviewPlaylistM3U(ctx context.Context, uc *UserCtx, content string) (M3uPreview, error) {
	lines, err := l.resolveM3U(ctx, uc, content)
	if err != nil {
		return M3uPreview{}, err
	}
	out := M3uPreview{Lines: make([]M3uPreviewLine, 0, len(lines))}
	for _, ln := range lines {
		row := M3uPreviewLine{Path: ln.path, Outcome: ln.outcome}
		switch ln.outcome {
		case M3uMatched:
			out.Matched++
		case M3uMerged:
			out.Merged++
		default:
			out.Unmatched++
		}
		if ln.item != nil {
			s := summary(ln.item)
			row.Item = &s
		}
		out.Lines = append(out.Lines, row)
	}
	return out, nil
}

// maxM3UChars is the bound the contract declares on an M3U8 document,
// in characters as its maxLength counts them.
const maxM3UChars = 1 << 20

// maxM3ULines bounds the path lines one document may name. The catalog
// resolves a relative line by scanning every file's path, about 13 ms a
// line on a 20,000-file catalog, so this keeps one document under half a
// minute there.
const maxM3ULines = 2000

// m3uPathLines counts the path lines of an M3U8 document as the
// catalog's parser reads them: not blank, and not a directive.
func m3uPathLines(content string) int {
	n := 0
	for line := range strings.Lines(strings.TrimPrefix(content, "\ufeff")) {
		if line = strings.TrimSpace(line); line != "" && !strings.HasPrefix(line, "#") {
			n++
		}
	}
	return n
}

// m3uLine is one path line of an M3U8 document as the caller would
// import it; item is nil on an unmatched line.
type m3uLine struct {
	path    string
	outcome string
	item    *model.ItemView
}

// resolveM3U reads every path line of an M3U8 document for the caller,
// in document order. The import builds from it and the preview reports
// it, so the two cannot disagree. A path naming an item the caller
// cannot see reads as unmatched, never as stored and then dropped; a
// merged line names the item of the line before it, so it shares that
// line's verdict.
func (l *Playlists) resolveM3U(ctx context.Context, uc *UserCtx, content string) ([]m3uLine, error) {
	if utf8.RuneCountInString(content) > maxM3UChars {
		return nil, errInvalid(fmt.Sprintf("an M3U8 document may be at most %d characters", maxM3UChars))
	}
	if m3uPathLines(content) > maxM3ULines {
		return nil, errInvalid(fmt.Sprintf("an M3U8 document may name at most %d paths; split a longer one and import it in parts", maxM3ULines))
	}
	matches, err := l.m3uMatches(ctx, content)
	if errors.Is(err, bufio.ErrTooLong) {
		return nil, errInvalid("a line of the M3U8 document is too long to be a path")
	}
	if err != nil {
		return nil, classify(err)
	}
	var found []*model.ItemView
	for _, m := range matches {
		if m.Item != nil {
			found = append(found, m.Item)
		}
	}
	f, err := l.withTagVerdicts(ctx, memberFilter{uc: uc, subs: l.Podcasts.newSubscriptionFilter(uc)}, found)
	if err != nil {
		return nil, err
	}
	lines := make([]m3uLine, 0, len(matches))
	for _, m := range matches {
		switch {
		case m.Item == nil || !l.memberVisible(ctx, f, m.Item):
			lines = append(lines, m3uLine{path: m.Path, outcome: M3uUnmatched})
		case m.Merged:
			lines = append(lines, m3uLine{path: m.Path, outcome: M3uMerged, item: m.Item})
		default:
			lines = append(lines, m3uLine{path: m.Path, outcome: M3uMatched, item: m.Item})
		}
	}
	return lines, nil
}

// resolveItemPIDs validates item pids against the caller's visibility
// and returns the bare catalog pids in order.
func (l *Playlists) resolveItemPIDs(ctx context.Context, uc *UserCtx, apiPIDs []string) ([]model.PID, error) {
	out := make([]model.PID, 0, len(apiPIDs))
	for _, p := range apiPIDs {
		it, err := l.Grants.getVisibleItem(ctx, uc, p)
		if err != nil {
			return nil, err
		}
		out = append(out, it.PID)
	}
	return out, nil
}
