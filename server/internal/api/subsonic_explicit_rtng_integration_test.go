package api

import (
	"context"
	"net/url"
	"testing"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
)

// The advisory on the other side of the tag surface: an MP4 whose own
// rtng atom says explicit, with no API tag write anywhere. The tag
// library projects rtng as ITUNESADVISORY now, which is what makes a
// file ripped or bought as explicit answer the OpenSubsonic advisory
// without anyone re-tagging it through WaxDeck.
//
// The atom is written here rather than by the fixture generator because
// the encoder does not write rtng; waxlabel's editor does, which is
// also how every other on-disk tag edit in the server happens.
func TestSubsonicExplicitStatusFromTheRtngAtom(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)

	// Its own album, so the album-level any-member assertion below is
	// about this file and not the demo release. A duration distinct
	// from every other preset, for the fingerprint-dedup reason
	// DemoLibrary gives.
	paths, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "advisory", Codec: fixtures.CodecAAC, Container: fixtures.ContainerMP4,
		Duration: 4300 * time.Millisecond,
		Tags: map[string]string{
			"TITLE": "Parental Advisory", "ARTIST": "Redacted Lyric",
			"ALBUMARTIST": "Redacted Lyric", "ALBUM": "Sticker Album",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	doc, err := waxlabel.ParseFile(context.Background(), paths[0])
	if err != nil {
		t.Fatal(err)
	}
	plan, err := doc.Edit().Set(tag.ITunesAdvisory, "1").Prepare()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := plan.Execute(context.Background(), waxlabel.SaveBack()); err != nil {
		t.Fatalf("writing the rtng atom: %v", err)
	}
	h.rescanAndWait(t)

	var pid, albumID string
	for _, it := range h.items(t, "").Items {
		if it.Title == "Parental Advisory" {
			pid = it.Pid
			if it.AlbumPid != nil {
				albumID = *it.AlbumPid
			}
		}
	}
	if pid == "" || albumID == "" {
		t.Fatalf("the advisory fixture did not scan: item=%q album=%q", pid, albumID)
	}

	// The facts sweep is cached against the change-feed position and a
	// background consumer advances it, so poll rather than race; the
	// response struct is declared inside the loop so an omitempty field
	// cannot survive from a prior round.
	deadline := time.Now().Add(30 * time.Second)
	for {
		var album struct {
			Status string `json:"status"`
			Album  struct {
				ExplicitStatus string `json:"explicitStatus"`
				Songs          []struct {
					ID             string `json:"id"`
					ExplicitStatus string `json:"explicitStatus"`
				} `json:"song"`
			} `json:"album"`
		}
		subsonicJSON(t, h, "getAlbum", secret, "&id="+url.QueryEscape(albumID), &album)
		if album.Status != "ok" {
			t.Fatalf("getAlbum envelope status = %q", album.Status)
		}
		got := ""
		for _, s := range album.Album.Songs {
			if s.ID == pid {
				got = s.ExplicitStatus
			}
		}
		if got == "explicit" {
			if album.Album.ExplicitStatus != "explicit" {
				t.Errorf("album advisory = %q, want explicit", album.Album.ExplicitStatus)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("a file whose rtng atom says explicit never reported it: %q", got)
		}
		time.Sleep(50 * time.Millisecond)
	}

	// The projection lands as the scan-read custom tag the facts sweep
	// queries, which is what the advisory above was answered from -
	// nothing in this test wrote it through the tag endpoint. Asserting
	// it here is what separates "the atom was read" from "the demo
	// library happened to answer explicit".
	advisory := ""
	for _, ct := range h.itemMeta(t, pid).CustomTags {
		if ct.Key == "ITUNESADVISORY" && len(ct.Values) > 0 {
			advisory = ct.Values[0]
		}
	}
	if advisory != "1" {
		t.Errorf("ITUNESADVISORY read off the file = %q, want 1", advisory)
	}
}
