package service

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// Playlist is the API-facing playlist shape. ItemCount is the members
// this caller is offered, which is what the item listing hands back;
// it is nil when the count is omitted (smart playlists on list pages,
// where computing it would evaluate every rule). Rule is nil for static
// playlists.
type Playlist struct {
	PID        string
	Name       string
	Kind       string
	Visibility string
	OwnerName  string
	IsOwner    bool
	ItemCount  *int
	Rule       *SmartRule
	// HasArt says a cover is stored for this playlist, whether the owner
	// uploaded one or WaxDeck built it from the members. It is what tells
	// a grid to fetch the art endpoint instead of drawing a placeholder.
	HasArt    bool
	CreatedAt time.Time
	UpdatedAt time.Time
}

// SmartRule is the wire shape of a smart playlist rule. LimitMode
// interprets Limit (empty or "count" is a plain member cap; "random",
// "minutes", and "megabytes" are the shuffle and budget modes);
// LimitSeed pins a random or budget draw.
type SmartRule struct {
	Root      RuleNode
	Sorts     []RuleSort
	Limit     int
	LimitMode string
	LimitSeed int64
}

// RuleNode is one node of a rule's condition tree; Type selects which
// fields are meaningful (all, any, not, condition).
type RuleNode struct {
	Type   string
	Nodes  []RuleNode
	Node   *RuleNode
	Field  string
	Op     string
	Value  string
	Values []string
}

// RuleSort is one sort key.
type RuleSort struct {
	Field string
	Desc  bool
}

// PlaylistPage is one page of playlists.
type PlaylistPage struct {
	Playlists []Playlist
	Next      string
}

// PlaylistEntry is one playlist member; Position is set only for
// static playlists and is the stored (unfiltered) order.
type PlaylistEntry struct {
	Position *int
	Item     ItemSummary
}

// PlaylistItemsPage is one page of playlist members.
type PlaylistItemsPage struct {
	Entries []PlaylistEntry
	Next    string
}

// PlaylistPreview is a stateless rule evaluation.
type PlaylistPreview struct {
	Items []ItemSummary
	Total int
}

// RuleFieldInfo describes one rule field for editors.
type RuleFieldInfo struct {
	Name        string
	Kind        string
	Ops         []string
	UserState   bool
	Sortable    bool
	Description string
}

// RuleTagKey is one custom tag key usable as a tag.KEY field.
type RuleTagKey struct {
	Key       string
	ItemCount int
}

// RuleFields is the rule vocabulary.
type RuleFields struct {
	Fields  []RuleFieldInfo
	TagKeys []RuleTagKey
}

// PlaylistCreate is the create request.
type PlaylistCreate struct {
	Name       string
	Kind       string
	Visibility string
	Rule       *SmartRule
	ItemPIDs   []string
}

// PlaylistUpdate is the partial update request; nil means unchanged.
type PlaylistUpdate struct {
	Name       *string
	Visibility *string
	Rule       *SmartRule
}

// M3uImportOutcome reports an M3U8 import.
type M3uImportOutcome struct {
	Playlist       Playlist
	Matched        int
	Unmatched      int
	UnmatchedPaths []string
}

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
	ruleKindText:      {"is", "isNot", "contains", "startsWith", "endsWith", "isPresent", "isMissing"},
	ruleKindNumber:    {"is", "isNot", "gt", "lt", "gte", "lte", "inTheRange", "isPresent", "isMissing"},
	ruleKindDate:      {"before", "after", "inTheRange", "inTheLast", "notInTheLast", "isPresent", "isMissing"},
	ruleKindBoolean:   {"is"},
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
	{api: "album", engine: "album", kind: ruleKindText, sortable: true, desc: "album, series, or show"},
	{api: "podcast", engine: "podcast", kind: ruleKindText, sortable: true, desc: "show title (episodes)"},
	{api: "genre", engine: "genre", kind: ruleKindText, sortable: true, desc: "genre"},
	{api: "year", engine: "year", kind: ruleKindNumber, sortable: true, desc: "release or publication year"},
	{api: "trackNumber", engine: "track_no", kind: ruleKindNumber, sortable: true, desc: "track number (music)"},
	{api: "discNumber", engine: "disc_no", kind: ruleKindNumber, sortable: true, desc: "disc number (music)"},
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
	{api: "source", engine: "source", kind: ruleKindText, sortable: true, desc: "origin: local, rss, youtube, manual"},
	{api: "codec", engine: "codec", kind: ruleKindText, sortable: true, desc: "audio codec"},
	{api: "container", engine: "container", kind: ruleKindText, sortable: true, desc: "file container"},
	{api: "path", engine: "path", kind: ruleKindText, sortable: true, desc: "file path"},
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
}

