package api

import (
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A profile's compilation folder round-trips in its three states: a body
// without it stores none, which the profile then omits, and an empty
// string and a name come back as sent. The preview's sample follows it.
func TestACompilationFolderRoundTripsInThreeStates(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	want := map[string]*string{"unset": nil, "own": ptr(""), "mixes": ptr("Mixes")}
	for name, folder := range want {
		body := map[string]any{}
		if folder != nil {
			body["compilationFolder"] = *folder
		}
		resp := h.putJSON(t, "/api/v1/organize/profiles/"+name, body)
		saved := decode[map[string]any](t, resp)
		got, present := saved["compilationFolder"]
		if resp.StatusCode != 200 || present != (folder != nil) || (folder != nil && got != *folder) {
			t.Fatalf("saving %s = %d %v, want the folder %v", name, resp.StatusCode, saved, folder)
		}
	}
	listed := map[string]*string{}
	for _, p := range decode[OrganizeProfiles](t, get(t, h.ts, "/api/v1/organize/profiles", h.token)).Profiles {
		listed[p.Name] = p.CompilationFolder
	}
	for name, folder := range want {
		if got := listed[name]; (got == nil) != (folder == nil) || (got != nil && *got != *folder) {
			t.Errorf("listed %s = %v, want %v", name, got, folder)
		}
	}
	if native, ok := listed["waxbin-native"]; !ok || native != nil {
		t.Errorf("the built-in lists the folder %v (listed %v), want none", native, ok)
	}

	// A save is a full replace: one without the folder clears it.
	resp := h.putJSON(t, "/api/v1/organize/profiles/mixes", map[string]any{"musicTemplate": "{title}.{ext}"})
	if saved := decode[OrganizeProfile](t, resp); resp.StatusCode != 200 || saved.CompilationFolder != nil {
		t.Errorf("a save without the folder = %d %v, want it cleared", resp.StatusCode, saved.CompilationFolder)
	}

	resp = h.postJSON(t, "/api/v1/organize/profiles/preview", map[string]any{"compilationFolder": "Mixes"})
	if sample := decode[OrganizeSample](t, resp); resp.StatusCode != 200 || !strings.HasPrefix(sample.Compilation, "Mixes/") ||
		!strings.HasPrefix(sample.Music, "Test Ensemble/") {
		t.Errorf("preview = %d %+v, want the compilation under Mixes and the track where it was", resp.StatusCode, sample)
	}
	resp = h.postJSON(t, "/api/v1/organize/profiles/preview", map[string]any{})
	if sample := decode[OrganizeSample](t, resp); !strings.HasPrefix(sample.Compilation, "Various Artists/") {
		t.Errorf("default preview = %+v, want the compilation under Various Artists", sample)
	}
	wantStatus(t, h.putJSON(t, "/api/v1/organize/profiles/dots", map[string]any{"compilationFolder": "..."}),
		400, "a folder naming none")
	wantStatus(t, h.postJSON(t, "/api/v1/organize/profiles/preview", map[string]any{"compilationFolder": strings.Repeat("x", 256)}),
		400, "an oversized folder")
}
