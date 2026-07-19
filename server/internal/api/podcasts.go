package api

import (
	"bytes"
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Handlers for the podcast, audiobook, and skip-map surfaces. Shapes
// convert here; behavior lives in the service.

func (s *Server) ListSubscriptions(ctx context.Context, req ListSubscriptionsRequestObject) (ListSubscriptionsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit := 100
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	if limit < 1 || limit > 500 {
		return ListSubscriptions400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	cursor := ""
	if req.Params.Cursor != nil {
		cursor = *req.Params.Cursor
	}
	subs, next, err := s.svc.Subscriptions(ctx, uc, cursor, limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ListSubscriptions400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return SubscribePodcast400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a request body is required"))}, nil
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
	sub, created, err := s.svc.Subscribe(ctx, uc, sr)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SubscribePodcast400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindUnsupported:
			return SubscribePodcast501JSONResponse{SourceUnavailableJSONResponse(errObj("source-unavailable", err.Error()))}, nil
		case service.KindUpstream:
			return SubscribePodcast502JSONResponse{FeedUnreachableJSONResponse(errObj("feed-unreachable", err.Error()))}, nil
		}
		return nil, err
	}
	if created {
		return SubscribePodcast201JSONResponse(subscriptionJSON(sub)), nil
	}
	return SubscribePodcast200JSONResponse(subscriptionJSON(sub)), nil
}

func (s *Server) GetPodcast(ctx context.Context, req GetPodcastRequestObject) (GetPodcastResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	det, err := s.svc.PodcastDetailFor(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetPodcast404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no show with pid "+req.Pid))}, nil
		}
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	removeDownloads := req.Params.RemoveDownloads != nil && *req.Params.RemoveDownloads
	if err := s.svc.Unsubscribe(ctx, uc, req.Pid, removeDownloads); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return UnsubscribePodcast404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no show with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return UnsubscribePodcast204Response{}, nil
}

func (s *Server) PutSubscriptionSettings(ctx context.Context, req PutSubscriptionSettingsRequestObject) (PutSubscriptionSettingsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return PutSubscriptionSettings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a request body is required"))}, nil
	}
	sub, err := s.svc.PutSubscriptionSettings(ctx, uc, req.Pid, settingsFromJSON(*req.Body))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PutSubscriptionSettings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return PutSubscriptionSettings404JSONResponse(errObj("not-found", err.Error())), nil
		}
		return nil, err
	}
	return PutSubscriptionSettings200JSONResponse(subscriptionJSON(sub)), nil
}

func (s *Server) ListEpisodes(ctx context.Context, req ListEpisodesRequestObject) (ListEpisodesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit := 100
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	if limit < 1 || limit > 500 {
		return ListEpisodes400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	cursor := ""
	if req.Params.Cursor != nil {
		cursor = *req.Params.Cursor
	}
	eps, next, err := s.svc.Episodes(ctx, uc, req.Pid, cursor, limit)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ListEpisodes400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return ListEpisodes404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no show with pid "+req.Pid))}, nil
		}
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	det, err := s.svc.EpisodeDetailFor(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetEpisode404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no episode with pid "+req.Pid))}, nil
		}
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
		HasTranscript: sum.HasTranscript,
		MediaType:     sum.MediaType,
		Pid:           sum.Pid,
		PublishedAt:   sum.PublishedAt,
		Season:        sum.Season,
		ShowPid:       sum.ShowPid,
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
	return GetEpisode200JSONResponse(out), nil
}

func (s *Server) GetEpisodeTranscript(ctx context.Context, req GetEpisodeTranscriptRequestObject) (GetEpisodeTranscriptResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	tx, err := s.svc.Transcript(ctx, uc, req.Pid)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return GetEpisodeTranscript404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
		case service.KindUpstream:
			return GetEpisodeTranscript502JSONResponse{FeedUnreachableJSONResponse(errObj("feed-unreachable", err.Error()))}, nil
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

func (s *Server) RefreshPodcast(ctx context.Context, req RefreshPodcastRequestObject) (RefreshPodcastResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	added, err := s.svc.RefreshPodcast(ctx, uc, req.Pid)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return RefreshPodcast404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no show with pid "+req.Pid))}, nil
		case service.KindForbidden:
			return RefreshPodcast403JSONResponse(errObj("forbidden", err.Error())), nil
		case service.KindUpstream:
			return RefreshPodcast502JSONResponse{FeedUnreachableJSONResponse(errObj("feed-unreachable", err.Error()))}, nil
		}
		return nil, err
	}
	return RefreshPodcast200JSONResponse(RefreshResult{NewEpisodes: added}), nil
}

