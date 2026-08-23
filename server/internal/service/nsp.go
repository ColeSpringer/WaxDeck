package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/playlist"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/waxerr"
)

// NSP is the Navidrome smart-playlist document, and the conversion is
// WaxBin's: `playlist.ImportNSP` and `playlist.ExportNSP` map the
// grammar onto the same `query.Query` a smart playlist already stores.
// This file is the thin part around them - the document's own name and
// visibility, which belong to WaxDeck's playlist record rather than to
// the rule, and the bound on how much document the endpoint will read.
//
// Deliberately not a second converter. WaxDeck's rule vocabulary is the
// larger one, so a WaxDeck-side mapping would drift from WaxBin's on
// every field either side gains, and the two would disagree about what
// an NSP field means - which is a silently different playlist, the
// failure the format guard exists to prevent.
//
// The conversion is all-or-nothing in both directions by default: a
// field or an operator with no faithful counterpart rejects the
// document rather than importing a rule that means something else, and
// rejects the export rather than writing one. What the converter's
// report buys is two things on top of that. The refusal itself names
// every gap rather than the first one the walk tripped over; and a
// caller who has seen the report can ask for the lossy conversion
// instead, which is the `partial` argument the import and the export
// take. Asking is its own entry point rather than something a
// successful partial carries back, because the export's body is the
// document another server reads and a report key beside `all` and
// `sort` would either be refused over there or change what the document
// means.

// maxNSPBytes bounds the document the import will read. The M3U8 import
// beside it caps its payload in the contract; a free-form JSON object
// has no `maxLength` to declare, so the cap is enforced here - and
// before the parse, since the rule-node bound cannot apply to a
// document nobody has parsed yet.
const maxNSPBytes = 1 << 20

// maxNSPGaps bounds how many distinct gaps a refusal names and a report
// carries. Past a handful the list stops being something a person acts
// on, and both surfaces render one row or one clause per entry - so an
// unbounded list turns a maxNSPBytes document (tens of thousands of
// clauses against one unsupported field) into a multi-megabyte body, a
// multi-megabyte log line, and a dialog nobody can scroll.
const maxNSPGaps = 12

// nspMessage is WaxBin's own sentence without the operation prefix its
// error type formats in. `waxerr.Error()` renders "<Op>: <Msg>", and Op
// is a package path - an internal name, never something to answer a
// caller with.
func nspMessage(err error) string {
	var we *waxerr.Error
	if errors.As(err, &we) && we.Msg != "" {
		return we.Msg
	}
	return err.Error()
}

// nspRefused turns a converter failure into a classified service error.
// The expressiveness refusals carry `kind`; anything else the converter
// can fail with - a value that will not marshal - is a fault rather than
// a statement about what the caller built, so it keeps its own class and
// its message stays off the wire.
func nspRefused(err error, kind ErrorKind) error {
	if KindOf(classify(err)) == KindInternal {
		return &Error{Kind: KindInternal, Err: err}
	}
	return &Error{Kind: kind, Msg: nspMessage(err)}
}

// nspMeta is the part of an NSP document that describes the playlist
// rather than the rule: the two keys WaxDeck's playlist record is made
// of. WaxBin reads and ignores `name`, and does not model `public` at
// all - it refuses every top-level key it does not know, which is the
// guard that stops a typo for `all` importing as a rule over the whole
// library, so `public` has to be lifted out here rather than left for
// it to trip over.
type nspMeta struct {
	Name   string `json:"name"`
	Public bool   `json:"public"`
}

// nspPlaylistKeys are the top-level keys that describe the playlist
// rather than the rule, and so are read here and withheld from the
// converter. Only `public`: WaxBin already ignores `name` and
// `comment`, and withholding a key it would have accepted would be a
// second place to keep that list in step.
var nspPlaylistKeys = []string{"public"}

