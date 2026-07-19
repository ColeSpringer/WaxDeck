package fixtures

import (
	"fmt"
	"math"
	"time"

	"github.com/colespringer/waxflow/audio"
	"github.com/colespringer/waxflow/codec"
	"github.com/colespringer/waxflow/codec/pcm"
	"github.com/colespringer/waxflow/container"
	"github.com/colespringer/waxflow/container/riff"
)

// buildSourceWAV synthesizes the spec's deterministic tone as an
// in-memory 16-bit WAV: the one source every encode route starts from.
// Channel c carries a 440*(c+1) Hz sine at -8 dBFS, so channels are
// tellable apart and lossy encoders get real content to work on. Lead
// and trail silence are literal zero samples around the tone.
func buildSourceWAV(s Spec) ([]byte, error) {
	toneFrames := int(s.Duration * time.Duration(s.SampleRate) / time.Second)
	if toneFrames < 1 {
		return nil, fmt.Errorf("fixtures: %v at %d Hz synthesizes no frames", s.Duration, s.SampleRate)
	}
	leadFrames := int(s.LeadSilence * time.Duration(s.SampleRate) / time.Second)
	trailFrames := int(s.TrailSilence * time.Duration(s.SampleRate) / time.Second)
	frames := leadFrames + toneFrames + trailFrames
	f := audio.Format{
		Rate:     s.SampleRate,
		Channels: s.Channels,
		Layout:   audio.DefaultLayout(s.Channels),
		Type:     audio.Int,
		BitDepth: 16,
	}
	buf := audio.Get(f, frames)
	defer audio.Put(buf)
	buf.N = frames
	const amp = 0.4 * 32767 // about -8 dBFS
	for c := 0; c < s.Channels; c++ {
		step := 2 * math.Pi * 440 * float64(c+1) / float64(s.SampleRate)
		ch := buf.ChanI(c)
		// Pooled buffers arrive dirty, so the silent stretches are
		// zeroed explicitly rather than assumed.
		for i := 0; i < leadFrames; i++ {
			ch[i] = 0
		}
		for i := 0; i < toneFrames; i++ {
			ch[leadFrames+i] = int32(math.Round(amp * math.Sin(step*float64(i))))
		}
		for i := leadFrames + toneFrames; i < frames; i++ {
			ch[i] = 0
		}
	}

	cfg := pcm.Config{Encoding: pcm.SignedInt, Bits: 16}
	enc, err := pcm.NewEncoder(cfg, f)
	if err != nil {
		return nil, err
	}
	ws := &memWriteSeeker{}
	mux := riff.NewMuxer(ws, nil)
	track := container.Track{
		Codec:       codec.PCM,
		CodecConfig: enc.CodecConfig(),
		Fmt:         f,
		Samples:     int64(frames),
		Default:     true,
	}
	if err := mux.Begin([]container.Track{track}); err != nil {
		return nil, err
	}
	emit := func(p codec.Packet) error {
		return mux.WritePacket(container.Packet{Track: 0, Packet: p})
	}
	if err := enc.Encode(buf, emit); err != nil {
		return nil, err
	}
	trailer, err := enc.Finish(emit)
	if err != nil {
		return nil, err
	}
	if err := mux.End(trailer); err != nil {
		return nil, err
	}
	return ws.b, nil
}
