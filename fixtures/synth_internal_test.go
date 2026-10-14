package fixtures

import (
	"bytes"
	"fmt"
	"testing"
	"time"
)

// A short tone has few whole-cycle pitches to land on, so two names can
// share one; the level differs with the name too, and the two stay
// different audio.
func TestTwoNamesOnOnePitchStillSoundApart(t *testing.T) {
	const rate, frames = 44100, 4410 // 100 ms: forty pitches in the band
	seen := map[float64]string{}
	var a, b string
	for i := 0; a == ""; i++ {
		name := fmt.Sprintf("name-%d", i)
		hz, _ := toneOf(name)
		hz = wholeCycles(hz, frames, rate)
		if other, ok := seen[hz]; ok {
			a, b = other, name
		}
		seen[hz] = name
	}
	render := func(name string) []byte {
		t.Helper()
		wav, err := buildSourceWAV(Spec{Name: name, Codec: CodecFLAC, Duration: 100 * time.Millisecond}.withDefaults())
		if err != nil {
			t.Fatal(err)
		}
		return wav
	}
	if bytes.Equal(render(a), render(b)) {
		t.Fatalf("%s and %s share a pitch and synthesized the same audio", a, b)
	}
}
