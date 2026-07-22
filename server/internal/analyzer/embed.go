package analyzer

// The waxdeck-melstat-v1 embedding: mel-band statistics over a short-
// time power spectrum. Not a learned model; a deterministic signal
// summary that separates timbre and texture well enough to power the
// similarity surface, computable anywhere Go runs, with no weights to
// ship. The pipeline, in order:
//
//   1. Frame the 16 kHz mono signal: window 1024, hop 512, periodic
//      Hann window.
//   2. Power spectrum per frame via the shared WaxFlow FFT kernel
//      (fixed floating-point op order, no FMA: identical output on
//      every platform).
//   3. 48 triangular mel bands spanning 20 Hz to 8 kHz, then
//      log(1 + x) compression.
//   4. Per band, over all frames: mean and standard deviation of the
//      band energy, plus mean and standard deviation of its
//      frame-to-frame delta. 48 * 4 = 192 values, laid out as
//      [means | stds | delta means | delta stds].
//   5. L2-normalize.
//
// Same audio in, bit-identical vector out: accumulation runs in
// float64 in a fixed order, and the FFT kernel pins its own op order.

import (
	"fmt"
	"math"

	"github.com/colespringer/waxflow/dsp/fft"
)

const (
	// Model names this embedding in reports; vectors of different
	// tags never compare, so any change to the math below must mint a
	// new tag.
	Model = "waxdeck-melstat-v1"
	Dims  = 192

	// Rate is the sample rate every input is decoded to; the
	// server's audio pull already serves it.
	Rate = 16000

	windowSize   = 1024
	hopSize      = 512
	melBandCount = 48
	melLoHz      = 20.0
	melHiHz      = 8000.0

	// minDurationMs is the analysis floor: shorter items carry too few
	// frames for stable statistics and are skipped.
	MinDurationMs = 2000
	minSamples    = Rate * MinDurationMs / 1000
)

// melBand holds one triangular filter as its first FFT bin plus the
// weight per consecutive bin.
type melBand struct {
	first   int
	weights []float64
}

// Embedder computes waxdeck-melstat-v1 vectors. Construction builds
// the FFT plan, the window, and the filterbank once; embed reuses the
// scratch buffers, so an Embedder is NOT safe for concurrent use. The
// worker is strictly sequential, which is exactly why.
type Embedder struct {
	plan   *fft.Plan
	window []float64
	bands  []melBand

	// Scratch reused across frames and calls.
	srcRe, srcIm []float32
	dstRe, dstIm []float32
	power        []float64
}

func hzToMel(f float64) float64 { return 2595 * math.Log10(1+f/700) }
func melToHz(m float64) float64 { return 700 * (math.Pow(10, m/2595) - 1) }

func NewEmbedder() *Embedder {
	e := &Embedder{
		plan:   fft.NewPlan(windowSize),
		window: make([]float64, windowSize),
		srcRe:  make([]float32, windowSize),
		srcIm:  make([]float32, windowSize),
		dstRe:  make([]float32, windowSize),
		dstIm:  make([]float32, windowSize),
		power:  make([]float64, windowSize/2+1),
	}
	for i := range e.window {
		// Periodic Hann, the STFT-standard form.
		e.window[i] = 0.5 - 0.5*math.Cos(2*math.Pi*float64(i)/windowSize)
	}

	// The filterbank: band b is the triangle rising from edge b to
	// edge b+1 and falling to edge b+2, with edges evenly spaced on
	// the mel scale between melLoHz and melHiHz.
	loMel, hiMel := hzToMel(melLoHz), hzToMel(melHiHz)
	edges := make([]float64, melBandCount+2)
	for i := range edges {
		edges[i] = melToHz(loMel + (hiMel-loMel)*float64(i)/float64(melBandCount+1))
	}
	binHz := float64(Rate) / windowSize
	bins := windowSize/2 + 1
	e.bands = make([]melBand, melBandCount)
	for b := range e.bands {
		fLo, fC, fHi := edges[b], edges[b+1], edges[b+2]
		band := melBand{first: -1}
		for k := 0; k < bins; k++ {
			f := float64(k) * binHz
			var w float64
			switch {
			case f <= fLo || f >= fHi:
				continue
			case f <= fC:
				w = (f - fLo) / (fC - fLo)
			default:
				w = (fHi - f) / (fHi - fC)
			}
			if band.first < 0 {
				band.first = k
			}
			band.weights = append(band.weights, w)
		}
		e.bands[b] = band
	}
	return e
}

// embed computes the 192-dim vector for mono samples at Rate.
// Inputs shorter than the analysis minimum, and inputs of pure
// silence (whose vector would be all zeros, which the server
// rejects), return an error; the caller logs and skips those items.
func (e *Embedder) Embed(samples []float32) ([]float32, error) {
	if len(samples) < minSamples {
		return nil, fmt.Errorf("%d samples is under the %d-sample (%d s) analysis minimum",
			len(samples), minSamples, MinDurationMs/1000)
	}
	frames := 1 + (len(samples)-windowSize)/hopSize

	// mel is the log-compressed band-energy matrix, frames x bands,
	// stored flat in frame-major order.
	mel := make([]float64, frames*melBandCount)
	for f := 0; f < frames; f++ {
		base := f * hopSize
		for i := 0; i < windowSize; i++ {
			e.srcRe[i] = float32(float64(samples[base+i]) * e.window[i])
			e.srcIm[i] = 0
		}
		e.plan.Transform(e.dstRe, e.dstIm, e.srcRe, e.srcIm)
		for k := range e.power {
			re, im := float64(e.dstRe[k]), float64(e.dstIm[k])
			e.power[k] = re*re + im*im
		}
		row := mel[f*melBandCount : (f+1)*melBandCount]
		for b, band := range e.bands {
			var sum float64
			for i, w := range band.weights {
				sum += w * e.power[band.first+i]
			}
			row[b] = math.Log1p(sum)
		}
	}

	// Per-band statistics. Population standard deviation via the
	// sum-of-squares identity, clamped at zero against rounding.
	vec := make([]float64, Dims)
	n := float64(frames)
	dn := float64(frames - 1) // frames >= 2 is guaranteed by minSamples
	for b := 0; b < melBandCount; b++ {
		var sum, sumSq float64
		for f := 0; f < frames; f++ {
			v := mel[f*melBandCount+b]
			sum += v
			sumSq += v * v
		}
		mean := sum / n
		vec[b] = mean
		vec[melBandCount+b] = math.Sqrt(math.Max(0, sumSq/n-mean*mean))

		var dSum, dSumSq float64
		for f := 1; f < frames; f++ {
			d := mel[f*melBandCount+b] - mel[(f-1)*melBandCount+b]
			dSum += d
			dSumSq += d * d
		}
		dMean := dSum / dn
		vec[2*melBandCount+b] = dMean
		vec[3*melBandCount+b] = math.Sqrt(math.Max(0, dSumSq/dn-dMean*dMean))
	}

	var norm float64
	for _, v := range vec {
		norm += v * v
	}
	norm = math.Sqrt(norm)
	if norm == 0 {
		return nil, fmt.Errorf("silent audio yields the zero vector, which the server rejects")
	}
	out := make([]float32, Dims)
	for i, v := range vec {
		out[i] = float32(v / norm)
	}
	return out, nil
}
