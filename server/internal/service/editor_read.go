package service

import (
	"context"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	waxlabel "github.com/colespringer/waxlabel"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// writeBackIssueCodes maps the catalog's write-back diagnostics onto the
// contract's codes. The catalog names them in snake_case and the API in
// kebab, so the two vocabularies are joined here once rather than
// stringified at the edge.
var writeBackIssueCodes = map[model.DiagnosticCode]string{
	model.DiagTagWriteUnsynced: "tag-write-unsynced",
	model.DiagTagWriteLost:     "tag-write-lost",
	model.DiagTagWriteOwed:     "tag-write-owed",
}

// writeBackIssues reads the write-back drift recorded against one item's
// files.
//
// The filter is by code and not by origin: `tag_write_lost` is recorded
// by the edit, organize, and replaygain writers alike, and all three are
// the same fact to an editor asking whether this file's tags match the
// catalog. Everything else the audit records (missing art, corrupt
// audio) belongs to the diagnostics dashboard, not here.
//
// It goes to the facade directly rather than through service
// FileDiagnostics, which is administrators-only because its rows carry
// raw file paths. This read is open to anyone who can see the item, so
// it has to withhold what makes that one administrators-only: the
// catalog stamps Detail with the tag writer's own error, and a failed
// write reads "writing tags to /srv/music/...: permission denied". Code,
// tag key, and file pid say what went wrong without saying where the
// library lives; Detail rides along for administrators, who can already
// read it whole from the diagnostics dashboard.
func (l *Editor) writeBackIssues(ctx context.Context, uc *UserCtx, itemPID model.PID) ([]WriteBackIssueDTO, error) {
	rows, err := l.lib.FileDiagnostics(ctx, model.DiagnosticFilter{ItemPID: itemPID})
	if err != nil {
		return nil, classify(err)
	}
	// A file in a library the reader is not granted is left out, as its
	// file list leaves it out.
	var seen map[model.PID]bool
	if !uc.AllLibraries {
		files, err := l.Reads.visibleItemFiles(ctx, uc, itemPID)
		if err != nil {
			return nil, err
		}
		seen = make(map[model.PID]bool, len(files))
		for _, f := range files {
			seen[f.ref.FilePID] = true
		}
	}
	out := make([]WriteBackIssueDTO, 0, len(rows))
	for _, d := range rows {
		code, ok := writeBackIssueCodes[d.Code]
		if !ok || (seen != nil && d.FilePID != "" && !seen[d.FilePID]) {
			continue
		}
		issue := WriteBackIssueDTO{
			FilePID: string(d.FilePID),
			Code:    code,
			TagKey:  d.TagKey,
		}
		if uc.Admin {
			issue.Detail = d.Detail
		}
		out = append(out, issue)
	}
	return out, nil
}

// acquisitionFor reads the item's recorded origin, or nil when the
// catalog holds no row for it. An item with no origin evidence is the
// ordinary case rather than a failure, so a not-found is silent; any
// other read failure leaves the block off the document, because a
// header caption is not worth failing the whole editor read for.
func (l *Editor) acquisitionFor(ctx context.Context, pid model.PID, prov []model.FieldProvenance) *ItemAcquisitionDTO {
	acq, err := l.lib.Acquisition(ctx, pid)
	if err != nil {
		if KindOf(err) != KindNotFound {
			l.log.Warn("reading item acquisition", "item", pid, "err", err)
		}
		return nil
	}
	if acq == nil {
		return nil
	}
	out := &ItemAcquisitionDTO{
		SourceType: string(acq.SourceType),
		SourceURL:  redactedSourceURL(acq.SourceURL),
		SourceID:   acq.SourceID,
		Provider:   acq.Provider,
	}
	if acq.AcquiredAt > 0 {
		out.AcquiredAt = time.Unix(0, acq.AcquiredAt).UTC()
	}
	// The lock rides the provenance rows the caller already read: it is
	// the same `acquisition` field the locks endpoint writes, so a
	// second query would only be a chance for the two to disagree.
	for _, r := range prov {
		if r.Field == provenanceFieldAcquisition {
			out.Locked = r.Locked
			break
		}
	}
	return out
}

// provenanceFieldAcquisition is the field name the origin row's lock
// lives under, shared by /items/{pid}/locks and the acquisition verbs.
const provenanceFieldAcquisition = "acquisition"

// AcquisitionEdit is a replacement origin row. The four columns are
// written as given - an absent one clears - because the automatic
// recorder is merge-wise and never lowers a field, so this surface is
// the only way a wrong url, id or provider comes off.
type AcquisitionEdit struct {
	SourceType string
	// SourceURL nil keeps the standing value; a non-nil empty string
	// clears it. The one column with that shape, because it is the one
	// the read redacts: a client is never shown the stored string in
	// full, so a form that resent what it displayed would replace a
	// credentialed or query-carrying URL with the truncated form.
	SourceURL *string
	SourceID  string
	Provider  string
	// AcquiredAt zero keeps the stamp the standing row carries, so
	// correcting a URL does not restamp the date as well.
	AcquiredAt time.Time
}

// SetItemAcquisition replaces an item's recorded origin under the
// curate gate. Two columns the wire cannot express - the provider's
// version string and the acquisition's stored options - are read off
// the standing row and carried forward, because upstream writes every
// column of its input as given and would otherwise drop them.
//
// The source type is validated upstream rather than here. The set is
// closed there - rss, youtube, manual - and the two refusals that
// matter, an unknown type and `local` (which is spelled by having no
// row at all), arrive as CodeInvalid with a sentence worth passing
// through. Repeating the list here would be a second copy to drift.
func (l *Editor) SetItemAcquisition(ctx context.Context, uc *UserCtx, apiPID string, edit AcquisitionEdit, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	in := model.AcquisitionInput{
		SourceType: model.SourceType(strings.TrimSpace(edit.SourceType)),
		SourceID:   strings.TrimSpace(edit.SourceID),
		Provider:   strings.TrimSpace(edit.Provider),
	}
	if edit.SourceURL != nil {
		in.SourceURL = strings.TrimSpace(*edit.SourceURL)
	}
	if !edit.AcquiredAt.IsZero() {
		in.AcquiredAt = edit.AcquiredAt.UnixNano()
	}
	// The standing row supplies what the body cannot say: the two
	// columns with no wire form, the stamp when none was sent, and the
	// URL when none was sent - that last one because the read redacts
	// it, so an absent value means "the client never saw this" rather
	// than "take it off". A missing row is the ordinary case (this is
	// also how an origin is stated for the first time), so a not-found
	// leaves them empty.
	if prior, err := l.lib.Acquisition(ctx, it.PID); err == nil && prior != nil {
		in.ProviderVersion = prior.ProviderVersion
		in.OptionsJSON = prior.OptionsJSON
		if in.AcquiredAt == 0 {
			in.AcquiredAt = prior.AcquiredAt
		}
		if edit.SourceURL == nil {
			in.SourceURL = prior.SourceURL
		}
	} else if err != nil && KindOf(classify(err)) != KindNotFound {
		return EditOutcomeDTO{}, classify(err)
	}
	err = l.lib.SetAcquisition(ctx, it.PID, in, waxbin.AcquisitionEditOptions{
		Lock: model.LockOf(p.Lock), Force: p.Force, WriteBack: p.WriteBack,
	})
	return editOutcomeFromWriteBack(err)
}

// ClearItemAcquisition takes an item's origin row off, so it reads the
// source it has without one: its show's type for an episode, local for
// everything else. Idempotent - an item with no row is unaffected.
//
// The lock defaults on at the wire, and that is what makes the clear
// stick: the row came from evidence still sitting in the file, so the
// next full scan re-derives it. Write-back strips those tags, which is
// the durable half.
func (l *Editor) ClearItemAcquisition(ctx context.Context, uc *UserCtx, apiPID string, p MetadataEditParams) error {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return err
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return err
		}
	}
	err = l.lib.ClearAcquisition(ctx, it.PID, waxbin.AcquisitionEditOptions{
		Lock: model.LockOf(p.Lock), Force: p.Force, WriteBack: p.WriteBack,
	})
	// A write-back failure leaves the catalog edit standing, and this
	// verb answers 204 with no body to report it in, so it is logged
	// rather than raised: the origin is gone either way, and the file's
	// tags are what a later rescan would re-derive from.
	if out, err := editOutcomeFromWriteBack(err); err != nil {
		return err
	} else if len(out.Failures) > 0 {
		l.log.Warn("clearing acquisition tags failed", "item", it.PID, "failures", len(out.Failures))
	}
	return nil
}

