package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// StreamSource resolves an API item PID to everything the WaxFlow
// bridge needs: the backing file's path and identity pin, the
// virtual-track window when the item is a CUE-backed span, the source
// codec facts the format policy reads, and the essence hash that keys
// the analysis cache. It re-resolves on every call, which is what makes
// organize-moves invisible to streaming. filePID selects one part of a
// multi-file book; empty means the item's own backing file.
//
// Loudness is read here for spoken word only, which voice boost derives
// its gain from. Every stream request runs through this, so a caller
// that wants it for music - timeline leveling - asks by hash through
// FillLoudness rather than making the whole library pay a second query
// per play.
func (l *Library) StreamSource(ctx context.Context, apiItemPID, filePID string) (flow.Source, error) {
	src, err := l.streamSource(ctx, apiItemPID, filePID)
	if KindOf(err) == KindMaintenance {
		// The engine reads no service kinds; its sentinel is how it tells
		// a catalog handed off for a moment from an item that is gone.
		err = &Error{Kind: KindMaintenance, Msg: err.Error(), Err: fmt.Errorf("%w: %w", flow.ErrCatalogMaintenance, err)}
	}
	return src, err
}

func (l *Library) streamSource(ctx context.Context, apiItemPID, filePID string) (flow.Source, error) {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return flow.Source{}, err
	}

	// A podcast episode without its audio has no local bytes, and a
	// flow.Source cannot express a remote URL: Path is a path on this
	// host, which the bridge maps to a WaxFlow root reference. So the
	// conflict stays here and the decision to relay the feed's enclosure
	// instead belongs one layer up, at each site that turns an item into
	// a URL. ErrEpisodeNotFetched is what those sites match on.
	if unfetchedEpisode(it) {
		return flow.Source{}, notFetchedEpisode()
	}

	src := flow.Source{
		Codec:      it.Codec,
		Container:  it.Container,
		DurationMS: it.DurationMS,
		SpokenWord: it.Kind == model.KindEpisode || it.Kind == model.KindBook,
	}

	var f *model.File
	if it.Kind == model.KindBook && filePID != "" {
		// Multi-file books stream one named part; the part must belong
		// to this book or the request resolves nothing.
		bd, err := l.lib.Book(ctx, it.PID)
		if err != nil {
			return flow.Source{}, classify(err)
		}
		part, ok := bookPartByFile(bd, filePID)
		if !ok {
			return flow.Source{}, errNotFound("no such part for book " + apiItemPID)
		}
		f, err = l.fileByPID(ctx, model.PID(filePID))
		if err != nil {
			return flow.Source{}, err
		}
		src.Path = string(f.Path)
		src.DurationMS = part.DurationMS
	} else {
		loc, err := l.paths.Locate(ctx, it.PID)
		if err != nil {
			return flow.Source{}, classify(err)
		}
		from, to, err := loc.Span()
		if err != nil {
			return flow.Source{}, classify(err)
		}
		src.Path = loc.Path
		src.Virtual = loc.Virtual
		src.FromSample = from
		src.ToSample = to
		f, err = l.fileByPID(ctx, loc.FilePID)
		if err != nil {
			return flow.Source{}, err
		}
	}
	l.attachFile(ctx, &src, f)
	return src, nil
}

// attachFile fills the half of a source that comes off the backing
// file row, and the loudness voice boost derives its gain from.
//
// Read here only for the content voice boost is for. Every stream
// request runs through this, and a caller that wants music loudness
// (timeline leveling) is rare enough to ask for it by hash rather than
// to make the whole library pay a second query per play.
func (l *Library) attachFile(ctx context.Context, src *flow.Source, f *model.File) {
	src.Codec, src.Container = fileFormat(f, src.Codec, src.Container)
	src.Size = f.Size
	src.MTimeNS = f.MTimeNS
	src.EssenceHash = f.EssenceHash
	src.BitrateKbps = f.Bitrate
	if src.SpokenWord && f.EssenceHash != "" {
		l.fillLoudness(ctx, src)
	}
}

// fileFormat answers a file's own codec and container where the scan read
// them, else the item's (codec, container): a book in parts is one item
// whatever its files are, and the item carries its primary file's.
func fileFormat(f *model.File, codec, container string) (string, string) {
	if f.Codec != "" {
		return f.Codec, f.Container
	}
	return codec, container
}

