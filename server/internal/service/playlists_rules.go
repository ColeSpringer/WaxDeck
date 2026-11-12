package service

import (
	"context"
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
)

// Rule bounds enforced on write, mirroring the spec.
const (
	maxRuleNodes = 200
	maxRuleDepth = 10
	maxRuleSorts = 4
)

// Value kinds for rule fields.
const (
	ruleKindText      = "text"
	ruleKindNumber    = "number"
	ruleKindDate      = "date"
	ruleKindBoolean   = "boolean"
	ruleKindMediaType = "mediaType"
	ruleKindPlaylist  = "playlist"
)

// Operator sets by value kind. Tag fields reuse the text set minus
// nothing (the engine already rejects ordered operators on tags, and
// the text set has none).
var ruleOpsByKind = map[string][]string{
	ruleKindText:   {"is", "isNot", "contains", "startsWith", "endsWith", "isPresent", "isMissing"},
	ruleKindNumber: {"is", "isNot", "gt", "lt", "gte", "lte", "inTheRange", "isPresent", "isMissing"},
	ruleKindDate:   {"before", "after", "inTheRange", "inTheLast", "notInTheLast", "isPresent", "isMissing"},
	// `isNot` alongside `is`: the .nsp importer accepts both on `loved`,
	// and an editor offering only `is` would refuse such a rule on save.
	ruleKindBoolean:   {"is", "isNot"},
	ruleKindMediaType: {"is", "isNot"},
	// Two operators, and the exclusions are deliberate. `in`/`notIn`
	// are deferred rather than refused: no rule kind offers list values
	// yet, and an Or of `is` says the same thing today. `isPresent` and
	// `isMissing` never: "in any playlist" would reach across every
	// other user's private lists, which is not a question a rule gets
	// to ask.
	ruleKindPlaylist: {"is", "isNot"},
}

// presenceOps take no value.
var presenceOps = map[string]bool{"isPresent": true, "isMissing": true}

// relativeOps take a day-count window rather than an absolute value;
// they map to the engine's relative-time operators on date fields.
var relativeOps = map[string]bool{"inTheLast": true, "notInTheLast": true}

// nanosPerDay is the day unit the relative-date wire value carries; the
// engine's relative operators compare a nanosecond window.
const nanosPerDay = int64(24 * time.Hour)

// maxRelativeDays bounds the wire window so days-to-nanoseconds stays
// well inside int64 (100000 days is ~273 years).
const maxRelativeDays = 100000

// limitModeToEngine maps the wire limit mode onto the engine's. Empty
// and "count" are the plain member cap; the rest ride the engine
// constants one-to-one.
var limitModeToEngine = map[string]query.LimitMode{
	"":          query.LimitCount,
	"count":     query.LimitCount,
	"random":    query.LimitRandom,
	"minutes":   query.LimitMinutes,
	"megabytes": query.LimitMegabytes,
}

// ruleFieldSpec maps one API rule field onto the engine's vocabulary.
type ruleFieldSpec struct {
	api       string
	engine    string
	kind      string
	userState bool
	sortable  bool
	desc      string
}

