package api

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/colespringer/waxdeck/server/internal/httpcache"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// Handlers for the podcast, audiobook, skip-map, and waveform surfaces.
// Shapes convert here; behavior lives in the service.

func (s *Server) ListSubscriptions(ctx context.Context, req ListSubscriptionsRequestObject) (ListSubscriptionsResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 100, 500)
	if err != nil {
		return nil, err
	}
	cursor := ""
	if req.Params.Cursor != nil {
		cursor = *req.Params.Cursor
	}
	subs, next, err := s.svc.Podcasts.Subscriptions(ctx, uc, cursor, limit, true)
	if err != nil {
		return nil, err
	}
	page := SubscriptionPage{Items: make([]Subscription, 0, len(subs))}
	for _, sub := range subs {
		page.Items = append(page.Items, subscriptionJSON(sub))
	}
	if next != "" {
		page.NextCursor = &next
	}
	return ListSubscriptions200JSONResponse(page), nil
}

func (s *Server) SubscribePodcast(ctx context.Context, req SubscribePodcastRequestObject) (SubscribePodcastResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	sr := service.SubscribeRequest{URL: req.Body.Url}
	if req.Body.SourceType != nil {
		sr.SourceType = *req.Body.SourceType
	}
	if req.Body.Username != nil {
		sr.Username = *req.Body.Username
	}
	if req.Body.Password != nil {
		sr.Password = *req.Body.Password
	}
	if req.Body.Folder != nil {
		sr.Folder = *req.Body.Folder
	}
	sub, created, err := s.svc.Podcasts.Subscribe(ctx, uc, sr)
	if err != nil {
		kind := service.KindOf(err)
		if kind == service.KindInvalid {
			return nil, refuseParams(http.StatusBadRequest, "invalid-request", serviceMessage(err), feedParams(err))
		}
		if kind == service.KindFeature {
			return nil, featureRefusal(err)
		}
		if kind == service.KindUpstream {
			return nil, refuseParams(http.StatusBadGateway, "feed-unreachable", serviceMessage(err), feedParams(err))
		}
		return nil, err
	}
	if created {
		return SubscribePodcast201JSONResponse(subscriptionJSON(sub)), nil
	}
	return SubscribePodcast200JSONResponse(subscriptionJSON(sub)), nil
}

// SearchPodcastDirectory answers show name searches. Every result
// carries the feed URL to subscribe with, so a match needs no source
// kind: a directory hit is always RSS.
func (s *Server) SearchPodcastDirectory(ctx context.Context, req SearchPodcastDirectoryRequestObject) (SearchPodcastDirectoryResponseObject, error) {
	limit, err := pageLimit(req.Params.Limit, 25, 100)
	if err != nil {
		return nil, err
	}
	entries, err := s.svc.Podcasts.SearchPodcastDirectory(ctx, req.Params.Query, limit)
	if err != nil {
		return nil, err
	}
	out := PodcastDirectoryResults{Entries: make([]PodcastDirectoryEntry, 0, len(entries))}
	for _, e := range entries {
		w := PodcastDirectoryEntry{Name: e.Name, FeedUrl: e.FeedURL}
		setOpt(&w.Author, e.Author)
		setOpt(&w.ArtworkUrl, e.ArtworkURL)
		setOpt(&w.Genre, e.Genre)
		if e.EpisodeCount > 0 {
			w.EpisodeCount = ptr(e.EpisodeCount)
		}
		out.Entries = append(out.Entries, w)
	}
	return SearchPodcastDirectory200JSONResponse(out), nil
}

func (s *Server) GetPodcast(ctx context.Context, req GetPodcastRequestObject) (GetPodcastResponseObject, error) {
	uc := userCtx(ctx)
	det, err := s.svc.Podcasts.DetailFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	out := PodcastDetail{Show: showJSON(det.Show), Subscribed: det.Subscribed}
	if det.Settings != nil {
		settings := settingsJSON(*det.Settings)
		out.Settings = &settings
	}
	return GetPodcast200JSONResponse(out), nil
}