// mediaTypeRuleValues maps rule values for the mediaType field onto the
// engine's kind values.
var mediaTypeRuleValues = map[string]string{
	"music":     string(model.KindTrack),
	"podcast":   string(model.KindEpisode),
	"audiobook": string(model.KindBook),
}

// RuleVocabulary returns the rule field vocabulary plus the catalog's
// custom tag keys, most used first.
func (l *Library) RuleVocabulary(ctx context.Context) (RuleFields, error) {
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
	out.TagKeys = make([]RuleTagKey, 0, len(keys))
	for _, k := range keys {
		out.TagKeys = append(out.TagKeys, RuleTagKey{Key: k.Key, ItemCount: k.Count})
	}
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
// ADR-0048. `state` is a documented rule field reachable through
// /playlists/rule-fields, so a blanket predicate would make `state is
// archived` answer nothing and quietly kill a contract-visible
// capability. Excluding archived unless the rule asks is what someone
// writing that rule means either way.
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
// state", so ADR-0048's predicate is conjoined on top of a rule that
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

// playlistDTO converts one catalog playlist for a caller.
// narrow is the caller-scope node for static counts; a loop over many
// rows builds it once with staticMemberNarrow (it costs a subscription
// read), a single conversion passes nil and pays for its own.
func (l *Library) playlistDTO(ctx context.Context, uc *UserCtx, pl *model.Playlist, withCount bool, narrow query.Node) Playlist {
	out := Playlist{
		PID:        apiPID(PrefixPlaylist, pl.PID),
		Name:       pl.Name,
		Kind:       string(pl.Kind),
		Visibility: string(pl.Visibility),
		OwnerName:  pl.OwnerName,
		IsOwner:    string(pl.OwnerPID) == uc.CatalogPID,
		HasArt:     pl.HasArt,
		CreatedAt:  time.Unix(0, pl.CreatedAt).UTC(),
		UpdatedAt:  time.Unix(0, pl.UpdatedAt).UTC(),
	}
	// The catalog names users by their account id; show the human name.
	if u, err := l.db.UserByID(ctx, pl.OwnerName); err == nil {
		if u.DisplayName != "" {
			out.OwnerName = u.DisplayName
		} else {
			out.OwnerName = u.Username
		}
	}
	if pl.Rule != nil {
		r := queryToRule(*pl.Rule)
		out.Rule = &r
	}
	// Counted off the same membership the listing hands back, for both
	// kinds. The static branch used to report pl.ItemCount, the catalog's
	// stored member count, so a list with one trashed member answered 10
	// here and 9 from /items indefinitely; the smart branch counted the
	// rule but not the caller's own visibility.
	//
	// A static row always counts, live, whether or not the caller asked:
	// membership is a query dimension, so the answer is one indexed
	// COUNT and a listing row can afford the truth. withCount still gates
	// the smart kind, for the reason it always did - evaluating every
	// stored rule to draw a grid of tiles is the work the flag exists to
	// skip - so a smart list still reports no count on a listing, which
	// clients already treat as absent.
	if withCount || pl.Kind == model.PlaylistStatic {
		if n, err := l.visibleMemberCount(ctx, uc, pl, narrow); err == nil {
			out.ItemCount = &n
		} else {
			l.log.Warn("counting playlist members", "playlist", pl.PID, "err", err)
		}
	}
	return out
}

// playlistMembers answers a playlist's members as its owner evaluates
// them, before the caller's own filtering.
//
// A smart list goes through the unpaged evaluator rather than
// Playlists().Items, because Items evaluates the stored rule in SQL and
// leaves the state predicate to be applied in Go afterwards - so the
// rule's own Limit and LimitMode were spent on rows that the archived
// filter then dropped, and a `limit: 25` list holding five trashed rows
// came back with 20 (ADR-0051). evaluableRule conjoins the predicate
// into the query, so the limit is applied to what survives it.
//
// The user pid is the owner's, not the caller's: a shared smart list
// evaluates against its owner's user state, which is the contract
// PlaylistItems documents. PreviewRule passes the caller's pid because
// a preview is stateless and belongs to whoever is typing; copying that
// argument here would silently evaluate a shared `played = false` rule
// against each reader.
func (l *Library) playlistMembers(ctx context.Context, pl *model.Playlist) ([]*model.ItemView, error) {
	if pl.Kind != model.PlaylistStatic && pl.Rule != nil {
		items, err := l.lib.Query(ctx, evaluableRule(*pl.Rule), pl.OwnerPID)
		if err != nil {
			return nil, classify(err)
		}
		return items, nil
	}
	items, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		return nil, classify(err)
	}
	return items, nil
}