// redactedSourceURL is the only form of a stored origin URL that may
// leave the server, and the redaction is unconditional because the
// read answers everyone who can see the item rather than only a
// curator.
//
// The stored value is verbatim: WaxBin keeps whatever the acquisition
// or the file's SOURCE_URL tag said, so it can be a credentialed feed
// URL, a signed link whose token is in the query, or a local path. So
// only http(s) survives at all, and only its scheme, host and path:
// userinfo, query and fragment are where the secrets live, and none of
// the three is needed to say where something came from.
func redactedSourceURL(raw string) string {
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	switch strings.ToLower(u.Scheme) {
	case "http", "https":
	default:
		return ""
	}
	if u.Host == "" {
		return ""
	}
	safe := url.URL{Scheme: strings.ToLower(u.Scheme), Host: u.Host, Path: u.Path}
	return safe.String()
}

// ItemMetadataFor assembles everything the editor shows for one item.
// Readable by any user who can see the item.
func (l *Editor) ItemMetadataFor(ctx context.Context, uc *UserCtx, apiPID string) (ItemMetadataDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return ItemMetadataDTO{}, err
	}
	prov, err := l.lib.Provenance(ctx, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, classify(err)
	}
	issues, err := l.writeBackIssues(ctx, uc, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, err
	}
	out := ItemMetadataDTO{
		PID:             itemAPIPID(it),
		MediaType:       mediaTypeForKind(it.Kind),
		Fields:          editorScalarFields(it, prov),
		LockedFields:    []string{},
		Provenance:      []FieldProvenanceDTO{},
		Credits:         []CreditDTO{},
		CustomTags:      []CustomTagDTO{},
		VirtualTrack:    it.Virtual,
		ArtistPID:       entityAPIPID(PrefixArtist, it.ArtistPID),
		AlbumPID:        entityAPIPID(PrefixAlbum, it.AlbumPID),
		ReleaseGroupPID: entityAPIPID(PrefixReleaseGroup, it.ReleaseGroupPID),
		WriteBackIssues: issues,
	}
	// The same predicate the twelve item-scoped mutations gate on, so
	// the form the client draws and the answer it gets back cannot
	// drift; a lookup that fails says nothing rather than no.
	if may, err := l.Ingest.MayCurateItem(ctx, uc, out.PID); err == nil {
		out.MayCurate = &may
	} else {
		l.log.Warn("describing curate permission", "item", out.PID, "err", err)
	}
	out.Acquisition = l.acquisitionFor(ctx, it.PID, prov)
	for _, r := range prov {
		dto := FieldProvenanceDTO{
			Field: r.Field, Source: string(r.Source), Provider: r.Provider,
			// Redacted for the same reason the acquisition block below
			// is, and it is the same class of value: a feed cover's row
			// carries the show's enclosure URL, credentials and all,
			// and this read answers everyone who can see the item.
			SourceURL: redactedSourceURL(r.SourceURL), Locked: r.Locked,
		}
		if r.UpdatedAt > 0 {
			dto.UpdatedAt = time.Unix(0, r.UpdatedAt).UTC()
		}
		out.Provenance = append(out.Provenance, dto)
		if r.Locked {
			out.LockedFields = append(out.LockedFields, r.Field)
		}
	}
	sort.Strings(out.LockedFields)

	if it.Kind == model.KindBook {
		l.fillBookMetadata(ctx, it, &out)
	}

	credits, err := l.lib.Credits(ctx, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, classify(err)
	}
	out.Credits = groupCredits(credits)

	tags, err := l.lib.ItemTags(ctx, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, classify(err)
	}
	for _, tg := range tags {
		out.CustomTags = append(out.CustomTags, CustomTagDTO{Key: tg.Key, Values: tg.Values})
		if tg.Key == releaseStatusKey {
			for _, v := range tg.Values {
				switch strings.ToLower(v) {
				case releaseStatusUnofficial, "bootleg":
					out.Unofficial = true
				}
			}
		}
	}

	if ly, err := l.lib.Lyrics(ctx, it.PID); err == nil && ly != nil {
		out.Lyrics = lyricsStateDTO(ly)
	} else if err != nil && KindOf(classify(err)) != KindNotFound {
		return ItemMetadataDTO{}, classify(err)
	}

	// The facade resolves art through the entity fallback chain, so an item
	// with only inherited album art reads HasArtwork true. Level names which
	// chain level answered, so HasOwnArtwork isolates the item's own cover
	// from an inherited one for the editor's has-artwork indicator.
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
	if it.Kind == model.KindEpisode {
		ref.Type = model.ArtEpisode
	}
	if prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront); err == nil && prov != nil {
		out.HasArtwork = true
		out.HasOwnArtwork = prov.Level == ref.Type && !prov.Derived
	}
	return out, nil
}