func (s *Server) FetchEpisode(ctx context.Context, req FetchEpisodeRequestObject) (FetchEpisodeResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.QueueEpisodeFetch(ctx, uc, req.Pid); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return FetchEpisode404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no episode with pid "+req.Pid))}, nil
		case service.KindForbidden:
			return FetchEpisode403JSONResponse(errObj("forbidden", err.Error())), nil
		}
		return nil, err
	}
	return FetchEpisode202Response{}, nil
}

func (s *Server) RemoveEpisodeDownload(ctx context.Context, req RemoveEpisodeDownloadRequestObject) (RemoveEpisodeDownloadResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.RemoveEpisodeDownload(ctx, uc, req.Pid); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return RemoveEpisodeDownload404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no episode with pid "+req.Pid))}, nil
		case service.KindForbidden:
			return RemoveEpisodeDownload403JSONResponse(errObj("forbidden", err.Error())), nil
		case service.KindConflict:
			return RemoveEpisodeDownload409JSONResponse(errObj("conflict", err.Error())), nil
		}
		return nil, err
	}
	return RemoveEpisodeDownload204Response{}, nil
}

func (s *Server) ExportOpml(ctx context.Context, req ExportOpmlRequestObject) (ExportOpmlResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	doc, err := s.svc.ExportOPML(ctx, uc)
	if err != nil {
		return nil, err
	}
	return ExportOpml200ApplicationxmlResponse{
		Body:          bytes.NewReader(doc),
		ContentLength: int64(len(doc)),
	}, nil
}

func (s *Server) ImportOpml(ctx context.Context, req ImportOpmlRequestObject) (ImportOpmlResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return ImportOpml400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a request body is required"))}, nil
	}
	results, err := s.svc.ImportOPML(ctx, uc, []byte(req.Body.Opml))
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ImportOpml400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
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
		out.Results = append(out.Results, entry)
	}
	return ImportOpml200JSONResponse(out), nil
}

func (s *Server) GetBook(ctx context.Context, req GetBookRequestObject) (GetBookResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	bd, err := s.svc.BookDetailFor(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetBook404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no book with pid "+req.Pid))}, nil
		}
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
	setOpt(&out.Subtitle, bd.Subtitle)
	setOpt(&out.Series, bd.Series)
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

func (s *Server) GetBookResume(ctx context.Context, req GetBookResumeRequestObject) (GetBookResumeResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	rp, err := s.svc.BookResumeFor(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetBookResume404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no book with pid "+req.Pid))}, nil
		}
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return PutBookSettings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a request body is required"))}, nil
	}
	stored, err := s.svc.PutBookSettings(ctx, uc, req.Pid, service.BookSettings{
		Speed:       req.Body.Speed,
		VoiceBoost:  req.Body.VoiceBoost,
		TrimSilence: req.Body.TrimSilence,
	})
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PutBookSettings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return PutBookSettings404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no book with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return PutBookSettings200JSONResponse(bookSettingsJSON(stored)), nil
}

func (s *Server) GetSkipMap(ctx context.Context, req GetSkipMapRequestObject) (GetSkipMapResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	partIndex := 0
	if req.Params.PartIndex != nil {
		partIndex = *req.Params.PartIndex
	}
	m, err := s.svc.SkipMapFor(ctx, uc, req.Pid, partIndex)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return GetSkipMap404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindInvalid:
			// The typed 400 is not declared for this endpoint; range
			// errors on partIndex answer not-found semantics instead of
			// leaking a 500.
			return GetSkipMap404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
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
	return out
}

func subscriptionJSON(sub service.Subscription) Subscription {
	return Subscription{
		Show:         showJSON(sub.Show),
		Settings:     settingsJSON(sub.Settings),
		SubscribedAt: time.Unix(0, sub.SubscribedAtNS).UTC(),
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
