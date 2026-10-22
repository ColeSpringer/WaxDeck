package gpodder

import (
	"fmt"
	"slices"
	"strings"
	"testing"
)

// Each refused feed is a notice of its own, however many share a host:
// two dead feeds on one host are two rows, and of seven more, five are
// named and the other two counted as two; the next sync names those two.
func TestFeedsOnOneHostAreEachSaid(t *testing.T) {
	e := newEnv(t)
	dead := func(i int) string { return fmt.Sprintf("%s/gone-%d.xml", e.feed.URL, i) }
	e.change("phone", []string{dead(1), dead(2)}, nil)
	if rows := e.failedAdds(); len(rows) != 2 {
		t.Fatalf("inbox = %+v, want a row for each of the two feeds", rows)
	}
	var seven []string
	for i := 3; i <= 9; i++ {
		seven = append(seven, dead(i))
	}
	e.change("phone", seven, nil)
	rows := e.failedAdds()
	counted := 0
	for _, r := range rows {
		if strings.Contains(r.Body, "2 more feeds that were not added") {
			counted++
		}
	}
	if len(rows) != 8 || counted != 1 {
		t.Fatalf("inbox = %d rows (%+v), want two, five more and one counting the other two", len(rows), rows)
	}
	e.change("phone", seven, nil)
	if rows := e.failedAdds(); len(rows) != 10 {
		t.Fatalf("inbox after the same seven again = %d rows, want the last two named", len(rows))
	}
}

// A refused feed is said once a month whatever becomes of the inbox row
// that said it: a device naming it on every sync does not file it again
// once the account has cleared its inbox.
func TestARefusalIsSaidOnceAMonthWhateverTheInbox(t *testing.T) {
	e := newEnv(t)
	gone := e.feed.URL + "/nothing-here.xml"
	e.put("phone", "txt", gone+"\n")
	if rows := e.failedAdds(); len(rows) != 1 {
		t.Fatalf("inbox = %+v, want the refusal said", rows)
	}
	if err := e.store.ClearNotifications(e.ctx, e.uc.ID); err != nil {
		t.Fatal(err)
	}
	e.put("phone", "txt", gone+"\n")
	e.change("phone", []string{gone}, nil)
	if rows := e.failedAdds(); len(rows) != 0 {
		t.Fatalf("inbox after clearing it = %+v, want the refusal not filed again", rows)
	}
}

// An address with no host is no feed URL, whatever port or credentials it
// spells: it is answered as dropped and never parked, so no later notice
// can name it.
func TestAnAddressWithoutAHostIsRefused(t *testing.T) {
	e := newEnv(t)
	dead := deadAddress(t)
	hostless := "http://user:pw@" + dead[strings.LastIndexByte(dead, ':'):] + "/feed?token=T"
	ack := e.change("phone", []string{hostless}, nil)
	if !slices.Equal(ack.UpdateURLs, [][2]string{{hostless, ""}}) {
		t.Errorf("update_urls = %v, want the address dropped", ack.UpdateURLs)
	}
	if parks, err := e.store.GpodderParks(e.ctx, e.uc.ID); err != nil || len(parks) != 0 {
		t.Errorf("parks = %+v (%v), want none", parks, err)
	}
}