// memberFilter is the caller's own view of a playlist's membership:
// what the owner's evaluation holds, narrowed to what this reader is
// offered. One spelling, because the owner's listing, the share page,
// and the count all have to agree.
type memberFilter struct {
	uc   *UserCtx
	subs *subscriptionFilter
	// keepArchived honours a rule that names `state` for itself rather
	// than guessing which arm it meant. A smart list's query already
	// applied the predicate, so this only matters for the exempt case;
	// a static list has no rule and always filters.
	keepArchived bool
}

func (l *Library) newMemberFilter(uc *UserCtx, pl *model.Playlist) memberFilter {
	return memberFilter{
		uc:           uc,
		subs:         l.newSubscriptionFilter(uc),
		keepArchived: pl.Rule != nil && ruleNamesState(pl.Rule.Where),
	}
}

// memberVisible reports whether one stored member is offered to this
// caller.
//
// viewVisible, not itemVisible: the members are fresh item views, so the
// library handle is a field already in hand. itemVisible takes a pid and
// resolves it through the located-path cache, which on a listing page
// meant one cache lookup per member per playlist - a page of fifty
// three-hundred-member lists is fifteen thousand of them, for an answer
// sitting in the row. It is also the more correct of the two for the
// same reason the sync paths prefer it.
func (l *Library) memberVisible(ctx context.Context, f memberFilter, it *model.ItemView) bool {
	if archived(it) && !f.keepArchived {
		return false
	}
	if !l.viewVisible(ctx, f.uc, it) {
		return false
	}
	return f.subs.allowsItem(ctx, l, it)
}

// staticMemberNarrow is memberVisible as a query node: the three
// clauses that decide whether a static list's member is offered to this
// caller, in the form CountItems takes.
//
// It tracks memberVisible clause for clause, which is the invariant that
// keeps a count and its listing from disagreeing. A static list carries
// no rule, so keepArchived is never set and the state predicate always
// applies; the library grants are the allow-list form viewVisible asks
// for per item; and episodes pass only for a subscriber of their show.
//
// The two empty cases both fail closed on purpose, matching the per-item
// filter. No grants compiles to `1=0` and counts nothing. No
// subscriptions makes the second arm of the Or `1=0`, leaving "anything
// that is not an episode" - which is what allowsEpisode answers for an
// empty set. A subscription read that fails is the same answer for the
// same reason, logged rather than propagated so a podcast outage costs a
// music playlist its episodes rather than its whole count.
func (l *Library) staticMemberNarrow(ctx context.Context, uc *UserCtx) query.Node {
	nodes := []query.Node{
		query.Cond{Field: "state", Op: query.OpIsNot, Value: string(model.StateArchived)},
	}
	if !uc.AllLibraries {
		libs := make([]string, 0, len(uc.Libraries))
		for lib := range uc.Libraries {
			libs = append(libs, lib)
		}
		sort.Strings(libs)
		nodes = append(nodes, inSet("library", libs))
	}
	set, err := l.subscribedShowSet(ctx, uc)
	if err != nil {
		l.log.Warn("loading subscription set for a playlist count", "user", uc.ID, "err", err)
		set = nil
	}
	shows := make([]string, 0, len(set))
	for show := range set {
		shows = append(shows, show)
	}
	sort.Strings(shows)
	nodes = append(nodes, query.Or{Nodes: []query.Node{
		query.Cond{Field: "kind", Op: query.OpIsNot, Value: string(model.KindEpisode)},
		inSet("podcast_pid", shows),
	}})
	return query.And{Nodes: nodes}
}

// inSet is field membership within the engine's per-condition value cap
// (waxbin's maxInValues, 500), chunked into an Or above it - its own
// docs say a caller needing more should chunk. Without this, a caller
// following 500+ shows or granted 500+ libraries would fail the count's
// compile and read null counts forever. An empty set stays one empty
// OpIn, which compiles to match-nothing: both callers fail closed on
// purpose.
func inSet(field string, values []string) query.Node {
	const maxInValues = 500
	if len(values) <= maxInValues {
		return query.Cond{Field: field, Op: query.OpIn, Values: query.Values(values)}
	}
	chunks := make([]query.Node, 0, (len(values)+maxInValues-1)/maxInValues)
	for start := 0; start < len(values); start += maxInValues {
		end := min(start+maxInValues, len(values))
		chunks = append(chunks, query.Cond{
			Field: field, Op: query.OpIn, Values: query.Values(values[start:end]),
		})
	}
	return query.Or{Nodes: chunks}
}

