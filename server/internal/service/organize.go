package service

// Organize: profile listing, dry-run planning, and applying moves. The
// plan is always recomputed server-side, so a stale preview can never
// apply.

import (
	"context"
	"strings"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/query"
)

// organizePreviewCap bounds the actions a preview response carries; the
// total still reports the full pass.
const organizePreviewCap = 500

// OrganizeProfileDTO is one configured profile. The facade exposes
// profile names only (waxbin.Library.Profiles); the templates and each
// profile's tag-write flag are not readable through it, so the listing
// carries names alone and the API leaves those fields absent.
type OrganizeProfileDTO struct {
	Name string
}

// OrganizeActionDTO is one planned move.
type OrganizeActionDTO struct {
	ItemPID string
	From    string
	To      string
}

// OrganizePlanDTO is a dry-run plan: the first organizePreviewCap
// pending actions plus the full pending count.
type OrganizePlanDTO struct {
	Profile      string
	TagWrite     bool
	TotalActions int
	Actions      []OrganizeActionDTO
}

// OrganizeFailureDTO is one file an applied pass could not move.
type OrganizeFailureDTO struct {
	Path   string
	Reason string
}

// OrganizeReportDTO is an applied pass's outcome.
type OrganizeReportDTO struct {
	Moved    int
	Skipped  int
	Failed   int
	Failures []OrganizeFailureDTO
}

// OrganizeProfilesFor lists the server-configured organize profiles.
func (l *Library) OrganizeProfilesFor(ctx context.Context, uc *UserCtx) ([]OrganizeProfileDTO, error) {
	if !uc.Admin {
		return nil, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	names := l.lib.Profiles()
	out := make([]OrganizeProfileDTO, 0, len(names))
	for _, n := range names {
		out = append(out, OrganizeProfileDTO{Name: n})
	}
	return out, nil
}

// organizePlanFor validates the profile and plans the pass, scoped to
// the named items when any are given. Scoping happens at plan time (the
// store's query grammar has a pid field) rather than by filtering a
// whole-library plan. An unknown profile answers invalid-request: the
// preview and apply operations route no 404.
func (l *Library) organizePlanFor(ctx context.Context, profile string, apiItemPids []string) (*organize.Plan, error) {
	if profile == "" {
		return nil, errInvalid("a profile is required")
	}
	known := false
	for _, n := range l.lib.Profiles() {
		if n == profile {
			known = true
			break
		}
	}
	if !known {
		return nil, errInvalid("no such organize profile: " + profile)
	}
	b := query.New(query.EntityItems)
	if len(apiItemPids) > 0 {
		or := query.Or{}
		for _, p := range apiItemPids {
			prefix, pid, ok := parseAPIPID(p)
			if !ok || !itemPrefix(prefix) {
				return nil, errInvalid("bad item pid " + p)
			}
			or.Nodes = append(or.Nodes, query.Cond{Field: "pid", Op: query.OpIs, Value: string(pid)})
		}
		b = b.WhereNode(or)
	}
	plan, err := l.lib.PlanOrganize(ctx, b.Build(), profile)
	if err != nil {
		return nil, classify(err)
	}
	return plan, nil
}

// PreviewOrganize plans a pass without touching anything and maps it to
// the bounded API shape.
func (l *Library) PreviewOrganize(ctx context.Context, uc *UserCtx, profile string, apiItemPids []string) (OrganizePlanDTO, error) {
	if !uc.Admin {
		return OrganizePlanDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	plan, err := l.organizePlanFor(ctx, profile, apiItemPids)
	if err != nil {
		return OrganizePlanDTO{}, err
	}
	out := OrganizePlanDTO{Profile: plan.Profile, TagWrite: plan.TagWrite}
	var pending []*organize.Action
	for i := range plan.Actions {
		if plan.Actions[i].Skip {
			continue
		}
		pending = append(pending, &plan.Actions[i])
	}
	out.TotalActions = len(pending)
	if len(pending) > organizePreviewCap {
		pending = pending[:organizePreviewCap]
	}
	kinds := l.itemKindsFor(ctx, pending)
	out.Actions = make([]OrganizeActionDTO, 0, len(pending))
	for _, a := range pending {
		out.Actions = append(out.Actions, OrganizeActionDTO{
			ItemPID: apiPID(prefixForKind(kinds[a.ItemPID]), a.ItemPID),
			From:    relToRoot(plan.Root, a.Src),
			To:      firstNonEmpty(a.RelDst, a.Dst),
		})
	}
	return out, nil
}

// itemKindsFor batch-resolves the kinds behind a plan's actions so each
// pid renders with the right API prefix; an unresolvable pid falls back
// to the track prefix.
func (l *Library) itemKindsFor(ctx context.Context, actions []*organize.Action) map[model.PID]model.Kind {
	out := map[model.PID]model.Kind{}
	pids := make([]model.PID, 0, len(actions))
	for _, a := range actions {
		if a.ItemPID != "" {
			pids = append(pids, a.ItemPID)
		}
	}
	if len(pids) == 0 {
		return out
	}
	views, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		l.log.Warn("organize: resolving action kinds", "err", err)
		return out
	}
	for _, v := range views {
		out[v.PID] = v.Kind
	}
	return out
}

// relToRoot renders src relative to the plan's library root when the
// root is known (single-library plans carry it; merged multi-library
// plans do not, and then the absolute source path is the honest value).
func relToRoot(root, src string) string {
	if root != "" {
		if rel, ok := strings.CutPrefix(src, strings.TrimSuffix(root, "/")+"/"); ok {
			return rel
		}
	}
	return src
}

// ApplyOrganize plans and applies a pass in one call, synchronously,
// and reports the outcome.
func (l *Library) ApplyOrganize(ctx context.Context, uc *UserCtx, profile string, apiItemPids []string) (OrganizeReportDTO, error) {
	if !uc.Admin {
		return OrganizeReportDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	plan, err := l.organizePlanFor(ctx, profile, apiItemPids)
	if err != nil {
		return OrganizeReportDTO{}, err
	}
	rep, err := l.lib.ApplyOrganize(ctx, plan)
	if err != nil {
		return OrganizeReportDTO{}, classify(err)
	}
	out := OrganizeReportDTO{Moved: rep.Moved, Skipped: rep.Skipped, Failed: rep.Errored}
	for _, f := range rep.Failures {
		out.Failures = append(out.Failures, OrganizeFailureDTO{
			Path:   firstNonEmpty(f.Src, f.Dst),
			Reason: f.Err,
		})
	}
	return out, nil
}
