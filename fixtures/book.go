package fixtures

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Audiobook fixtures. WaxBin classifies a file as a book when its
// extension is .m4b, its iTunes media kind is audiobook (stik=2), or it
// carries a narrator credit; the extension is the one signal a
// synthesized fixture can rely on, so every part below is generated as
// MP4/AAC and renamed to .m4b. Parts group into one book by their
// identity key (album + album-artist), and order by track number.

// bookAuthor and bookTitle name the multi-file fixture book.
const (
	bookAuthor = "Ada Author"
	bookTitle  = "The Fixture Book"
)

// chapteredBookTitle names the single-file chaptered fixture book.
const chapteredBookTitle = "The Chaptered Fixture"

// GenerateM4B renders one MP4/AAC spec into dir and renames the result
// to the .m4b extension that classifies it as an audiobook. Exported
// for the tests whose subject is a book's own tags - a series name, a
// narrator credit - which the two named books below do not carry.
func GenerateM4B(dir string, spec Spec) (string, error) {
	spec.Codec = CodecAAC
	spec.Container = ContainerMP4
	paths, err := Generate(dir, spec)
	if err != nil {
		return "", err
	}
	m4b := strings.TrimSuffix(paths[0], filepath.Ext(paths[0])) + ".m4b"
	if err := os.Rename(paths[0], m4b); err != nil {
		return "", fmt.Errorf("fixtures: renaming to m4b: %w", err)
	}
	return m4b, nil
}

// GenerateBook writes a three-part audiobook under dir using the
// conventional Author/Title layout: "Ada Author/The Fixture Book"
// holding parts "01 - Part One.m4b" through "03 - Part Three.m4b". The
// parts share ALBUM and ALBUMARTIST and carry track numbers, so a
// WaxBin scan groups them into one book item with three files in
// reading order. Tone durations are distinct per part so fingerprint
// dedup cannot merge them. It returns the book's directory.
func GenerateBook(dir string) (string, error) {
	bookDir := filepath.Join(dir, bookAuthor, bookTitle)
	parts := []struct {
		file  string
		title string
		track string
		tone  time.Duration
	}{
		{"01 - Part One", "Part One", "1", 4 * time.Second},
		{"02 - Part Two", "Part Two", "2", 5 * time.Second},
		{"03 - Part Three", "Part Three", "3", 6 * time.Second},
	}
	for _, p := range parts {
		spec := Spec{
			Name:     p.file,
			Duration: p.tone,
			Tags: map[string]string{
				"TITLE":       p.title,
				"ALBUM":       bookTitle,
				"ARTIST":      bookAuthor,
				"ALBUMARTIST": bookAuthor,
				"TRACKNUMBER": p.track,
			},
		}
		if _, err := GenerateM4B(bookDir, spec); err != nil {
			return "", fmt.Errorf("fixtures: book part %s: %w", p.file, err)
		}
	}
	return bookDir, nil
}

// GenerateChapteredBook writes a single-file audiobook into dir: one
// .m4b whose MP4 container embeds three chapter markers, with book tags
// (album is the book title, album-artist the author). The tone duration
// differs from every GenerateBook part so the two books never share an
// essence. It returns the file's path.
func GenerateChapteredBook(dir string) (string, error) {
	spec := Spec{
		Name:     chapteredBookTitle,
		Duration: 7 * time.Second,
		Tags: map[string]string{
			"TITLE":       chapteredBookTitle,
			"ALBUM":       chapteredBookTitle,
			"ARTIST":      bookAuthor,
			"ALBUMARTIST": bookAuthor,
		},
		Chapters: []Chapter{
			{Start: 0, End: 2 * time.Second, Title: "Opening"},
			{Start: 2 * time.Second, End: 4500 * time.Millisecond, Title: "Middle"},
			{Start: 4500 * time.Millisecond, End: 7 * time.Second, Title: "Ending"},
		},
	}
	path, err := GenerateM4B(dir, spec)
	if err != nil {
		return "", fmt.Errorf("fixtures: chaptered book: %w", err)
	}
	return path, nil
}

// seriesNarrator credits the series fixture's books, which is also what
// classifies them: see GenerateSeriesBooks.
const seriesNarrator = "Vale Reader"

// GenerateSeriesBooks writes n single-file audiobooks under dir, all
// tagged into one series and numbered 1..n. It returns their paths in
// that order.
//
// FLAC rather than the .m4b every other book fixture uses, and a
// narrator credit rather than the extension: the sequence rides on
// GROUPING as "<series> #<n>" - the spelling the tag reader splits back
// into a name and a sequence, and the only way to carry one, since no
// editor writes a sequence - and the MP4 muxer has no atom for that
// key. A Vorbis comment block takes the key it is given, and a narrator
// credit is a book signal in its own right. Tone durations step per
// book so fingerprint dedup cannot merge them.
func GenerateSeriesBooks(dir, series string, n int) ([]string, error) {
	if n <= 0 {
		return nil, fmt.Errorf("fixtures: series needs at least one book")
	}
	seriesDir := filepath.Join(dir, bookAuthor, series)
	paths := make([]string, 0, n)
	for i := 1; i <= n; i++ {
		title := fmt.Sprintf("%s Book %d", series, i)
		made, err := Generate(seriesDir, Spec{
			Name:      title,
			Codec:     CodecFLAC,
			Container: ContainerFLAC,
			// Distinct per book and short: 1s, 1.5s, 2s, ...
			Duration: time.Duration(i+1) * 500 * time.Millisecond,
			Tags: map[string]string{
				"TITLE":       title,
				"ALBUM":       title,
				"ARTIST":      bookAuthor,
				"ALBUMARTIST": bookAuthor,
				"NARRATOR":    seriesNarrator,
				"GROUPING":    fmt.Sprintf("%s #%d", series, i),
			},
		})
		if err != nil {
			return nil, fmt.Errorf("fixtures: series book %d: %w", i, err)
		}
		paths = append(paths, made[0])
	}
	return paths, nil
}