func (s *Server) UnsubscribePodcast(ctx context.Context, req UnsubscribePodcastRequestObject) (UnsubscribePodcastResponseObject, error) {
	uc := userCtx(ctx)
	removeDownloads := req.Params.RemoveDownloads != nil && *req.Params.RemoveDownloads
	if err := s.svc.Podcasts.Unsubscribe(ctx, uc, req.Pid, removeDownloads); err != nil {
		return nil, err
	}
	return UnsubscribePodcast204Response{}, nil
}

func (s *Server) PutSubscriptionSettings(ctx context.Context, req PutSubscriptionSettingsRequestObject) (PutSubscriptionSettingsResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	sub, err := s.svc.Podcasts.PutSubscriptionSettings(ctx, uc, req.Pid, settingsFromJSON(*req.Body))
	if err != nil {
		return nil, err
	}
	return PutSubscriptionSettings200JSONResponse(subscriptionJSON(sub)), nil
}

func (s *Server) ListSubscribedEpisodes(ctx context.Context, req ListSubscribedEpisodesRequestObject) (ListSubscribedEpisodesResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 100, 500)
	if err != nil {
		return nil, err
	}
	filter := service.EpisodesLatest
	if req.Params.Filter != nil {
		filter = service.SubscribedEpisodeFilter(*req.Params.Filter)
	}
	eps, next, err := s.svc.Podcasts.SubscribedEpisodes(ctx, uc, filter, deref(req.Params.Cursor), limit)
	if err != nil {
		return nil, err
	}
	page := EpisodePage{Items: make([]EpisodeSummary, 0, len(eps))}
	for _, ep := range eps {
		page.Items = append(page.Items, episodeSummaryJSON(ep))
	}
	if next != "" {
		page.NextCursor = &next
	}
	return ListSubscribedEpisodes200JSONResponse(page), nil
}

func (s *Server) ListEpisodes(ctx context.Context, req ListEpisodesRequestObject) (ListEpisodesResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 100, 500)
	if err != nil {
		return nil, err
	}
	cursor := ""
	if req.Params.Cursor != nil {
		cursor = *req.Params.Cursor
	}
	eps, next, err := s.svc.Podcasts.Episodes(ctx, uc, req.Pid, cursor, limit)
	if err != nil {
		return nil, err
	}
	page := EpisodePage{Items: make([]EpisodeSummary, 0, len(eps))}
	for _, ep := range eps {
		page.Items = append(page.Items, episodeSummaryJSON(ep))
	}
	if next != "" {
		page.NextCursor = &next
	}
	return ListEpisodes200JSONResponse(page), nil
}

func (s *Server) GetEpisode(ctx context.Context, req GetEpisodeRequestObject) (GetEpisodeResponseObject, error) {
	uc := userCtx(ctx)
	det, err := s.svc.Podcasts.EpisodeDetailFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	sum := episodeSummaryJSON(det.EpisodeSummary)
	out := Episode{
		Album:         sum.Album,
		ArtUrl:        sum.ArtUrl,
		Artist:        sum.Artist,
		Downloaded:    sum.Downloaded,
		DurationMs:    sum.DurationMs,
		EpisodeNumber: sum.EpisodeNumber,
		EpisodeType:   sum.EpisodeType,
		Explicit:      sum.Explicit,
		FetchError:    sum.FetchError,
		FetchState:    sum.FetchState,
		HasEnclosure:  sum.HasEnclosure,
		HasTranscript: sum.HasTranscript,
		MediaType:     sum.MediaType,
		Pid:           sum.Pid,
		PublishedAt:   sum.PublishedAt,
		Season:        sum.Season,
		ShowPid:       sum.ShowPid,
		SortKey:       sum.SortKey,
		Title:         sum.Title,
	}
	if det.DescriptionHTML != "" {
		out.DescriptionHtml = &det.DescriptionHTML
	}
	if det.Link != "" {
		out.Link = &det.Link
	}
	if len(det.Chapters) > 0 {
		chapters := make([]ChapterMark, 0, len(det.Chapters))
		for _, ch := range det.Chapters {
			chapters = append(chapters, chapterJSON(ch))
		}
		out.Chapters = &chapters
	}
	if persons := feedPersonsJSON(det.Persons); len(persons) > 0 {
		out.Persons = &persons
	}
	if soundbites := soundbitesJSON(det.Soundbites); len(soundbites) > 0 {
		out.Soundbites = &soundbites
	}
	return GetEpisode200JSONResponse(out), nil
}

