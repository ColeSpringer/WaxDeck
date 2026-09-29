package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"regexp"
	"slices"
	"strconv"
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
	Name   string
	Public bool
}

// splitNSP reads the playlist half of a document and returns the rest
// for the converter. Keys match exactly, as the converter's do, so a
// `Public` is a key it reports rather than a switch that takes effect.
func splitNSP(doc []byte) (nspMeta, []byte, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(doc, &top); err != nil || top == nil {
		var syntax *json.SyntaxError
		if errors.As(err, &syntax) {
			return nspMeta{}, nil, errInvalid("the NSP document is not valid JSON: " + err.Error())
		}
		return nspMeta{}, nil, errInvalid("the NSP document is not a JSON object")
	}
	var meta nspMeta
	if raw, ok := top["name"]; ok && json.Unmarshal(raw, &meta.Name) != nil {
		return nspMeta{}, nil, errInvalid("an NSP document's `name` is text")
	}
	raw, ok := top["public"]
	if !ok {
		return meta, doc, nil
	}
	if json.Unmarshal(raw, &meta.Public) != nil {
		return nspMeta{}, nil, errInvalid("an NSP document's `public` is true or false")
	}
	delete(top, "public")
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
		// Still refuses a malformed document, a broken file rather than
		// an unmappable one, and one where nothing survives, since a rule
		// with every condition dropped matches the whole library.
		held, _ := nspHold(rule)
		res, perr := playlist.ImportNSPPartial(held)
		if perr != nil {
			return Playlist{}, nspRefused(perr, KindInvalid)
		}
		q = res.Rule
	} else {
		// Every offender named rather than the first the strict walk
		// stops at, as invalid-request: what was sent has to change.
		if rep, _, cerr := nspImportCheck(rule); cerr == nil && !rep.OK() {
			return Playlist{}, errInvalid(nspReasons(nspReport(rep), nil))
		}
		if q, err = playlist.ImportNSP(rule); err != nil {
			return Playlist{}, nspRefused(err, KindInvalid)
		}
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
	Code   string
	Field  string
	Op     string
	Value  any
	Key    string
	Mode   string
	Path   string
	Reason string
}

// NSPReport is what one mapping could not carry: gaps refuse the strict
// conversion and are what a partial one drops, notes refuse nothing. Rule
// is what a partial conversion keeps; an export's also names the rule read.
type NSPReport struct {
	Direction string
	Gaps      []NSPGap
	Notes     []NSPGap
	Truncated bool
	RuleHash  string
	Rule      *SmartRule
}

func nspReport(rep playlist.NSPReport) NSPReport {
	export := rep.Direction == playlist.NSPDirExport
	gaps, gapsCut := nspGaps(rep.Gaps, export)
	notes, notesCut := nspGaps(rep.Notes, export)
	return NSPReport{
		Direction: string(rep.Direction),
		Gaps:      gaps,
		Notes:     notes,
		Truncated: gapsCut || notesCut,
	}
}

// nspGaps re-shapes the converter's gaps for WaxDeck's callers: on an
// export, field names and pointers in the rule's own vocabulary; either
// way, deduped by what each names and capped, saying whether it was.
func nspGaps(gaps []playlist.NSPGap, export bool) ([]NSPGap, bool) {
	if len(gaps) == 0 {
		return nil, false
	}
	seen := make(map[string]bool, len(gaps))
	out := make([]NSPGap, 0, min(len(gaps), maxNSPGaps))
	for _, g := range gaps {
		row := NSPGap{
			Kind:   string(g.Kind),
			Code:   string(g.Code),
			Field:  g.Field,
			Op:     g.Op,
			Value:  g.Value,
			Key:    g.Key,
			Mode:   g.Mode,
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
			// A dropped sort term, as the rule's sort writes one.
			if term, ok := g.Value.(query.Sort); ok {
				row.Value = map[string]any{"field": row.Field, "desc": term.Desc}
			}
			row.Path = nspRulePointer(row.Path)
		}
		key := fmt.Sprintf("%s\x00%s\x00%s\x00%s\x00%s\x00%#v", row.Code, row.Field, row.Op, row.Key, row.Mode, row.Value)
		if seen[key] {
			continue
		}
		seen[key] = true
		if len(out) == maxNSPGaps {
			return out, true
		}
		out = append(out, row)
	}
	return out, false
}

// ruleHashForm is what ruleHash answers.
var ruleHashForm = regexp.MustCompile(`^[0-9a-f]{16}$`)