// splitNSP reads the playlist half of a document and returns the rest
// for the converter.
func splitNSP(doc []byte) (nspMeta, []byte, error) {
	var meta nspMeta
	if err := json.Unmarshal(doc, &meta); err != nil {
		return nspMeta{}, nil, errInvalid("the NSP document is not valid JSON: " + err.Error())
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal(doc, &top); err != nil {
		return nspMeta{}, nil, errInvalid("the NSP document is not a JSON object")
	}
	held := false
	for _, key := range nspPlaylistKeys {
		if _, ok := top[key]; ok {
			delete(top, key)
			held = true
		}
	}
	if !held {
		return meta, doc, nil
	}
	rule, err := json.Marshal(top)
	if err != nil {
		return nspMeta{}, nil, errInvalid("the NSP document could not be read")
	}
	return meta, rule, nil
}

// ImportPlaylistNSP creates a smart playlist from an NSP document.
// nameOverride wins over the document's own name, which is what lets a
// nameless document be imported at all. partial drops what has no
// WaxDeck form instead of refusing the document for it.
func (l *Library) ImportPlaylistNSP(ctx context.Context, uc *UserCtx, doc []byte, nameOverride string, partial bool) (Playlist, error) {
	if len(doc) > maxNSPBytes {
		return Playlist{}, errInvalid(fmt.Sprintf("an NSP document may be at most %d bytes", maxNSPBytes))
	}
	meta, rule, err := splitNSP(doc)
	if err != nil {
		return Playlist{}, err
	}
	name := strings.TrimSpace(meta.Name)
	if s := strings.TrimSpace(nameOverride); s != "" {
		name = s
	}
	if name == "" {
		return Playlist{}, errInvalid("the NSP document has no name; supply one with the name parameter")
	}
	var q query.Query
	if partial {
		// Still refuses two things: a malformed document, which is a
		// broken file rather than an unmappable one, and a document
		// where nothing survives, since a rule with every condition
		// dropped matches the whole library.
		res, perr := playlist.ImportNSPPartial(rule)
		if perr != nil {
			return Playlist{}, nspRefused(perr, KindInvalid)
		}
		q = res.Rule
	} else if q, err = playlist.ImportNSP(rule); err != nil {
		// WaxBin's refusals name the offending field, operator, or key,
		// which is the whole value of an all-or-nothing import. The
		// sentences are kept and answered as invalid-request rather than
		// as the unsupported code they carry: what the caller sent is
		// what has to change.
		return Playlist{}, errInvalid(nspImportRefusal(rule, err))
	}
	vis := model.VisibilityPrivate
	if meta.Public {
		vis = model.VisibilityShared
	}
	return l.createSmartFromQuery(ctx, uc, name, vis, q)
}

// NSPGap is one part of a rule or a document with no faithful
// counterpart on the other side, in WaxDeck's own shape so the API
// layer never sees a WaxBin type. Field for field with
// `playlist.NSPGap`, which is the point: a report that drifted from the
// converter's would be a second answer about the same conversion.
type NSPGap struct {
	Kind   string
	Field  string
	Op     string
	Value  any
	Path   string
	Reason string
}

// NSPReport is what one mapping could not carry: gaps refuse the strict
// conversion and are what a partial one drops, notes refuse nothing.
type NSPReport struct {
	Direction string
	Gaps      []NSPGap
	Notes     []NSPGap
}

func nspReport(rep playlist.NSPReport) NSPReport {
	export := rep.Direction == playlist.NSPDirExport
	return NSPReport{
		Direction: string(rep.Direction),
		Gaps:      nspGaps(rep.Gaps, export),
		Notes:     nspGaps(rep.Notes, export),
	}
}

// nspGaps re-shapes the converter's gaps for WaxDeck's own callers.
//
// Three things happen here, and export is where all three matter. The
// gap's field is named in the vocabulary of the side being read, and on
// an export that side is WaxDeck - whose vocabulary is the one
// `GET /playlists/rule-fields` publishes and the rule editor speaks, not
// the engine spelling underneath it; untranslated, a rule holding
// "mediaType is music" reports a gap on `kind`, a field the person who
// built the rule has never seen. The pointer's root segment is the
// converter's `where`, which is `root` in the rule schema a client would
// dereference it against. And the list is deduped by sentence and
// capped: a rule or a document repeating one problem is one problem, and
// the row a client draws per entry says nothing new the second time.
//
// The import direction is Navidrome's vocabulary and its pointers are
// into the document the caller sent, so only the dedupe applies.
func nspGaps(gaps []playlist.NSPGap, export bool) []NSPGap {
	if len(gaps) == 0 {
		return nil
	}
	seen := make(map[string]bool, len(gaps))
	out := make([]NSPGap, 0, min(len(gaps), maxNSPGaps))
	for _, g := range gaps {
		if seen[g.Reason] {
			continue
		}
		seen[g.Reason] = true
		if len(out) == maxNSPGaps {
			break
		}
		row := NSPGap{
			Kind:   string(g.Kind),
			Field:  g.Field,
			Op:     g.Op,
			Value:  g.Value,
			Path:   g.Path,
			Reason: g.Reason,
		}
		if export {
			// Only a field the table knows. A `tag.KEY` field, and
			// anything the engine gained since, is already the name
			// WaxDeck uses.
			if spec, ok := ruleFieldsByEngine[row.Field]; ok {
				row.Field = spec.api
			}
			row.Path = nspRulePointer(row.Path)
		}
		out = append(out, row)
	}
	return out
}

// nspRulePointer rewrites the converter's pointer into the rule schema a
// client holds. `query.Query` calls the condition tree `Where`; the
// `SmartRule` a client dereferences against calls it `root`. Every other
// segment (`/sorts/0`, `/limitMode`, `/limit`) already agrees.
func nspRulePointer(path string) string {
	const from = "/where"
	if path == from {
		return "/root"
	}
	if strings.HasPrefix(path, from+"/") {
		return "/root" + path[len(from):]
	}
	return path
}

// ReportPlaylistNSPImport says what importing a document would drop,
// without importing it. Never refuses on expressiveness - that is the
// whole point of asking - so its only failure is a document that is not
// readable JSON.
func (l *Library) ReportPlaylistNSPImport(doc []byte) (NSPReport, error) {
	if len(doc) > maxNSPBytes {
		return NSPReport{}, errInvalid(fmt.Sprintf("an NSP document may be at most %d bytes", maxNSPBytes))
	}
	_, rule, err := splitNSP(doc)
	if err != nil {
		return NSPReport{}, err
	}
	rep, err := playlist.CheckNSPImport(rule)
	if err != nil {
		return NSPReport{}, errInvalid("the NSP document could not be read: " + err.Error())
	}
	return nspReport(rep), nil
}

// nspImportRefusal composes the sentence an all-or-nothing import refuses
// with. The strict parse stops at the first gap, so a document with a typo
// for `all` is refused for the missing root group the typo caused and never
// names the typo; the check walks the whole document, so the refusal names
// every offender the caller has to fix instead of one round trip each.
//
// The strict sentence stands when the two disagree: an unparseable document
// is the check's only failure, and a check that found nothing has nothing
// to say about a refusal that happened anyway.
func nspImportRefusal(rule []byte, strict error) string {
	rep, err := playlist.CheckNSPImport(rule)
	if err != nil {
		return nspMessage(strict)
	}
	return nspReasons(nspReport(rep), strict)
}

// nspExportRefusal composes the sentence an all-or-nothing export refuses
// with, for the same reason nspImportRefusal does on the way in: the
// strict render stops at the first gap, and a rule built in the editor
// routinely holds several. Naming one per round trip makes fixing a rule
// a sequence of refusals instead of one.
func nspExportRefusal(q query.Query, strict error) string {
	return nspReasons(nspReport(playlist.CheckNSPExport(q)), strict)
}

// nspReasons is the composition both directions share: every gap the
// report carries, joined, or the strict sentence when the check has
// nothing to say about a refusal that happened anyway. The dedupe and
// the cap already happened in nspGaps, so this is the same set of
// problems the report endpoint answers with - one refusal and one
// listing cannot disagree about what is wrong.
func nspReasons(rep NSPReport, strict error) string {
	if len(rep.Gaps) == 0 {
		return nspMessage(strict)
	}
	reasons := make([]string, 0, len(rep.Gaps))
	for _, g := range rep.Gaps {
		reasons = append(reasons, g.Reason)
	}
	return strings.Join(reasons, "; ")
}

// exportableRule resolves a playlist and insists it has a rule to
// convert. Not owner-gated, deliberately: a shared playlist is readable
// by everyone who can see it, and exporting its rule says nothing the
// playlist detail does not already.
func (l *Library) exportableRule(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (*model.Playlist, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return nil, err
	}
	if pl.Kind != model.PlaylistSmart || pl.Rule == nil {
		return nil, &Error{Kind: KindFeature, Msg: "a static playlist has no rule to export as NSP"}
	}
	return pl, nil
}

// ReportPlaylistNSPExport says what exporting a playlist's rule would
// drop, without exporting it. Never refuses on expressiveness, so the
// static playlist is the one thing it can refuse for.
func (l *Library) ReportPlaylistNSPExport(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (NSPReport, error) {
	pl, err := l.exportableRule(ctx, uc, apiPlaylistPID)
	if err != nil {
		return NSPReport{}, err
	}
	return nspReport(playlist.CheckNSPExport(*pl.Rule)), nil
}

// ExportPlaylistNSP renders a smart playlist's rule as an NSP document.
// A static playlist has no rule, and a rule holding anything NSP cannot
// say is refused with every offender named rather than written as
// something else. partial drops those parts and writes the rest.
func (l *Library) ExportPlaylistNSP(ctx context.Context, uc *UserCtx, apiPlaylistPID string, partial bool) (map[string]any, error) {
	pl, err := l.exportableRule(ctx, uc, apiPlaylistPID)
	if err != nil {
		return nil, err
	}
	rule := *pl.Rule
	var raw []byte
	if partial {
		// Refuses only when nothing survives: a document with every
		// condition dropped selects the whole library on the far side,
		// which is not a smaller version of what was asked for.
		res, perr := playlist.ExportNSPPartial(rule)
		if perr != nil {
			return nil, nspRefused(perr, KindFeature)
		}
		raw = res.Data
	} else if raw, err = playlist.ExportNSP(rule); err != nil {
		return nil, &Error{Kind: KindFeature, Msg: nspExportRefusal(rule, err)}
	}
	// Back through a map so the handler answers the operation's declared
	// object rather than a string of JSON. WaxBin's document is the
	// authority on shape; this only re-types it.
	out := map[string]any{}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	// The playlist's own name and visibility, which the rule does not
	// carry and WaxBin deliberately does not invent.
	out["name"] = pl.Name
	if pl.Visibility == model.VisibilityShared {
		out["public"] = true
	}
	return out, nil
}
