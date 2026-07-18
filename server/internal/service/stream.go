package service

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// StreamSource resolves an API item PID to everything the WaxFlow
// bridge needs: the containing file's path and identity pin, the
// virtual-track window when the item is a CUE-backed span, and the
// source codec facts the format policy reads. It re-resolves on every
// call, which is what makes organize-moves invisible to streaming.
func (l *Library) StreamSource(ctx context.Context, apiItemPID string) (flow.Source, error) {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return flow.Source{}, err
	}
	loc, err := l.paths.Locate(ctx, it.PID)
	if err != nil {
		return flow.Source{}, classify(err)
	}
	from, to, err := loc.Span()
	if err != nil {
		return flow.Source{}, classify(err)
	}
	f, err := l.lib.File(ctx, loc.FilePID)
	if err != nil {
		return flow.Source{}, classify(err)
	}
	return flow.Source{
		Path:       loc.Path,
		Size:       f.Size,
		MTimeNS:    f.MTimeNS,
		Virtual:    loc.Virtual,
		FromSample: from,
		ToSample:   to,
		Codec:      it.Codec,
		Container:  it.Container,
		DurationMS: it.DurationMS,
	}, nil
}