// ruleHash names a rule's current form: its canonical JSON, hashed.
func ruleHash(q query.Query) string {
	raw, err := json.Marshal(q)
	if err != nil {
		return ""
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])[:16]
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
// and what a partial import would keep, without importing it. It never
// refuses on expressiveness, only a document that is not one.
func (l *Library) ReportPlaylistNSPImport(doc []byte) (NSPReport, error) {
	if len(doc) > maxNSPBytes {
		return NSPReport{}, errInvalid(fmt.Sprintf("an NSP document may be at most %d bytes", maxNSPBytes))
	}
	_, rule, err := splitNSP(doc)
	if err != nil {
		return NSPReport{}, err
	}
	rep, held, err := nspImportCheck(rule)
	if err != nil {
		return NSPReport{}, errInvalid("the NSP document could not be read: " + err.Error())
	}
	out := nspReport(rep)
	// The partial import's own walk, which refuses a malformed document
	// or one where nothing survives, so it keeps no rule for either.
	broken := slices.ContainsFunc(rep.Gaps, func(g playlist.NSPGap) bool { return g.Kind == playlist.NSPGapMalformed })
	if len(out.Gaps) > 0 && !broken {
		if res, perr := playlist.ImportNSPPartial(held); perr == nil {
			kept := queryToRule(res.Rule)
			out.Rule = &kept
		}
	}
	return out, nil
}

// nspDroppedLeaf is a condition the converter drops, standing in for one
// a rule cannot hold so a partial import prunes what that empties.
var nspDroppedLeaf = json.RawMessage(`{"is":{"":0}}`)

// nspImportCheck is everything an import of rule would lose: the
// converter's report plus what a WaxDeck rule cannot hold, and the
// document a partial import reads.
func nspImportCheck(rule []byte) (playlist.NSPReport, []byte, error) {
	rep, err := playlist.CheckNSPImport(rule)
	if err != nil {
		return rep, nil, err
	}
	held, gaps := nspHold(rule)
	rep.Gaps = append(rep.Gaps, gaps...)
	return rep, held, nil
}

// nspHold finds what the converter carries but a rule's next save would
// refuse or rewrite, swapping each condition for nspDroppedLeaf. A
// non-zero offset is one: a rule has no offset to keep it in.
func nspHold(rule []byte) ([]byte, []playlist.NSPGap) {
	var top map[string]json.RawMessage
	if json.Unmarshal(rule, &top) != nil {
		return rule, nil
	}
	var gaps []playlist.NSPGap
	if raw, ok := top["offset"]; ok {
		var n int
		if json.Unmarshal(raw, &n) == nil && n != 0 {
			gaps = append(gaps, playlist.NSPGap{Kind: playlist.NSPGapShape, Code: playlist.NSPReasonUnsupportedKey,
				Key: "offset", Path: "/offset", Reason: "nsp: unsupported top-level key: offset"})
			delete(top, "offset")
		}
	}
	// The converter reads `all`, or failing that `any`.
	for _, key := range []string{"all", "any"} {
		if raw, ok := top[key]; ok {
			held, heldGaps := nspHoldGroup(raw, "/"+key)
			top[key], gaps = held, append(gaps, heldGaps...)
			break
		}
	}
	if len(gaps) == 0 {
		return rule, nil
	}
	out, err := json.Marshal(top)
	if err != nil {
		return rule, gaps
	}
	return out, gaps
}

// nspHoldGroup is nspHold for one group's rules, at path.
func nspHoldGroup(raw json.RawMessage, path string) (json.RawMessage, []playlist.NSPGap) {
	var rules []json.RawMessage
	if json.Unmarshal(raw, &rules) != nil {
		return raw, nil
	}
	var gaps []playlist.NSPGap
	for i, r := range rules {
		var one map[string]json.RawMessage
		if json.Unmarshal(r, &one) != nil || len(one) != 1 {
			continue
		}
		at := path + "/" + strconv.Itoa(i)
		for op, val := range one {
			if op == "all" || op == "any" {
				if held, heldGaps := nspHoldGroup(val, at+"/"+op); len(heldGaps) > 0 {
					rules[i], _ = json.Marshal(map[string]json.RawMessage{op: held})
					gaps = append(gaps, heldGaps...)
				}
			} else if g, ok := nspHeldLeaf(r, op, val, at); ok {
				rules[i] = nspDroppedLeaf
				gaps = append(gaps, g)
			}
		}
	}
	if len(gaps) == 0 {
		return raw, nil
	}
	out, err := json.Marshal(rules)
	if err != nil {
		return raw, gaps
	}
	return out, gaps
}

