package envflag

import (
	"flag"
	"io"
	"strings"
	"testing"
)

func newSet() (*flag.FlagSet, *Set) {
	fs := flag.NewFlagSet("t", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	return fs, New(fs)
}

// Unset or empty keeps the default, and a switch takes the spellings its
// flag's own parser takes, so 1 is on.
func TestReadsWhatItCan(t *testing.T) {
	t.Setenv("WAXDECK_T_EMPTY", "")
	t.Setenv("WAXDECK_T_MINUTES", "7")
	t.Setenv("WAXDECK_T_KEEP", "12")
	fs, env := newSet()
	unset := env.Int("unset", "WAXDECK_T_UNSET", 30, "")
	empty := env.Bool("empty", "WAXDECK_T_EMPTY", true, "")
	minutes := env.Int("minutes", "WAXDECK_T_MINUTES", 30, "")
	keep := env.Int64("keep", "WAXDECK_T_KEEP", 0, "")
	if err := fs.Parse(nil); err != nil {
		t.Fatal(err)
	}
	if *unset != 30 || !*empty || *minutes != 7 || *keep != 12 {
		t.Errorf("unset %d, empty %v, minutes %d, keep %d; want 30, true, 7, 12", *unset, *empty, *minutes, *keep)
	}
	for v, want := range map[string]bool{"true": true, "1": true, "True": true, "false": false, "0": false, "FALSE": false} {
		t.Setenv("WAXDECK_T_SWITCH", v)
		fs, env := newSet()
		got := env.Bool("switch", "WAXDECK_T_SWITCH", !want, "")
		if err := fs.Parse(nil); err != nil {
			t.Fatal(err)
		}
		if *got != want {
			t.Errorf("switch %q = %v, want %v", v, *got, want)
		}
	}
	if err := env.Err(); err != nil {
		t.Errorf("Err() = %v, want nothing refused", err)
	}
}

// A value its flag could not have taken is refused by name, rather than
// quietly becoming the default.
func TestRefusesWhatItCannotRead(t *testing.T) {
	t.Setenv("WAXDECK_T_MINUTES", "30m")
	t.Setenv("WAXDECK_T_KEEP", "all")
	t.Setenv("WAXDECK_T_SWITCH", "yes")
	fs, env := newSet()
	env.Int("minutes", "WAXDECK_T_MINUTES", 30, "")
	env.Int64("keep", "WAXDECK_T_KEEP", 0, "")
	env.Bool("switch", "WAXDECK_T_SWITCH", true, "")
	if err := fs.Parse(nil); err != nil {
		t.Fatal(err)
	}
	err := env.Err()
	for _, key := range []string{"WAXDECK_T_MINUTES", "WAXDECK_T_KEEP", "WAXDECK_T_SWITCH"} {
		if err == nil || !strings.Contains(err.Error(), key) {
			t.Errorf("Err() = %v, want it to name %s", err, key)
		}
	}
}

// A flag beats the environment, so an unreadable value the command line
// overrides is no reason to refuse.
func TestAFlagExcusesTheVariableItOverrides(t *testing.T) {
	t.Setenv("WAXDECK_T_SWITCH", "yes")
	t.Setenv("WAXDECK_T_MINUTES", "30m")
	fs, env := newSet()
	on := env.Bool("switch", "WAXDECK_T_SWITCH", false, "")
	env.Int("minutes", "WAXDECK_T_MINUTES", 30, "")
	if err := fs.Parse([]string{"-switch=true"}); err != nil {
		t.Fatal(err)
	}
	if !*on {
		t.Error("switch = false, want the command line's true")
	}
	err := env.Err()
	if err == nil || !strings.Contains(err.Error(), "WAXDECK_T_MINUTES") {
		t.Errorf("Err() = %v, want the unset flag's variable refused", err)
	}
	if err != nil && strings.Contains(err.Error(), "WAXDECK_T_SWITCH") {
		t.Errorf("Err() = %v, want the overridden variable excused", err)
	}
}
