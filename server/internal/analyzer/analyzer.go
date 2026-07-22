// Package analyzer computes the waxdeck-melstat-v1 sonic embedding.
// It backs two consumers: the server's embedded analysis worker (the
// zero-setup default; the server already links WaxFlow's decoders
// through the catalog, so in-process analysis costs nothing extra to
// ship) and the standalone waxdeck-analyzer binary for installs that
// offload analysis to another machine through the worker API.
package analyzer

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/colespringer/waxflow"
	"github.com/colespringer/waxflow/container"
)

// Analyzer decodes source audio and embeds it. Construction builds the
// FFT plan and filterbank once; the scratch buffers are reused, so an
// Analyzer is NOT safe for concurrent use. Its consumers are strictly
// sequential by design (analysis is a paced background chore, never a
// hot path).
type Analyzer struct {
	engine *waxflow.Engine
	emb    *Embedder
}

// New builds an analyzer.
func New() *Analyzer {
	return &Analyzer{engine: waxflow.New(), emb: NewEmbedder()}
}

// Model names the embedding these vectors carry.
func (a *Analyzer) Model() string { return Model }

// VectorDims is the embedding dimensionality.
func (a *Analyzer) VectorDims() int { return Dims }

// AnalyzeFile decodes one source file (any codec WaxFlow knows) and
// embeds it.
func (a *Analyzer) AnalyzeFile(ctx context.Context, path string) ([]float32, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	src, err := container.FileSource(f)
	if err != nil {
		return nil, err
	}
	hint := strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")
	samples, err := a.DecodeSource(ctx, src, hint)
	if err != nil {
		return nil, err
	}
	return a.emb.Embed(samples)
}

// EmbedSamples embeds mono samples already at the analysis rate.
func (a *Analyzer) EmbedSamples(samples []float32) ([]float32, error) {
	return a.emb.Embed(samples)
}

// DecodeSource is the generic decode path: WaxFlow sniffs and decodes
// any codec it knows (the hint only breaks ties), and its DSP chain
// resamples to the analysis rate and downmixes to mono. The
// intermediate is 16-bit WAV in memory; the dither in that
// quantization is position-seeded, so the path stays deterministic.
func (a *Analyzer) DecodeSource(ctx context.Context, src container.Source, hint string) ([]float32, error) {
	dst := &memWriteSeeker{}
	if _, err := a.engine.Transcode(ctx, src, hint, dst, waxflow.TranscodeOptions{
		Format:   "wav",
		Rate:     Rate,
		Channels: 1,
		BitDepth: 16,
	}); err != nil {
		return nil, fmt.Errorf("decoding: %w", err)
	}
	samples, rate, err := ParseWAV(dst.b)
	if err != nil {
		return nil, fmt.Errorf("reading decoded WAV: %w", err)
	}
	if rate != Rate {
		return nil, fmt.Errorf("decode produced %d Hz, want %d", rate, Rate)
	}
	return samples, nil
}