// fillBookMetadata overlays the book-only detail fields and chapters;
// a detail read failure leaves the base view standing rather than
// failing the whole metadata read. The chapters are on the timeline the
// parts play on, as the book detail serves them and as SetBookChapters
// reads an edit: the catalog's own, saved back, would move every mark
// after a part whose marks outrun its audio, once per save.
func (l *Editor) fillBookMetadata(ctx context.Context, it *model.ItemView, out *ItemMetadataDTO) {
	bd, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		return
	}
	set := func(name, value string) {
		if value != "" {
			out.Fields[name] = value
		}
	}
	set("subtitle", bd.Subtitle)
	set("isbn", bd.ISBN)
	set("publisher", bd.Publisher)
	set("edition", bd.Edition)
	set("description", bd.Description)
	out.Chapters, _ = bookMarks(bd)
}

// editorScalarFields builds the kind's scalar field map from the item
// view, then overlays curated provenance values for the fields the view
// does not carry. Empty values are omitted.
func editorScalarFields(it *model.ItemView, prov []model.FieldProvenance) map[string]string {
	fields := map[string]string{}
	set := func(name, value string) {
		if value != "" {
			fields[name] = value
		}
	}
	setInt := func(name string, v int) {
		if v > 0 {
			fields[name] = strconv.Itoa(v)
		}
	}
	switch it.Kind {
	case model.KindBook:
		set("title", it.Title)
		set("author", it.Artist)
		set("author_sort", it.AuthorSort)
		set("narrator", it.Narrator)
		set("series", it.Series)
		set("subtitle", it.Subtitle)
		set("genre", it.Genre)
		setInt("year", it.Year)
		set("asin", it.ASIN)
		set("mbid", it.MBID)
	case model.KindEpisode:
		set("title", it.Title)
		setInt("season", it.Season)
	default:
		set("title", it.Title)
		set("artist", it.Artist)
		set("album_artist", it.AlbumArtist)
		set("album", it.Album)
		set("composer", it.Composer)
		set("composer_sort", it.ComposerSort)
		set("genre", it.Genre)
		setInt("year", it.Year)
		setInt("track_no", it.TrackNo)
		setInt("track_total", it.TrackTotal)
		setInt("disc_no", it.DiscNo)
		setInt("disc_total", it.DiscTotal)
		setInt("bpm", it.BPM)
		set("isrc", it.ISRC)
		set("mbid", it.MBID)
		if it.Compilation {
			fields["compilation"] = "true"
		}
	}
	// Curated values cover the vocabulary the view does not surface
	// (comment, the episode extras); a tag-sourced value for those
	// fields has no provenance row and stays absent until a fuller item
	// read exists upstream. A curated identifier still wins over the
	// view's, which is what an edit that has not been written back to
	// the file yet looks like.
	allowed := map[string]bool{}
	for _, f := range editorFieldsForKind(it.Kind) {
		allowed[f.Name] = true
	}
	for _, r := range prov {
		if allowed[r.Field] && r.Value != "" {
			fields[r.Field] = r.Value
		}
	}
	return fields
}