// visibleMemberCount counts a playlist's members as this caller sees
// them.
//
// A static list counts in the engine: membership is a query dimension
// now, so the whole thing is one indexed COUNT rather than hydrating
// every member to filter it in Go. It counts entries, not distinct
// items, which is what the listing beside it shows - a list holding a
// track twice reads 2.
//
// A smart list deliberately does not, even though CountItems serves both
// kinds. WaxDeck evaluates a stored rule through evaluableRule, which
// conjoins the archived predicate *before* the rule's own limit
// (ADR-0051); CountItems evaluates the rule as stored. For a limited
// rule over a list holding archived members the two disagree, and the
// half that has to be right is the one the member listing uses.
func (l *Library) visibleMemberCount(ctx context.Context, uc *UserCtx, pl *model.Playlist, narrow query.Node) (int, error) {
	if pl.Kind == model.PlaylistStatic {
		if narrow == nil {
			narrow = l.staticMemberNarrow(ctx, uc)
		}
		n, err := l.lib.Playlists().CountItems(ctx, pl.PID, pl.OwnerPID, narrow)
		if err != nil {
			return 0, classify(err)
		}
		return n, nil
	}
	members, err := l.playlistMembers(ctx, pl)
	if err != nil {
		return 0, err
	}
	f := l.newMemberFilter(uc, pl)
	n := 0
	for _, it := range members {
		if l.memberVisible(ctx, f, it) {
			n++
		}
	}
	return n, nil
}

// resolvePlaylist fetches a playlist the caller may read: their own, or
// any shared one. Anything else reads as absent.
func (l *Library) resolvePlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (*model.Playlist, error) {
	prefix, pid, ok := parseAPIPID(apiPlaylistPID)
	if !ok || prefix != PrefixPlaylist {
		return nil, errNotFound("no playlist " + apiPlaylistPID)
	}
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		if KindOf(classify(err)) == KindNotFound {
			return nil, errNotFound("no playlist " + apiPlaylistPID)
		}
		return nil, classify(err)
	}
	if string(pl.OwnerPID) != uc.CatalogPID && pl.Visibility != model.VisibilityShared {
		return nil, errNotFound("no playlist " + apiPlaylistPID)
	}
	return pl, nil
}

// resolveOwnedPlaylist fetches a playlist the caller may edit.
func (l *Library) resolveOwnedPlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (*model.Playlist, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return nil, err
	}
	if string(pl.OwnerPID) != uc.CatalogPID {
		return nil, &Error{Kind: KindForbidden, Msg: "only the owner may edit a playlist"}
	}
	return pl, nil
}

// Playlists pages the caller's own playlists plus every shared one,
// ordered by name then pid. containsItem restricts to static playlists
// holding that item.
func (l *Library) Playlists(ctx context.Context, uc *UserCtx, containsItem, cursor string, limit int) (PlaylistPage, error) {
	all, err := l.lib.Playlists().List(ctx, model.PID(uc.CatalogPID))
	if err != nil {
		return PlaylistPage{}, classify(err)
	}
	sort.SliceStable(all, func(i, j int) bool {
		ni, nj := strings.ToLower(all[i].Name), strings.ToLower(all[j].Name)
		if ni != nj {
			return ni < nj
		}
		return all[i].PID < all[j].PID
	})
	if containsItem != "" {
		filtered, err := l.filterPlaylistsByMember(ctx, all, containsItem)
		if err != nil {
			return PlaylistPage{}, err
		}
		all = filtered
	}
	off, err := decodeOffsetCursor(cursor)
	if err != nil {
		return PlaylistPage{}, err
	}
	out := PlaylistPage{Playlists: []Playlist{}}
	// Once for the page: the node depends only on the caller, and every
	// static row's count rides it.
	narrow := l.staticMemberNarrow(ctx, uc)
	for i := off; i < len(all); i++ {
		if len(out.Playlists) == limit {
			out.Next = encodeOffsetCursor(i)
			break
		}
		out.Playlists = append(out.Playlists, l.playlistDTO(ctx, uc, all[i], false, narrow))
	}
	return out, nil
}

// filterPlaylistsByMember keeps static playlists whose stored members
// include the item. Membership scans each candidate's stored list;
// playlist libraries are small and the filter is an interactive
// add-to-playlist affordance, not a hot path.
func (l *Library) filterPlaylistsByMember(ctx context.Context, all []*model.Playlist, apiItemPID string) ([]*model.Playlist, error) {
	prefix, itemPID, ok := parseAPIPID(apiItemPID)
	if !ok || !itemPrefix(prefix) {
		return nil, errInvalid("containsItem must be an item pid")
	}
	var out []*model.Playlist
	for _, pl := range all {
		if pl.Kind != model.PlaylistStatic {
			continue
		}
		items, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range items {
			if it.PID == itemPID {
				out = append(out, pl)
				break
			}
		}
	}
	return out, nil
}

// PlaylistByPID returns one playlist with a computed count for smart
// lists.
func (l *Library) PlaylistByPID(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (Playlist, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return Playlist{}, err
	}
	return l.playlistDTO(ctx, uc, pl, true, nil), nil
}

