package pagetext

import (
	"reflect"
	"regexp"
	"testing"
	"time"

	"golang.org/x/text/language"
)

func TestNegotiate(t *testing.T) {
	t.Parallel()
	cases := []struct {
		header string
		want   language.Tag
	}{
		{"", language.English},
		{"es", language.Spanish},
		{"es-MX", language.Spanish},
		{"fr", language.English},
		{"de, es;q=0.8", language.Spanish},
		{"en-GB", language.English},
		{"*", language.English},
		{";;;", language.English},
		// A header the parser rejects outright still gets read as far
		// as it can be: junk after a clean first choice must not cost
		// the reader their language.
		{"es-ES,es;q=0.9,i-klingon;q=0.1", language.Spanish},
		{"es;q=high", language.Spanish},
		{"nonsense-@!,es", language.Spanish},
	}
	for _, tc := range cases {
		t.Run(tc.header, func(t *testing.T) {
			if got := Negotiate(tc.header); got != tc.want {
				t.Errorf("Negotiate(%q) = %v, want %v", tc.header, got, tc.want)
			}
		})
	}
}

func TestForFallsBackToEnglish(t *testing.T) {
	t.Parallel()
	if got := For(language.Japanese); got != &en {
		t.Errorf("For(ja) = %v, want the English table", got.Lang)
	}
	if got := For(language.Spanish); got != &es {
		t.Errorf("For(es) = %v, want the Spanish table", got.Lang)
	}
}

// For falls back to English, so a supported language whose table was
// never wired up is indistinguishable from an unsupported tag, and the
// completeness test below would pass while it rendered English to every
// reader. Hence a separate assertion, on what the table says it is.
func TestEverySupportedLanguageHasATable(t *testing.T) {
	t.Parallel()
	for _, tag := range supported {
		got := For(tag)
		if got.Lang != tag.String() {
			t.Errorf("For(%v).Lang = %q; %v is negotiable but has no table of its own", tag, got.Lang, tag)
		}
	}
}

// A field left at its zero value renders as a blank line on a page
// nobody on this side reads, so the check has to be structural.
func TestLocalesAreComplete(t *testing.T) {
	t.Parallel()
	base := reflect.ValueOf(en)
	typ := base.Type()
	for _, tag := range supported {
		loc := reflect.ValueOf(*For(tag))
		for i := range typ.NumField() {
			name := typ.Field(i).Name
			field := loc.Field(i)
			switch field.Kind() {
			case reflect.String:
				if field.String() == "" {
					t.Errorf("%v: %s is empty", tag, name)
					continue
				}
				// A dropped verb makes Sprintf render "%!s(MISSING)"
				// on a live page. Counting rather than comparing
				// positions, so a translator reordering with %[2]s
				// still passes.
				if got, want := countVerbs(field.String()), countVerbs(base.Field(i).String()); got != want {
					t.Errorf("%v: %s has %d format verbs, English has %d", tag, name, got, want)
				}
			case reflect.Func:
				if field.IsNil() {
					t.Errorf("%v: %s is nil", tag, name)
				}
			}
		}
	}
}

var verbPattern = regexp.MustCompile(`%(\[\d+\])?[a-z]`)

func countVerbs(s string) int { return len(verbPattern.FindAllString(s, -1)) }

func TestDateFormats(t *testing.T) {
	t.Parallel()
	at := time.Date(2026, time.August, 12, 15, 4, 5, 0, time.UTC)
	if got := en.FormatDate(at); got != "Aug 12, 2026" {
		t.Errorf("en date = %q, want %q", got, "Aug 12, 2026")
	}
	// CLDR's es abbreviations as intl ships them: no period, and
	// September is the four-letter one.
	if got := es.FormatDate(at); got != "12 ago 2026" {
		t.Errorf("es date = %q, want %q", got, "12 ago 2026")
	}
	sept := time.Date(2026, time.September, 1, 0, 0, 0, 0, time.UTC)
	if got := es.FormatDate(sept); got != "1 sept 2026" {
		t.Errorf("es September = %q, want %q", got, "1 sept 2026")
	}
}
