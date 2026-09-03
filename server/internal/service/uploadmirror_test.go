package service

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// The client keeps its own copy of the accepted-format set, and it is
// not decoration: the pickers filter against the health payload's set
// once one has been read, and against this constant until then - which
// on the web is routine, because the file dialog has to open inside the
// tap's user-activation budget and cannot wait on a request. A stale
// mirror silently drops files the server would have taken, and offers
// ones it refuses.
//
// Pinned from this side because this is where the set is authored. The
// Dart constant is read as text rather than compiled, which is enough:
// what can drift is its contents, not its shape.
func TestClientAcceptedFormatMirrorMatchesTheDefaultSet(t *testing.T) {
	t.Parallel()
	path := filepath.Join("..", "..", "..", "app", "app", "lib", "src", "uploads", "file_picker_port.dart")
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading the client mirror: %v", err)
	}
	const opens = "const kAcceptedAudioExtensions = {"
	_, after, found := strings.Cut(string(src), opens)
	if !found {
		t.Fatalf("%s no longer declares %s; this guard is reading the wrong thing", path, opens)
	}
	body, _, found := strings.Cut(after, "}")
	if !found {
		t.Fatalf("%s: the mirror's declaration does not close", path)
	}
	mirror := regexp.MustCompile(`'([^']+)'`).FindAllStringSubmatch(body, -1)
	got := make([]string, 0, len(mirror))
	for _, m := range mirror {
		got = append(got, m[1])
	}
	slices.Sort(got)

	def := &Library{}
	def.setUploadFormats(nil)
	want := def.UploadFormats()
	if !slices.Equal(got, want) {
		t.Errorf("the client mirror and the server default have drifted\n mirror: %v\n server: %v",
			got, want)
	}
}
