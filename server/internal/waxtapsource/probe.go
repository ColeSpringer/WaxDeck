package waxtapsource

import (
	"context"
	"errors"

	waxtap "github.com/colespringer/waxtap/v3"
	"github.com/colespringer/waxtap/v3/youtube"

	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// Probe decides what a link names from the link alone, as WaxTap's own
// command line does, then asks YouTube about it: a video's basic info, or a
// list's first entry. A link with a video id is the video unless
// wantPlaylist asks for the list it also names. The target carries the
// shape even when the question fails, so a caller that queues anyway knows
// the path to take. A link that is not a video, playlist or channel is
// refused before anything is asked.
func (p *Provider) Probe(ctx context.Context, url string, wantPlaylist bool) (syncsource.AcquireTarget, error) {
	shape, err := linkShape(url, wantPlaylist)
	if err != nil {
		return syncsource.AcquireTarget{}, err
	}
	target := syncsource.AcquireTarget{Shape: shape}
	if shape == syncsource.ShapeVideo {
		v, err := p.tap.Info(ctx, url, waxtap.InfoBasic)
		if err != nil {
			return target, sourceErr(ctx, "waxtapsource.Probe", err)
		}
		target.Title = v.Title
		return target, nil
	}
	pl, err := p.tap.Enumerate(ctx, url, waxtap.EnumerateOptions{MaxItems: 1})
	if err != nil {
		return target, sourceErr(ctx, "waxtapsource.Probe", err)
	}
	target.Title = pl.Title
	return target, nil
}

// LinkShape decides what a link names without the network, refusing one
// that is not a video, playlist or channel.
func (p *Provider) LinkShape(url string, wantPlaylist bool) (string, error) {
	return linkShape(url, wantPlaylist)
}

// linkShape classifies a link without the network.
func linkShape(url string, wantPlaylist bool) (string, error) {
	_, videoErr := youtube.ExtractVideoID(url)
	_, listErr := youtube.ExtractPlaylistID(url)
	switch {
	case videoErr == nil && wantPlaylist && listErr == nil:
		return syncsource.ShapePlaylist, nil
	case videoErr == nil:
		return syncsource.ShapeVideo, nil
	case errors.Is(videoErr, waxtap.ErrIsPlaylist):
		// Only a YouTube link without a video answers this, so the
		// playlist id read off a foreign host's list= never gets here.
		return syncsource.ShapePlaylist, nil
	}
	if _, chErr := youtube.ExtractChannelRef(url); chErr == nil {
		return syncsource.ShapeChannel, nil
	}
	return "", &syncsource.Refusal{Reason: syncsource.ReasonUnsupportedURL, Err: videoErr}
}

// notAVideo reports a fetch's refusal of a link that names no single
// video, which WaxTap answers before any request.
func notAVideo(err error) bool {
	for _, s := range []error{waxtap.ErrIsPlaylist, waxtap.ErrIsChannel, waxtap.ErrInvalidVideoID,
		waxtap.ErrVideoIDTooShort, waxtap.ErrVideoIDTooLong} {
		if errors.Is(err, s) {
			return true
		}
	}
	return false
}