// ruleFieldSpecs is the API rule vocabulary, mirrored from the engine's
// field map (which is not exported; this table is the contract).
var ruleFieldSpecs = []ruleFieldSpec{
	{api: "mediaType", engine: "kind", kind: ruleKindMediaType, sortable: false, desc: "music, podcast, or audiobook"},
	{api: "title", engine: "title", kind: ruleKindText, sortable: true, desc: "item title"},
	{api: "artist", engine: "artist", kind: ruleKindText, sortable: true, desc: "artist, author, or show"},
	{api: "albumArtist", engine: "album_artist", kind: ruleKindText, sortable: true, desc: "album artist"},
	{api: "composer", engine: "composer", kind: ruleKindText, sortable: true, desc: "composer (music)"},
	{api: "album", engine: "album", kind: ruleKindText, sortable: true, desc: "album, series, or show"},
	{api: "podcast", engine: "podcast", kind: ruleKindText, sortable: true, desc: "show title (episodes)"},
	{api: "genre", engine: "genre", kind: ruleKindText, sortable: true, desc: "genre"},
	{api: "year", engine: "year", kind: ruleKindNumber, sortable: true, desc: "release or publication year"},
	{api: "trackNumber", engine: "track_no", kind: ruleKindNumber, sortable: true, desc: "track number (music)"},
	{api: "discNumber", engine: "disc_no", kind: ruleKindNumber, sortable: true, desc: "disc number (music)"},
	{api: "bpm", engine: "bpm", kind: ruleKindNumber, sortable: true, desc: "tempo in beats per minute (music); 0 when untagged"},
	{api: "season", engine: "season", kind: ruleKindNumber, sortable: true, desc: "season number (episodes)"},
	{api: "publishedAt", engine: "published", kind: ruleKindDate, sortable: true, desc: "episode publication time"},
	{api: "durationMs", engine: "duration_ms", kind: ruleKindNumber, sortable: true, desc: "duration in milliseconds"},
	// The album's release identity. Scan stores the tag verbatim and an
	// entity edit normalizes, so the two spellings coexist in one library
	// - `albumCountry is "US"` misses albums scanned "USA", and media has
	// no normalizer at all, so "CD", "2xCD", and "CD, Album, Reissue" are
	// three values. `contains` is the operator that behaves on all five
	// unless the library is uniformly tagged.
	//
	// Not sortable, like the album MBID they sit beside: they are
	// identifiers, and ordering a playlist by barcode is not a question
	// anyone asks. Filtering by them is ("everything on this label",
	// "the Japanese pressings"), which is what they are here for.
	{api: "albumBarcode", engine: "album_barcode", kind: ruleKindText, sortable: false, desc: "album barcode (UPC/EAN)"},
	{api: "albumLabel", engine: "album_label", kind: ruleKindText, sortable: false, desc: "record label"},
	{api: "albumCatalogNumber", engine: "album_catalog_number", kind: ruleKindText, sortable: false, desc: "label catalog number"},
	{api: "albumMedia", engine: "album_media", kind: ruleKindText, sortable: false, desc: "release medium (CD, vinyl, digital)"},
	{api: "albumCountry", engine: "album_country", kind: ruleKindText, sortable: false, desc: "release country"},
	{api: "recordingMbid", engine: "recording_mbid", kind: ruleKindText, sortable: false, desc: "MusicBrainz recording id (music)"},
	{api: "albumMbid", engine: "album_mbid", kind: ruleKindText, sortable: false, desc: "MusicBrainz release id of the album or book"},
	{api: "releaseGroupMbid", engine: "release_group_mbid", kind: ruleKindText, sortable: false, desc: "MusicBrainz release group id"},
	{api: "source", engine: "source", kind: ruleKindText, sortable: true, desc: "origin: local, rss, youtube, manual"},
	{api: "codec", engine: "codec", kind: ruleKindText, sortable: true, desc: "audio codec"},
	{api: "container", engine: "container", kind: ruleKindText, sortable: true, desc: "file container"},
	{api: "path", engine: "path", kind: ruleKindText, sortable: true, desc: "file path"},
	{api: "relPath", engine: "rel_path", kind: ruleKindText, sortable: true, desc: "file path under the library root, with forward slashes"},
	{api: "state", engine: "state", kind: ruleKindText, sortable: false, desc: "present, archived, remote, or missing"},
	{api: "addedAt", engine: "added", kind: ruleKindDate, sortable: true, desc: "when the item entered the library"},
	{api: "updatedAt", engine: "updated_at", kind: ruleKindDate, sortable: true, desc: "when the item last changed"},
	{api: "starred", engine: "starred", kind: ruleKindBoolean, userState: true, sortable: true, desc: "starred by the evaluating user"},
	{api: "starredAt", engine: "starred_at", kind: ruleKindDate, userState: true, sortable: true, desc: "when the star was set"},
	{api: "rating", engine: "rating", kind: ruleKindNumber, userState: true, sortable: true, desc: "rating 0 to 100; unrated is missing"},
	{api: "playCount", engine: "play_count", kind: ruleKindNumber, userState: true, sortable: true, desc: "completed plays; never missing, 0 when unplayed"},
	{api: "played", engine: "played", kind: ruleKindBoolean, userState: true, sortable: true, desc: "reached the played threshold"},
	{api: "finished", engine: "finished", kind: ruleKindBoolean, userState: true, sortable: true, desc: "listened to the end"},
	{api: "lastPlayedAt", engine: "last_played", kind: ruleKindDate, userState: true, sortable: true, desc: "most recent play; never played is missing"},
	{api: "playlist", engine: "playlist_pid", kind: ruleKindPlaylist, sortable: false, desc: "sits in a given playlist"},
}