func (s *Server) GetEpisodeTranscript(ctx context.Context, req GetEpisodeTranscriptRequestObject) (GetEpisodeTranscriptResponseObject, error) {
	uc := userCtx(ctx)
	tx, err := s.svc.Podcasts.Transcript(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindUpstream {
			return nil, refuseParams(http.StatusBadGateway, "feed-unreachable", serviceMessage(err), feedParams(err))
		}
		return nil, err
	}
	out := Transcript{Format: tx.Format, Cues: make([]TranscriptCue, 0, len(tx.Cues))}
	for _, c := range tx.Cues {
		cue := TranscriptCue{StartMs: c.StartMS, Text: c.Text}
		if c.EndMS > 0 {
			end := c.EndMS
			cue.EndMs = &end
		}
		if c.Speaker != "" {
			speaker := c.Speaker
			cue.Speaker = &speaker
		}
		out.Cues = append(out.Cues, cue)
	}
	return GetEpisodeTranscript200JSONResponse(out), nil
}

func (s *Server) CaptureEpisodeTranscript(ctx context.Context, req CaptureEpisodeTranscriptRequestObject) (CaptureEpisodeTranscriptResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.Podcasts.CaptureEpisodeTranscript(ctx, uc, req.Pid); err != nil {
		if service.KindOf(err) == service.KindUpstream {
			return nil, refuseParams(http.StatusBadGateway, "feed-unreachable", serviceMessage(err), feedParams(err))
		}
		return nil, err
	}
	return CaptureEpisodeTranscript204Response{}, nil
}

func (s *Server) RefreshPodcast(ctx context.Context, req RefreshPodcastRequestObject) (RefreshPodcastResponseObject, error) {
	uc := userCtx(ctx)
	added, err := s.svc.Podcasts.RefreshPodcast(ctx, uc, req.Pid)
	if err != nil {
		kind := service.KindOf(err)
		if kind == service.KindUpstream {
			return nil, refuseParams(http.StatusBadGateway, "feed-unreachable", serviceMessage(err), feedParams(err))
		}
		return nil, err
	}
	return RefreshPodcast200JSONResponse(RefreshResult{NewEpisodes: added}), nil
}

func (s *Server) FetchEpisode(ctx context.Context, req FetchEpisodeRequestObject) (FetchEpisodeResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.Podcasts.QueueEpisodeFetch(ctx, uc, req.Pid); err != nil {
		return nil, err
	}
	return FetchEpisode202Response{}, nil
}

func (s *Server) RemoveEpisodeDownload(ctx context.Context, req RemoveEpisodeDownloadRequestObject) (RemoveEpisodeDownloadResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.Podcasts.RemoveEpisodeDownload(ctx, uc, req.Pid); err != nil {
		return nil, err
	}
	return RemoveEpisodeDownload204Response{}, nil
}

func (s *Server) ExportOpml(ctx context.Context, req ExportOpmlRequestObject) (ExportOpmlResponseObject, error) {
	uc := userCtx(ctx)
	doc, err := s.svc.Podcasts.ExportOPML(ctx, uc)
	if err != nil {
		return nil, err
	}
	return ExportOpml200ApplicationxmlResponse{
		Body:          bytes.NewReader(doc),
		ContentLength: int64(len(doc)),
	}, nil
}

func (s *Server) ImportOpml(ctx context.Context, req ImportOpmlRequestObject) (ImportOpmlResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	results, err := s.svc.Podcasts.ImportOPML(ctx, uc, []byte(req.Body.Opml))
	if err != nil {
		if service.KindOf(err) == service.KindFeature {
			return nil, featureRefusal(err)
		}
		return nil, err
	}
	out := OpmlImportResult{Results: make([]OpmlImportEntry, 0, len(results))}
	for _, r := range results {
		entry := OpmlImportEntry{FeedUrl: r.FeedURL}
		if r.Title != "" {
			title := r.Title
			entry.Title = &title
		}
		if r.PID != "" {
			pid := r.PID
			entry.Pid = &pid
		}
		if r.Err != "" {
			msg := r.Err
			entry.Error = &msg
		}
		if r.Reason != "" {
			reason := r.Reason
			entry.Reason = &reason
		}
		out.Results = append(out.Results, entry)
	}
	return ImportOpml200JSONResponse(out), nil
}