// nspHeldLeaf answers the gap for one condition the converter reads but
// a rule's save would refuse or rewrite, judged by that save's own
// round trip; the converter's own gaps are left to it.
func nspHeldLeaf(leaf json.RawMessage, op string, val json.RawMessage, path string) (playlist.NSPGap, bool) {
	q, err := playlist.ImportNSP(slices.Concat([]byte(`{"all":[`), leaf, []byte(`]}`)))
	and, ok := q.Where.(query.And)
	if err != nil || !ok || len(and.Nodes) != 1 {
		return playlist.NSPGap{}, false
	}
	node := and.Nodes[0]
	if back, err := ruleNodeToEngine(engineNodeToRule(node), 1, new(int)); err == nil && sameRuleNode(node, back) {
		return playlist.NSPGap{}, false
	}
	var fieldValue map[string]any
	_ = json.Unmarshal(val, &fieldValue)
	g := playlist.NSPGap{Kind: playlist.NSPGapValue, Op: op, Path: path}
	for field, value := range fieldValue {
		g.Field, g.Value = field, value
	}
	cond, _ := node.(query.Cond)
	if not, ok := node.(query.Not); ok {
		cond, _ = not.Node.(query.Cond)
	}
	kind := ruleFieldsByEngine[cond.Field].kind
	switch {
	case !opAllowed(kind, string(cond.Op)):
		g.Kind, g.Code, g.Value = playlist.NSPGapOperator, playlist.NSPReasonUnsupportedOperator, nil
		g.Reason = "nsp: unsupported operator: " + op
	case relativeOps[string(cond.Op)]:
		g.Code = playlist.NSPReasonWindowTooLarge
		g.Reason = fmt.Sprintf("nsp: %s window of %v days is too large", op, g.Value)
	case kind == ruleKindNumber:
		g.Code = playlist.NSPReasonValueNotNumeric
		g.Reason = "nsp: " + g.Field + " value must be numeric"
	default:
		g.Code = playlist.NSPReasonBadValue
		g.Reason = "nsp: bad value for " + op
	}
	return g, true
}

// sameRuleNode reports whether a save's round trip gave a condition back
// unchanged, comparing numbers as numbers.
func sameRuleNode(a, b query.Node) bool {
	switch x := a.(type) {
	case query.Not:
		y, ok := b.(query.Not)
		return ok && sameRuleNode(x.Node, y.Node)
	case query.Cond:
		y, ok := b.(query.Cond)
		if !ok || model.CanonicalQueryField(x.Field) != model.CanonicalQueryField(y.Field) || x.Op != y.Op ||
			!sameRuleValue(x.Value, y.Value) || len(x.Values) != len(y.Values) {
			return false
		}
		for i := range x.Values {
			if !sameRuleValue(x.Values[i], y.Values[i]) {
				return false
			}
		}
		return true
	}
	return false
}

func sameRuleValue(a, b any) bool {
	number := func(v any) (float64, bool) {
		switch n := v.(type) {
		case int64:
			return float64(n), true
		case int:
			return float64(n), true
		case float64:
			return n, true
		}
		return 0, false
	}
	if x, ok := number(a); ok {
		y, ok := number(b)
		return ok && x == y
	}
	return reflect.DeepEqual(a, b)
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
		// The field in the rule's words where the converter's sentence
		// leaves it out or spells it as the catalog does.
		reason := g.Reason
		if g.Field != "" && !strings.Contains(reason, g.Field) {
			reason += " (" + g.Field + ")"
		}
		if !slices.Contains(reasons, reason) {
			reasons = append(reasons, reason)
		}
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
// drop, and what a partial export would keep, without exporting it.
func (l *Library) ReportPlaylistNSPExport(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (NSPReport, error) {
	pl, err := l.exportableRule(ctx, uc, apiPlaylistPID)
	if err != nil {
		return NSPReport{}, err
	}
	rule := *pl.Rule
	var rep NSPReport
	if res, perr := playlist.ExportNSPPartial(rule); perr == nil {
		rep = nspReport(res.Report)
		if len(rep.Gaps) > 0 {
			kept := queryToRule(res.Rule)
			rep.Rule = &kept
		}
	} else {
		// Nothing survives, so there is no kept rule to show.
		rep = nspReport(playlist.CheckNSPExport(rule))
	}
	rep.RuleHash = ruleHash(rule)
	return rep, nil
}

// ExportPlaylistNSP renders a smart playlist's rule as an NSP document,
// refusing what NSP cannot say unless partial drops it. wantHash, when
// set, refuses a rule changed since its report was read.
func (l *Library) ExportPlaylistNSP(ctx context.Context, uc *UserCtx, apiPlaylistPID string, partial bool, wantHash string) (map[string]any, error) {
	// A hash no report could have given is the request's fault.
	if wantHash != "" && !ruleHashForm.MatchString(wantHash) {
		return nil, errInvalid("ruleHash must be the 16 lower-case hex characters a report gave")
	}
	pl, err := l.exportableRule(ctx, uc, apiPlaylistPID)
	if err != nil {
		return nil, err
	}
	rule := *pl.Rule
	if wantHash != "" && ruleHash(rule) != wantHash {
		return nil, &Error{Kind: KindConflict, Msg: "the rule changed since the report was read; ask again"}
	}
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
