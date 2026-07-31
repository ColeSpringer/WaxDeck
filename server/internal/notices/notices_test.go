package notices

import (
	"strings"
	"testing"
)

// The licensing posture: everything linked into the server binary is
// currently permissive, and this pins that state so a
// copyleft or non-free license entering the graph is a deliberate,
// reviewed decision rather than an accident (conveyance obligations and
// F-Droid eligibility change with it). The strings are the license
// texts' own opening headers, which is what keeps prose out of scope:
// GNU texts open in caps, so a title-case mention in someone's notice
// does not match, and the MPL string carries its header's "Version" so
// a dual-licensing sentence does not either. A hit means a matching
// text landed in the file; investigate the module rather than softening
// the match.
func TestNoticesArePermissiveOnly(t *testing.T) {
	for _, banned := range []string{
		"GNU GENERAL PUBLIC LICENSE",
		"GNU LESSER GENERAL PUBLIC LICENSE",
		"GNU AFFERO GENERAL PUBLIC LICENSE",
		"Mozilla Public License Version",
		"Server Side Public License",
		"Business Source License",
		"Commons Clause",
		"Creative Commons Attribution-NonCommercial",
	} {
		if strings.Contains(Text, banned) {
			t.Errorf("notices contain %q: a linked dependency is no longer permissive", banned)
		}
	}
}

func TestNoticesCoverKnownDeps(t *testing.T) {
	for _, want := range []string{
		"Go standard library and runtime",
		"Go standard library and runtime (PATENTS)",
		"modernc.org/sqlite",
		"github.com/coder/websocket",
		// The x modules ship their patent grant beside the license;
		// losing it would mean the name pattern regressed.
		"golang.org/x/sys (PATENTS)",
		// goja's float formatter carries its own notices beside the
		// module license; losing them would mean the walk regressed.
		"ftoa/LICENSE_LUCENE",
		"ftoa/internal/fast/LICENSE_V8",
	} {
		if !strings.Contains(Text, want) {
			t.Errorf("notices missing %q", want)
		}
	}
}