// featureRefusal refuses a feature this server is not running, naming
// podcasts when they are the one turned off.
func featureRefusal(err error) error {
	var params map[string]string
	if errors.Is(err, service.ErrPodcastsOff) {
		params = map[string]string{"feature": "podcasts"}
	}
	return refuseParams(http.StatusNotImplemented, "feature-unavailable", serviceMessage(err), params)
}

// feedParams is a feed failure's reason, for the refusal that carries
// the service's sentence; none when the failure names no reason.
func feedParams(err error) map[string]string {
	if reason := service.FeedFailureReason(err); reason != "" {
		return map[string]string{"reason": reason}
	}
	return nil
}

func (s *Server) GetBook(ctx context.Context, req GetBookRequestObject) (GetBookResponseObject, error) {
	uc := userCtx(ctx)
	bd, err := s.svc.Reads.BookDetailFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	out := BookDetail{
		Pid:        bd.PID,
		Title:      bd.Title,
		DurationMs: bd.DurationMS,
		Authors:    bd.Authors,
		Narrators:  bd.Narrators,
		Chapters:   make([]ChapterMark, 0, len(bd.Chapters)),
		Parts:      make([]BookPart, 0, len(bd.Parts)),
		Abridged:   bd.Abridged,
	}
	art := "/api/v1/items/" + bd.PID + "/art"
	out.ArtUrl = &art
	out.ArtSource = artSourceJSON(bd.ArtSource)
	setOpt(&out.Subtitle, bd.Subtitle)
	setOpt(&out.Series, bd.Series)
	setOpt(&out.AuthorPid, bd.AuthorPID)
	setOpt(&out.SeriesPid, bd.SeriesPID)
	setOpt(&out.SeriesSequence, bd.SeriesSequence)
	setOpt(&out.Publisher, bd.Publisher)
	setOpt(&out.Asin, bd.ASIN)
	setOpt(&out.Isbn, bd.ISBN)
	setOpt(&out.Edition, bd.Edition)
	setOpt(&out.DescriptionHtml, bd.DescriptionHTML)
	for _, ch := range bd.Chapters {
		out.Chapters = append(out.Chapters, chapterJSON(ch))
	}
	for _, p := range bd.Parts {
		part := BookPart{Index: p.Index, StartMs: p.StartMS, DurationMs: p.DurationMS}
		setOpt(&part.DisplayName, p.DisplayName)
		out.Parts = append(out.Parts, part)
	}
	if bd.Settings != nil {
		settings := bookSettingsJSON(*bd.Settings)
		out.Settings = &settings
	}
	return GetBook200JSONResponse(out), nil
}

// ListBookSeries pages the series behind the visible books. A series is
// a tag rather than a curated entity, so a split spelling has no
// duplicates finding to arrive through: this both offers the target of
// a merge and backs the browse index. Two callers with different page
// budgets, which is what the limit is sized against - the merge picker
// drains the whole list, the hub's shelf stops as soon as it has
// enough tiles to draw.
func (s *Server) ListBookSeries(ctx context.Context, req ListBookSeriesRequestObject) (ListBookSeriesResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 100, 500)
	if err != nil {
		return nil, err
	}
	page, err := s.svc.Reads.ListBookSeries(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
		return nil, err
	}
	out := BookSeriesPage{Series: make([]BookSeries, 0, len(page.Series))}
	for _, sr := range page.Series {
		row := BookSeries{Pid: sr.PID, Name: sr.Name}
		if sr.BookCount > 0 {
			row.BookCount = ptr(sr.BookCount)
		}
		if sr.TotalDurationMS > 0 {
			row.TotalDurationMs = ptr(sr.TotalDurationMS)
		}
		out.Series = append(out.Series, row)
	}
	if page.NextCursor != "" {
		out.NextCursor = ptr(page.NextCursor)
	}
	return ListBookSeries200JSONResponse(out), nil
}

