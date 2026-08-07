package service

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

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
		if uc.Explicit {
			return true
		}
		// The view carries both advisory flags -- the episode's own and its
		// show's -- so a restricted caller costs no reads at all. Both,
		// because a feed may mark itself explicit at the channel level and
		// leave every episode unmarked.
		return !it.AdvisoryFlagged()
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
