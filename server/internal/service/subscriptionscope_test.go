package service

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/query"
)

// The subscription scope is one `in` predicate now rather than an OR arm
// per show. Three properties ride on that and none of them is visible
// from the call site, so pin them here.
func TestSubscribedEpisodeScope(t *testing.T) {
	t.Parallel()
	unrestricted := &UserCtx{Explicit: true}

	t.Run("one in predicate, whatever the arity", func(t *testing.T) {
		for _, shows := range [][]string{
			{"pc-one"},
			{"pc-one", "pc-two", "pc-three"},
		} {
			q := subscribedEpisodeScope(unrestricted, shows).Build()
			conds := condsOn(t, q, "podcast_pid")
			if len(conds) != 1 {
				t.Fatalf("%d shows compiled to %d podcast_pid conditions, want 1", len(shows), len(conds))
			}
			if conds[0].Op != query.OpIn {
				t.Errorf("podcast_pid op = %q, want %q", conds[0].Op, query.OpIn)
			}
			if len(conds[0].Values) != len(shows) {
				t.Errorf("in-set holds %d values, want %d", len(conds[0].Values), len(shows))
			}
		}
	})

	// A follower of no shows must get nothing, not everything. Upstream
	// compiles an empty set to 1=0, which is the whole reason the caller
	// needs no guard of its own.
	t.Run("an empty subscription set matches nothing", func(t *testing.T) {
		q := subscribedEpisodeScope(unrestricted, nil).Build()
		conds := condsOn(t, q, "podcast_pid")
		if len(conds) != 1 || conds[0].Op != query.OpIn {
			t.Fatalf("empty scope did not compile to one `in`: %+v", conds)
		}
		if len(conds[0].Values) != 0 {
			t.Errorf("empty scope carries %d values, want none", len(conds[0].Values))
		}
	})

	// The compiled scope feeds cursor validity, so a caller's scope has to
	// compile to the same string every time. The sort is the caller's job
	// (SubscribedEpisodes sorts before building); this pins that the
	// builder preserves the order it is handed rather than reordering it.
	t.Run("order is preserved so the scope is stable", func(t *testing.T) {
		shows := []string{"pc-aaa", "pc-bbb", "pc-ccc"}
		first := scopeJSON(t, subscribedEpisodeScope(unrestricted, shows).Build())
		second := scopeJSON(t, subscribedEpisodeScope(unrestricted, shows).Build())
		if first != second {
			t.Fatalf("same input compiled two ways:\n%s\n%s", first, second)
		}
		if strings.Index(first, "pc-aaa") > strings.Index(first, "pc-ccc") {
			t.Errorf("scope reordered its show set: %s", first)
		}
	})

	// A restricted caller gets both advisory predicates; an unrestricted
	// one gets neither.
	t.Run("the advisory predicates follow the caller", func(t *testing.T) {
		restricted := scopeJSON(t, subscribedEpisodeScope(&UserCtx{Explicit: false}, []string{"pc-one"}).Build())
		for _, field := range []string{"explicit", "podcast_explicit"} {
			if !strings.Contains(restricted, field) {
				t.Errorf("restricted scope drops %q: %s", field, restricted)
			}
		}
		open := scopeJSON(t, subscribedEpisodeScope(unrestricted, []string{"pc-one"}).Build())
		if strings.Contains(open, "podcast_explicit") {
			t.Errorf("unrestricted scope carries an advisory predicate: %s", open)
		}
	})
}

// condsOn pulls every top-level condition naming field out of a built
// query, through its JSON form so the test does not depend on the
// builder's internal node shape.
func condsOn(t *testing.T, q query.Query, field string) []query.Cond {
	t.Helper()
	var out []query.Cond
	var walk func(any)
	walk = func(n any) {
		switch v := n.(type) {
		case map[string]any:
			if v["field"] == field {
				raw, err := json.Marshal(v)
				if err != nil {
					t.Fatal(err)
				}
				var c query.Cond
				if err := json.Unmarshal(raw, &c); err != nil {
					t.Fatal(err)
				}
				out = append(out, c)
			}
			for _, child := range v {
				walk(child)
			}
		case []any:
			for _, child := range v {
				walk(child)
			}
		}
	}
	var tree any
	if err := json.Unmarshal([]byte(scopeJSON(t, q)), &tree); err != nil {
		t.Fatal(err)
	}
	walk(tree)
	return out
}

func scopeJSON(t *testing.T, q query.Query) string {
	t.Helper()
	raw, err := json.Marshal(q)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}
