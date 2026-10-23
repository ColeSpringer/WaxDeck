package service

// Organize: profiles, dry-run planning, applying moves as catalog jobs,
// and undoing them from the journal those jobs keep. The plan is always
// recomputed server-side, so a stale preview can never apply.

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// organizePreviewCap bounds the actions a preview response carries; the
// total still reports the full pass.
const organizePreviewCap = 500

// maxItemPids is the most items an organize request or a health fix
// names, as the API bounds them.
const maxItemPids = 1000

// catalogSetCap is the most values one set-membership condition of the
// catalog's queries takes.
const catalogSetCap = 500

// A profile name is an API path segment, and a template is bounded like
// any field a request carries; the catalog bounds its group nesting.
const (
	maxProfileNameLen = 64
	maxTemplateLen    = 1024
)

// OrganizeProfileDTO is one organize profile, its templates after
// inheritance, and the paths it gives the sample items. BuiltIn is a
// built-in no saved profile overrides.
type OrganizeProfileDTO struct {
	Name                      string
	Music, Audiobook, Podcast string
	TagWrite                  bool
	BuiltIn                   bool
	Sample                    OrganizeSampleDTO
	// Saved is what a saved profile sets itself, an empty template
	// inheriting; nil for a built-in nothing overrides.
	Saved *OrganizeTemplatesDTO
}

// OrganizeTemplatesDTO is a profile's three path templates.
type OrganizeTemplatesDTO struct {
	Music, Audiobook, Podcast string
}

// OrganizeSampleDTO is where a profile lays out a sample track, book and
// episode.
type OrganizeSampleDTO struct {
	Music, Audiobook, Podcast string
}

// OrganizeProfileInput is an administrator's profile; an empty template
// inherits the built-in of the same name, or the native layout.
type OrganizeProfileInput struct {
	Music, Audiobook, Podcast string
	TagWrite                  bool
}

// OrganizeActionDTO is one planned move.
type OrganizeActionDTO struct {
	ItemPID string
	From    string
	To      string
}

// OrganizeHoldDTO is one move held back: the item, when the pass planned
// it, where its file is and would go, and why, by the catalog's code and
// in its words.
type OrganizeHoldDTO struct {
	ItemPID  string
	From, To string
	Code     string
	Reason   string
}

// OrganizePlanDTO is a dry-run plan: the first organizePreviewCap
// pending actions plus the full pending count, the moves held back, and
// the read-only libraries the plan passed over.
type OrganizePlanDTO struct {
	Profile      string
	TagWrite     bool
	TotalActions int
	// Held counts the moves held back, and HeldByCode the same by the
	// catalog's hold code (a read-only server's under "read-only");
	// Holds lists the first organizePreviewCap of them.
	Held              int
	HeldByCode        map[string]int
	Holds             []OrganizeHoldDTO
	ReadOnlyLibraries int
	Actions           []OrganizeActionDTO
}

// OrganizeFailureDTO is one file an applied pass could not move.
type OrganizeFailureDTO struct {
	Path   string
	Reason string
}

// OrganizeReportDTO is an applied pass's outcome. JobPID is the catalog
// job it ran as, empty when nothing was left to move; Skipped counts
// files already in place, Held the moves held back for any cause, and
// ReadOnlyLibraries the read-only libraries the pass left alone.
type OrganizeReportDTO struct {
	JobPID            string
	Moved             int
	Skipped           int
	Held              int
	Holds             []OrganizeHoldDTO
	ReadOnlyLibraries int
	Failed            int
	Failures          []OrganizeFailureDTO
	DirsPruned        int
}