var (
	ruleFieldsByAPI    = map[string]ruleFieldSpec{}
	ruleFieldsByEngine = map[string]ruleFieldSpec{}
)

func init() {
	for _, s := range ruleFieldSpecs {
		ruleFieldsByAPI[s.api] = s
		ruleFieldsByEngine[s.engine] = s
	}
	// Read aliases, on top of the spellings WaxDeck writes. The query
	// engine accepts both spellings of each of these as one column, so
	// which one a stored rule holds is arbitrary - a rule that arrived
	// through the .nsp converter carries whichever the document used.
	// Reading one back as anything but WaxDeck's own name gives the rule
	// editor a field it cannot draw and a later PATCH one it will refuse.
	for alias, canonical := range model.QueryFieldAliases() {
		if spec, ok := ruleFieldsByEngine[canonical]; ok {
			ruleFieldsByEngine[alias] = spec
		}
	}
}

// mediaTypeRuleValues maps rule values for the mediaType field onto the
// engine's kind values.
var mediaTypeRuleValues = map[string]string{
	"music":     string(model.KindTrack),
	"podcast":   string(model.KindEpisode),
	"audiobook": string(model.KindBook),
}

// RuleVocabulary returns the rule field vocabulary plus the custom tag
// keys the caller's items carry, most used first, each counted over
// those items.
func (l *Playlists) RuleVocabulary(ctx context.Context, uc *UserCtx) (RuleFields, error) {
	out := RuleFields{Fields: make([]RuleFieldInfo, 0, len(ruleFieldSpecs))}
	for _, s := range ruleFieldSpecs {
		out.Fields = append(out.Fields, RuleFieldInfo{
			Name:        s.api,
			Kind:        s.kind,
			Ops:         ruleOpsByKind[s.kind],
			UserState:   s.userState,
			Sortable:    s.sortable,
			Description: s.desc,
		})
	}
	keys, err := l.lib.TagKeys(ctx)
	if err != nil {
		return RuleFields{}, classify(err)
	}
	if !fullReach(uc) {
		if keys, err = l.tagKeysInReach(ctx, uc, keys); err != nil {
			return RuleFields{}, err
		}
	}
	out.TagKeys = make([]RuleTagKey, 0, len(keys))
	for _, k := range keys {
		out.TagKeys = append(out.TagKeys, RuleTagKey{Key: k.Key, ItemCount: k.Count})
	}
	return out, nil
}

// tagKeysInReach recounts the catalog's tag keys over the items the
// caller may enumerate, the scope a tag facet counts in, dropping the
// keys none of them carries. The catalog counts every library.
func (l *Playlists) tagKeysInReach(ctx context.Context, uc *UserCtx, keys []read.TagKeyCount) ([]read.TagKeyCount, error) {
	out := make([]read.TagKeyCount, 0, len(keys))
	for _, k := range keys {
		if model.IsReservedTagKey(k.Key) {
			continue
		}
		q := l.Reads.facetScopeBuilder(ctx, uc).WherePresence(facetTagPrefix+k.Key, query.OpIsPresent).Build()
		n, err := l.lib.Count(ctx, q, "")
		if err != nil {
			return nil, classify(err)
		}
		if n > 0 {
			out = append(out, read.TagKeyCount{Key: k.Key, Count: n})
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Count != out[j].Count {
			return out[i].Count > out[j].Count
		}
		return out[i].Key < out[j].Key
	})
	return out, nil
}