// GetBookSeries reads one series and the books in it.
func (s *Server) GetBookSeries(ctx context.Context, req GetBookSeriesRequestObject) (GetBookSeriesResponseObject, error) {
	uc := userCtx(ctx)
	detail, err := s.svc.Reads.BookSeriesDetailFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	out := BookSeriesDetail{
		Pid:   detail.PID,
		Name:  detail.Name,
		Books: make([]BookSeriesEntry, 0, len(detail.Books)),
	}
	if detail.BookCount > 0 {
		out.BookCount = ptr(detail.BookCount)
	}
	if detail.TotalDurationMS > 0 {
		out.TotalDurationMs = ptr(detail.TotalDurationMS)
	}
	for _, entry := range detail.Books {
		row := BookSeriesEntry{Book: summaryJSON(entry.Book)}
		if entry.Sequence != "" {
			row.Sequence = ptr(entry.Sequence)
		}
		out.Books = append(out.Books, row)
	}
	return GetBookSeries200JSONResponse(out), nil
}

func (s *Server) GetBookResume(ctx context.Context, req GetBookResumeRequestObject) (GetBookResumeResponseObject, error) {
	uc := userCtx(ctx)
	rp, err := s.svc.Reads.BookResumeFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	out := BookResume{PositionMs: rp.PositionMS}
	if rp.Chapter != nil {
		ch := chapterJSON(*rp.Chapter)
		out.Chapter = &ch
	}
	if rp.UpdatedAtNS > 0 {
		t := time.Unix(0, rp.UpdatedAtNS).UTC()
		out.UpdatedAt = &t
	}
	return GetBookResume200JSONResponse(out), nil
}

func (s *Server) PutBookSettings(ctx context.Context, req PutBookSettingsRequestObject) (PutBookSettingsResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	stored, err := s.svc.Reads.PutBookSettings(ctx, uc, req.Pid, service.BookSettings{
		Speed:       req.Body.Speed,
		VoiceBoost:  req.Body.VoiceBoost,
		TrimSilence: req.Body.TrimSilence,
	})
	if err != nil {
		return nil, err
	}
	return PutBookSettings200JSONResponse(bookSettingsJSON(stored)), nil
}

func (s *Server) ListBookmarks(ctx context.Context, req ListBookmarksRequestObject) (ListBookmarksResponseObject, error) {
	uc := userCtx(ctx)
	marks, err := s.svc.Reads.BookmarksFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	out := BookmarkList{Bookmarks: make([]Bookmark, 0, len(marks))}
	for _, m := range marks {
		out.Bookmarks = append(out.Bookmarks, bookmarkJSON(m))
	}
	return ListBookmarks200JSONResponse(out), nil
}

func (s *Server) CreateBookmark(ctx context.Context, req CreateBookmarkRequestObject) (CreateBookmarkResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	mark, err := s.svc.Reads.CreateBookmark(ctx, uc, req.Pid, deref(req.Body.Id), req.Body.PositionMs, deref(req.Body.Note))
	if err != nil {
		kind := service.KindOf(err)
		if kind == service.KindConflict {
			var params map[string]string
			if errors.Is(err, service.ErrBookmarkRemoved) {
				params = map[string]string{"reason": "removed"}
			}
			return nil, refuseParams(http.StatusConflict, "conflict", serviceMessage(err), params)
		}
		return nil, err
	}
	return CreateBookmark201JSONResponse(bookmarkJSON(mark)), nil
}

func (s *Server) DeleteBookmark(ctx context.Context, req DeleteBookmarkRequestObject) (DeleteBookmarkResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.Reads.DeleteBookmark(ctx, uc, req.Pid, req.BookmarkId); err != nil {
		// The service's not-found names which is missing, book or bookmark.
		return nil, err
	}
	return DeleteBookmark204Response{}, nil
}

func bookmarkJSON(m service.Bookmark) Bookmark {
	out := Bookmark{
		Id:         m.ID,
		PositionMs: m.PositionMS,
		CreatedAt:  time.Unix(0, m.CreatedAtNS).UTC(),
	}
	setOpt(&out.Note, m.Note)
	return out
}

