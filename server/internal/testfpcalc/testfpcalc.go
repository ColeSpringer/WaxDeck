// Package testfpcalc writes stand-ins for the fpcalc binary, for tests
// of the paths that fingerprint files.
package testfpcalc

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// DecodeNote is what fpcalc prints for a damaged frame.
const DecodeNote = "ERROR: Error decoding audio frame (End of file)"

// Write returns the path of an executable that ignores its arguments,
// prints stdout and stderr, and exits with code. It is a shell script, so
// the test is skipped on Windows. The executable is written by a child
// process, so a concurrent fork in the test process cannot inherit its
// write descriptor and make exec fail with ETXTBSY.
func Write(t testing.TB, stdout, stderr string, code int) string {
	t.Helper()
	bin, _ := write(t, stdout, stderr, code)
	return bin
}

// WriteLogging is Write for a stand-in that also appends each run's
// arguments, a line per run, to the file it returns second.
func WriteLogging(t testing.TB, stdout, stderr string, code int) (bin, calls string) {
	t.Helper()
	return write(t, stdout, stderr, code)
}

// WriteOverlapping is WriteLogging for a stand-in that takes a moment
// over each run and logs its start and end as lines of their own, which
// Overlapped reads. No lock decides it: a lock taken through a shell tool
// is only as exclusive as that tool makes it, and uutils mkdir lets two
// racing runs both through.
func WriteOverlapping(t testing.TB, stdout string) (bin, calls string) {
	t.Helper()
	return writeScript(t, stdout, "", 0, func(_, calls string) string {
		return fmt.Sprintf("echo start >> '%[1]s'\nsleep 0.5\necho end >> '%[1]s'\n", calls)
	})
}

// Overlapped reports whether a WriteOverlapping log holds a run that
// started while another was still going.
func Overlapped(log string) bool {
	running := 0
	for line := range strings.SplitSeq(log, "\n") {
		switch line {
		case "start":
			if running > 0 {
				return true
			}
			running++
		case "end":
			running--
		}
	}
	return false
}

// WriteHanging returns a stand-in that never finishes on its own. It
// becomes the sleep, so killing it ends the run at once.
func WriteHanging(t testing.TB) string {
	t.Helper()
	bin, _ := writeScript(t, "", "", 0, func(_, _ string) string { return "exec sleep 60\n" })
	return bin
}

func write(t testing.TB, stdout, stderr string, code int) (string, string) {
	t.Helper()
	return writeScript(t, stdout, stderr, code, nil)
}

// writeScript writes the stand-in, with body's lines, given the
// script's own folder and calls file, run before it prints.
func writeScript(t testing.TB, stdout, stderr string, code int, body func(dir, calls string) string) (string, string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("the fpcalc stand-in is a shell script")
	}
	dir := t.TempDir()
	for name, body := range map[string]string{"out": stdout, "err": stderr} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	bin := filepath.Join(dir, "fpcalc")
	calls := filepath.Join(dir, "calls")
	extra := ""
	if body != nil {
		extra = body(dir, calls)
	}
	script := fmt.Sprintf("#!/bin/sh\necho \"$*\" >> '%s'\n%scat '%s/out'\ncat '%s/err' >&2\nexit %d\n", calls, extra, dir, dir, code)
	cmd := exec.Command("/bin/sh", "-c", `cat > "$1" && chmod 755 "$1"`, "testfpcalc", bin)
	cmd.Stdin = strings.NewReader(script)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("write fpcalc stand-in: %v: %s", err, out)
	}
	return bin, calls
}

// Compressed is fpcalc -json output holding a compressed fingerprint of
// n values, for a file of the given seconds: 948 values cover the 120
// seconds fpcalc reads by default, 300 about 40.
func Compressed(seconds float64, n int) string {
	fp := base64.RawURLEncoding.EncodeToString([]byte{1, byte(n >> 16), byte(n >> 8), byte(n), 0x5a, 0xc3})
	return fmt.Sprintf(`{"duration": %.2f, "fingerprint": "%s"}`, seconds, fp)
}