// ruleToQuery converts and validates a wire rule against the
// vocabulary, producing the engine query a smart playlist stores.
func ruleToQuery(r SmartRule) (query.Query, error) {
	count := 0
	where, err := ruleNodeToEngine(r.Root, 1, &count)
	if err != nil {
		return query.Query{}, err
	}
	if len(r.Sorts) > maxRuleSorts {
		return query.Query{}, errInvalid(fmt.Sprintf("at most %d sort keys", maxRuleSorts))
	}
	if r.Limit < 0 {
		return query.Query{}, errInvalid("limit cannot be negative")
	}
	mode, ok := limitModeToEngine[r.LimitMode]
	if !ok {
		return query.Query{}, errInvalid("limitMode must be count, random, minutes, or megabytes")
	}
	q := query.Query{Entity: query.EntityItems, Where: where, Limit: r.Limit, LimitMode: mode, LimitSeed: r.LimitSeed}
	// Mirror the engine's limit-mode contract so a bad rule answers 400
	// on write instead of failing its first evaluation. The dry-run
	// Count call is the backstop, but an early check gives a message
	// naming the offending combination.
	switch mode {
	case query.LimitCount:
		if r.LimitSeed != 0 {
			return query.Query{}, errInvalid("limitSeed needs a random, minutes, or megabytes limit mode")
		}
	case query.LimitRandom, query.LimitMinutes, query.LimitMegabytes:
		if r.Limit <= 0 {
			return query.Query{}, errInvalid("the " + r.LimitMode + " limit mode needs a positive limit")
		}
	}
	for _, s := range r.Sorts {
		spec, ok := ruleFieldsByAPI[s.Field]
		if !ok || !spec.sortable {
			return query.Query{}, errInvalid("field " + s.Field + " cannot sort")
		}
		q.Sorts = append(q.Sorts, query.Sort{Field: spec.engine, Desc: s.Desc})
	}
	switch mode {
	case query.LimitRandom:
		if len(q.Sorts) > 0 {
			return query.Query{}, errInvalid("a random limit cannot take a sort order; the shuffle is the order")
		}
	case query.LimitMinutes, query.LimitMegabytes:
		if r.LimitSeed != 0 && len(q.Sorts) > 0 {
			return query.Query{}, errInvalid("a seeded budget limit cannot take a sort order; the seed supplies the order")
		}
		if len(q.Sorts) == 0 && r.LimitSeed == 0 {
			// Budget fill order defaults to title, per the contract, unless
			// a seed is shuffling it.
			q.Sorts = []query.Sort{{Field: "title"}}
		}
	default:
		if len(q.Sorts) == 0 {
			// A deterministic default order, per the contract.
			q.Sorts = []query.Sort{{Field: "title"}}
		}
	}
	return q, nil
}

// evaluableRule is the stored rule as a smart playlist evaluates it:
// archived members excluded, unless the rule names `state` itself.
//
// `state` is a documented rule field reachable through
// /playlists/rule-fields, so a blanket predicate would make `state is
// archived` answer nothing and kill a contract-visible capability.
//
// The stored rule is never rewritten, only the copy that gets evaluated,
// so the editor keeps showing what its author typed.
func evaluableRule(q query.Query) query.Query {
	if ruleNamesState(q.Where) {
		return q
	}
	out := q
	out.Where = withoutArchived(q.Where)
	return out
}

// withoutArchived conjoins the state predicate onto a rule's condition
// tree. A nil tree is a rule that matches everything, so the predicate
// becomes the whole condition.
func withoutArchived(where query.Node) query.Node {
	cond := query.Cond{Field: "state", Op: query.OpIsNot, Value: string(model.StateArchived)}
	if where == nil {
		return cond
	}
	return query.And{Nodes: []query.Node{where, cond}}
}

// ruleNamesState reports whether a rule's condition tree mentions the
// state field anywhere, at any depth or polarity. Deliberately coarse:
// a rule that reasons about state at all gets to keep saying what it
// means, rather than having WaxDeck guess which arm it meant.
//
// The arms here must cover every node type ruleNodeToEngine can emit.
// They do today, and the two are meant to move together: a node type
// added there and forgotten here reads as "this rule says nothing about
// state", so the archived predicate is conjoined on top of a rule that
// explicitly asked for archived items and the list comes back empty.
// The direction is at least safe - archived stays hidden rather than
// leaking - but the rule is silently not the one that was written.
func ruleNamesState(n query.Node) bool {
	switch t := n.(type) {
	case query.Cond:
		return t.Field == "state"
	case query.And:
		return slices.ContainsFunc(t.Nodes, ruleNamesState)
	case query.Or:
		return slices.ContainsFunc(t.Nodes, ruleNamesState)
	case query.Not:
		return ruleNamesState(t.Node)
	default:
		return false
	}
}