func (s *Server) GetSkipMap(ctx context.Context, req GetSkipMapRequestObject) (GetSkipMapResponseObject, error) {
	uc := userCtx(ctx)
	partIndex := 0
	if req.Params.PartIndex != nil {
		partIndex = *req.Params.PartIndex
	}
	m, err := s.svc.Tools.SkipMapFor(ctx, uc, req.Pid, partIndex)
	if err != nil {
		kind := service.KindOf(err)
		if kind == service.KindInvalid {
			// The typed 400 is not declared for this endpoint; range
			// errors on partIndex answer not-found semantics instead of
			// leaking a 500.
			return nil, refuse(http.StatusNotFound, "not-found", serviceMessage(err))
		}
		if kind == service.KindFeature {
			// Only an engine that is away refuses a read: its analysis waits.
			return nil, toolEngineAway(err)
		}
		return nil, err
	}
	out := SkipMap{State: m.State, PartIndex: m.PartIndex}
	setOpt(&out.EssenceHash, m.EssenceHash)
	setOpt(&out.Version, m.Version)
	if m.State == "ready" {
		if m.ThresholdDB != 0 {
			v := m.ThresholdDB
			out.ThresholdDb = &v
		}
		if m.MinSeconds != 0 {
			v := m.MinSeconds
			out.MinSeconds = &v
		}
		spans := make([]SkipSpan, 0, len(m.Spans))
		for _, sp := range m.Spans {
			spans = append(spans, SkipSpan{StartMs: sp.StartMS, EndMs: sp.EndMS})
		}
		out.Spans = &spans
		if m.CreatedAtNS > 0 {
			t := time.Unix(0, m.CreatedAtNS).UTC()
			out.UpdatedAt = &t
		}
	}
	return GetSkipMap200JSONResponse(out), nil
}

// waveformCacheControl caches a ready waveform exactly as artwork is
// cached, and for the same reasons: peaks are deterministic per audio
// essence, the URL names a pid rather than the bytes (so re-analysis
// under the same pid must be able to invalidate), and the answer follows
// the item's visibility (so a shared browser must not serve one account
// from another's copy). Neither `public` nor `immutable`, for those two
// reasons in that order.
const waveformCacheControl = artCacheControl

func (s *Server) GetWaveform(ctx context.Context, req GetWaveformRequestObject) (GetWaveformResponseObject, error) {
	uc := userCtx(ctx)
	partIndex := 0
	if req.Params.PartIndex != nil {
		partIndex = *req.Params.PartIndex
	}
	// The whole-item span ignores partIndex by contract: a book's
	// timeline is the book, and naming a part inside it names nothing.
	wholeItem := req.Params.Span != nil && *req.Params.Span == GetWaveformParamsSpanItem
	var (
		wf  service.WaveformResult
		err error
	)
	if wholeItem {
		wf, err = s.svc.Playback.WaveformForItem(ctx, uc, req.Pid)
	} else {
		wf, err = s.svc.Playback.WaveformFor(ctx, uc, req.Pid, partIndex)
	}
	if err != nil {
		kind := service.KindOf(err)
		if kind == service.KindInvalid {
			// No 400 declared here, as on the skip map: a partIndex range
			// error answers not-found rather than leaking a 500.
			return nil, refuse(http.StatusNotFound, "not-found", serviceMessage(err))
		}
		return nil, err
	}
	out := Waveform{State: wf.State, PartIndex: wf.PartIndex}
	setOpt(&out.EssenceHash, wf.EssenceHash)
	if wf.State != "ready" {
		// Both non-ready states are waiting to be contradicted: pending
		// by the next analyze pass, unavailable by an audio change. A
		// cached copy of either would outlive the answer.
		noStore := "no-store"
		return GetWaveform200JSONResponse{
			Body:    out,
			Headers: GetWaveform200ResponseHeaders{CacheControl: &noStore},
		}, nil
	}
	// The essence scoped by the peaks revision, the way artwork's
	// validator is the source hash scoped by the requested size. The
	// essence alone is not enough: an analysis-version bump re-analyzes
	// audio whose essence never changed and can rewrite both the values
	// and the bucket count, which a client would otherwise not see for
	// a day of freshness plus a week of stale-while-revalidate.
	tag := fmt.Sprintf("%s-%d", wf.EssenceHash, wf.Version)
	if wf.Window != "" {
		// Carved siblings share the file's essence and version.
		tag += "-w" + wf.Window
	}
	etag := fmt.Sprintf("%q", tag)
	cacheControl, vary := waveformCacheControl, artVary
	if req.Params.IfNoneMatch != nil && httpcache.ETagMatches(*req.Params.IfNoneMatch, etag) {
		return GetWaveform304Response{Headers: GetWaveform304ResponseHeaders{
			ETag:         &etag,
			CacheControl: &cacheControl,
			Vary:         &vary,
		}}, nil
	}
	peaks := make([]int, len(wf.Peaks))
	for i, v := range wf.Peaks {
		peaks[i] = int(v)
	}
	out.Peaks = &peaks
	out.Resolution = &wf.Resolution
	return GetWaveform200JSONResponse{
		Body: out,
		Headers: GetWaveform200ResponseHeaders{
			ETag:         &etag,
			CacheControl: &cacheControl,
			Vary:         &vary,
		},
	}, nil
}

