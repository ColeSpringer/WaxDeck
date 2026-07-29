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

// WaveformFor answers one item's waveform.
//
// The three states are not "found, queued, refused": they are three
// populations that all read as an absent peaks row upstream, and telling
// them apart is the whole of this function. Getting it wrong ships a
// spinner that never resolves, because a client polling `pending` has
// been told to wait for something that will never arrive.
func (l *Library) WaveformFor(ctx context.Context, uc *UserCtx, apiItemPID string) (WaveformResult, error) {
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
	// A multi-file book has one peaks row, hanging off the file the
	// catalog calls primary, which is part one. Answering it for the
	// book would draw part one's envelope under part five: the same
	// convincing wrong answer the virtual-track branch refuses, and the
	// reason the skip-map endpoint takes a partIndex. Serving this
	// honestly needs a peaks read scoped to a file rather than an item,
	// which the catalog does not expose; the ask is recorded in
	// docs/upstream-requests.md.
	if it.Kind == model.KindBook {
		bd, err := l.lib.Book(ctx, it.PID)
		if err != nil {
			return WaveformResult{}, classify(err)
		}
		if len(bd.Files) >= 2 {
			return WaveformResult{State: waveformStateUnavailable}, nil
		}
	}

	f, err := l.streamFile(ctx, it, "")
	if err != nil {
		return WaveformResult{}, err
	}
	// No essence hash means the catalog could not read the audio's
	// identity, and the analyze pass selects on that column being
	// present, so this file is never picked up and never gains peaks.
	// Pending would be a promise nothing keeps.
	if f.EssenceHash == "" {
		return WaveformResult{State: waveformStateUnavailable}, nil
	}

	pk, err := l.lib.Peaks(ctx, it.PID)
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
	if f.AnalyzedEssence == f.EssenceHash {
		return WaveformResult{State: waveformStateUnavailable, EssenceHash: f.EssenceHash}, nil
	}
	return WaveformResult{State: waveformStatePending, EssenceHash: f.EssenceHash}, nil
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
