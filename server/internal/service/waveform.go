package service

import (
	"context"
	"encoding/binary"

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
