package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/playlist"
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
// The conversion is all-or-nothing in both directions: a field or an
// operator with no faithful counterpart rejects the document rather
// than importing a rule that means something else, and rejects the
// export rather than writing one. There is no lossy escape hatch,
// because "export what maps and say what did not" needs the converter
// to report what it dropped, which is upstream's to add (filed in
// docs/upstream-requests.md).

// maxNSPBytes bounds the document the import will read. The M3U8 import
// beside it caps its payload in the contract; a free-form JSON object
// has no `maxLength` to declare, so the cap is enforced here - and
// before the parse, since the rule-node bound cannot apply to a
// document nobody has parsed yet.
const maxNSPBytes = 1 << 20

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
// nameless document be imported at all.
func (l *Library) ImportPlaylistNSP(ctx context.Context, uc *UserCtx, doc []byte, nameOverride string) (Playlist, error) {
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
	q, err := playlist.ImportNSP(rule)
	if err != nil {
		// WaxBin's refusals name the offending field, operator, or key,
		// which is the whole value of an all-or-nothing import. The
		// sentence is kept and answered as invalid-request rather than
		// as the unsupported code it carries: what the caller sent is
		// what has to change.
		return Playlist{}, errInvalid(err.Error())
	}
	vis := model.VisibilityPrivate
	if meta.Public {
		vis = model.VisibilityShared
	}
	return l.createSmartFromQuery(ctx, uc, name, vis, q)
}

// ExportPlaylistNSP renders a smart playlist's rule as an NSP document.
// A static playlist has no rule, and a rule holding anything NSP cannot
// say is refused with the offender named rather than written as
// something else.
func (l *Library) ExportPlaylistNSP(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (map[string]any, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return nil, err
	}
	if pl.Kind != model.PlaylistSmart || pl.Rule == nil {
		return nil, &Error{Kind: KindFeature, Msg: "a static playlist has no rule to export as NSP"}
	}
	raw, err := playlist.ExportNSP(*pl.Rule)
	if err != nil {
		return nil, &Error{Kind: KindFeature, Msg: err.Error()}
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