// --- converters --------------------------------------------------------------

func setOpt(dst **string, v string) {
	if v != "" {
		s := v
		*dst = &s
	}
}

func showJSON(show service.PodcastShow) PodcastShow {
	out := PodcastShow{
		Pid:        show.PID,
		Title:      show.Title,
		SourceType: show.SourceType,
	}
	setOpt(&out.Author, show.Author)
	setOpt(&out.DescriptionHtml, show.DescriptionHTML)
	setOpt(&out.FeedUrl, show.FeedURL)
	setOpt(&out.Link, show.Link)
	art := "/api/v1/items/" + show.PID + "/art"
	out.ArtUrl = &art
	if show.EpisodeCount > 0 {
		n := show.EpisodeCount
		out.EpisodeCount = &n
	}
	if show.LastPublishedNS > 0 {
		t := time.Unix(0, show.LastPublishedNS).UTC()
		out.LastPublishedAt = &t
	}
	if show.RefreshDisabled {
		v := true
		out.RefreshDisabled = &v
	}
	if show.Explicit {
		v := true
		out.Explicit = &v
	}
	if show.FundingURL != "" {
		f := PodcastFunding{Url: show.FundingURL}
		setOpt(&f.Message, show.FundingMessage)
		out.Funding = &f
	}
	setOpt(&out.Medium, show.Medium)
	if persons := feedPersonsJSON(show.Persons); len(persons) > 0 {
		out.Persons = &persons
	}
	out.ArtSource = artSourceJSON(show.ArtSource)
	return out
}

// feedPersonsJSON maps service person credits onto the generated API type.
func feedPersonsJSON(in []service.FeedPerson) []FeedPerson {
	if len(in) == 0 {
		return nil
	}
	out := make([]FeedPerson, 0, len(in))
	for _, p := range in {
		fp := FeedPerson{Name: p.Name}
		setOpt(&fp.Role, p.Role)
		setOpt(&fp.Group, p.Group)
		setOpt(&fp.Img, p.Img)
		setOpt(&fp.Href, p.Href)
		out = append(out, fp)
	}
	return out
}

// soundbitesJSON maps service soundbites onto the generated API type.
func soundbitesJSON(in []service.Soundbite) []Soundbite {
	if len(in) == 0 {
		return nil
	}
	out := make([]Soundbite, 0, len(in))
	for _, s := range in {
		sb := Soundbite{StartMs: s.StartMS, DurationMs: s.DurationMS}
		setOpt(&sb.Title, s.Title)
		out = append(out, sb)
	}
	return out
}

func settingsJSON(st service.SubscriptionSettings) SubscriptionSettings {
	out := SubscriptionSettings{
		Speed:       st.Speed,
		TrimSilence: st.TrimSilence,
		VoiceBoost:  st.VoiceBoost,
	}
	if st.RetentionKeep != nil {
		n := int(*st.RetentionKeep)
		out.RetentionKeep = &n
	}
	if st.AutoDownload {
		v := true
		out.AutoDownload = &v
	}
	setOpt(&out.Folder, st.Folder)
	if st.Private {
		v := true
		out.Private = &v
	}
	if st.SkipIntroSec != nil {
		n := int(*st.SkipIntroSec)
		out.SkipIntroSeconds = &n
	}
	if st.SkipOutroSec != nil {
		n := int(*st.SkipOutroSec)
		out.SkipOutroSeconds = &n
	}
	// An unset filter is absent rather than a pair of empty arrays: the
	// two mean the same thing and one representation is enough. Each
	// side is then set only when it has terms, per field rather than per
	// pair: `omitempty` on a *[]string omits a nil pointer, not a
	// pointer to a nil slice, so setting both unconditionally would put
	// `"include": null` on the wire for an exclude-only filter, which
	// the schema does not declare nullable.
	if !st.AutoDLFilter.Empty() {
		filter := EpisodeFilter{}
		if len(st.AutoDLFilter.Include) > 0 {
			filter.Include = &st.AutoDLFilter.Include
		}
		if len(st.AutoDLFilter.Exclude) > 0 {
			filter.Exclude = &st.AutoDLFilter.Exclude
		}
		out.AutoDownloadFilter = &filter
	}
	return out
}