// groupCredits folds contributor rows into per-role name lists,
// preserving stored order.
func groupCredits(rows []model.Contributor) []CreditDTO {
	out := []CreditDTO{}
	index := map[model.ContributorRole]int{}
	for _, c := range rows {
		i, ok := index[c.Role]
		if !ok {
			i = len(out)
			index[c.Role] = i
			out = append(out, CreditDTO{Role: string(c.Role), Names: []string{}})
		}
		out[i].Names = append(out[i].Names, c.Name)
	}
	return out
}

// lyricsStateDTO renders stored lyrics in the editor's working format.
func lyricsStateDTO(ly *model.Lyrics) *LyricsStateDTO {
	out := &LyricsStateDTO{Source: string(ly.Source), Provider: ly.Provider, Synced: len(ly.Synced) > 0}
	if len(ly.Synced) > 0 {
		out.LRC = syncedLRC(ly.Synced)
	} else {
		out.LRC = ly.Unsynced
	}
	return out
}

// syncedLRC renders timed lyric lines as an LRC document, in time order.
func syncedLRC(synced []model.SyncedLine) string {
	lines := make([]waxlabel.SyncedLine, 0, len(synced))
	for _, ln := range syncedInTimeOrder(synced) {
		lines = append(lines, waxlabel.SyncedLine{
			Time: time.Duration(ln.TimeMS) * time.Millisecond, Text: ln.Text,
		})
	}
	return waxlabel.FormatLRC(lines)
}