// CreatePlaylist creates a static or smart playlist owned by the
// caller.
func (l *Library) CreatePlaylist(ctx context.Context, uc *UserCtx, req PlaylistCreate) (Playlist, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return Playlist{}, errInvalid("a playlist needs a name")
	}
	vis, err := playlistVisibility(req.Visibility)
	if err != nil {
		return Playlist{}, err
	}
	owner := model.PID(uc.CatalogPID)
	var pid model.PID
	switch req.Kind {
	case string(model.PlaylistStatic):
		if req.Rule != nil {
			return Playlist{}, errInvalid("a static playlist does not take a rule")
		}
		items, err := l.resolveItemPIDs(ctx, uc, req.ItemPIDs)
		if err != nil {
			return Playlist{}, err
		}
		pid, err = l.lib.Playlists().CreateStatic(ctx, name, owner, vis)
		if err != nil {
			return Playlist{}, classify(err)
		}
		if len(items) > 0 {
			if err := l.lib.Playlists().Add(ctx, pid, items...); err != nil {
				return Playlist{}, classify(err)
			}
		}
	case string(model.PlaylistSmart):
		if req.Rule == nil {
			return Playlist{}, errInvalid("a smart playlist needs a rule")
		}
		if len(req.ItemPIDs) > 0 {
			return Playlist{}, errInvalid("a smart playlist does not take members")
		}
		q, err := ruleToQuery(*req.Rule)
		if err != nil {
			return Playlist{}, err
		}
		// A dry-run evaluation surfaces engine-level rejections (a bad
		// tag key, an unsortable sort) at write time, per the contract.
		if _, err := l.lib.Count(ctx, q, owner); err != nil {
			return Playlist{}, classify(err)
		}
		pid, err = l.lib.Playlists().CreateSmart(ctx, name, owner, vis, q)
		if err != nil {
			return Playlist{}, classify(err)
		}
	default:
		return Playlist{}, errInvalid("kind must be static or smart")
	}
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		return Playlist{}, classify(err)
	}
	// Cover the playlist now rather than on its first open, so a list
	// created from a selection is not a blank tile on the grid it lands
	// back on.
	l.refreshPlaylistCover(ctx, pl)
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pid))
	return l.playlistDTO(ctx, uc, pl, true, nil), nil
}

// UpdatePlaylist applies a partial update: a rename, a visibility
// change, or a smart playlist's rule, in any combination. Each applies
// in place under a stable pid - the rule setter lets the rule change
// without reissuing - so one server event carries the result.
func (l *Library) UpdatePlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string, req PlaylistUpdate) (Playlist, error) {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return Playlist{}, err
	}
	wasShared := pl.Visibility == model.VisibilityShared

	name := pl.Name
	if req.Name != nil {
		name = strings.TrimSpace(*req.Name)
		if name == "" {
			return Playlist{}, errInvalid("a playlist needs a name")
		}
	}
	vis := pl.Visibility
	if req.Visibility != nil {
		vis, err = playlistVisibility(*req.Visibility)
		if err != nil {
			return Playlist{}, err
		}
	}

	// Validate the rule before any mutation, so a bad rule (a static
	// playlist, an unknown field, an invalid limit mode) fails the whole
	// PATCH with nothing changed. The dry-run Count surfaces engine-level
	// rejections at write time, per the contract.
	var newRule *query.Query
	if req.Rule != nil {
		if pl.Kind != model.PlaylistSmart {
			return Playlist{}, errInvalid("a static playlist does not take a rule")
		}
		q, err := ruleToQuery(*req.Rule)
		if err != nil {
			return Playlist{}, err
		}
		if _, err := l.lib.Count(ctx, q, pl.OwnerPID); err != nil {
			return Playlist{}, classify(err)
		}
		newRule = &q
	}

	// Apply the changes. The engine facade has no cross-call transaction,
	// so a multi-field PATCH interrupted by a transient engine fault can
	// apply some fields and not others. Two things bound that: every
	// validation is front-loaded above (name, visibility, and the rule
	// dry-run all run before the first mutation), so only an I/O fault
	// can interrupt here; and each setter is idempotent, so the caller's
	// retry converges. The cheap metadata applies first and the rule
	// last, so a metadata fault never leaves a changed rule behind.
	if req.Name != nil && name != pl.Name {
		if err := l.lib.Playlists().Rename(ctx, pl.PID, name); err != nil {
			return Playlist{}, classify(err)
		}
	}
	if req.Visibility != nil && vis != pl.Visibility {
		if err := l.lib.Playlists().SetVisibility(ctx, pl.PID, vis); err != nil {
			return Playlist{}, classify(err)
		}
	}
	if newRule != nil {
		if err := l.lib.Playlists().SetRule(ctx, pl.PID, *newRule); err != nil {
			return Playlist{}, classify(err)
		}
	}
	// A visibility flip in either direction changes who can see the
	// playlist, so fan out to everyone when it is (or was) shared.
	l.emitPlaylistEvent(ctx, uc, wasShared || vis == model.VisibilityShared, string(pl.PID))
	got, err := l.lib.Playlists().Get(ctx, pl.PID)
	if err != nil {
		return Playlist{}, classify(err)
	}
	if newRule != nil {
		// A new rule is a new member list, so the cover built from the old
		// one is stale. This is a one-shot edit, not a gesture like the
		// reorder, and the caller often lands back on the playlist grid,
		// which loads no members of its own.
		l.refreshPlaylistCover(ctx, got)
	}
	return l.playlistDTO(ctx, uc, got, true, nil), nil
}

