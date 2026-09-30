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

// OrganizeProfileDTO is one organize profile. The facade exposes
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
// pending actions plus the full pending count, and the moves a
// read-only library holds back.
type OrganizePlanDTO struct {
	Profile      string
	TagWrite     bool
	TotalActions int
	Held         int
	Actions      []OrganizeActionDTO
}

// OrganizeFailureDTO is one file an applied pass could not move.
type OrganizeFailureDTO struct {
	Path   string
	Reason string
}

// OrganizeReportDTO is an applied pass's outcome. Skipped counts files
// already in place, Held those a read-only library kept.
type OrganizeReportDTO struct {
	Moved    int
	Skipped  int
	Held     int
	Failed   int
	Failures []OrganizeFailureDTO
}

// OrganizeProfilesDTO is the profile listing, and how many libraries
// the profiles can lay out: the catalog organizes managed roots only.
type OrganizeProfilesDTO struct {
	Profiles         []OrganizeProfileDTO
	ManagedLibraries int
}

// OrganizeProfilesFor lists the catalog's organize profiles.
func (l *Library) OrganizeProfilesFor(ctx context.Context, uc *UserCtx) (OrganizeProfilesDTO, error) {
	if !uc.Admin {
		return OrganizeProfilesDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return OrganizeProfilesDTO{}, classify(err)
	}
	names := l.lib.Profiles()
	out := OrganizeProfilesDTO{Profiles: make([]OrganizeProfileDTO, 0, len(names))}
	for _, n := range names {
		out.Profiles = append(out.Profiles, OrganizeProfileDTO{Name: n})
	}
	for _, lib := range libs {
		if lib.Mode == model.ModeManaged {
			out.ManagedLibraries++
		}
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
	if err := l.holdReadOnly(ctx, plan); err != nil {
		return nil, err
	}
	return plan, nil
}

// holdReadOnly skips the plan's moves out of a read-only library, or
// every move while the server is read-only, so neither a preview nor
// an apply moves them.
func (l *Library) holdReadOnly(ctx context.Context, plan *organize.Plan) error {
	t := l.currentToggles()
	if !t.readOnly && len(t.readOnlyLibs) == 0 {
		return nil
	}
	for i := range plan.Actions {
		a := &plan.Actions[i]
		if a.Skip {
			continue
		}
		held := t.readOnly
		if !held {
			pid, err := l.libraryForPath(ctx, a.Src)
			if err != nil {
				return classify(err)
			}
			held = t.readOnlyLibs[pid]
		}
		if held {
			a.Skip, a.Reason = true, readOnlyReason
		}
	}
	return nil
}

// heldCount is how many of the plan's moves holdReadOnly held back.
func heldCount(plan *organize.Plan) int {
	n := 0
	for _, a := range plan.Actions {
		if a.Skip && a.Reason == readOnlyReason {
			n++
		}
	}
	return n
}

// readOnlyReason is how a fix or a plan names what a read-only library
// held back.
const readOnlyReason = "read-only library"

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
	out := OrganizePlanDTO{Profile: plan.Profile, TagWrite: plan.TagWrite, Held: heldCount(plan)}
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
	if err := l.CheckWritable(ctx, ""); err != nil {
		return OrganizeReportDTO{}, err
	}
	plan, err := l.organizePlanFor(ctx, profile, apiItemPids)
	if err != nil {
		return OrganizeReportDTO{}, err
	}
	// Nothing to move is no job: it would take the file-mutation lease,
	// and a scan holding it would turn this into a conflict.
	rep := &organize.Report{Skipped: len(plan.Actions)}
	if plan.Pending() > 0 {
		if rep, err = l.lib.ApplyOrganize(ctx, plan); err != nil {
			return OrganizeReportDTO{}, classify(err)
		}
	}
	held := heldCount(plan)
	out := OrganizeReportDTO{Moved: rep.Moved, Skipped: rep.Skipped - held, Held: held, Failed: rep.Errored}
	for _, f := range rep.Failures {
		out.Failures = append(out.Failures, OrganizeFailureDTO{
			Path:   firstNonEmpty(f.Src, f.Dst),
			Reason: f.Err,
		})
	}
	l.notifyWorkDone(ctx, uc, Job{Kind: "organize", Organize: &OrganizeTallyDTO{
		Profile: plan.Profile, Moved: rep.Moved, Skipped: rep.Skipped,
		Errored: rep.Errored, SidecarsMoved: rep.SidecarsMoved,
	}})
	return out, nil
}