// OrganizeBatchDTO is one organize run, or an undo of one, whose moves
// the catalog's journal holds: what its moves came to, the profile it
// laid out by, and whether an undo takes it now.
type OrganizeBatchDTO struct {
	JobPID                         string
	Kind                           string
	State                          string
	StartedAt                      time.Time
	Profile                        string
	Committed, RolledBack, Planned int
	Undoable                       bool
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
	rows, err := l.db.OrganizeProfilesList(ctx)
	if err != nil {
		return OrganizeProfilesDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	saved := map[string]*wdb.OrganizeProfile{}
	for i := range rows {
		saved[rows[i].Name] = &rows[i]
	}
	profiles := l.lib.Profiles()
	out := OrganizeProfilesDTO{Profiles: make([]OrganizeProfileDTO, 0, len(profiles))}
	for _, p := range profiles {
		out.Profiles = append(out.Profiles, profileDTO(p, saved[p.Name]))
	}
	for _, lib := range libs {
		if lib.Mode == model.ModeManaged {
			out.ManagedLibraries++
		}
	}
	return out, nil
}

func builtinProfile(name string) bool { return slices.Contains(organize.Profiles(), name) }

// profileDTO maps a catalog profile and the saved row behind it, if any.
func profileDTO(p organize.Profile, row *wdb.OrganizeProfile) OrganizeProfileDTO {
	out := OrganizeProfileDTO{
		Name: p.Name, Music: p.Music, Audiobook: p.Audiobook, Podcast: p.Podcast,
		TagWrite: p.TagWrite, BuiltIn: row == nil && builtinProfile(p.Name), Sample: organizeSample(p),
	}
	if row != nil {
		out.Saved = &OrganizeTemplatesDTO{Music: row.Music, Audiobook: row.Audiobook, Podcast: row.Podcast}
	}
	return out
}

// profileName trims an organize profile name and checks what a path
// segment can carry.
func profileName(raw string) (string, error) {
	name := strings.TrimSpace(raw)
	if name == "" || utf8.RuneCountInString(name) > maxProfileNameLen {
		return "", errInvalid("a profile name is 1 to 64 characters")
	}
	if strings.ContainsAny(name, `/\?#`) || strings.ContainsFunc(name, unicode.IsControl) {
		return "", errInvalid(`a profile name cannot contain /, \, ?, # or control characters`)
	}
	return name, nil
}

// checkTemplates refuses a template longer than the catalog parses safely.
func checkTemplates(in OrganizeProfileInput) error {
	for _, t := range []string{in.Music, in.Audiobook, in.Podcast} {
		if utf8.RuneCountInString(t) > maxTemplateLen {
			return errInvalid("a template is at most 1024 characters")
		}
	}
	return nil
}

// The items every sample renders: fixed, so a sample shows what the
// templates do rather than what the catalog holds.
var (
	sampleTrack = &model.ItemView{Kind: model.KindTrack, Title: "Amber Waves", Artist: "Test Ensemble",
		AlbumArtist: "Test Ensemble", Album: "Signal Garden", TrackNo: 3, DiscNo: 1, Year: 2024,
		Genre: "Ambient", DisplayPath: "sample.flac"}
	sampleBook = &model.ItemView{Kind: model.KindBook, Title: "The Long Harbor", Artist: "Mara Quill",
		AuthorSort: "Quill, Mara", Series: "Harbor Tales", SeriesSeq: "2", Year: 2021,
		Narrator: "Owen Vale", Subtitle: "A Coastline Story", ASIN: "B0SAMPLE01", DisplayPath: "sample.m4b"}
	sampleEpisode = &model.ItemView{Kind: model.KindEpisode, Title: "The Lighthouse Keeper",
		Album: "Night Shift Radio", Season: 3, DisplayPath: "sample.mp3",
		PubDateNS: time.Date(2026, 1, 15, 0, 0, 0, 0, time.UTC).UnixNano()}
)

func organizeSample(p organize.Profile) OrganizeSampleDTO {
	render := func(it *model.ItemView) string {
		rel, err := organize.RenderRelPath(p, it)
		if err != nil {
			return ""
		}
		return rel
	}
	return OrganizeSampleDTO{Music: render(sampleTrack), Audiobook: render(sampleBook), Podcast: render(sampleEpisode)}
}

// profileDefs is the saved profiles as the catalog takes them.
func profileDefs(rows []wdb.OrganizeProfile) []config.ProfileDef {
	out := make([]config.ProfileDef, 0, len(rows))
	for _, r := range rows {
		out = append(out, config.ProfileDef{Name: r.Name, Music: r.Music, Audiobook: r.Audiobook,
			Podcast: r.Podcast, TagWrite: r.TagWrite})
	}
	return out
}

// savedProfileDefs reads the saved profiles for the catalog's open.
func savedProfileDefs(ctx context.Context, store *wdb.DB, log *slog.Logger) ([]config.ProfileDef, error) {
	rows, err := store.OrganizeProfilesList(ctx)
	if err != nil {
		return nil, err
	}
	return profileDefs(usableProfiles(rows, log)), nil
}

// usableProfiles is the saved rows the catalog takes, leaving out one that
// no longer validates (a grammar change, a hand edit) without deleting it.
func usableProfiles(rows []wdb.OrganizeProfile, log *slog.Logger) []wdb.OrganizeProfile {
	out := make([]wdb.OrganizeProfile, 0, len(rows))
	for _, r := range rows {
		if _, err := waxbin.ProfilesFor(profileDefs([]wdb.OrganizeProfile{r})); err != nil {
			log.Warn("an organize profile no longer validates; leaving it out", "profile", r.Name, "err", err)
			continue
		}
		out = append(out, r)
	}
	return out
}

// PutOrganizeProfile saves a profile, replacing one of the same name, and
// hands the catalog the new set. Administrators only.
func (l *Library) PutOrganizeProfile(ctx context.Context, uc *UserCtx, name string, in OrganizeProfileInput) (OrganizeProfileDTO, error) {
	if !uc.Admin {
		return OrganizeProfileDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	name, err := profileName(name)
	if err != nil {
		return OrganizeProfileDTO{}, err
	}
	if err := checkTemplates(in); err != nil {
		return OrganizeProfileDTO{}, err
	}
	l.profilesMu.Lock()
	defer l.profilesMu.Unlock()
	rows, err := l.db.OrganizeProfilesList(ctx)
	if err != nil {
		return OrganizeProfileDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	row := wdb.OrganizeProfile{Name: name, Music: in.Music, Audiobook: in.Audiobook, Podcast: in.Podcast,
		TagWrite: in.TagWrite, UpdatedAtNS: time.Now().UnixNano()}
	next := slices.DeleteFunc(usableProfiles(rows, l.log), func(r wdb.OrganizeProfile) bool { return r.Name == name })
	next = append(next, row)
	if err := l.lib.SetProfiles(ctx, profileDefs(next)); err != nil {
		return OrganizeProfileDTO{}, classify(err)
	}
	if err := l.db.OrganizeProfilesUpsert(ctx, row); err != nil {
		l.restoreProfiles(ctx, rows)
		return OrganizeProfileDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.Audit(ctx, uc, "organize.profile", AuditTarget{Kind: "organize-profile", Name: name},
		map[string]any{"music": in.Music, "audiobook": in.Audiobook, "podcast": in.Podcast, "tagWrite": in.TagWrite})
	for _, p := range l.lib.Profiles() {
		if p.Name == name {
			return profileDTO(p, &row), nil
		}
	}
	return OrganizeProfileDTO{}, &Error{Kind: KindInternal, Msg: "the saved profile is not in the catalog's set"}
}

// DeleteOrganizeProfile removes a saved profile; one a managed library
// lays out by stays until the library moves off it. Deleting a built-in's
// override brings the built-in back. Administrators only.
func (l *Library) DeleteOrganizeProfile(ctx context.Context, uc *UserCtx, name string) error {
	if !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	name, err := profileName(name)
	if err != nil {
		return err
	}
	l.profilesMu.Lock()
	defer l.profilesMu.Unlock()
	rows, err := l.db.OrganizeProfilesList(ctx)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if !slices.ContainsFunc(rows, func(r wdb.OrganizeProfile) bool { return r.Name == name }) {
		if builtinProfile(name) {
			return errInvalid("the built-in profile " + name + " cannot be deleted")
		}
		return errNotFound("no organize profile named " + name)
	}
	if !builtinProfile(name) {
		libs, err := l.lib.Libraries(ctx)
		if err != nil {
			return classify(err)
		}
		for _, lib := range libs {
			if lib.Mode == model.ModeManaged && lib.Profile == name {
				return &Error{Kind: KindConflict, Msg: "the library at " + lib.DisplayRoot +
					" is laid out by " + name + "; give it another profile first"}
			}
		}
	}
	next := slices.DeleteFunc(usableProfiles(rows, l.log), func(r wdb.OrganizeProfile) bool { return r.Name == name })
	if err := l.lib.SetProfiles(ctx, profileDefs(next)); err != nil {
		return classify(err)
	}
	if err := l.db.OrganizeProfilesDelete(ctx, name); err != nil {
		l.restoreProfiles(ctx, rows)
		return &Error{Kind: KindInternal, Err: err}
	}
	l.Audit(ctx, uc, "organize.profile", AuditTarget{Kind: "organize-profile", Name: name},
		map[string]any{"deleted": true})
	return nil
}

// restoreProfiles hands the catalog back the saved set a failed save
// changed.
func (l *Library) restoreProfiles(ctx context.Context, rows []wdb.OrganizeProfile) {
	if err := l.lib.SetProfiles(ctx, profileDefs(usableProfiles(rows, l.log))); err != nil {
		l.log.Warn("restoring the organize profiles after a failed save", "err", err)
	}
}

// PreviewOrganizeProfile renders the sample paths of a profile being
// edited, without saving it. Administrators only.
func (l *Library) PreviewOrganizeProfile(ctx context.Context, uc *UserCtx, name string, in OrganizeProfileInput) (OrganizeSampleDTO, error) {
	if !uc.Admin {
		return OrganizeSampleDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	var err error
	if strings.TrimSpace(name) == "" {
		name = "preview"
	} else if name, err = profileName(name); err != nil {
		return OrganizeSampleDTO{}, err
	}
	if err := checkTemplates(in); err != nil {
		return OrganizeSampleDTO{}, err
	}
	profiles, err := waxbin.ProfilesFor([]config.ProfileDef{{Name: name, Music: in.Music,
		Audiobook: in.Audiobook, Podcast: in.Podcast, TagWrite: in.TagWrite}})
	if err != nil {
		return OrganizeSampleDTO{}, classify(err)
	}
	for _, p := range profiles {
		if p.Name == name {
			return organizeSample(p), nil
		}
	}
	return OrganizeSampleDTO{}, &Error{Kind: KindInternal, Msg: "the previewed profile is missing"}
}

// SetLibraryProfile names the profile a managed library is laid out by,
// which the catalog keeps. Administrators only.
func (l *Library) SetLibraryProfile(ctx context.Context, uc *UserCtx, apiLibraryPID, name string) (LibraryInfo, error) {
	if !uc.Admin {
		return LibraryInfo{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return LibraryInfo{}, errNotFound("no library with pid " + apiLibraryPID)
	}
	lib, err := l.libraryByPID(ctx, pid)
	if KindOf(err) == KindNotFound {
		return LibraryInfo{}, errNotFound("no library with pid " + apiLibraryPID)
	} else if err != nil {
		return LibraryInfo{}, err
	}
	if lib.Mode != model.ModeManaged {
		return LibraryInfo{}, errInvalid("only a managed library is laid out by a profile")
	}
	name = strings.TrimSpace(name)
	if !slices.ContainsFunc(l.lib.Profiles(), func(p organize.Profile) bool { return p.Name == name }) {
		return LibraryInfo{}, errInvalid("no such organize profile: " + name)
	}
	// An existing library's folder may be unmounted; the profile is policy.
	updated, err := l.lib.AddRoot(ctx, config.Root{Path: lib.DisplayRoot, Mode: lib.Mode, Media: lib.Media, Profile: name},
		waxbin.AllowAbsent())
	if err != nil {
		return LibraryInfo{}, classify(err)
	}
	l.refreshLibraryState(ctx)
	l.Audit(ctx, uc, "library.profile", l.libraryAuditTarget(ctx, apiLibraryPID, pid),
		map[string]any{"profile": name})
	return l.libraryInfo(updated), nil
}

// organizeScope is what a pass plans over: its items, and the profile
// when one is named. items are the bare pids named, none for every
// managed library.
type organizeScope struct {
	q     query.Query
	opts  waxbin.OrganizeOptions
	items []string
}

// organizePlanFor plans under the named profile, or each library's own when
// none is named, and answers the scope it planned, which a job plans again.
// An unknown profile is invalid-request because preview and apply route no
// 404.
func (l *Library) organizePlanFor(ctx context.Context, profile string, apiItemPids []string) (*organize.Plan, organizeScope, error) {
	var sc organizeScope
	if profile != "" {
		if !slices.ContainsFunc(l.lib.Profiles(), func(p organize.Profile) bool { return p.Name == profile }) {
			return nil, sc, errInvalid("no such organize profile: " + profile)
		}
		sc.opts.ProfileName = profile
	}
	if len(apiItemPids) > maxItemPids {
		return nil, sc, errInvalid(fmt.Sprintf("at most %d items per organize request", maxItemPids))
	}
	b := query.New(query.EntityItems)
	if len(apiItemPids) > 0 {
		for _, p := range apiItemPids {
			prefix, pid, ok := parseAPIPID(p)
			if !ok || !itemPrefix(prefix) {
				return nil, sc, errInvalid("bad item pid " + p)
			}
			sc.items = append(sc.items, string(pid))
		}
		// Sets of pids: a condition per pid nests deeper than the catalog's
		// database parses.
		b = b.WhereNode(inSet("pid", sc.items))
	}
	sc.q = b.Build()
	plan, err := l.lib.PlanOrganize(ctx, sc.q, sc.opts)
	if err != nil {
		return nil, sc, classify(err)
	}
	l.holdReadOnly(plan)
	return plan, sc, nil
}

// holdReadOnly holds every move while the server is read-only, so
// neither a preview nor an apply moves them; the catalog plans no move
// in a read-only library. Every move rather than some: with nothing
// pending no apply runs, and an apply re-opens a read-only hold and
// decides it again from the catalog's own flags.
func (l *Library) holdReadOnly(plan *organize.Plan) {
	if !l.currentToggles().readOnly {
		return
	}
	for i := range plan.Actions {
		if a := &plan.Actions[i]; !a.Skip {
			a.Skip, a.Code, a.Reason = true, organize.HoldReadOnly, serverReadOnlyReason
		}
	}
}

// heldByCode counts the plan's held moves by hold code, and in all.
func heldByCode(plan *organize.Plan) (map[string]int, int) {
	out, total := map[string]int{}, 0
	for i := range plan.Actions {
		if a := &plan.Actions[i]; isHold(a) {
			out[string(a.Code)]++
			total++
		}
	}
	return out, total
}

// isHold reports whether a planned move is held back; a file already in
// place is not.
func isHold(a *organize.Action) bool {
	return a.Skip && a.Code != "" && a.Code != organize.HoldInPlace
}

// readOnlyReason and serverReadOnlyReason are how a fix or a plan names
// what a read-only library, or the server's read-only switch, held back.
const (
	readOnlyReason       = "read-only library"
	serverReadOnlyReason = "read-only server"
)

// readOnlyCause names what makes a write refused as read-only now: the
// server's switch, which every write meets first, or a library's flag.
func (l *Library) readOnlyCause() string {
	if l.ServerReadOnly() {
		return serverReadOnlyReason
	}
	return readOnlyReason
}

// PreviewOrganize plans a pass without touching anything and maps it to
// the bounded API shape.
func (l *Library) PreviewOrganize(ctx context.Context, uc *UserCtx, profile string, apiItemPids []string) (OrganizePlanDTO, error) {
	if !uc.Admin {
		return OrganizePlanDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	plan, _, err := l.organizePlanFor(ctx, profile, apiItemPids)
	if err != nil {
		return OrganizePlanDTO{}, err
	}
	byCode, held := heldByCode(plan)
	out := OrganizePlanDTO{Profile: plan.Profile, TagWrite: plan.TagWrite, Held: held,
		HeldByCode: byCode, ReadOnlyLibraries: plan.ReadOnlyLibraries}
	var pending, holds []*organize.Action
	for i := range plan.Actions {
		switch a := &plan.Actions[i]; {
		case isHold(a):
			holds = append(holds, a)
		case !a.Skip:
			pending = append(pending, a)
		}
	}
	out.TotalActions = len(pending)
	pending = pending[:min(len(pending), organizePreviewCap)]
	holds = holds[:min(len(holds), organizePreviewCap)]
	kinds := l.itemKindsFor(ctx, slices.Concat(pending, holds))
	out.Actions = make([]OrganizeActionDTO, 0, len(pending))
	for _, a := range pending {
		out.Actions = append(out.Actions, OrganizeActionDTO{
			ItemPID: apiPID(prefixForKind(kinds[a.ItemPID]), a.ItemPID),
			From:    relToRoot(plan.Root, a.Src),
			To:      firstNonEmpty(a.RelDst, a.Dst),
		})
	}
	out.Holds = make([]OrganizeHoldDTO, 0, len(holds))
	for _, a := range holds {
		out.Holds = append(out.Holds, OrganizeHoldDTO{
			ItemPID: entityAPIPID(prefixForKind(kinds[a.ItemPID]), a.ItemPID),
			From:    relToRoot(plan.Root, a.Src),
			To:      relToRoot(plan.Root, a.Dst),
			Code:    string(a.Code),
			Reason:  a.Reason,
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

// ApplyOrganize plans a pass and runs it as a catalog job, waiting for
// the job to end, and reports the outcome. The moved items' path rule is
// re-checked at once, rather than at the next sweep.
func (l *Library) ApplyOrganize(ctx context.Context, uc *UserCtx, profile string, apiItemPids []string) (OrganizeReportDTO, error) {
	if !uc.Admin {
		return OrganizeReportDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return OrganizeReportDTO{}, err
	}
	plan, sc, err := l.organizePlanFor(ctx, profile, apiItemPids)
	if err != nil {
		return OrganizeReportDTO{}, err
	}
	// Nothing to move is no job: it would take the file-mutation lease,
	// and a scan holding it would turn this into a conflict.
	if plan.Pending() == 0 {
		_, held := heldByCode(plan)
		rep := &organize.Report{Skipped: len(plan.Actions) - held, Held: held}
		for i := range plan.Actions {
			if a := &plan.Actions[i]; isHold(a) {
				rep.Holds = append(rep.Holds, organize.HeldMove{FilePID: a.FilePID, Src: a.Src, Dst: a.Dst, Code: a.Code, Reason: a.Reason})
			}
		}
		l.notifyWorkDone(ctx, uc, Job{Kind: "organize", Organize: organizeTally(plan.Profile, rep)})
		return l.organizeReport(ctx, "", rep, plan), nil
	}
	pid, err := l.lib.RunOrganize(l.procCtx, sc.q, sc.opts)
	if err != nil {
		return OrganizeReportDTO{}, classifyMutation(err)
	}
	res, err := l.awaitOrganize(ctx, uc, pid, sc.items)
	if err != nil {
		return OrganizeReportDTO{}, err
	}
	return l.organizeReport(ctx, pid, &res.Report, plan), nil
}

// awaitOrganize waits out an organize run or undo a request started over
// items (none for every managed library, or an undo). Its end is settled
// once, by this request, the follower or, for a run a stop cut short, the
// next start, and the settle does the run's bookkeeping
// (finishOrganizeJob), so a request gone first leaves none of it undone.
// This one returns once that is done, with what the run recorded; a run
// that did not finish is a failure.
func (l *Library) awaitOrganize(ctx context.Context, uc *UserCtx, pid model.PID, items []string) (*organize.RunResult, error) {
	settled := l.recordStarter(ctx, uc, pid, items)
	j, err := l.awaitJob(ctx, pid, 0, nil)
	if err != nil {
		return nil, err
	}
	if err := settled(ctx, j); err != nil {
		return nil, err
	}
	if j.State != model.JobDone {
		return nil, &Error{Kind: KindInternal, Err: fmt.Errorf("%s job %s ended %s: %s", j.Kind, pid, j.State, j.Error)}
	}
	res := organizeRunResult(j)
	if res == nil {
		return nil, &Error{Kind: KindInternal, Err: fmt.Errorf("%s job %s recorded no report", j.Kind, pid)}
	}
	return res, nil
}

// organizeReport maps a run's report. plan is the dry run before it, which
// names the item behind each held file; an undo has none, and its holds
// name files alone.
func (l *Library) organizeReport(ctx context.Context, pid model.PID, rep *organize.Report, plan *organize.Plan) OrganizeReportDTO {
	out := OrganizeReportDTO{JobPID: entityAPIPID(PrefixJob, pid), Moved: rep.Moved, Skipped: rep.Skipped,
		Held: rep.Held, Failed: rep.Errored, DirsPruned: rep.DirsPruned}
	for _, f := range rep.Failures {
		out.Failures = append(out.Failures, OrganizeFailureDTO{
			Path:   firstNonEmpty(f.Src, f.Dst),
			Reason: f.Err,
		})
	}
	var root string
	items := map[model.PID]*organize.Action{}
	if plan != nil {
		root, out.ReadOnlyLibraries = plan.Root, plan.ReadOnlyLibraries
		for i := range plan.Actions {
			items[plan.Actions[i].FilePID] = &plan.Actions[i]
		}
	}
	holds := rep.Holds[:min(len(rep.Holds), organizePreviewCap)]
	held := make([]*organize.Action, 0, len(holds))
	for _, h := range holds {
		if a := items[h.FilePID]; a != nil {
			held = append(held, a)
		}
	}
	kinds := l.itemKindsFor(ctx, held)
	out.Holds = make([]OrganizeHoldDTO, 0, len(holds))
	for _, h := range holds {
		dto := OrganizeHoldDTO{From: relToRoot(root, h.Src), To: relToRoot(root, h.Dst), Code: string(h.Code), Reason: h.Reason}
		if a := items[h.FilePID]; a != nil {
			dto.ItemPID = entityAPIPID(prefixForKind(kinds[a.ItemPID]), a.ItemPID)
		}
		out.Holds = append(out.Holds, dto)
	}
	return out
}

// recordStarter records the account that started an organize run or undo
// with its job, and the items it was asked to lay out, so the run's end is
// settled for them however the request fares, and hands the job to the
// follower. It answers the request's part in that settle, once the run has
// ended: settling it there, unless the follower or a waiter of its own got
// there first, and waiting until it is done.
func (l *Library) recordStarter(ctx context.Context, uc *UserCtx, pid model.PID, items []string) func(context.Context, *model.Job) error {
	ctx = context.WithoutCancel(ctx)
	o := wdb.JobOrigin{PID: string(pid), UserID: uc.ID, CreatedAtNS: time.Now().UnixNano()}
	if len(items) > 0 {
		o.Detail = marshalJSON(organizeOriginDetail{Items: items})
	}
	err := l.insertJobOrigin(ctx, o)
	l.followJob(pid)
	if err != nil {
		// Nothing durable names the starter yet: a waiter that outlives
		// the request keeps trying the record, and settles the run.
		l.log.Warn("recording who started an organize run; trying again as it runs", "job", string(pid), "err", err)
		done := make(chan struct{})
		if !l.workers.GoOnce(l.procCtx, "organize-settle", func(ctx context.Context) error {
			defer close(done)
			l.settleUnrecorded(ctx, o)
			return nil
		}) {
			close(done)
		}
		return func(ctx context.Context, _ *model.Job) error {
			select {
			case <-done:
				return nil
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}
	// A run that ended before its record landed may have been read by the
	// follower with no one to tell, so it is settled now.
	if j, err := l.lib.Job(ctx, pid); err == nil && j.State != model.JobRunning {
		l.settleLater(func(ctx context.Context) { l.settleJobOrigin(ctx, j) })
	}
	return func(ctx context.Context, j *model.Job) error {
		l.settleJobOrigin(ctx, j)
		return l.awaitSettled(ctx, pid)
	}
}

// originInsert records who started a job: the database's insert, or a
// test's stand-in.
func (l *Library) originInsert() func(context.Context, wdb.JobOrigin) error {
	if l.jobOriginInsertHook != nil {
		return l.jobOriginInsertHook
	}
	return l.db.InsertJobOrigin
}

// insertJobOrigin records who started a job, trying again for a moment: a
// busy database's refusal is usually brief.
func (l *Library) insertJobOrigin(ctx context.Context, o wdb.JobOrigin) error {
	insert := l.originInsert()
	for pause := 100 * time.Millisecond; ; pause *= 4 {
		err := insert(ctx, o)
		if err == nil || pause > time.Second {
			return err
		}
		time.Sleep(pause)
	}
}

// The pauses between a waiter's tries at recording a run's starter.
const (
	originRetryFirst = 250 * time.Millisecond
	originRetryCap   = time.Minute
)

// settleUnrecorded settles a run whose starter could not be recorded. It
// keeps trying the record while the run goes on; once one lands, the run
// is settled as any recorded one, which a stop leaves to the next start.
// A run that ends with none landed is settled here, from what this
// process holds, so only a database that refused every write for the
// whole run loses the run's bookkeeping to a stop.
func (l *Library) settleUnrecorded(ctx context.Context, o wdb.JobOrigin) {
	insert := l.originInsert()
	recorded := false
	pause := originRetryFirst
	next := time.Now().Add(pause)
	j, err := l.awaitJob(ctx, model.PID(o.PID), 0, func(ctx context.Context) {
		if recorded || time.Now().Before(next) {
			return
		}
		if recorded = insert(ctx, o) == nil; !recorded {
			pause = min(2*pause, originRetryCap)
			next = time.Now().Add(pause)
		}
	})
	if err != nil {
		if ctx.Err() == nil {
			l.log.Warn("waiting out an organize run no record names the starter of", "job", o.PID, "err", err)
		}
		return
	}
	if recorded || insert(ctx, o) == nil {
		// The follower may have read the end before the record landed,
		// with no one to tell; the claim keeps the settle once.
		l.settleJobOrigin(ctx, j)
		if err := l.awaitSettled(ctx, j.PID); err != nil && ctx.Err() == nil {
			l.log.Warn("waiting for an organize run's settle", "job", o.PID, "err", err)
		}
		return
	}
	// Once the run has ended, a stop waits for its bookkeeping.
	ctx = context.WithoutCancel(ctx)
	audit := l.finishOrganizeJob(ctx, o, j)
	ended := []Job{jobDTO(j)}
	l.nameJobTargets(ctx, ended)
	l.notifyJobEnd(ctx, o.UserID, ended[0])
	if audit == nil {
		return
	}
	if err := l.db.AppendAudit(ctx, *audit); err != nil {
		l.log.Warn("auditing an organize run", "job", o.PID, "err", err)
	}
}

// awaitSettled waits until a job's end has been settled, by this request
// or the follower, which drops its origin once done.
func (l *Library) awaitSettled(ctx context.Context, pid model.PID) error {
	for pause := 10 * time.Millisecond; ; pause = min(2*pause, organizeJobAwaitCap) {
		held, err := l.db.HasJobOrigin(ctx, string(pid))
		if err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		if !held {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(pause):
		}
	}
}

// organizeOriginDetail is what an organize run's origin keeps for its
// end: the items the run was asked to lay out, none for every managed
// library.
type organizeOriginDetail struct {
	Items []string `json:"items,omitempty"`
}

// finishOrganizeJob is an organize run's or undo's own end, done once by
// whoever settles it, from the origin o its starter recorded. It re-checks
// the path rule where the run moved files, so their rows drop now rather
// than at the next sweep, and for an undo asks for that sweep, the only
// thing that flags the files it moved back. It answers the run's audit
// row, for a run that failed or was cut short too, as the account that
// started it, which the settle writes with its own end; nil for a job of
// another kind.
func (l *Library) finishOrganizeJob(ctx context.Context, o wdb.JobOrigin, j *model.Job) *wdb.AuditEvent {
	if j.Kind != "organize" && j.Kind != "organize-undo" {
		return nil
	}
	userID := o.UserID
	var rep organize.Report
	var profile string
	if res := organizeRunResult(j); res != nil {
		rep, profile = res.Report, res.Profile
	} else {
		// A run killed outright recorded no report; its journal still
		// holds what it committed.
		rep.Moved = l.journalCommitted(ctx, j.PID)
	}
	jobPID := apiPID(PrefixJob, j.PID)
	detail := map[string]any{"jobPid": jobPID, "state": string(j.State),
		"moved": rep.Moved, "held": rep.Held, "failed": rep.Errored}
	if j.Kind == "organize-undo" {
		undone := apiPID(PrefixJob, j.TargetPID)
		detail["undoneJob"] = undone
		if rep.Moved > 0 && userID != "" {
			// The starter was an administrator when they asked for the undo.
			if err := l.QueueHealthSweep(ctx, &UserCtx{ID: userID, Admin: true}); err != nil {
				l.log.Warn("organize: asking for a sweep after an undo", "job", jobPID, "err", err)
			}
		}
		return l.jobEndAudit(ctx, userID, "organize.undo", AuditTarget{Kind: "job", PID: undone}, detail)
	}
	detail["profile"] = profile
	if rep.Moved > 0 {
		l.recheckRunPaths(ctx, jobPID, o)
	}
	return l.jobEndAudit(ctx, userID, "organize.apply", AuditTarget{Kind: "job", PID: jobPID, Name: profile}, detail)
}

// recheckRunPaths re-checks the path rule after a run that moved files:
// for the items the run was asked to lay out that the rule flags, or, for
// a run over every library, every item it flags. A request waits for
// this, so it never plans the whole library; and since each item it
// re-checks was flagged, one that passes or is gone changed a row, the
// only health news it sends.
func (l *Library) recheckRunPaths(ctx context.Context, jobPID string, o wdb.JobOrigin) {
	var scope organizeOriginDetail
	if o.Detail != "" {
		if err := json.Unmarshal([]byte(o.Detail), &scope); err != nil {
			l.log.Warn("organize: reading the items a run was asked to lay out", "job", jobPID, "err", err)
		}
	}
	var items []string
	if len(scope.Items) > 0 {
		failing, err := l.db.FailingItemsAmong(ctx, rulePathMismatch, scope.Items)
		if err != nil {
			l.log.Warn("organize: reading which of a run's items the path rule flags", "job", jobPID, "err", err)
			return
		}
		if len(failing) == 0 {
			return
		}
		items = failing
	}
	if res, err := l.recheckHealthRule(ctx, rulePathMismatch, items); err != nil {
		l.log.Warn("organize: re-checking the path rule", "job", jobPID, "err", err)
	} else if res.passing+res.gone > 0 {
		l.emitEveryoneEvent(ctx, eventHealth)
	}
}

// journalCommitted is how many file moves the organize journal holds
// committed for a run; 0 when it cannot say. The catalog reads one run's
// count only as part of the whole listing, which the history keeps.
func (l *Library) journalCommitted(ctx context.Context, pid model.PID) int {
	batches, err := l.organizeBatches(ctx)
	if err != nil {
		l.log.Warn("organize: reading a run's journal", "job", string(pid), "err", err)
		return 0
	}
	for _, b := range batches {
		if b.JobPID == pid {
			return b.Committed
		}
	}
	return 0
}

// jobEndAudit is the audit row of a job's end, as Audit writes one, with
// the account that started the job as its actor (none when no one did).
func (l *Library) jobEndAudit(ctx context.Context, userID, action string, target AuditTarget, detail map[string]any) *wdb.AuditEvent {
	e := &wdb.AuditEvent{Action: action, TargetKind: target.Kind, TargetPID: target.PID, TargetName: target.Name,
		Detail: "{}", CreatedAtNS: time.Now().UnixNano()}
	if userID != "" {
		e.ActorID, e.ActorName = userID, l.usernameOf(ctx, userID)
	}
	if raw, err := json.Marshal(detail); err == nil {
		e.Detail = string(raw)
	}
	return e
}

// organizeJobAwaitCap bounds the pause between two reads of a job a
// request or a task waits out.
const organizeJobAwaitCap = 500 * time.Millisecond

// errJobSilent answers a wait on a job whose row still says it runs while
// its heartbeat has stood still past the bound: a row the catalog failed to
// close, which its next open settles.
var errJobSilent = errors.New("the job stopped reporting progress")

// awaitJob waits for a catalog job to end, calling tick between reads, and
// answers the job as it ended. A job that reports nothing new for silence,
// as the waiter's own clock measures it from the last change it saw, is
// let go with errJobSilent; 0 waits for as long as its row says it runs.
func (l *Library) awaitJob(ctx context.Context, pid model.PID, silence time.Duration, tick func(context.Context)) (*model.Job, error) {
	if l.awaitJobHook != nil {
		return l.awaitJobHook(ctx, pid, silence, tick)
	}
	read := func(ctx context.Context) (*model.Job, error) { return l.lib.Job(ctx, pid) }
	return waitJob(ctx, read, time.Now, silence, tick)
}

// waitJob is awaitJob over any read of the job and any clock. The stamps
// the row carries say only whether the job moved: a clock step between
// the catalog's writes and this read is no silence.
func waitJob(ctx context.Context, read func(context.Context) (*model.Job, error), now func() time.Time,
	silence time.Duration, tick func(context.Context)) (*model.Job, error) {
	type beat struct {
		at       int64
		progress float64
		message  string
	}
	var last beat
	var since time.Time
	for pause := 10 * time.Millisecond; ; pause = min(2*pause, organizeJobAwaitCap) {
		j, err := read(ctx)
		if err != nil {
			return nil, classify(err)
		}
		if j.State != model.JobRunning {
			return j, nil
		}
		if b := (beat{j.HeartbeatAt, j.Progress, j.Message}); since.IsZero() || b != last {
			last, since = b, now()
		} else if silence > 0 && now().Sub(since) > silence {
			return j, errJobSilent
		}
		if tick != nil {
			tick(ctx)
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(pause):
		}
	}
}

// organizeRunResult is what an organize run or undo recorded; nil when it
// recorded nothing.
func organizeRunResult(j *model.Job) *organize.RunResult {
	var r organize.RunResult
	if j.Result == "" || json.Unmarshal([]byte(j.Result), &r) != nil {
		return nil
	}
	return &r
}

// OrganizeHistory lists the organize runs, and undos of them, whose moves
// the catalog's journal still holds, newest first by when each started, a
// page of limit after cursor (every one when limit is not positive),
// answering the next page's cursor ("" on the last). Administrators only.
func (l *Library) OrganizeHistory(ctx context.Context, uc *UserCtx, cursor string, limit int) ([]OrganizeBatchDTO, string, error) {
	if !uc.Admin {
		return nil, "", &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	beforeNS, beforeID, err := decodeTimeCursor(cursor)
	if err != nil {
		return nil, "", errInvalid("bad cursor")
	}
	// Every run the journal holds, paged here: a non-positive limit lists
	// them all, and the journal keeps no more than the retention window's.
	all, err := l.organizeBatches(ctx)
	if err != nil {
		return nil, "", err
	}
	if cursor != "" {
		all = all[sort.Search(len(all), func(i int) bool {
			b := all[i]
			return b.StartedAt < beforeNS || (b.StartedAt == beforeNS && string(b.JobPID) < beforeID)
		}):]
	}
	batches, next := all, ""
	if limit > 0 && len(all) > limit {
		batches = all[:limit]
		last := batches[len(batches)-1]
		next = encodeTimeCursor(last.StartedAt, string(last.JobPID))
	}
	profiles := l.runProfilesOf(ctx, batches)
	out := make([]OrganizeBatchDTO, 0, len(batches))
	for _, b := range batches {
		dto := OrganizeBatchDTO{JobPID: apiPID(PrefixJob, b.JobPID), Kind: b.Kind, State: string(b.State),
			Profile: profiles[b.JobPID], Committed: b.Committed, RolledBack: b.RolledBack, Planned: b.Planned,
			Undoable: b.Committed > 0 && b.State != model.JobRunning}
		if b.StartedAt > 0 {
			dto.StartedAt = time.Unix(0, b.StartedAt).UTC()
		}
		out = append(out, dto)
	}
	return out, next, nil
}

// organizeHistory is the organize journal's listing as last read, newest
// first by start, and the catalog's change position and generation it was
// read at: the catalog lists the journal only whole, each row of it, so
// the pages of an unchanged journal share one listing. epoch counts the
// listings dropped for a change no catalog change records.
type organizeHistory struct {
	mu      sync.Mutex
	read    bool
	gen     string
	seq     int64
	epoch   uint64
	batches []model.OrganizeBatch
}

// organizeBatches is every run the organize journal holds, newest first by
// when each started, listed again only once the catalog has changed since
// the last listing. Callers share the slice and never change it.
func (l *Library) organizeBatches(ctx context.Context) ([]model.OrganizeBatch, error) {
	// The position before the listing: a change during it only makes the
	// next call list again.
	seq, err := l.lib.LatestChangeSeq(ctx)
	if err != nil {
		return nil, classify(err)
	}
	l.feed.mu.Lock()
	gen := l.feed.gen
	l.feed.mu.Unlock()
	h := &l.history
	h.mu.Lock()
	if h.read && h.seq == seq && h.gen == gen {
		defer h.mu.Unlock()
		return h.batches, nil
	}
	epoch := h.epoch
	h.mu.Unlock()
	if l.historyReadHook != nil {
		l.historyReadHook()
	}
	all, err := l.lib.OrganizeHistory(ctx, 0)
	if err != nil {
		return nil, classify(err)
	}
	slices.SortFunc(all, func(a, b model.OrganizeBatch) int {
		return cmp.Or(cmp.Compare(b.StartedAt, a.StartedAt), cmp.Compare(b.JobPID, a.JobPID))
	})
	h.mu.Lock()
	if h.epoch == epoch {
		h.read, h.seq, h.gen, h.batches = true, seq, gen, all
	}
	h.mu.Unlock()
	return all, nil
}

// forgetOrganizeHistory drops the kept listing after a change to the
// journal the catalog records no change for: the scheduled prune.
func (l *Library) forgetOrganizeHistory() {
	h := &l.history
	h.mu.Lock()
	defer h.mu.Unlock()
	h.epoch++
	h.read, h.batches = false, nil
}

// runProfilesOf reads the profile each listed organize run laid out by (an
// undo lays out by none), decoding that one field of the run's report. A
// finished run's is kept for the next listing, and only the listed runs'
// are, so the memory is the listing's size.
func (l *Library) runProfilesOf(ctx context.Context, batches []model.OrganizeBatch) map[model.PID]string {
	return l.runProfilesWith(ctx, batches, l.lib.Job)
}

// runProfilesWith is runProfilesOf reading each run's job with read. The
// lock guards the memory, never a read of the catalog, so listings do not
// wait on each other's reads.
func (l *Library) runProfilesWith(ctx context.Context, batches []model.OrganizeBatch,
	read func(context.Context, model.PID) (*model.Job, error)) map[model.PID]string {
	kept := make(map[model.PID]string, len(batches))
	var unread []model.PID
	l.runProfilesMu.Lock()
	for _, b := range batches {
		if b.Kind != "organize" {
			continue
		}
		if p, ok := l.runProfiles[b.JobPID]; ok {
			kept[b.JobPID] = p
		} else {
			unread = append(unread, b.JobPID)
		}
	}
	l.runProfilesMu.Unlock()
	for _, pid := range unread {
		j, err := read(ctx, pid)
		if err != nil || j.State == model.JobRunning {
			continue
		}
		var r struct {
			Profile string `json:"profile"`
		}
		if j.Result != "" && json.Unmarshal([]byte(j.Result), &r) == nil {
			kept[pid] = r.Profile
		}
	}
	l.runProfilesMu.Lock()
	l.runProfiles = kept
	l.runProfilesMu.Unlock()
	return kept
}

// UndoOrganize moves back what an organize run moved, as a catalog job of
// its own, waits for it, and reports it as an applied pass. Administrators
// only.
func (l *Library) UndoOrganize(ctx context.Context, uc *UserCtx, apiJobPID string) (OrganizeReportDTO, error) {
	if !uc.Admin {
		return OrganizeReportDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, undone, ok := parseAPIPID(apiJobPID)
	if !ok || prefix != PrefixJob {
		return OrganizeReportDTO{}, errNotFound("no job with pid " + apiJobPID)
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return OrganizeReportDTO{}, err
	}
	pid, err := l.lib.RunOrganizeUndo(l.procCtx, undone)
	if err != nil {
		return OrganizeReportDTO{}, classifyMutation(err)
	}
	res, err := l.awaitOrganize(ctx, uc, pid, nil)
	if err != nil {
		return OrganizeReportDTO{}, err
	}
	return l.organizeReport(ctx, pid, &res.Report, nil), nil
}
