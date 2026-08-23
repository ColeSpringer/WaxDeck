package service

import (
	"testing"

	"github.com/colespringer/waxbin/model"
)

// A stored rule may hold either spelling of a field the query engine
// accepts under two names, since nothing about evaluation says which is
// canonical and an imported document carries whichever it used. Reading
// one back as anything but WaxDeck's own API name gives the rule editor
// a field it cannot draw and a later PATCH one it will refuse, so every
// alias the engine declares has to resolve here.
func TestRuleFieldsByEngineResolvesEveryEngineAlias(t *testing.T) {
	t.Parallel()

	aliases := model.QueryFieldAliases()
	if len(aliases) == 0 {
		t.Fatal("the engine declares no field aliases")
	}
	for alias, canonical := range aliases {
		canonSpec, ok := ruleFieldsByEngine[canonical]
		if !ok {
			// A field WaxDeck's vocabulary does not carry at all needs no
			// alias; only one it does carry has to answer to both names.
			continue
		}
		spec, ok := ruleFieldsByEngine[alias]
		if !ok {
			t.Errorf("engine alias %q does not resolve; %q reads back as %q",
				alias, canonical, canonSpec.api)
			continue
		}
		if spec.api != canonSpec.api {
			t.Errorf("engine alias %q resolves to %q, want %q", alias, spec.api, canonSpec.api)
		}
	}
}

// The four the engine declares today, named so a silent narrowing
// upstream is a failure here rather than a rule that stops reading back.
func TestRuleFieldsByEngineNamesTheKnownAliases(t *testing.T) {
	t.Parallel()

	for alias, wantAPI := range map[string]string{
		"albumartist": "albumArtist",
		"track":       "trackNumber",
		"disc":        "discNumber",
		"created_at":  "addedAt",
	} {
		spec, ok := ruleFieldsByEngine[alias]
		if !ok {
			t.Errorf("engine alias %q does not resolve to a rule field", alias)
			continue
		}
		if spec.api != wantAPI {
			t.Errorf("engine alias %q resolves to %q, want %q", alias, spec.api, wantAPI)
		}
	}
}