func ruleNodeToEngine(n RuleNode, depth int, count *int) (query.Node, error) {
	if depth > maxRuleDepth {
		return nil, errInvalid(fmt.Sprintf("rule nesting exceeds %d levels", maxRuleDepth))
	}
	*count++
	if *count > maxRuleNodes {
		return nil, errInvalid(fmt.Sprintf("rule exceeds %d nodes", maxRuleNodes))
	}
	switch n.Type {
	case "all", "any":
		nodes := make([]query.Node, 0, len(n.Nodes))
		for _, c := range n.Nodes {
			cn, err := ruleNodeToEngine(c, depth+1, count)
			if err != nil {
				return nil, err
			}
			nodes = append(nodes, cn)
		}
		if n.Type == "all" {
			return query.And{Nodes: nodes}, nil
		}
		return query.Or{Nodes: nodes}, nil
	case "not":
		if n.Node == nil {
			return nil, errInvalid("a not node needs a child node")
		}
		cn, err := ruleNodeToEngine(*n.Node, depth+1, count)
		if err != nil {
			return nil, err
		}
		return query.Not{Node: cn}, nil
	case "condition":
		return ruleCondToEngine(n)
	default:
		return nil, errInvalid("unknown rule node type " + n.Type)
	}
}

func ruleCondToEngine(n RuleNode) (query.Node, error) {
	if n.Field == "" {
		return nil, errInvalid("a condition needs a field")
	}
	kind := ""
	engineField := ""
	if strings.HasPrefix(n.Field, "tag.") {
		kind = ruleKindText
		engineField = n.Field
	} else {
		spec, ok := ruleFieldsByAPI[n.Field]
		if !ok {
			return nil, errInvalid("unknown rule field " + n.Field)
		}
		kind = spec.kind
		engineField = spec.engine
	}
	if !opAllowed(kind, n.Op) {
		return nil, errInvalid("operator " + n.Op + " is not valid on " + n.Field)
	}
	cond := query.Cond{Field: engineField, Op: query.Op(n.Op)}
	switch {
	case presenceOps[n.Op]:
		// No value.
	case relativeOps[n.Op]:
		ns, err := relativeWindowToNanos(n.Field, kind, n.Value)
		if err != nil {
			return nil, err
		}
		cond.Value = ns
	case n.Op == "inTheRange":
		if len(n.Values) != 2 {
			return nil, errInvalid("inTheRange on " + n.Field + " needs exactly two values")
		}
		lo, err := ruleValueToEngine(kind, n.Field, n.Values[0])
		if err != nil {
			return nil, err
		}
		hi, err := ruleValueToEngine(kind, n.Field, n.Values[1])
		if err != nil {
			return nil, err
		}
		cond.Values = []any{lo, hi}
	default:
		v, err := ruleValueToEngine(kind, n.Field, n.Value)
		if err != nil {
			return nil, err
		}
		cond.Value = v
	}
	return cond, nil
}

func opAllowed(kind, op string) bool {
	for _, o := range ruleOpsByKind[kind] {
		if o == op {
			return true
		}
	}
	return false
}

// ruleValueToEngine parses one string-encoded wire value into the typed
// value the engine compares with.
func ruleValueToEngine(kind, field, v string) (any, error) {
	switch kind {
	case ruleKindText:
		return v, nil
	case ruleKindNumber:
		if i, err := strconv.ParseInt(v, 10, 64); err == nil {
			return i, nil
		}
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f, nil
		}
		return nil, errInvalid("value for " + field + " must be a number")
	case ruleKindDate:
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			return nil, errInvalid("value for " + field + " must be an RFC 3339 timestamp")
		}
		return t.UnixNano(), nil
	case ruleKindBoolean:
		switch v {
		case "true":
			return int64(1), nil
		case "false":
			return int64(0), nil
		}
		return nil, errInvalid("value for " + field + " must be true or false")
	case ruleKindMediaType:
		mv, ok := mediaTypeRuleValues[v]
		if !ok {
			return nil, errInvalid("value for mediaType must be music, podcast, or audiobook")
		}
		return mv, nil
	case ruleKindPlaylist:
		// Syntactic only. A pid naming a playlist that was deleted, or
		// one that is smart or is this list itself, matches nothing -
		// which is the harmless answer, and cheaper than a read on
		// every rule write to say so.
		prefix, pid, ok := parseAPIPID(v)
		if !ok || prefix != PrefixPlaylist {
			return nil, errInvalid("value for playlist must be a playlist pid")
		}
		return pid, nil
	}
	return nil, errInvalid("unsupported value kind for " + field)
}