// FillLoudness attaches the stored measurements for a source's essence,
// for callers that need them on content StreamSource does not read them
// for. Absent measurements leave the fields nil, which every reader
// already treats as "not analyzed".
func (l *Library) FillLoudness(ctx context.Context, src *flow.Source) {
	if src == nil || src.EssenceHash == "" {
		return
	}
	l.fillLoudness(ctx, src)
}

func (l *Library) fillLoudness(ctx context.Context, src *flow.Source) {
	m, err := l.db.SilenceMapFor(ctx, src.EssenceHash)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("reading loudness cache", "err", err)
		}
		return
	}
	src.IntegratedLUFS = m.IntegratedLUFS
	src.TruePeakDB = m.TruePeakDB
}

// fileByPID reads one file row, classified.
func (l *Library) fileByPID(ctx context.Context, pid model.PID) (*model.File, error) {
	f, err := l.lib.File(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	return f, nil
}

// bookPartByFile finds a book's part by backing file PID.
func bookPartByFile(bd *model.BookDetail, filePID string) (model.BookPart, bool) {
	for _, p := range bd.Files {
		if string(p.FilePID) == filePID {
			return p, true
		}
	}
	return model.BookPart{}, false
}

// PlayPart is play-info's part resolution for multi-file books: one
// backing file placed on the book's own timeline.
type PlayPart struct {
	FilePID    string
	Index      int
	Count      int
	StartMS    int64
	DurationMS int64
	MultiPart  bool
}

// playParts lays a book's backing files out on the book timeline, one
// PlayPart per file with its cumulative start. Fewer than two files is
// not a multi-part book and lays out as nothing, which is what every
// caller reads as "stream the item as itself".
func playParts(bd *model.BookDetail) []PlayPart {
	if bd == nil || len(bd.Files) < 2 {
		return nil
	}
	out := make([]PlayPart, len(bd.Files))
	var offset int64
	for i, f := range bd.Files {
		out[i] = PlayPart{
			FilePID:    string(f.FilePID),
			Index:      i,
			Count:      len(bd.Files),
			StartMS:    offset,
			DurationMS: f.DurationMS,
			MultiPart:  true,
		}
		offset += f.DurationMS
	}
	return out
}

// bookTimeline maps a book between two timelines. Its parts play end to
// end, each as long as its measured audio: play-info, the players, the
// waveform and every stored position use that one. The catalog's runs a
// part as long as its chapter marks when they outrun its audio (CHAP
// frames or a chapter track ending past it), so its marks and its length
// sit off the first by every such part before them. Projected onto the
// parts' own timeline, a mark is held to its part's audio: every mark is
// a position there is audio at, and the book ends where its last part
// does.
type bookTimeline struct {
	parts []model.BookPart
	// starts is each part's start where it plays; catalog its start on the
	// catalog's timeline, which a chapter edit is written on.
	starts, catalog []int64
	index           map[model.PID]int
	// end is where the last part's audio ends.
	end int64
}

// timelineOf lays bd out on both timelines, false where a part's audio
// has no measured length to lay it by. The catalog's part starts are read
// off the marks themselves (a mark's book offset less its offset into its
// file), and where a part has none, from the part before it: its audio,
// or its marks where they run longer, as the catalog lays it.
func timelineOf(bd *model.BookDetail) (bookTimeline, bool) {
	n := len(bd.Files)
	if n == 0 {
		return bookTimeline{}, false
	}
	tl := bookTimeline{parts: bd.Files, starts: make([]int64, n), catalog: make([]int64, n), index: make(map[model.PID]int, n)}
	for i, f := range bd.Files {
		tl.index[f.FilePID] = i
	}
	anchored := make([]bool, n)
	extent := make([]int64, n)
	for _, ch := range bd.Chapters {
		i, ok := tl.index[ch.FilePID]
		if !ok {
			continue
		}
		if !anchored[i] {
			tl.catalog[i], anchored[i] = ch.StartMS-ch.FileStartMS, true
		}
		extent[i] = max(extent[i], ch.FileStartMS, ch.FileEndMS)
	}
	var at, cat int64
	for i, f := range bd.Files {
		if f.DurationMS <= 0 {
			return bookTimeline{}, false
		}
		if anchored[i] {
			cat = tl.catalog[i]
		}
		tl.starts[i], tl.catalog[i] = at, cat
		at += f.DurationMS
		cat += max(f.DurationMS, extent[i])
	}
	tl.end = at
	return tl, true
}

// at is fileMS into part i, held to its audio, on the parts' own timeline.
func (tl bookTimeline) at(i int, fileMS int64) int64 {
	return tl.starts[i] + min(max(fileMS, 0), tl.parts[i].DurationMS)
}

// catalogAt maps pos on the parts' own timeline onto the catalog's: the
// same offset into the same part. An end belongs to the part it closes,
// so one at a part's end stays that part's.
func (tl bookTimeline) catalogAt(pos int64, end bool) int64 {
	i := len(tl.parts) - 1
	for k := range tl.parts {
		limit := tl.starts[k] + tl.parts[k].DurationMS
		if pos < limit || (end && pos == limit) {
			i = k
			break
		}
	}
	return tl.catalog[i] + pos - tl.starts[i]
}

// bookMarks answers a book's chapter marks and its length on the timeline
// its parts play on (bookTimeline); the catalog's own where its parts
// cannot be laid out by their audio.
func bookMarks(bd *model.BookDetail) ([]ChapterMark, int64) {
	var out []ChapterMark
	if len(bd.Chapters) > 0 {
		out = make([]ChapterMark, len(bd.Chapters))
	}
	tl, ok := timelineOf(bd)
	if !ok {
		for i, ch := range bd.Chapters {
			out[i] = ChapterMark{Index: i, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS}
		}
		return out, bd.TotalDurationMS
	}
	for i, ch := range bd.Chapters {
		out[i] = ChapterMark{Index: i, Title: ch.Title, StartMS: ch.StartMS}
		p, known := tl.index[ch.FilePID]
		if !known {
			continue
		}
		out[i].StartMS = tl.at(p, ch.FileStartMS)
		if ch.FileEndMS > 0 {
			out[i].EndMS = tl.at(p, ch.FileEndMS)
		}
	}
	// An open end runs to the next mark, the last to the end of the audio,
	// as the catalog fills them on its own timeline.
	for i := range out {
		switch {
		case out[i].EndMS != 0:
		case i+1 < len(out):
			out[i].EndMS = out[i+1].StartMS
		default:
			out[i].EndMS = tl.end
		}
	}
	return out, tl.end
}

// chapterAt answers the mark a position falls in, marks in timeline
// order: the last to start at or before it, so a position in a gap
// between two marks is in the one before the gap, as the player names it
// while it plays there, and one before the first mark is in the first.
// Nil for a book without marks.
func chapterAt(marks []ChapterMark, positionMS int64) *ChapterMark {
	if len(marks) == 0 {
		return nil
	}
	at := &marks[0]
	for i := range marks {
		if marks[i].StartMS <= positionMS {
			at = &marks[i]
		}
	}
	return at
}

// catalogMarks maps a chapter edit made on the timeline a book's parts
// play on onto the catalog's, which the catalog splits it across the
// parts by; as it is where the parts cannot be laid out by their audio.
func catalogMarks(bd *model.BookDetail, marks []model.Chapter) []model.Chapter {
	tl, ok := timelineOf(bd)
	if !ok {
		return marks
	}
	out := make([]model.Chapter, len(marks))
	for i, ch := range marks {
		out[i] = ch
		out[i].StartMS = tl.catalogAt(ch.StartMS, false)
		if ch.EndMS != 0 {
			out[i].EndMS = tl.catalogAt(ch.EndMS, true)
		}
	}
	return out
}

// BookParts is the whole part layout of a multi-file book, in reading
// order, for callers that load every part at once - a device endpoint
// fetches its own URLs and steps through them itself.
//
// A pid that is not a book, or names one this catalog does not hold,
// lays out as nil without an error: every caller reads that as "stream
// the item as itself", which is what a track, an episode, and a
// single-file book all are. A catalog that could not answer is a real
// error and travels as one - swallowing it would render a fifteen-hour
// book as one item that is really its first forty minutes.
func (l *Library) BookParts(ctx context.Context, apiItemPID string) ([]PlayPart, error) {
	prefix, pid, ok := parseAPIPID(apiItemPID)
	if !ok || !bookOrTrackPrefix(prefix) {
		return nil, nil
	}
	// Either prefix can name a book, or what was one: the catalog's
	// "not a book" is the second, a track that streams as itself.
	bd, err := l.lib.Book(ctx, pid)
	if err != nil {
		if waxerr.Is(err, waxerr.CodeInvalid) {
			return nil, nil
		}
		if out := classify(err); KindOf(out) == KindNotFound {
			return nil, nil
		}
		return nil, classify(err)
	}
	return playParts(bd), nil
}

// PlayPiece is one fetchable piece of a multi-file audiobook: where
// the part sits on the book's own timeline, the streaming engine's
// view of its bytes, and the original file for a server running
// without the engine. Both views come off one file row, so which of
// them a server can use costs it nothing.
type PlayPiece struct {
	Part PlayPart
	Src  flow.Source
	File DownloadFile
}

// BookPieces resolves every part of a multi-file audiobook for
// delivery, in one pass.
//
// The item and the book are read once between them and each backing
// file once. Resolving the parts one at a time through StreamSource or
// DirectPlayInfo re-reads both for every part - a thirty-part book
// handed to a cast device is ninety reads that way, on the synchronous
// path a load runs on, repeated per advertise base and again on every
// chapter jump.
//
// Nil for anything that is not a multi-file book: a track, an episode,
// and a single-file book are served whole and resolve as themselves.
func (l *Library) BookPieces(ctx context.Context, uc *UserCtx, apiItemPID string) ([]PlayPiece, error) {
	parts, err := l.BookParts(ctx, apiItemPID)
	if err != nil || len(parts) == 0 {
		return nil, err
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return nil, err
	}
	out := make([]PlayPiece, 0, len(parts))
	for _, part := range parts {
		f, err := l.lib.File(ctx, model.PID(part.FilePID))
		if err != nil {
			return nil, classify(err)
		}
		// The item's codec and container until the file's own replace
		// them, as StreamSource reads them.
		src := flow.Source{
			Codec:      it.Codec,
			Container:  it.Container,
			DurationMS: part.DurationMS,
			SpokenWord: true,
			Path:       string(f.Path),
		}
		l.attachFile(ctx, &src, f)
		out = append(out, PlayPiece{Part: part, Src: src, File: downloadFileOf(f)})
	}
	return out, nil
}

// The bridge plays a book in parts as one stream through this.
var _ flow.PartsResolver = (*Library)(nil)

// StreamParts lays out a multi-file book for the engine's joined stream:
// every part in reading order, its source, and the rate and channel count
// the stream's one envelope is chosen from. The item is read once and each
// file once, as BookPieces reads them, and no loudness is read: a joined
// stream is not voice-boosted. Nil for anything that is not a book in
// parts.
func (l *Library) StreamParts(ctx context.Context, apiItemPID string) ([]flow.Part, error) {
	parts, err := l.BookParts(ctx, apiItemPID)
	if err != nil || len(parts) == 0 {
		return nil, err
	}
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return nil, err
	}
	out := make([]flow.Part, 0, len(parts))
	for _, part := range parts {
		f, err := l.fileByPID(ctx, model.PID(part.FilePID))
		if err != nil {
			return nil, err
		}
		// The file's own codec: whether a part is lossless sets the
		// stream's rate.
		codec, container := fileFormat(f, it.Codec, it.Container)
		out = append(out, flow.Part{
			FilePID: part.FilePID,
			Src: flow.Source{
				Path:        string(f.Path),
				Size:        f.Size,
				MTimeNS:     f.MTimeNS,
				Codec:       codec,
				Container:   container,
				BitrateKbps: f.Bitrate,
				DurationMS:  part.DurationMS,
				SpokenWord:  true,
				EssenceHash: f.EssenceHash,
			},
			Rate:     f.SampleRate,
			Channels: f.Channels,
		})
	}
	return out, nil
}

