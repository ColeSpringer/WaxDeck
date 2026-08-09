package service

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"

	"github.com/colespringer/waxbin/model"
)

// Waveform overviews: the amplitude envelope a seek bar paints behind
// itself. Unlike skip maps, which queue their own analysis on a miss,
// this is a pure read. The producer is the catalog's analyze pass, and
// a miss here means that pass has not covered the item yet.

// WaveformResult is the waveform endpoint's answer.
type WaveformResult struct {
	State       string
	EssenceHash string
	// PartIndex echoes the described part, multi-file books only, so a
	// client can tell a part answer from a whole-item one.
	PartIndex *int
	// Version is the stored peaks format/algorithm revision. It scopes
	// the endpoint's validator: re-analysis under a bumped version
	// rewrites the peaks for audio whose essence never changed, so the
	// essence hash alone would let a client hold superseded values for
	// the whole cache lifetime.
	Version    int
	Resolution int
	Peaks      []byte
}

const (
	waveformStateReady       = "ready"
	waveformStatePending     = "pending"
	waveformStateUnavailable = "unavailable"
)

// WaveformFor answers one item's waveform. partIndex selects a
// multi-file book's part (ignored elsewhere), exactly as SkipMapFor
// takes it.
//
// The three states are not "found, queued, refused": they are three
// populations that all read as an absent peaks row upstream, and telling
// them apart is the whole of this function. Getting it wrong ships a
// spinner that never resolves, because a client polling `pending` has
// been told to wait for something that will never arrive.
func (l *Library) WaveformFor(ctx context.Context, uc *UserCtx, apiItemPID string, partIndex int) (WaveformResult, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return WaveformResult{}, err
	}
	// A cue-carved track shares one backing file with the rest of its
	// album, and the peaks row hangs off that file. Serving it would
	// draw the whole album's envelope under track three's seek bar: a
	// convincing wrong answer, which is worse than no answer. Windowing
	// the stored buckets by the track's sample span is the richer fix
	// and costs effective resolution; it belongs with the standing
	// "virtual tracks are not sonically analyzed" gap, not here.
	if it.Virtual {
		return WaveformResult{State: waveformStateUnavailable}, nil
	}
	// Podcast episodes are excluded from analysis upstream, by design:
	// fingerprinting hours of speech would pollute the duplicate-
	// detection min-hash. So an episode is never analyzed and this is
	// permanent, not pending.
	if it.Kind == model.KindEpisode {
		return WaveformResult{State: waveformStateUnavailable}, nil
	}
	// Each part has its own peaks row. Reading through the item answers
	// the primary's, and the primary is not part one - it is whichever
	// part was attached first.
	filePID, partOut, err := l.resolvePart(ctx, it, partIndex)
	if err != nil {
		return WaveformResult{}, err
	}

	f, err := l.streamFile(ctx, it, filePID)
	if err != nil {
		return WaveformResult{}, err
	}
	// No essence hash means the catalog could not read the audio's
	// identity, and the analyze pass selects on that column being
	// present, so this file is never picked up and never gains peaks.
	// Pending would be a promise nothing keeps.
	if f.EssenceHash == "" {
		return WaveformResult{State: waveformStateUnavailable, PartIndex: partOut}, nil
	}

	// A track and a single-file book have one file, so the item read is
	// the same row and stays the simpler call.
	var pk *model.PeaksData
	if filePID != "" {
		pk, err = l.lib.PeaksForFile(ctx, model.PID(filePID))
	} else {
		pk, err = l.lib.Peaks(ctx, it.PID)
	}
	if err == nil && pk != nil && pk.Buckets > 0 && len(pk.Data) >= pk.Buckets*2 {
		return WaveformResult{
			State: waveformStateReady,
			// Peaks come back with no essence hash of their own: the
			// upstream read selects version, bucket count, and data only.
			// The file view is the source for it, and it is the same
			// value the row was keyed on, since the read joins the two.
			EssenceHash: f.EssenceHash,
			Version:     pk.Version,
			Resolution:  pk.Buckets,
			Peaks:       narrowPeaks(pk.Data, pk.Buckets),
			PartIndex:   partOut,
		}, nil
	}
	if err != nil && kindFromWaxErr(err) != KindNotFound {
		return WaveformResult{}, classify(err)
	}

	// No peaks row. Whether that is pending or permanent is decided by
	// the file's analysis stamp, never by the missing row: the pass
	// stamps a file even when loudness and peaks could not be measured
	// (a damaged tail past the fingerprinted head, say), storing the
	// fingerprint so the file still groups. A stamped file never
	// re-enters the pass's work list, so it will not gain peaks until
	// its audio changes, and reporting it as pending would spin forever.
	//
	// The stamp's algorithm-version half is upstream's own composite and
	// is not readable from here, so a version bump leaves an old stamp
	// reading unavailable until the next pass re-analyzes the file and
	// writes peaks. That resolves itself, and the alternative (reading a
	// stale stamp as pending) is the failure this whole branch exists to
	// avoid.
	//
	// The stamp is the requested part's file, so a partly analyzed book
	// reads ready for some parts and pending for others.
	if f.AnalyzedEssence == f.EssenceHash {
		return WaveformResult{State: waveformStateUnavailable, EssenceHash: f.EssenceHash, PartIndex: partOut}, nil
	}
	return WaveformResult{State: waveformStatePending, EssenceHash: f.EssenceHash, PartIndex: partOut}, nil
}

