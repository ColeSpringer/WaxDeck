package fixtures

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// ErrNeedsFFmpeg reports a spec only ffmpeg can produce when no ffmpeg
// binary is on PATH. ffmpeg is never hard-required: callers (and tests)
// match it with errors.Is and skip those specs.
var ErrNeedsFFmpeg = errors.New("fixtures: spec requires ffmpeg, which is not on PATH")

// FFmpegAvailable reports whether an ffmpeg binary is on PATH, so
// callers can filter ffmpeg-only specs up front instead of handling
// ErrNeedsFFmpeg per spec.
func FFmpegAvailable() bool {
	_, err := exec.LookPath("ffmpeg")
	return err == nil
}

// renderFFmpeg encodes the source WAV through the host ffmpeg, feeding
// it on stdin and reading the muxed result back from a scratch file.
// Bitexact flags keep the output deterministic (no encoder version
// strings, timestamps, or random Matroska UIDs).
func renderFFmpeg(wav []byte, r route) ([]byte, error) {
	bin, err := exec.LookPath("ffmpeg")
	if err != nil {
		return nil, ErrNeedsFFmpeg
	}
	out, err := runFFmpeg(bin, wav, r.ffArgs, r.ext)
	if err != nil && r.ffAlt != nil {
		if alt, altErr := runFFmpeg(bin, wav, r.ffAlt, r.ext); altErr == nil {
			return alt, nil
		}
	}
	return out, err
}

// runFFmpeg performs one ffmpeg invocation with the given codec+mux
// arguments.
func runFFmpeg(bin string, wav []byte, codecArgs []string, ext string) ([]byte, error) {
	tmp, err := os.MkdirTemp("", "waxdeck-fixtures-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)
	outPath := filepath.Join(tmp, "out."+ext)
	args := []string{
		"-hide_banner", "-nostdin", "-loglevel", "error", "-y",
		"-f", "wav", "-i", "pipe:0",
		"-map_metadata", "-1",
		"-fflags", "+bitexact", "-flags:a", "+bitexact",
	}
	args = append(args, codecArgs...)
	args = append(args, outPath)
	cmd := exec.Command(bin, args...)
	cmd.Stdin = bytes.NewReader(wav)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("fixtures: ffmpeg %v: %w: %s", codecArgs, err, bytes.TrimSpace(stderr.Bytes()))
	}
	return os.ReadFile(outPath)
}