// DeletePlaylist deletes an owned playlist.
func (l *Library) DeletePlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	wasShared := pl.Visibility == model.VisibilityShared
	if err := l.lib.Playlists().Delete(ctx, pl.PID); err != nil {
		return classify(err)
	}
	// The catalog drops the art rows with the playlist; this drops the
	// provenance beside them, so a later playlist minted with the same
	// pid does not inherit a custom origin over an empty slot.
	if err := l.db.DeletePlaylistCover(ctx, string(pl.PID)); err != nil {
		l.log.Warn("clearing playlist cover state", "playlist", pl.PID, "err", err)
	}
	l.emitPlaylistEvent(ctx, uc, wasShared, string(pl.PID))
	l.Audit(ctx, uc, "playlist.delete",
		AuditTarget{Kind: "playlist", PID: apiPID(PrefixPlaylist, pl.PID), Name: pl.Name},
		map[string]any{"shared": wasShared})
	return nil
}

// PlaylistItems pages a playlist's members. A smart playlist evaluates
// against its owner's user state (the contract for shared lists); the
// caller's own library visibility still filters what they see.
func (l *Library) PlaylistItems(ctx context.Context, uc *UserCtx, apiPlaylistPID, cursor string, limit int) (PlaylistItemsPage, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return PlaylistItemsPage{}, err
	}
	items, err := l.playlistMembers(ctx, pl)
	if err != nil {
		return PlaylistItemsPage{}, err
	}
	off, err := decodeOffsetCursor(cursor)
	if err != nil {
		return PlaylistItemsPage{}, err
	}
	// The members are loaded here anyway, so this is where a generated
	// cover catches up with them: a smart playlist whose computed
	// membership drifted refreshes the next time anyone opens it, without
	// costing an art request a resolve. It runs after the cursor check, so
	// a malformed cursor answers 400 without doing the work. The full
	// member list is used, not the caller's filtered view -- the cover
	// belongs to the playlist, like its name, not to whoever is reading it.
	// For a smart list "full" now means the rule's own evaluation with
	// the state predicate inside it, so a trashed member stops
	// contributing cover art; that is a deliberate consequence of moving
	// the predicate into the query rather than a second policy.
	l.syncPlaylistCover(ctx, pl, items)
	static := pl.Kind == model.PlaylistStatic
	// A static list's members are stored rows and are filtered here; a
	// smart list's already left the query filtered. Positions still count
	// off the full stored list, exactly as they do for members the caller
	// cannot see, so a restore lands where it was.
	f := l.newMemberFilter(uc, pl)
	out := PlaylistItemsPage{Entries: []PlaylistEntry{}}
	for i := off; i < len(items); i++ {
		if len(out.Entries) == limit {
			out.Next = encodeOffsetCursor(i)
			break
		}
		it := items[i]
		if !l.memberVisible(ctx, f, it) {
			continue
		}
		entry := PlaylistEntry{Item: summary(it)}
		if static {
			pos := i
			entry.Position = &pos
		}
		out.Entries = append(out.Entries, entry)
	}
	return out, nil
}