// JoinKey and JoinShape are the query flag of a book's MP3 parts joined
// as they are, and the media-token shape that binds it. The key is one
// /media/stream never binds, so a token for this join fits no URL of the
// engine's joined stream, whose shape binds join, nor that one this.
const (
	JoinKey   = "mp3join"
	JoinShape = JoinKey + "=1"
)

// JoinableMP3 reports whether a book's parts join into one stream with no
// encode: every part an MP3 file, all at one rate and one channel count,
// since a player sets its decoder up once per stream.
func JoinableMP3(parts []flow.Part) bool {
	if len(parts) < 2 {
		return false
	}
	for _, p := range parts {
		if !flow.SameAsSource(p.Src, "mp3") || p.Rate <= 0 || p.Channels <= 0 ||
			p.Rate != parts[0].Rate || p.Channels != parts[0].Channels {
			return false
		}
	}
	return true
}

// ResolvePlayPart maps a book-timeline position to the backing part.
// Single-file items (and every non-book) resolve to a zero PlayPart
// with MultiPart false.
func (l *Library) ResolvePlayPart(ctx context.Context, uc *UserCtx, apiItemPID string, positionMS int64) (PlayPart, error) {
	parts, err := l.BookParts(ctx, apiItemPID)
	if err != nil {
		return PlayPart{}, err
	}
	return PlayPartAt(parts, positionMS), nil
}