// relativeWindowToNanos parses a relative-date wire value (a positive
// whole number of days) into the nanosecond window the engine's
// inTheLast/notInTheLast operators compare, anchored at read time.
func relativeWindowToNanos(field, kind, v string) (int64, error) {
	if kind != ruleKindDate {
		return 0, errInvalid("inTheLast and notInTheLast apply only to date fields, not " + field)
	}
	days, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
	if err != nil || days <= 0 {
		return 0, errInvalid("value for " + field + " must be a positive number of days")
	}
	if days > maxRelativeDays {
		return 0, errInvalid("value for " + field + " is too large a day window")
	}
	return days * nanosPerDay, nil
}

// queryToRule converts a stored engine query back to the wire shape.
// Unknown engine fields keep their engine names, so a rule created by
// a different tool still renders read-only.
func queryToRule(q query.Query) SmartRule {
	r := SmartRule{Limit: q.Limit, LimitSeed: q.LimitSeed}
	switch q.LimitMode {
	case query.LimitRandom:
		r.LimitMode = "random"
	case query.LimitMinutes:
		r.LimitMode = "minutes"
	case query.LimitMegabytes:
		r.LimitMode = "megabytes"
	}
	if q.Where != nil {
		r.Root = engineNodeToRule(q.Where)
	} else {
		r.Root = RuleNode{Type: "all"}
	}
	for _, s := range q.Sorts {
		api := s.Field
		if spec, ok := ruleFieldsByEngine[s.Field]; ok {
			api = spec.api
		}
		// The implicit default sort round-trips invisibly.
		if len(q.Sorts) == 1 && s.Field == "title" && !s.Desc {
			continue
		}
		r.Sorts = append(r.Sorts, RuleSort{Field: api, Desc: s.Desc})
	}
	return r
}

func engineNodeToRule(n query.Node) RuleNode {
	switch v := n.(type) {
	case query.And:
		out := RuleNode{Type: "all"}
		for _, c := range v.Nodes {
			out.Nodes = append(out.Nodes, engineNodeToRule(c))
		}
		return out
	case query.Or:
		out := RuleNode{Type: "any"}
		for _, c := range v.Nodes {
			out.Nodes = append(out.Nodes, engineNodeToRule(c))
		}
		return out
	case query.Not:
		child := engineNodeToRule(v.Node)
		return RuleNode{Type: "not", Node: &child}
	case query.Cond:
		out := RuleNode{Type: "condition", Op: string(v.Op)}
		kind := ruleKindText
		if strings.HasPrefix(v.Field, "tag.") {
			out.Field = v.Field
		} else if spec, ok := ruleFieldsByEngine[v.Field]; ok {
			out.Field = spec.api
			kind = spec.kind
		} else {
			out.Field = v.Field
		}
		if v.Value != nil {
			if relativeOps[string(v.Op)] {
				// The engine stores a nanosecond window; the wire carries days.
				if ns, ok := numAsInt64(v.Value); ok {
					out.Value = strconv.FormatInt(ns/nanosPerDay, 10)
				} else {
					out.Value = engineValueToRule(kind, v.Value)
				}
			} else {
				out.Value = engineValueToRule(kind, v.Value)
			}
		}
		for _, val := range v.Values {
			out.Values = append(out.Values, engineValueToRule(kind, val))
		}
		return out
	}
	return RuleNode{Type: "all"}
}

func engineValueToRule(kind string, v any) string {
	switch kind {
	case ruleKindDate:
		if ns, ok := numAsInt64(v); ok {
			return time.Unix(0, ns).UTC().Format(time.RFC3339)
		}
	case ruleKindBoolean:
		if n, ok := numAsInt64(v); ok {
			if n != 0 {
				return "true"
			}
			return "false"
		}
	case ruleKindMediaType:
		if s, ok := v.(string); ok {
			for api, engine := range mediaTypeRuleValues {
				if engine == s {
					return api
				}
			}
		}
	case ruleKindPlaylist:
		if s, ok := v.(string); ok {
			return apiPID(PrefixPlaylist, model.PID(s))
		}
	}
	switch t := v.(type) {
	case string:
		return t
	case int64:
		return strconv.FormatInt(t, 10)
	case int:
		return strconv.Itoa(t)
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	}
	return fmt.Sprint(v)
}

func numAsInt64(v any) (int64, bool) {
	switch t := v.(type) {
	case int64:
		return t, true
	case int:
		return int64(t), true
	case float64:
		return int64(t), true
	}
	return 0, false
}