// ReplacePlaylistItems replaces a static playlist's full member list;
// this is the reorder primitive.
func (l *Library) ReplacePlaylistItems(ctx context.Context, uc *UserCtx, apiPlaylistPID string, itemPIDs []string, baseUpdatedAt *time.Time) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	if pl.Kind != model.PlaylistStatic {
		return errInvalid("a smart playlist's membership is its rule")
	}
	// Clients echo the timestamp through their own date-time types
	// (Dart keeps microseconds, JavaScript milliseconds), so the
	// lost-update guard compares at millisecond grain; nanosecond
	// identity would refuse every honest reorder from a client that
	// cannot represent the stored precision.
	if baseUpdatedAt != nil {
		stored := time.Unix(0, pl.UpdatedAt).UTC().Truncate(time.Millisecond)
		if !baseUpdatedAt.Truncate(time.Millisecond).Equal(stored) {
			return &Error{Kind: KindConflict, Msg: "the playlist changed since this member list was built; refetch and retry"}
		}
	}
	// A replace built by an owner who cannot currently see every stored
	// member would silently drop the hidden ones; refuse instead. The
	// member list hides on three dimensions - library visibility,
	// unsubscribed shows' episodes, and trashed members (ADR-0048) - so
	// the guard covers all three, and the last two apply to
	// full-visibility users too. This path is static-only (refused
	// above), so pl.Rule is nil and no state-naming rule exempts the
	// archived arm.
	stored, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		return classify(err)
	}
	subs := l.newSubscriptionFilter(uc)
	for _, it := range stored {
		if archived(it) {
			return &Error{Kind: KindConflict, Msg: "the playlist holds members that are in the trash; a replace would drop them permanently"}
		}
		if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
			return &Error{Kind: KindConflict, Msg: "the playlist holds members outside your current library visibility; a replace would drop them"}
		}
		if !subs.allowsItem(ctx, l, it) {
			return &Error{Kind: KindConflict, Msg: "the playlist holds episodes of shows you are not subscribed to; a replace would drop them"}
		}
	}
	items, err := l.resolveItemPIDs(ctx, uc, itemPIDs)
	if err != nil {
		return err
	}
	if err := l.lib.Playlists().Set(ctx, pl.PID, items); err != nil {
		return classify(err)
	}
	// No eager cover rebuild here. This is the reorder primitive, so it
	// runs on every drag, and rebuilding a mosaic is four art resolves
	// and a composite; the caller is looking at the member list and
	// re-reads it immediately, where the read-path sync catches up.
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	return nil
}

// AddPlaylistItems appends members to a static playlist.
func (l *Library) AddPlaylistItems(ctx context.Context, uc *UserCtx, apiPlaylistPID string, itemPIDs []string) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	if pl.Kind != model.PlaylistStatic {
		return errInvalid("a smart playlist's membership is its rule")
	}
	items, err := l.resolveItemPIDs(ctx, uc, itemPIDs)
	if err != nil {
		return err
	}
	if len(items) == 0 {
		return errInvalid("no items to add")
	}
	if err := l.lib.Playlists().Add(ctx, pl.PID, items...); err != nil {
		return classify(err)
	}
	// Unlike the reorder and remove above, nothing reads the members
	// after this: adding happens from the player, and the next thing to
	// show the playlist is a grid tile. Cover it now.
	l.refreshPlaylistCover(ctx, pl)
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	return nil
}

// RemovePlaylistItemAt removes the member at one stored position.
func (l *Library) RemovePlaylistItemAt(ctx context.Context, uc *UserCtx, apiPlaylistPID string, position int) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	if pl.Kind != model.PlaylistStatic {
		return errInvalid("a smart playlist's membership is its rule")
	}
	if err := l.lib.Playlists().RemoveAt(ctx, pl.PID, position); err != nil {
		return classify(err)
	}
	// Same as the reorder: the caller is in the member list and re-reads
	// it, so the cover catches up there rather than on this request.
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	return nil
}

// PreviewRule evaluates a rule statelessly for the caller.
func (l *Library) PreviewRule(ctx context.Context, uc *UserCtx, rule SmartRule, limit int) (PlaylistPreview, error) {
	q, err := ruleToQuery(rule)
	if err != nil {
		return PlaylistPreview{}, err
	}
	// The preview has to evaluate what the saved playlist would, or a
	// rule looks right in the editor and comes back shorter once saved.
	q = evaluableRule(q)
	user := model.PID(uc.CatalogPID)
	// Total is the condition-match count, ignoring the rule's own limit.
	// A random or budget mode rejects a zero limit, so count as a plain
	// match count rather than reusing the rule's mode.
	qc := q
	qc.Limit = 0
	qc.LimitMode = query.LimitCount
	qc.LimitSeed = 0
	qc.Sorts = nil
	total, err := l.lib.Count(ctx, qc, user)
	if err != nil {
		return PlaylistPreview{}, classify(err)
	}
	// The items evaluate the real rule. A plain count limit can be
	// narrowed to the preview page for efficiency; a random or budget
	// limit must evaluate as written (its limit is a draw size or a
	// budget, not a row cap) and is capped for display in the loop.
	qi := q
	if qi.LimitMode == query.LimitCount && (qi.Limit == 0 || qi.Limit > limit) {
		qi.Limit = limit
	}
	items, err := l.lib.Query(ctx, qi, user)
	if err != nil {
		return PlaylistPreview{}, classify(err)
	}
	subs := l.newSubscriptionFilter(uc)
	out := PlaylistPreview{Items: []ItemSummary{}, Total: total}
	for _, it := range items {
		if len(out.Items) >= limit {
			break
		}
		if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
			continue
		}
		if !subs.allowsItem(ctx, l, it) {
			continue
		}
		out.Items = append(out.Items, summary(it))
	}
	return out, nil
}

