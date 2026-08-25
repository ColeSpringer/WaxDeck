package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

func TestHardcoverBridgesAnASINToTheISBN(t *testing.T) {
	t.Parallel()
	var gotAuth string
	var gotASIN string
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		var req struct {
			Variables struct {
				ASIN string `json:"asin"`
			} `json:"variables"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Errorf("decoding the GraphQL body: %v", err)
		}
		gotASIN = req.Variables.ASIN
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"data":{"editions":[{"isbn_13":"9780306406157","isbn_10":"0306406152",
			"release_date":"2014-06-17","publisher":{"name":"Bridge House"}}]}}`)
	}))
	defer srv.Close()
	h := NewHardcover(HardcoverConfig{
		BaseURL: srv.URL, Token: "hc-token", HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	cand, err := h.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, ASIN: "B000002L5R"})
	if err != nil {
		t.Fatal(err)
	}
	if gotAuth != "Bearer hc-token" {
		t.Errorf("Authorization = %q, want the bearer token", gotAuth)
	}
	if gotASIN != "B000002L5R" {
		t.Errorf("queried ASIN = %q", gotASIN)
	}
	if cand == nil || cand.ISBN != "9780306406157" {
		t.Fatalf("candidate = %+v, want the ISBN-13 preferred", cand)
	}
	if cand.Publisher != "Bridge House" || cand.Fields["year"] != "2014" {
		t.Errorf("candidate = %+v, want publisher and year filled", cand)
	}
}

func TestHardcoverSurfacesGraphQLErrorsAndSkipsWithoutAToken(t *testing.T) {
	t.Parallel()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		// GraphQL reports failure in-band with a 200.
		fmt.Fprint(w, `{"errors":[{"message":"invalid token"}]}`)
	}))
	defer srv.Close()
	h := NewHardcover(HardcoverConfig{
		BaseURL: srv.URL, Token: "revoked", HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	if _, err := h.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, ASIN: "B0"}); err == nil {
		t.Error("an in-band GraphQL error was read as a clean miss")
	}

	keyless := NewHardcover(HardcoverConfig{BaseURL: "https://never-dialed.invalid"})
	if cand, err := keyless.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, ASIN: "B0"}); cand != nil || err != nil {
		t.Errorf("keyless Enrich = %+v, %v; want a silent miss", cand, err)
	}
}

func TestGoogleBooksKeysOnISBNAndGatesTextSearches(t *testing.T) {
	t.Parallel()
	var lastQuery string
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		lastQuery = r.URL.Query().Get("q")
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"items":[
			{"volumeInfo":{"title":"A Different Book","authors":["Somebody Else"],
				"publisher":"Wrong House","publishedDate":"1999",
				"industryIdentifiers":[{"type":"ISBN_13","identifier":"9999999999999"}]}},
			{"volumeInfo":{"title":"project  hail mary","authors":["Andy Weir"],
				"publisher":"Ballantine","publishedDate":"2021-05-04",
				"description":"<p>An astronaut wakes alone.</p>",
				"industryIdentifiers":[{"type":"ISBN_13","identifier":"978-0-593-13520-4"}]}}]}`)
	}))
	defer srv.Close()
	g := NewGoogleBooks(GoogleBooksConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	// An ISBN request queries by the (normalized) identifier, and only
	// believes a volume that actually carries it - the search can answer
	// related volumes around the edition it was asked for.
	cand, err := g.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, ISBN: "978-0593135204"})
	if err != nil {
		t.Fatal(err)
	}
	if lastQuery != "isbn:9780593135204" {
		t.Errorf("ISBN query = %q, want the hyphens folded", lastQuery)
	}
	if cand == nil || cand.Fields["publisher"] != "Ballantine" {
		t.Fatalf("ISBN candidate = %+v, want the volume carrying the identifier", cand)
	}
	if cand.ISBN != "" {
		t.Errorf("an ISBN-keyed hit proposed an ISBN back: %q", cand.ISBN)
	}

	// A text request must earn its hit with both names, and its hit
	// bridges its own edition's ISBN. The description is tag-stripped.
	cand, err = g.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetBook, Title: "Project Hail Mary", Artist: "Andy Weir",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.ISBN != "978-0-593-13520-4" {
		t.Fatalf("text candidate = %+v, want the name-gated hit's ISBN", cand)
	}
	if cand.Fields["publisher"] != "Ballantine" || cand.Fields["year"] != "2021" {
		t.Errorf("text candidate fields = %+v", cand.Fields)
	}
	if cand.Fields["description"] != "An astronaut wakes alone." {
		t.Errorf("description = %q, want the markup stripped", cand.Fields["description"])
	}
}

// TestAudnexusScopedBookAskSkipsTheCover: no consumer of a TargetBook
// candidate reads its cover today, so a book-metadata-scoped ask must
// not download one per book.
func TestAudnexusScopedBookAskSkipsTheCover(t *testing.T) {
	t.Parallel()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/books/B000002L5R":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"publisherName":"Bridge House","releaseDate":"2014-06-17T00:00:00.000Z",
				"image":"https://%s/cover.png"}`, r.Host)
		case "/cover.png":
			t.Error("a book-scoped ask fetched the cover image")
			w.WriteHeader(http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	a := NewAudnexus(AudnexusConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	cand, err := a.EnrichScoped(context.Background(), enrich.Request{
		Type: enrich.TargetBook, ASIN: "B000002L5R",
	}, enrich.CapBookMeta)
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Publisher != "Bridge House" {
		t.Fatalf("scoped candidate = %+v, want the metadata", cand)
	}
	if cand.Cover != nil {
		t.Error("a book-scoped candidate carries a cover")
	}
}

func TestOpenLibraryReadsEditionsAndSearchesByName(t *testing.T) {
	t.Parallel()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/isbn/9780593135204.json":
			fmt.Fprint(w, `{"publishers":["Ballantine"],"publish_date":"2021-05-04"}`)
		case "/search.json":
			fmt.Fprint(w, `{"docs":[
				{"title":"Project Hail Mary the Companion","author_name":["Andy Weir"],"first_publish_year":2022},
				{"title":"Project Hail Mary","author_name":["Andy Weir"],"first_publish_year":2021}]}`)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	o := NewOpenLibrary(OpenLibraryConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	// A hyphenated stored ISBN still reads the edition (the path takes
	// the normalized form), and the ISO-shaped publish date still
	// yields its year.
	cand, err := o.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, ISBN: "978-0-593-13520-4"})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Publisher != "Ballantine" || cand.Fields["year"] != "2021" {
		t.Fatalf("edition candidate = %+v", cand)
	}

	// The name search answers the exact title's year and, deliberately,
	// no ISBN: a work-level hit's isbn array is every edition of the
	// book in no defined order, and an arbitrary member written into
	// the item's durable ISBN would key later lookups to the wrong
	// edition.
	cand, err = o.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetBook, Title: "Project Hail Mary", Artist: "Andy Weir",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Fields["year"] != "2021" {
		t.Fatalf("search candidate = %+v, want the exact title's year", cand)
	}
	if cand.ISBN != "" {
		t.Errorf("search candidate proposed ISBN %q from the work-level union", cand.ISBN)
	}
}