func settingsFromJSON(in SubscriptionSettings) service.SubscriptionSettings {
	out := service.SubscriptionSettings{
		Speed:       in.Speed,
		TrimSilence: in.TrimSilence,
		VoiceBoost:  in.VoiceBoost,
	}
	if in.RetentionKeep != nil {
		n := int64(*in.RetentionKeep)
		out.RetentionKeep = &n
	}
	if in.AutoDownload != nil {
		out.AutoDownload = *in.AutoDownload
	}
	if in.Folder != nil {
		out.Folder = *in.Folder
	}
	if in.Private != nil {
		out.Private = *in.Private
	}
	if in.SkipIntroSeconds != nil {
		n := int64(*in.SkipIntroSeconds)
		out.SkipIntroSec = &n
	}
	if in.SkipOutroSeconds != nil {
		n := int64(*in.SkipOutroSeconds)
		out.SkipOutroSec = &n
	}
	if in.AutoDownloadFilter != nil {
		if v := in.AutoDownloadFilter.Include; v != nil {
			out.AutoDLFilter.Include = *v
		}
		if v := in.AutoDownloadFilter.Exclude; v != nil {
			out.AutoDLFilter.Exclude = *v
		}
	}
	return out
}

func subscriptionJSON(sub service.Subscription) Subscription {
	return Subscription{
		Show:         showJSON(sub.Show),
		Settings:     settingsJSON(sub.Settings),
		SubscribedAt: time.Unix(0, sub.SubscribedAtNS).UTC(),
		// Omitted rather than zeroed where it was not computed: the
		// field means "this many are waiting", and a hard zero on the
		// response to subscribing would say the opposite of the truth
		// about a show whose whole backlog is unheard.
		UnplayedCount: sub.UnplayedCount,
	}
}

func episodeSummaryJSON(ep service.EpisodeSummary) EpisodeSummary {
	out := EpisodeSummary{
		Pid:         ep.PID,
		MediaType:   MediaType(ep.MediaType),
		Title:       ep.Title,
		DurationMs:  ep.DurationMS,
		ShowPid:     ep.ShowPID,
		Downloaded:  ep.Downloaded,
		PublishedAt: time.Unix(0, ep.PublishedNS).UTC(),
	}
	setOpt(&out.Artist, ep.Artist)
	setOpt(&out.Album, ep.Album)
	setOpt(&out.SortKey, ep.SortKey)
	art := "/api/v1/items/" + ep.PID + "/art"
	out.ArtUrl = &art
	if ep.Season > 0 {
		n := ep.Season
		out.Season = &n
	}
	if ep.EpisodeNo > 0 {
		n := ep.EpisodeNo
		out.EpisodeNumber = &n
	}
	if ep.EpisodeType != "" && ep.EpisodeType != "full" {
		t := ep.EpisodeType
		out.EpisodeType = &t
	}
	setOpt(&out.FetchState, ep.FetchState)
	setOpt(&out.FetchError, ep.FetchError)
	if ep.Explicit {
		v := true
		out.Explicit = &v
	}
	if ep.HasTx {
		v := true
		out.HasTranscript = &v
	}
	if ep.HasEnclosure {
		v := true
		out.HasEnclosure = &v
	}
	return out
}

func chapterJSON(ch service.ChapterMark) ChapterMark {
	out := ChapterMark{Index: ch.Index, StartMs: ch.StartMS}
	setOpt(&out.Title, ch.Title)
	if ch.EndMS > 0 {
		end := ch.EndMS
		out.EndMs = &end
	}
	return out
}

func bookSettingsJSON(bs service.BookSettings) BookSettings {
	return BookSettings{
		Speed:       bs.Speed,
		VoiceBoost:  bs.VoiceBoost,
		TrimSilence: bs.TrimSilence,
	}
}
