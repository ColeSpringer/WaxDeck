// Command corpusgen synthesizes a large catalog corpus for performance
// gates: real audio files, each carrying a cue sheet that carves it
// into first-class virtual tracks at scan. A hundred thousand items
// need only a thousand small files this way, and every item exercises
// the same query, pagination, and location machinery real rips do.
//
//	corpusgen -out /tmp/corpus -items 100000
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

func main() {
	out := flag.String("out", "corpus", "output directory")
	items := flag.Int("items", 100000, "total virtual tracks to produce")
	perFile := flag.Int("perfile", 100, "tracks per audio file")
	flag.Parse()

	if err := run(*out, *items, *perFile); err != nil {
		fmt.Fprintln(os.Stderr, "corpusgen:", err)
		os.Exit(1)
	}
}

func run(out string, items, perFile int) error {
	if perFile < 1 || perFile > 100 {
		return fmt.Errorf("perfile must be 1..100 (tracks must start inside the audio)")
	}
	files := (items + perFile - 1) / perFile
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}
	genres := []string{"Rock", "Jazz", "Ambient", "Folk", "Electronic", "Classical", "Blues", "Soul"}
	start := time.Now()
	made := 0
	for f := 0; f < files; f++ {
		name := fmt.Sprintf("album%05d", f)
		// Distinct durations keep essences distinct, so fingerprint
		// dedup never merges corpus files into one item.
		dur := 3000*time.Millisecond + time.Duration(f%1000)*time.Millisecond
		if _, err := fixtures.Generate(out, fixtures.Spec{
			Name:     name,
			Codec:    fixtures.CodecFLAC,
			Duration: dur,
		}); err != nil {
			return fmt.Errorf("file %d: %w", f, err)
		}
		n := min(perFile, items-made)
		if err := writeCue(filepath.Join(out, name+".cue"), name+".flac", f, n, genres); err != nil {
			return err
		}
		made += n
		if f%100 == 99 {
			fmt.Printf("corpusgen: %d/%d files (%d items) in %s\n", f+1, files, made, time.Since(start).Round(time.Second))
		}
	}
	fmt.Printf("corpusgen: wrote %d files carrying %d items in %s\n", files, made, time.Since(start).Round(time.Second))
	return nil
}

// writeCue writes an album cue: n tracks starting every two cue frames
// (all inside the first ~2.7 seconds of audio, which every corpus file
// has). Titles and performers are distinct across the corpus so search
// and grouping behave like a real library.
func writeCue(path, audioName string, album, n int, genres []string) error {
	var b []byte
	b = fmt.Appendf(b, "PERFORMER %q\n", fmt.Sprintf("Corpus Artist %03d", album%977))
	b = fmt.Appendf(b, "TITLE %q\n", fmt.Sprintf("Corpus Album %05d", album))
	b = fmt.Appendf(b, "REM GENRE %q\n", genres[album%len(genres)])
	b = fmt.Appendf(b, "FILE %q WAVE\n", audioName)
	for t := 1; t <= n; t++ {
		frame := (t - 1) * 2
		b = fmt.Appendf(b, "  TRACK %02d AUDIO\n", t)
		b = fmt.Appendf(b, "    TITLE %q\n", fmt.Sprintf("Corpus Track %05d-%03d", album, t))
		b = fmt.Appendf(b, "    INDEX 01 00:%02d:%02d\n", frame/75, frame%75)
	}
	return os.WriteFile(path, b, 0o644)
}
