package fixtures

import (
	"fmt"
	"hash/fnv"
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
// Channel c carries an f*(c+1) Hz sine near -8 dBFS, the pitch and the
// level both drawn from the spec's name (toneOf), so channels are
// tellable apart, lossy encoders get real content to work on, and two
// specs named apart share their audio about once in a few hundred
// thousand pairs. Lead and trail silence are literal zero samples
// around the tone.
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
	hz, level := toneOf(s.toneSeed())
	hz = wholeCycles(hz, toneFrames, s.SampleRate)
	amp := level * 32767
	for c := 0; c < s.Channels; c++ {
		step := 2 * math.Pi * hz * float64(c+1) / float64(s.SampleRate)
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

// toneSeed names the audio a spec synthesizes: SameAudioAs, else its
// name, else its derived file name less any corruption, since flavors of
// one spec share one clean encode.
func (s Spec) toneSeed() string {
	if s.SameAudioAs != "" {
		return s.SameAudioAs
	}
	if s.Name != "" {
		return s.Name
	}
	s.Corrupt = CorruptNone
	return s.Filename()
}

// toneOf is the pitch and level a seed synthesizes: one of 4000 tenth-hertz
// steps from 300 Hz, low enough for lossy encoders to keep it and the
// harmonics other channels carry, and one of 1000 levels from -8.9 to -8
// dBFS, since wholeCycles leaves only a few hundred pitches per second of tone.
func toneOf(seed string) (hz, level float64) {
	h := fnv.New64a()
	h.Write([]byte(seed))
	sum := h.Sum64()
	return 300 + float64(sum%4000)/10, 0.36 + 0.04*float64((sum>>32)%1000)/1000
}

// wholeCycles nudges hz to the nearest pitch that fits a whole number of
// cycles into frames, so the tone ends on a zero crossing rather than in
// a click a lossy encoder smears into the silence after it.
func wholeCycles(hz float64, frames, rate int) float64 {
	secs := float64(frames) / float64(rate)
	return max(1, math.Round(hz*secs)) / secs
}