// WaveformForItem answers one envelope over a whole item: a book's
// parts stitched in reading order into the shape a single file answers
// with.
//
// Server-side rather than client-side because the stitch is
// duration-weighted arithmetic over every part, and doing it in the
// client would mean N requests, N cache entries, N validators, and the
// same weighting written again in Dart. `PeaksForItem` reads every
// part's envelope in one call, which is what makes this cheap here and
// expensive anywhere else.
func (l *Library) WaveformForItem(ctx context.Context, uc *UserCtx, apiItemPID string) (WaveformResult, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return WaveformResult{}, err
	}
	// The two populations with no envelope of their own answer the same
	// under either span: a window of a shared file, and audio the pass
	// deliberately never reads.
	if it.Virtual || it.Kind == model.KindEpisode {
		return WaveformResult{State: waveformStateUnavailable}, nil
	}
	parts, err := l.itemParts(ctx, it)
	if err != nil {
		return WaveformResult{}, err
	}
	// One file is one envelope: the whole item IS the part, so this is
	// the answer the default span already gives.
	if len(parts) < 2 {
		return l.WaveformFor(ctx, uc, apiItemPID, 0)
	}

	stored, err := l.lib.PeaksForItem(ctx, it.PID)
	if err != nil && kindFromWaxErr(err) != KindNotFound {
		return WaveformResult{}, classify(err)
	}
	byFile := make(map[string]model.PeaksData, len(stored))
	for _, p := range stored {
		if p.Peaks.Buckets > 0 && len(p.Peaks.Data) >= p.Peaks.Buckets*2 {
			byFile[string(p.FilePID)] = p.Peaks
		}
	}

	// All parts or nothing. A book missing one part's envelope has no
	// honest whole-book answer: stitching around the gap would draw
	// silence over minutes of audio, and a listener would seek into it.
	// Which non-ready state it is comes from the missing parts' own
	// analysis stamps, exactly as the per-part path decides it.
	var (
		version     int
		essence     []string
		totalMS     int64
		unavailable bool
		pending     bool
	)
	for _, part := range parts {
		totalMS += part.DurationMS
		pk, ok := byFile[string(part.FilePID)]
		if ok && pk.Version > version {
			version = pk.Version
		}
		f, ferr := l.fileByPID(ctx, part.FilePID)
		if ferr != nil {
			return WaveformResult{}, ferr
		}
		essence = append(essence, f.EssenceHash)
		// A part with no duration has no span on a timeline whose
		// parts are placed by duration, so its audio cannot be drawn at
		// all - and the whole-book envelope would come out as if that
		// part were not in the book, which is the same silent lie a
		// missing envelope would be. So it answers the same way rather
		// than being skipped. The duration column is nullable and read
		// as zero, so this is a state to refuse rather than one to
		// assume away.
		if part.DurationMS <= 0 {
			unavailable = true
			continue
		}
		if ok {
			continue
		}
		// Same reading as the per-part path: an unreadable essence or a
		// file the pass has already stamped will never gain peaks, and
		// calling that pending is a promise nothing keeps.
		if f.EssenceHash == "" || f.AnalyzedEssence == f.EssenceHash {
			unavailable = true
		} else {
			pending = true
		}
	}
	switch {
	case unavailable:
		return WaveformResult{State: waveformStateUnavailable}, nil
	case pending:
		return WaveformResult{State: waveformStatePending}, nil
	case totalMS <= 0:
		// Durations are what the parts are weighted by; without them
		// there is no timeline to spread buckets across.
		return WaveformResult{State: waveformStateUnavailable}, nil
	}

	buckets := wholeItemBuckets(totalMS)
	stitched := stitchPeaks(parts, byFile, totalMS, buckets)
	return WaveformResult{
		State:       waveformStateReady,
		EssenceHash: wholeItemValidator(parts, essence, buckets),
		Version:     version,
		Resolution:  buckets,
		Peaks:       stitched,
	}, nil
}

