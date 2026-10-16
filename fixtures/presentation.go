package fixtures

import (
	"context"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"

	"github.com/colespringer/waxflow"
	"github.com/colespringer/waxflow/container"
	"github.com/colespringer/waxflow/container/mp4"
)

// ConformancePresentationFormats are the renderings the engine suite
// plays: Opus, what a capped or boosted stream gets, and FLAC, what a
// track carved from a lossless rip gets.
var ConformancePresentationFormats = []string{"opus", "flac"}

// ConformancePresentationDir is where the conformance preset writes the
// tone's presentation in format: beside the tone, so a harness that knows
// where the tone is finds it.
func ConformancePresentationDir(format string) string { return "conformance-hls-" + format }

// GenerateConformancePresentations writes the conformance tone into out as
// a presentation in each of ConformancePresentationFormats, cut every two
// seconds, and returns their master playlists' paths in that order.
func GenerateConformancePresentations(out string) ([]string, error) {
	var masters []string
	for _, format := range ConformancePresentationFormats {
		master, err := GeneratePresentation(filepath.Join(out, ConformancePresentationDir(format)),
			ConformanceMedia()[0], format, 2)
		if err != nil {
			return masters, err
		}
		masters = append(masters, master)
	}
	return masters, nil
}

// GeneratePresentation writes spec's tone into dir as an HLS presentation
// the way the streaming engine renders one item for a player that plays
// HLS, through the engine's own segmenter: master.m3u8 naming one variant,
// its VOD media.m3u8, an fMP4 init.mp4 and seg-<n>.m4s every segSeconds.
// format is an engine output with a segmented form ("opus" is what the
// server hands a capped or boosted stream). Returns the master's path.
func GeneratePresentation(dir string, spec Spec, format string, segSeconds float64) (string, error) {
	s := spec.withDefaults()
	wav, err := buildSourceWAV(s)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("fixtures: creating %s: %w", dir, err)
	}
	info, err := engine.Probe(container.BytesSource(wav), "wav", nil)
	if err != nil {
		return "", fmt.Errorf("fixtures: probing the tone: %w", err)
	}
	opts := waxflow.TranscodeOptions{Format: format}
	plan, err := engine.PlanSegments(info.Default(), opts, segSeconds)
	if err != nil {
		return "", fmt.Errorf("fixtures: planning %s segments: %w", format, err)
	}
	init, err := engine.InitSegment(plan, opts)
	if err != nil {
		return "", fmt.Errorf("fixtures: the init header: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "init.mp4"), init, 0o644); err != nil {
		return "", err
	}
	_, err = engine.TranscodeSegments(context.Background(), container.BytesSource(wav), "wav", opts,
		waxflow.SegmentedOptions{SegmentSamples: plan.SegmentSamples},
		func(seg mp4.Segment) error {
			return os.WriteFile(filepath.Join(dir, fmt.Sprintf("seg-%d.m4s", seg.Index)), seg.Data, 0o644)
		})
	if err != nil {
		return "", fmt.Errorf("fixtures: encoding %s segments: %w", format, err)
	}

	// The playlists as the engine writes them: each segment's presented
	// length, the decode span less the encoder's priming. The text is the
	// engine's own form, written out here because its playlist writer is
	// internal to WaxFlow (docs/upstream-requests.md).
	rate := float64(plan.Format.Rate)
	segments := plan.Segments
	var media strings.Builder
	var longest float64
	for n := range segments {
		longest = max(longest, float64(plan.PresentationDuration(n))/rate)
	}
	fmt.Fprintf(&media, "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:%d\n", int(math.Ceil(longest)))
	media.WriteString("#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-INDEPENDENT-SEGMENTS\n")
	media.WriteString("#EXT-X-MAP:URI=\"init.mp4\"\n")
	for n := range segments {
		fmt.Fprintf(&media, "#EXTINF:%.5f,\nseg-%d.m4s\n", float64(plan.PresentationDuration(n))/rate, n)
	}
	media.WriteString("#EXT-X-ENDLIST\n")
	if err := os.WriteFile(filepath.Join(dir, "media.m3u8"), []byte(media.String()), 0o644); err != nil {
		return "", err
	}
	master := fmt.Sprintf("#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n"+
		"#EXT-X-STREAM-INF:BANDWIDTH=%d,CODECS=\"%s\"\nmedia.m3u8\n", plan.Bandwidth, plan.Codecs)
	path := filepath.Join(dir, "master.m3u8")
	if err := os.WriteFile(path, []byte(master), 0o644); err != nil {
		return "", err
	}
	return path, nil
}
