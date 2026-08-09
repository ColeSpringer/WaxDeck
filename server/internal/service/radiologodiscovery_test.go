package service

import (
	"net/url"
	"strings"
	"testing"
)

// flat is the tiers in the order radioLogoCandidates consumes them,
// minus the conventional guesses it interleaves. og trails, which is
// the ordering the budget truncation makes load-bearing.
func flat(l iconLinks) []string {
	out := append([]string{}, l.apple...)
	out = append(out, l.icons...)
	return append(out, l.og...)
}

func mustURL(t *testing.T, raw string) *url.URL {
	t.Helper()
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("parsing %q: %v", raw, err)
	}
	return u
}

func TestIconLinksIn(t *testing.T) {
	t.Parallel()
	base := mustURL(t, "https://station.example/index.html")

	t.Run("apple-touch-icon leads, og:image trails", func(t *testing.T) {
		// The order is the point. An apple-touch-icon is required to be
		// a square raster of a usable size; a favicon is routinely a
		// 16px ICO that draws as mush on a tile; og:image is the
		// sharing card and is often a wide banner.
		const page = `<html><head>
			<meta property="og:image" content="https://cdn.example/card.png">
			<link rel="shortcut icon" href="/favicon.ico">
			<link rel="apple-touch-icon" href="/touch.png">
		</head><body></body></html>`
		got := flat(iconLinksIn(strings.NewReader(page), base))
		want := []string{
			"https://station.example/touch.png",
			"https://station.example/favicon.ico",
			"https://cdn.example/card.png",
		}
		if len(got) != len(want) {
			t.Fatalf("icons = %v, want %v", got, want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("icons = %v, want %v", got, want)
			}
		}
	})

	// `rel` is a token list, so matching by substring would take
	// apple-touch-icon-precomposed as a plain icon and mis-rank it.
	t.Run("rel is matched as tokens", func(t *testing.T) {
		const page = `<html><head>
			<link rel="icon shortcut" href="/a.png">
			<link rel="preconnect" href="/not-an-icon.png">
			<link rel="iconic" href="/nope.png">
		</head></html>`
		got := flat(iconLinksIn(strings.NewReader(page), base))
		if len(got) != 1 || got[0] != "https://station.example/a.png" {
			t.Fatalf("icons = %v, want just the real icon", got)
		}
	})

	// There is nothing to fetch from a data: URI, and a candidate that
	// cannot be fetched would spend one of the small number of tries.
	t.Run("non-http references are dropped", func(t *testing.T) {
		const page = `<html><head>
			<link rel="icon" href="data:image/png;base64,iVBORw0KGgo=">
			<link rel="icon" href="//cdn.example/proto-relative.png">
		</head></html>`
		got := flat(iconLinksIn(strings.NewReader(page), base))
		if len(got) != 1 || got[0] != "https://cdn.example/proto-relative.png" {
			t.Fatalf("icons = %v, want only the protocol-relative one resolved", got)
		}
	})

	// Every declaration this reads is required to be in <head>, so the
	// body is not worth tokenizing - and an <img> in it is not an icon.
	t.Run("the body is not searched", func(t *testing.T) {
		const page = `<html><head><link rel="icon" href="/a.png"></head>
			<body><link rel="apple-touch-icon" href="/late.png"></body></html>`
		got := flat(iconLinksIn(strings.NewReader(page), base))
		if len(got) != 1 || got[0] != "https://station.example/a.png" {
			t.Fatalf("icons = %v, want only the head's icon", got)
		}
	})

	// Real station markup is not reliably well formed; a truncated read
	// must answer what it saw rather than nothing.
	t.Run("a truncated document keeps what it read", func(t *testing.T) {
		const page = `<html><head><link rel="icon" href="/a.png"><link rel="apple`
		got := flat(iconLinksIn(strings.NewReader(page), base))
		if len(got) != 1 || got[0] != "https://station.example/a.png" {
			t.Fatalf("icons = %v, want the complete declaration", got)
		}
	})
}

func TestRadioLogoCandidates(t *testing.T) {
	t.Parallel()
	l := &Library{}

	// With no homepage the stream host is the only lead there is, which
	// is the By-URL station's case.
	t.Run("stream host when there is no homepage", func(t *testing.T) {
		got := l.radioLogoCandidates(t.Context(), "", "https://ice.example/live.mp3")
		if len(got) != 1 || got[0] != "https://ice.example/favicon.ico" {
			t.Fatalf("candidates = %v", got)
		}
	})

	// A stream URL that is not fetchable proposes nothing rather than a
	// candidate that cannot be tried.
	t.Run("a non-http stream proposes nothing", func(t *testing.T) {
		if got := l.radioLogoCandidates(t.Context(), "", "rtsp://ice.example/live"); len(got) != 0 {
			t.Fatalf("candidates = %v, want none", got)
		}
	})

	t.Run("no leads at all", func(t *testing.T) {
		if got := l.radioLogoCandidates(t.Context(), "", ""); len(got) != 0 {
			t.Fatalf("candidates = %v, want none", got)
		}
	})
}

// The candidate budget truncates, so the order the tiers are *consumed*
// in decides what a station with a busy <head> actually gets tried. A
// page listing several sharing cards must not spend every slot on them
// and leave the conventional favicon unproposed.
func TestRadioLogoCandidateOrderSurvivesTheBudget(t *testing.T) {
	t.Parallel()
	declared := iconLinks{
		icons: []string{"https://station.example/icon.png"},
		og: []string{
			"https://cdn.example/card1.png",
			"https://cdn.example/card2.png",
			"https://cdn.example/card3.png",
			"https://cdn.example/card4.png",
			"https://cdn.example/card5.png",
		},
	}
	page := mustURL(t, "https://station.example/")
	stream := mustURL(t, "https://ice.example/live")
	got := orderedLogoCandidates(declared, page, stream)

	if len(got) != radioLogoCandidates {
		t.Fatalf("candidates = %v, want %d of them", got, radioLogoCandidates)
	}
	// The declared icon, then both conventional guesses, and only then
	// whatever og:image slots are left.
	want := []string{
		"https://station.example/icon.png",
		"https://station.example/favicon.ico",
		"https://ice.example/favicon.ico",
		"https://cdn.example/card1.png",
		"https://cdn.example/card2.png",
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("candidates = %v, want %v", got, want)
		}
	}
}