// wholeItemValidator digests everything the stitched bytes are built
// from: each part's essence in reading order, each part's duration, and
// the bucket count the total resolves to.
//
// The durations are not decoration. They are what each part's span on
// the timeline is computed from, and what the resolution is chosen
// from, so a rescan that corrects a lying VBR header rewrites every
// bucket while leaving essence and analysis version untouched - a
// client holding the old bytes under a day of freshness and a week of
// stale-while-revalidate would draw an envelope that no longer lines up
// with the seek positions under it.
//
// Digested rather than joined, because the join is unusable at the
// length that matters: a shipping audiobook runs to a hundred parts and
// an essence digest is some seventy characters, so the validator would
// be kilobytes - past the header buffers reverse proxies ship with by
// default, in both directions, which turns every conditional request
// into an error instead of the 304 it exists to earn.
func wholeItemValidator(parts []model.BookPart, essence []string, buckets int) string {
	sum := sha256.New()
	for i, part := range parts {
		fmt.Fprintf(sum, "%d\x00%s\x00%d\n", i, essence[i], part.DurationMS)
	}
	fmt.Fprintf(sum, "buckets\x00%d", buckets)
	// Half a SHA-256 is 128 bits of collision resistance against an
	// accident, which is all a cache validator is defending against.
	return hex.EncodeToString(sum.Sum(nil)[:16])
}

// itemParts lists a book's backing files in reading order. Anything
// else has no parts, which is what makes the whole-item span the same
// answer as the default one for it.
func (l *Library) itemParts(ctx context.Context, it *model.ItemView) ([]model.BookPart, error) {
	if it.Kind != model.KindBook {
		return nil, nil
	}
	bd, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		return nil, classify(err)
	}
	return bd.Files, nil
}

// wholeItemBuckets picks the resolution a whole-item envelope is drawn
// at: roughly one bucket per ten seconds, clamped.
//
// Fixed at 1000 like a track's, a twenty-hour book would give a
// three-minute chapter three bars, which is a line rather than a shape.
// The ceiling is what keeps the response a few kilobytes. Both ends are
// free to move: `resolution` is read rather than assumed on both sides
// of the wire, so this is a rendering choice and not a contract.
func wholeItemBuckets(totalMS int64) int {
	const (
		floor  = 1000
		cap    = 4000
		perSec = 10
	)
	want := int(totalMS / 1000 / perSec)
	if want < floor {
		return floor
	}
	if want > cap {
		return cap
	}
	return want
}

// stitchPeaks lays every part's envelope onto one timeline.
//
// Each bucket covers an equal slice of the whole duration, so a part
// occupies bucket-space in proportion to its length, and each output
// bucket takes the loudest input bucket overlapping it. Loudest-wins is
// truthful here because the stored values are absolute full-scale
// amplitude with no per-file normalisation anywhere in the pipeline: a
// quiet part stays honestly quiet beside a loud one, which is the whole
// reason a whole-book envelope is worth drawing.
//
// Done in the stored 16-bit domain and narrowed once at the end, so the
// maximum is taken at full precision rather than after the wire's
// rounding.
func stitchPeaks(parts []model.BookPart, byFile map[string]model.PeaksData, totalMS int64, buckets int) []byte {
	out := make([]uint16, buckets)
	var elapsedMS int64
	for _, part := range parts {
		pk := byFile[string(part.FilePID)]
		start := elapsedMS
		elapsedMS += part.DurationMS
		if part.DurationMS <= 0 || pk.Buckets == 0 {
			continue
		}
		// The output range this part owns, right-open so a boundary
		// bucket belongs to the part that starts in it and no sample is
		// counted twice.
		from := int(start * int64(buckets) / totalMS)
		to := int(elapsedMS * int64(buckets) / totalMS)
		if to > buckets {
			to = buckets
		}
		if to <= from {
			// A part shorter than one bucket still gets the bucket it
			// falls in: dropping it would silence real audio.
			to = from + 1
			if to > buckets {
				continue
			}
		}
		span := to - from
		for i := from; i < to; i++ {
			// The input buckets this output bucket covers.
			lo := (i - from) * pk.Buckets / span
			hi := (i - from + 1) * pk.Buckets / span
			if hi <= lo {
				hi = lo + 1
			}
			if hi > pk.Buckets {
				hi = pk.Buckets
			}
			var peak uint16
			for b := lo; b < hi; b++ {
				if v := binary.LittleEndian.Uint16(pk.Data[b*2:]); v > peak {
					peak = v
				}
			}
			if peak > out[i] {
				out[i] = peak
			}
		}
	}
	wire := make([]byte, buckets)
	for i, v := range out {
		wire[i] = byte(v >> 8)
	}
	return wire
}

// narrowPeaks converts the stored little-endian uint16 buckets to the
// bytes the wire carries. A waveform is drawn a few hundred pixels wide
// at most, so the low byte is below the resolution of anything that
// renders it, and dropping it halves the response.
func narrowPeaks(data []byte, buckets int) []byte {
	out := make([]byte, buckets)
	for i := range buckets {
		out[i] = byte(binary.LittleEndian.Uint16(data[i*2:]) >> 8)
	}
	return out
}
