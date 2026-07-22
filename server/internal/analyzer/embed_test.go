package analyzer

import (
	"math"
	"math/rand/v2"
	"slices"
	"testing"
)

// toneF32 synthesizes a float32 sine at the analysis rate.
func toneF32(freq float64, seconds float64) []float32 {
	n := int(seconds * Rate)
	out := make([]float32, n)
	step := 2 * math.Pi * freq / Rate
	for i := range out {
		out[i] = float32(0.5 * math.Sin(step*float64(i)))
	}
	return out
}

// texturedSignal is a deterministic tone-plus-noise mixture, richer
// than a pure sine so every stat lane carries signal.
func texturedSignal(seconds float64) []float32 {
	n := int(seconds * Rate)
	rng := rand.New(rand.NewPCG(11, 47))
	out := make([]float32, n)
	for i := range out {
		t := float64(i)
		s := 0.3*math.Sin(2*math.Pi*330/Rate*t) +
			0.2*math.Sin(2*math.Pi*1250/Rate*t) +
			0.1*(rng.Float64()*2-1)
		out[i] = float32(s)
	}
	return out
}

func cosineDistance(t *testing.T, a, b []float32) float64 {
	t.Helper()
	if len(a) != len(b) {
		t.Fatalf("length mismatch: %d vs %d", len(a), len(b))
	}
	var dot, na, nb float64
	for i := range a {
		dot += float64(a[i]) * float64(b[i])
		na += float64(a[i]) * float64(a[i])
		nb += float64(b[i]) * float64(b[i])
	}
	return 1 - dot/math.Sqrt(na*nb)
}

func TestEmbedIsDeterministic(t *testing.T) {
	sig := texturedSignal(3)
	first, err := NewEmbedder().Embed(sig)
	if err != nil {
		t.Fatalf("embed: %v", err)
	}
	second, err := NewEmbedder().Embed(sig)
	if err != nil {
		t.Fatalf("embed again: %v", err)
	}
	if len(first) != Dims {
		t.Fatalf("vector has %d dims, want %d", len(first), Dims)
	}
	if !slices.Equal(first, second) {
		t.Fatal("same audio produced different vectors")
	}
	var norm float64
	for _, v := range first {
		norm += float64(v) * float64(v)
	}
	if norm = math.Sqrt(norm); math.Abs(norm-1) > 1e-4 {
		t.Fatalf("vector norm = %v, want 1 (L2-normalized)", norm)
	}
}

func TestEmbedDiscriminatesTones(t *testing.T) {
	e := NewEmbedder()
	low, err := e.Embed(toneF32(200, 3))
	if err != nil {
		t.Fatalf("embedding 200 Hz tone: %v", err)
	}
	high, err := e.Embed(toneF32(3000, 3))
	if err != nil {
		t.Fatalf("embedding 3 kHz tone: %v", err)
	}
	if d := cosineDistance(t, low, high); d <= 0.1 {
		t.Fatalf("cosine distance between 200 Hz and 3 kHz tones = %v, want > 0.1", d)
	}
	// Sanity in the other direction: a signal against itself is at
	// distance zero (within float32 rounding).
	if d := cosineDistance(t, low, low); d > 1e-6 {
		t.Fatalf("self distance = %v, want about 0", d)
	}
}

func TestEmbedRefusesShortAndSilentInput(t *testing.T) {
	e := NewEmbedder()
	if _, err := e.Embed(toneF32(440, 1)); err == nil {
		t.Fatal("expected an error for audio under the 2 s minimum")
	}
	if _, err := e.Embed(make([]float32, 3*Rate)); err == nil {
		t.Fatal("expected an error for silence (the zero vector is rejected server-side)")
	}
}