// ExportPlaylistM3U renders a playlist as an M3U8 document.
func (l *Library) ExportPlaylistM3U(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (string, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return "", err
	}
	var buf bytes.Buffer
	if err := l.lib.Playlists().ExportM3U8(ctx, pl.PID, &buf, pl.OwnerPID); err != nil {
		return "", classify(err)
	}
	return buf.String(), nil
}

// ImportPlaylistM3U creates a static playlist from an M3U8 document.
func (l *Library) ImportPlaylistM3U(ctx context.Context, uc *UserCtx, name, visibility, content string) (M3uImportOutcome, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return M3uImportOutcome{}, errInvalid("a playlist needs a name")
	}
	vis, err := playlistVisibility(visibility)
	if err != nil {
		return M3uImportOutcome{}, err
	}
	res, err := l.lib.Playlists().ImportM3U8(ctx, name, model.PID(uc.CatalogPID), vis, strings.NewReader(content))
	if err != nil {
		return M3uImportOutcome{}, classify(err)
	}
	pl, err := l.lib.Playlists().Get(ctx, res.PlaylistPID)
	if err != nil {
		return M3uImportOutcome{}, classify(err)
	}
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	return M3uImportOutcome{
		Playlist:       l.playlistDTO(ctx, uc, pl, true, nil),
		Matched:        res.Matched,
		Unmatched:      res.Unmatched,
		UnmatchedPaths: res.UnmatchedPaths,
	}, nil
}

// resolveItemPIDs validates item pids against the caller's visibility
// and returns the bare catalog pids in order.
func (l *Library) resolveItemPIDs(ctx context.Context, uc *UserCtx, apiPIDs []string) ([]model.PID, error) {
	out := make([]model.PID, 0, len(apiPIDs))
	for _, p := range apiPIDs {
		it, err := l.getVisibleItem(ctx, uc, p)
		if err != nil {
			return nil, err
		}
		out = append(out, it.PID)
	}
	return out, nil
}

// playlistVisibility validates the wire visibility; empty means
// private.
func playlistVisibility(v string) (model.PlaylistVisibility, error) {
	switch v {
	case "", string(model.VisibilityPrivate):
		return model.VisibilityPrivate, nil
	case string(model.VisibilityShared):
		return model.VisibilityShared, nil
	}
	return "", errInvalid("visibility must be private or shared")
}

// emitPlaylistEvent appends playlist change events: always to the
// acting user, and to every other user when the playlist is (or was)
// shared, since shared playlists are visible to everyone. barePID is
// the bare catalog pid.
func (l *Library) emitPlaylistEvent(ctx context.Context, uc *UserCtx, shared bool, barePID string) {
	l.emitUserEvent(ctx, uc.ID, eventPlaylist, barePID)
	if !shared {
		return
	}
	users, err := l.db.ListUsers(ctx, "", 10000)
	if err != nil {
		l.log.Warn("fanning out playlist event", "err", err)
		return
	}
	for _, u := range users {
		if u.ID != uc.ID {
			l.emitUserEvent(ctx, u.ID, eventPlaylist, barePID)
		}
	}
}

// encodeOffsetCursor and decodeOffsetCursor page in-memory lists (a
// playlist's members, the playlist listing itself). The offset is
// opaque on the wire; positions inside one evaluation are what the
// contract promises.
//
// The prefix carries a version, retired the same way the scoped
// cursors' one is: bump it in the change that alters what the offset
// indexes into, and the old spelling stops parsing, so a cursor from
// before the change answers 400 instead of walking a shifted window.
// ADR-0052 bumped it to o1 - a smart playlist's offset used to index
// into the unfiltered member list and now indexes into the rule's own
// filtered evaluation, so the same number names a different row.
//
// Two surfaces mint these, and only one of them changed: the member
// listing above and the playlist listing itself. They share the prefix
// deliberately, because a second version constant is a second thing to
// remember to bump - but it means a bump for either 400s an in-flight
// scroll of both. The blast radius is one scroll, which is why that is
// the cheaper trade; whoever bumps it next should know they are
// retiring both.
const offsetCursorVersion = "o1:"

func encodeOffsetCursor(off int) string {
	return base64.RawURLEncoding.EncodeToString([]byte(offsetCursorVersion + strconv.Itoa(off)))
}

func decodeOffsetCursor(c string) (int, error) {
	if c == "" {
		return 0, nil
	}
	raw, err := base64.RawURLEncoding.DecodeString(c)
	if err != nil || !strings.HasPrefix(string(raw), offsetCursorVersion) {
		return 0, errInvalid("malformed cursor")
	}
	off, err := strconv.Atoi(strings.TrimPrefix(string(raw), offsetCursorVersion))
	if err != nil || off < 0 {
		return 0, errInvalid("malformed cursor")
	}
	return off, nil
}
