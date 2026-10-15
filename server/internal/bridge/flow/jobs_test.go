package flow

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/colespringer/waxflow/waxerr"
)

// A job's result lands in the mode its caller names, not the 0600 of the
// temp file it is staged in, so no caller can leave a library file only
// the server's uid can read.
func TestAJobResultLandsInTheModeItsCallerNames(t *testing.T) {
	t.Parallel()
	if runtime.GOOS == "windows" {
		t.Skip("file modes are POSIX")
	}
	dir := t.TempDir()
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/jobs/jb-result/result/0" {
			http.NotFound(w, r)
			return
		}
		fmt.Fprint(w, "merged audio")
	}, Source{Path: filepath.Join(dir, "book.m4b")})
	dst := filepath.Join(dir, "merged.m4b")
	if err := b.DownloadJobResult(context.Background(), "jb-result", 0, dst, 0o640); err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(dst)
	if err != nil {
		t.Fatal(err)
	}
	if st.Mode().Perm() != 0o640 {
		t.Fatalf("result mode = %v, want the caller's 0640", st.Mode().Perm())
	}
	if raw, err := os.ReadFile(dst); err != nil || string(raw) != "merged audio" {
		t.Fatalf("result = %q (%v), want the job's bytes", raw, err)
	}
}

// Every engine code is placed on one side on purpose, so a code a later
// WaxFlow adds fails here instead of silently reading as transient.
func TestPermanentJobErrClassifiesEveryCode(t *testing.T) {
	t.Parallel()
	permanent := map[waxerr.Code]bool{
		waxerr.CodeInvalidRequest:     true,
		waxerr.CodeUnauthorized:       true,
		waxerr.CodeSignatureInvalid:   true,
		waxerr.CodeSignatureExpired:   true,
		waxerr.CodeSourceChanged:      true,
		waxerr.CodeNotFound:           true,
		waxerr.CodeUnsupportedFormat:  true,
		waxerr.CodeUnsupportedSource:  true,
		waxerr.CodeMalformedInput:     true,
		waxerr.CodePayloadTooLarge:    true,
		waxerr.CodeSourceUnreadable:   false,
		waxerr.CodeOutputUnwritable:   false,
		waxerr.CodeOverloaded:         false,
		waxerr.CodeCanceled:           false,
		waxerr.CodeCatalogUnavailable: false,
		waxerr.CodeInternal:           false,
	}
	for _, code := range waxerr.Codes() {
		want, ok := permanent[code]
		if !ok {
			t.Errorf("%s is unclassified: does the same input always reproduce it?", code)
			continue
		}
		if got := PermanentJobErr(waxerr.New(code, "x")); got != want {
			t.Errorf("PermanentJobErr(%s) = %v, want %v", code, got, want)
		}
	}
}
