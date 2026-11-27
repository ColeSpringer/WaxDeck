//go:build freebsd || netbsd || openbsd

package diskspace

// modernc.org/sqlite's other platforms, named rather than negated: gopls
// checks a file as the first platform its constraint allows, and for "not
// linux, darwin or windows" that is aix, where nothing importing waxbin
// builds. The server does not build on these yet either (WaxBin's
// diskfree, in docs/upstream-requests.md).

// Free reports the bytes this process may still write to the volume
// holding path, and whether the platform could answer - which here it
// does not, so every caller's check is skipped rather than guessed.
func Free(string) (int64, bool) { return 0, false }