// PlayPartAt answers the part of a laid-out book whose half-open window
// holds a book-timeline position, the last for anything at or past the
// end, and the zero PlayPart for a layout of nothing.
func PlayPartAt(parts []PlayPart, positionMS int64) PlayPart {
	if len(parts) == 0 {
		return PlayPart{}
	}
	for _, part := range parts {
		if positionMS < part.StartMS+part.DurationMS {
			return part
		}
	}
	return parts[len(parts)-1]
}

// DirectPlayResolution is direct playback of original bytes, the
// no-transcoder path: the selected backing file, the duration of what
// plays, and the playback window for items carved out of a larger
// file (the client clips; nothing here rewrites audio).
type DirectPlayResolution struct {
	File        DownloadFile
	DurationMS  int64
	HasSpan     bool
	SpanStartMS int64
	SpanEndMS   int64
}

// DirectPlayInfo resolves what to serve for one item on a server
// running without the streaming engine: the original file, or the
// selected part of a multi-file book, served whole. filePID comes
// from ResolvePlayPart; empty means the item's own backing file.
func (l *Library) DirectPlayInfo(ctx context.Context, uc *UserCtx, apiItemPID, filePID string) (DirectPlayResolution, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return DirectPlayResolution{}, err
	}
	// Same contract as the engine path: there are no local bytes, so the
	// caller falls back to enclosure passthrough or reports the conflict.
	if unfetchedEpisode(it) {
		return DirectPlayResolution{}, notFetchedEpisode()
	}
	out := DirectPlayResolution{DurationMS: it.DurationMS}
	if filePID != "" {
		bd, err := l.lib.Book(ctx, it.PID)
		if err != nil {
			return DirectPlayResolution{}, classify(err)
		}
		part, ok := bookPartByFile(bd, filePID)
		if !ok {
			return DirectPlayResolution{}, errNotFound("no such part for item " + apiItemPID)
		}
		df, err := l.downloadFile(ctx, part.FilePID)
		if err != nil {
			return DirectPlayResolution{}, err
		}
		out.File = df
		out.DurationMS = part.DurationMS
		return out, nil
	}
	loc, err := l.paths.Locate(ctx, it.PID)
	if err != nil {
		return DirectPlayResolution{}, classify(err)
	}
	df, err := l.downloadFile(ctx, loc.FilePID)
	if err != nil {
		return DirectPlayResolution{}, err
	}
	out.File = df
	if it.Virtual {
		out.HasSpan = true
		out.SpanStartMS, out.SpanEndMS = spanWindow(it)
	}
	return out, nil
}

// EffectiveVoiceBoost resolves the caller's stored voice-boost setting
// for an item: the subscription setting for a podcast episode, the
// book settings for an audiobook, false elsewhere.
func (l *Library) EffectiveVoiceBoost(ctx context.Context, uc *UserCtx, apiItemPID string) bool {
	prefix, pid, ok := parseAPIPID(apiItemPID)
	if !ok {
		return false
	}
	switch prefix {
	case PrefixEpisode:
		det, err := l.lib.Podcasts().Episode(ctx, pid)
		if err != nil {
			return false
		}
		sub, err := l.db.SubscriptionFor(ctx, uc.ID, string(det.Episode.PodcastPID))
		if err != nil {
			return false
		}
		return sub.VoiceBoost != nil && *sub.VoiceBoost
	case PrefixBook, PrefixTrack:
		// Either prefix reaches a book, whose setting holds while it is
		// one; the catalog is asked only when a setting is on.
		bs, err := l.db.BookSettingsFor(ctx, uc.ID, string(pid))
		if err != nil || bs.VoiceBoost == nil || !*bs.VoiceBoost {
			return false
		}
		it, err := l.lib.Get(ctx, pid)
		return err == nil && it.Kind == model.KindBook
	}
	return false
}
