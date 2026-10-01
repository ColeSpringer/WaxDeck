package service

// Organize: profiles, dry-run planning, and applying moves. The plan is
// always recomputed server-side, so a stale preview can never apply.

import (
	"context"
	"log/slog"
	"slices"
	"strings"
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

// A profile name is an API path segment, and the catalog parses a
// template recursively, one level per '<' group.
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

// OrganizePlanDTO is a dry-run plan: the first organizePreviewCap
// pending actions plus the full pending count, the moves a read-only
// server holds back, and the read-only libraries the plan passed over.
type OrganizePlanDTO struct {
	Profile           string
	TagWrite          bool
	TotalActions      int
	Held              int
	ReadOnlyLibraries int
	Actions           []OrganizeActionDTO
}

// OrganizeFailureDTO is one file an applied pass could not move.
type OrganizeFailureDTO struct {
	Path   string
	Reason string
}

// OrganizeReportDTO is an applied pass's outcome. Skipped counts files
// already in place, Held those a read-only server kept, and
// ReadOnlyLibraries the read-only libraries the pass left alone.
type OrganizeReportDTO struct {
	Moved             int
	Skipped           int
	Held              int
	ReadOnlyLibraries int
	Failed            int
	Failures          []OrganizeFailureDTO
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
	updated, err := l.lib.AddRoot(ctx, config.Root{Path: lib.DisplayRoot, Mode: lib.Mode, Media: lib.Media, Profile: name})
	if err != nil {
		return LibraryInfo{}, classify(err)
	}
	l.refreshLibraryState(ctx)
	l.Audit(ctx, uc, "library.profile", AuditTarget{Kind: "library", PID: apiLibraryPID},
		map[string]any{"profile": name})
	return l.libraryInfo(updated), nil
}

// organizePlanFor plans under the named profile, or each library's own when
// none is named. An unknown profile is invalid-request because preview and
// apply route no 404.
func (l *Library) organizePlanFor(ctx context.Context, profile string, apiItemPids []string) (*organize.Plan, error) {
	var opts waxbin.OrganizeOptions
	if profile != "" {
		if !slices.ContainsFunc(l.lib.Profiles(), func(p organize.Profile) bool { return p.Name == profile }) {
			return nil, errInvalid("no such organize profile: " + profile)
		}
		opts.ProfileName = profile
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
	plan, err := l.lib.PlanOrganize(ctx, b.Build(), opts)
	if err != nil {
		return nil, classify(err)
	}
	l.holdReadOnly(plan)
	return plan, nil
}

// holdReadOnly skips every move while the server is read-only, so
// neither a preview nor an apply moves them; the catalog plans no move
// in a read-only library.
func (l *Library) holdReadOnly(plan *organize.Plan) {
	if !l.currentToggles().readOnly {
		return
	}
	for i := range plan.Actions {
		if a := &plan.Actions[i]; !a.Skip {
			a.Skip, a.Reason = true, readOnlyReason
		}
	}
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
	out := OrganizePlanDTO{Profile: plan.Profile, TagWrite: plan.TagWrite, Held: heldCount(plan),
		ReadOnlyLibraries: plan.ReadOnlyLibraries}
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
	out := OrganizeReportDTO{Moved: rep.Moved, Skipped: rep.Skipped - held, Held: held,
		ReadOnlyLibraries: plan.ReadOnlyLibraries, Failed: rep.Errored}
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
