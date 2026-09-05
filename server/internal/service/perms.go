package service

import (
	"context"
	"encoding/json"
	"reflect"
	"slices"
	"strings"
	"sync"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// tagValueCache memoizes each custom-tag field's stored spellings within
// one generation of the catalog they were read from.
type tagValueCache struct {
	mu      sync.Mutex
	gen     facetGeneration
	byField map[string][]string
}

// Permissions is one account's granular toggles. Administrators
// implicitly hold every permission and carry no tag rules; these govern
// everyone else.
type Permissions struct {
	Download       bool
	Delete         bool
	Explicit       bool
	SharedOutputs  bool
	ManagePodcasts bool
	// MaxTranscodeKbps caps the account's transcode bitrate; 0 means the
	// server default applies.
	MaxTranscodeKbps int64
	// TagAllow, when non-empty, restricts visibility to items matching
	// every rule; TagDeny hides items matching any rule. An item without
	// a deny rule's tag passes it (absence is not a match) - the exact
	// deny-list contract.
	TagAllow []TagRule
	TagDeny  []TagRule
}

// TagRule is one custom-tag predicate: key equality with an optional
// value (absent matches any value, case-insensitively).
type TagRule struct {
	Key   string `json:"key"`
	Value string `json:"value,omitempty"`
}

// DefaultPermissions is a new account's toggle set: everything on
// except delete, and no tag rules.
func DefaultPermissions() Permissions {
	return Permissions{Download: true, Explicit: true, SharedOutputs: true, ManagePodcasts: true}
}

// tagRulesDoc is the users.tag_rules JSON shape.
type tagRulesDoc struct {
	Allow []TagRule `json:"allow,omitempty"`
	Deny  []TagRule `json:"deny,omitempty"`
}

// PermissionsOf reads an account row's permission set.
func PermissionsOf(u *wdb.User) Permissions { return permissionsOf(u) }

// permissionsOf reads an account row's permission set.
func permissionsOf(u *wdb.User) Permissions {
	p := Permissions{
		Download:         u.PermDownload,
		Delete:           u.PermDelete,
		Explicit:         u.PermExplicit,
		SharedOutputs:    u.PermSharedOutputs,
		ManagePodcasts:   u.PermPodcasts,
		MaxTranscodeKbps: u.MaxTranscodeKbps,
	}
	if u.TagRules != "" {
		var doc tagRulesDoc
		// A malformed document (impossible through the API) fails closed
		// to "no rules" rather than poisoning every read.
		if err := json.Unmarshal([]byte(u.TagRules), &doc); err == nil {
			p.TagAllow, p.TagDeny = doc.Allow, doc.Deny
		}
	}
	return p
}

// applyPermissions writes a permission set onto an account row.
func applyPermissions(u *wdb.User, p Permissions) error {
	u.PermDownload = p.Download
	u.PermDelete = p.Delete
	u.PermExplicit = p.Explicit
	u.PermSharedOutputs = p.SharedOutputs
	u.PermPodcasts = p.ManagePodcasts
	u.MaxTranscodeKbps = p.MaxTranscodeKbps
	if len(p.TagAllow) == 0 && len(p.TagDeny) == 0 {
		u.TagRules = ""
		return nil
	}
	raw, err := json.Marshal(tagRulesDoc{Allow: p.TagAllow, Deny: p.TagDeny})
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	u.TagRules = string(raw)
	return nil
}

// validatePermissions rejects out-of-range values and malformed rules.
func validatePermissions(p Permissions) error {
	if p.MaxTranscodeKbps < 0 {
		return errInvalid("maxTranscodeKbps must not be negative")
	}
	for _, r := range append(append([]TagRule{}, p.TagAllow...), p.TagDeny...) {
		key := strings.TrimSpace(r.Key)
		if key == "" || key != r.Key {
			return errInvalid("tag rule keys must not be empty or carry surrounding whitespace")
		}
		if len(key) > 64 {
			return errInvalid("tag rule keys must be at most 64 characters")
		}
		if len(r.Value) > 256 {
			return errInvalid("tag rule values must be at most 256 characters")
		}
	}
	if len(p.TagAllow) > 32 || len(p.TagDeny) > 32 {
		return errInvalid("at most 32 tag rules per list")
	}
	return nil
}

// allowedByContent reports whether the caller's explicit toggle and tag
// rules admit the item. Unrestricted callers (everyone by default, and
// every administrator) short-circuit without any lookups; restricted
// callers cost one tag read per item, the same class as the restricted
// visibility check. Episodes gate on the feed-declared explicit flag;
// tag rules cover the music and audiobook side, where no canonical
// explicit flag exists.
func (l *Library) allowedByContent(ctx context.Context, uc *UserCtx, it *model.ItemView) bool {
	if uc.Admin || uc.ContentUnrestricted() {
		return true
	}
	if it.Kind == model.KindEpisode {
		return advisoryAllows(uc, it)
	}
	if len(uc.TagAllow) == 0 && len(uc.TagDeny) == 0 {
		return true
	}
	tags, err := l.lib.ItemTags(ctx, it.PID)
	if err != nil {
		return false // fail closed for restricted callers
	}
	return matchesTagRules(tags, uc.TagAllow, uc.TagDeny)
}

// advisoryAllows is the episode half of allowedByContent, and the whole
// of it for a listing whose query already carries the tag rules. It
// stays per-item because the advisory flags are a per-item decision no
// aggregation expresses, and it costs no reads: the view projects both
// flags - the episode's own and its show's - because a feed may mark
// itself explicit at the channel level and leave every episode unmarked.
func advisoryAllows(uc *UserCtx, it *model.ItemView) bool {
	if uc.Admin || uc.Explicit {
		return true
	}
	return !it.AdvisoryFlagged()
}

// episodeAllowed is the whole of "may this caller open this episode":
// its own advisory flag, then its show's. It is the episode-row form of
// what ItemView.AdvisoryFlagged answers for free, and exists because
// model.Episode projects no show flag: a caller holding a detail read
// has to fetch the show to ask the same question. Trading that read for
// an item-view read would buy nothing, so this stays.
//
// Both flags, because a feed may mark itself explicit at the channel
// level and leave every episode unmarked, so the episode flag alone
// would let the unmarked ones through. The rule lives in one place so
// every surface applies it identically: the alternative is what this
// replaced, where a detail read answered an episode the stream refused.
//
// Fails closed on a missing episode row and on an unreadable show, as
// the rest of this file does. The nil guard is first and not beside the
// caller that happened to need it: a detail read hands its row straight
// in, and a permission rule that panics on the input one caller already
// treats as a refusal is not a shared rule.
func (l *Library) episodeAllowed(ctx context.Context, uc *UserCtx, ep *model.Episode) bool {
	if ep == nil {
		return false
	}
	if uc.Explicit {
		return true
	}
	if ep.Explicit {
		return false
	}
	show, err := l.lib.Podcasts().Get(ctx, ep.PodcastPID)
	return err == nil && !show.Explicit
}

// contentAllowsPID is allowedByContent for callers holding only a PID
// (search hits): unrestricted callers short-circuit, restricted ones
// pay one item read.
func (l *Library) contentAllowsPID(ctx context.Context, uc *UserCtx, pid model.PID) bool {
	if uc.Admin || uc.ContentUnrestricted() {
		return true
	}
	it, err := l.lib.Get(ctx, pid)
	if err != nil {
		return false
	}
	return l.allowedByContent(ctx, uc, it)
}

// contentRuleNode is matchesTagRules as a query node, so an aggregation
// can carry the caller's tag rules instead of a per-item pass being the
// only place they apply. A nil node means "no narrowing": an
// administrator, an unrestricted caller, or one with no tag rules.
//
// The translation mirrors the per-item filter. Case-folded value
// matching becomes membership over the stored spellings that fold to
// the rule's value (SQL does not fold, and changing the collation
// would change every query with it). Deny rides the set field's own
// negation - NOT EXISTS upstream - so an item tagged both Rock and
// Jazz under a Jazz deny is excluded rather than passing on its other
// value. A key the engine cannot address (reserved or illegal) admits
// nothing under allow and denies nothing under deny, which is what
// tagRuleMatches answers, since such keys are never stored as custom
// tags.
//
// Episodes sit outside every arm, including the failed ones: their
// content gate is the feed's advisory flag, per-item by nature, and
// the per-item filter short-circuits them before it ever reads tags.
//
// A spelling read that fails compiles to match-nothing for the
// caller's non-episode rows, allow and deny alike. The per-item filter
// fails closed on an unreadable tag read, and the listing path carries
// this node in place of that filter, so a transient store error must
// not serve a page the deny rules would have hidden.
func (l *Library) contentRuleNode(ctx context.Context, uc *UserCtx) query.Node {
	if uc.Admin || uc.ContentUnrestricted() {
		return nil
	}
	if len(uc.TagAllow) == 0 && len(uc.TagDeny) == 0 {
		return nil
	}
	// Every non-nil return keeps the episode arm open, the fail-closed
	// ones included: hiding episodes a detail read still serves would be
	// the listing/detail disagreement this function exists to remove.
	episodesAside := func(n query.Node) query.Node {
		return query.Or{Nodes: []query.Node{
			query.Cond{Field: "kind", Op: query.OpIs, Value: string(model.KindEpisode)},
			n,
		}}
	}
	// An empty Or matches nothing: the arm for an allow rule that can
	// never be satisfied, and for a spelling read that failed.
	matchNothing := query.Or{}
	// One rule, one condition, deliberately: a presence rule beside a
	// value rule on the same key compiles a conjunct the value rule
	// already implies, and it stays. This function's contract is being
	// a structural mirror of matchesTagRules; cross-rule minimisation
	// would trade one cheap indexed subquery for divergence risk.
	conds := make([]query.Node, 0, len(uc.TagAllow)+len(uc.TagDeny))
	for _, r := range uc.TagAllow {
		field, ok := tagRuleField(r.Key)
		if !ok {
			return episodesAside(matchNothing)
		}
		if r.Value == "" {
			conds = append(conds, query.Cond{Field: field, Op: query.OpIsPresent})
			continue
		}
		spellings, err := l.tagSpellings(ctx, field, r.Value)
		if err != nil {
			return episodesAside(matchNothing)
		}
		conds = append(conds, query.Cond{
			Field: field, Op: query.OpIn, Values: query.Values(spellings),
		})
	}
	for _, r := range uc.TagDeny {
		field, ok := tagRuleField(r.Key)
		if !ok {
			continue
		}
		if r.Value == "" {
			conds = append(conds, query.Cond{Field: field, Op: query.OpIsMissing})
			continue
		}
		spellings, err := l.tagSpellings(ctx, field, r.Value)
		if err != nil {
			return episodesAside(matchNothing)
		}
		if len(spellings) == 0 {
			continue
		}
		conds = append(conds, query.Cond{
			Field: field, Op: query.OpNotIn, Values: query.Values(spellings),
		})
	}
	if len(conds) == 0 {
		return nil
	}
	return episodesAside(query.And{Nodes: conds})
}

// tagRuleField names the query field a tag rule's key addresses, or
// reports that the key has none: it is not a legal custom-tag key, or it
// is one of the reserved names another surface owns.
func tagRuleField(key string) (string, bool) {
	canonical, ok := model.CanonicalTagKey(key)
	if !ok || model.IsReservedTagKey(canonical) {
		return "", false
	}
	return facetTagPrefix + canonical, true
}

// tagSpellings lists the stored values of a tag field that case-fold to
// value, which is how EqualFold survives the trip into SQL. An error is
// the caller's to fail closed on; a value nothing carries is a nil
// slice and no error.
//
// Read off the catalog's own aggregation over the whole library, not the
// caller's scope: this builds a filter, so it needs every spelling that
// exists rather than the ones the caller can already see. Memoized per
// field on the facet generation, beside the browse enumerations and for
// the same reason - a listing page asks this once per rule per request
// otherwise. Published the way facet buckets are: only while the
// generation the read started under is still current, so a slow
// aggregation neither lands stale nor rolls the stamp back over a newer
// field's entry.
func (l *Library) tagSpellings(ctx context.Context, field, value string) ([]string, error) {
	gen := l.facetGeneration()
	l.tagValues.mu.Lock()
	if l.tagValues.gen == gen {
		if held, ok := l.tagValues.byField[field]; ok {
			l.tagValues.mu.Unlock()
			return foldMatching(held, value), nil
		}
	}
	l.tagValues.mu.Unlock()

	// visibleItems, not a bare query: a spelling carried only by trashed
	// items cannot change any answer - the state predicate drops those
	// rows wherever this node is conjoined - and narrowing the
	// aggregation is the cheaper way to say so.
	res, err := l.lib.Facet(ctx, visibleItems().Build(),
		read.GroupBy(field), read.FacetOrderLabel, 0, "")
	if err != nil {
		l.log.Warn("enumerating tag values for a content rule", "field", field, "err", err)
		return nil, classify(err)
	}
	stored := make([]string, 0, len(res.Buckets))
	for _, b := range res.Buckets {
		if !b.IsUnknown && b.Display != "" {
			stored = append(stored, b.Display)
		}
	}
	l.tagValues.mu.Lock()
	if l.facetGeneration() == gen {
		if l.tagValues.gen != gen || l.tagValues.byField == nil {
			l.tagValues.gen, l.tagValues.byField = gen, map[string][]string{}
		}
		l.tagValues.byField[field] = stored
	}
	l.tagValues.mu.Unlock()
	return foldMatching(stored, value), nil
}

func foldMatching(stored []string, value string) []string {
	out := make([]string, 0, 1)
	for _, s := range stored {
		if strings.EqualFold(s, value) {
			out = append(out, s)
		}
	}
	return out
}

// matchesTagRules applies allow-then-deny: every allow rule must match
// and no deny rule may. Value comparison is case-insensitive; a rule
// without a value matches key presence.
func matchesTagRules(tags []model.ItemTag, allow, deny []TagRule) bool {
	for _, r := range allow {
		if !tagRuleMatches(tags, r) {
			return false
		}
	}
	for _, r := range deny {
		if tagRuleMatches(tags, r) {
			return false
		}
	}
	return true
}

func tagRuleMatches(tags []model.ItemTag, r TagRule) bool {
	for _, tg := range tags {
		if !strings.EqualFold(tg.Key, r.Key) {
			continue
		}
		if r.Value == "" {
			return true
		}
		for _, v := range tg.Values {
			if strings.EqualFold(v, r.Value) {
				return true
			}
		}
	}
	return false
}

// requirePodcastManagement gates subscription management (subscribe,
// unsubscribe, refresh, fetch, download removal); playback and
// per-subscription tuning stay open to every subscriber.
func requirePodcastManagement(uc *UserCtx) error {
	if uc.ManagePodcasts {
		return nil
	}
	return &Error{Kind: KindForbidden, Msg: "this account cannot manage podcasts"}
}

// samePermissions answers whether two permission sets grant the same
// thing.
//
// The scalars are compared by zeroing the two slice fields and letting
// == do the rest, so a toggle added to Permissions is covered by
// construction rather than by remembering to add a clause here - which
// is the failure mode this whole comparison exists to prevent.
func samePermissions(a, b Permissions) bool {
	if !slices.Equal(a.TagAllow, b.TagAllow) || !slices.Equal(a.TagDeny, b.TagDeny) {
		return false
	}
	// Zeroed first because DeepEqual calls an absent list and an empty
	// one different, which they are not; what is left is every scalar,
	// compared whole rather than clause by clause.
	a.TagAllow, a.TagDeny, b.TagAllow, b.TagDeny = nil, nil, nil, nil
	return reflect.DeepEqual(a, b)
}

// contentRulesChanged reports whether the visibility-shaping parts of a
// permission set changed (the explicit toggle or either tag list).
func contentRulesChanged(a, b Permissions) bool {
	if a.Explicit != b.Explicit {
		return true
	}
	eq := func(x, y []TagRule) bool {
		if len(x) != len(y) {
			return false
		}
		for i := range x {
			if x[i] != y[i] {
				return false
			}
		}
		return true
	}
	return !eq(a.TagAllow, b.TagAllow) || !eq(a.TagDeny, b.TagDeny)
}

// UserSharedOutputsAllowed answers the connect service's permission
// callback: whether the user may control shared device endpoints.
// Unknown users fail closed.
func (l *Library) UserSharedOutputsAllowed(userID string) bool {
	u, err := l.db.UserByID(context.Background(), userID)
	if err != nil {
		return false
	}
	return hasRole(u.Roles, "admin") || u.PermSharedOutputs
}
