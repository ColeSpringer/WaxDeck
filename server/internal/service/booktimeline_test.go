package service

import (
	"fmt"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// marksOf is each mark as [start, end].
func marksOf(marks []ChapterMark) [][2]int64 {
	out := make([][2]int64, len(marks))
	for i, m := range marks {
		out[i] = [2]int64{m.StartMS, m.EndMS}
	}
	return out
}

// A book as the catalog reads it: parts of 4, 3 and 5 s of audio. Part
// one's last mark starts at 4.5 s, past its audio, and part two carries
// none, so the catalog places part two at 4.5 s and part three at 7.5 s,
// and fills each open end from the next mark's start, the last from its
// 12.5 s total: off the parts' own 0, 4 and 7 s.
func longMarks() *model.BookDetail {
	return &model.BookDetail{
		Files: []model.BookPart{
			{FilePID: "f1", DurationMS: 4000},
			{FilePID: "f2", DurationMS: 3000},
			{FilePID: "f3", DurationMS: 5000},
		},
		Chapters: []model.Chapter{
			{Title: "One", FilePID: "f1", StartMS: 0, EndMS: 2000, FileEndMS: 2000},
			{Title: "Two", FilePID: "f1", StartMS: 2000, EndMS: 4500, FileStartMS: 2000},
			{Title: "Coda", FilePID: "f1", StartMS: 4500, EndMS: 7500, FileStartMS: 4500},
			{Title: "Three", FilePID: "f3", StartMS: 7500, EndMS: 12500},
		},
		TotalDurationMS: 12500,
	}
}

// Every mark lands on the timeline the parts play on, held to its part's
// audio; an open end runs on to the next mark across a part with none,
// and the book ends where its last part's audio does.
func TestBookMarksSitOnThePartsOwnTimeline(t *testing.T) {
	marks, total := bookMarks(longMarks())
	want := [][2]int64{{0, 2000}, {2000, 4000}, {4000, 7000}, {7000, 12000}}
	if got := marksOf(marks); fmt.Sprint(got) != fmt.Sprint(want) || total != 12000 {
		t.Fatalf("marks %v over %d ms, want %v over 12000", got, total, want)
	}
	for _, c := range []struct {
		at   int64
		want string
	}{{0, "One"}, {3999, "Two"}, {4000, "Coda"}, {6500, "Coda"}, {7000, "Three"}, {99000, "Three"}} {
		if ch := chapterAt(marks, c.at); ch == nil || ch.Title != c.want {
			t.Errorf("at %d the chapter is %+v, want %s", c.at, ch, c.want)
		}
	}
}

// An edit made on the parts' own timeline is written on the catalog's:
// the same offset into the same part, an end at a part's end staying that
// part's, so what is written reads back where it was put.
func TestChapterEditsMapOntoTheCatalogsTimeline(t *testing.T) {
	edit := []model.Chapter{
		{Title: "One", StartMS: 0, EndMS: 4000},
		{Title: "Two", StartMS: 4000, EndMS: 7000},
		{Title: "Three", StartMS: 7000, EndMS: 12000},
	}
	got := catalogMarks(longMarks(), edit)
	want := [][2]int64{{0, 4000}, {4500, 7500}, {7500, 12500}}
	for i, ch := range got {
		if [2]int64{ch.StartMS, ch.EndMS} != want[i] {
			t.Errorf("mark %d written at [%d, %d], want %v", i, ch.StartMS, ch.EndMS, want[i])
		}
	}
}

// A part with no measured length cannot be laid out by its audio, so the
// catalog's timeline stands as it is, for reading and for writing alike.
func TestAnUnmeasuredPartKeepsTheCatalogsTimeline(t *testing.T) {
	bd := longMarks()
	bd.Files[1].DurationMS = 0
	marks, total := bookMarks(bd)
	want := [][2]int64{{0, 2000}, {2000, 4500}, {4500, 7500}, {7500, 12500}}
	if got := marksOf(marks); fmt.Sprint(got) != fmt.Sprint(want) || total != 12500 {
		t.Fatalf("marks %v over %d ms, want the catalog's %v over 12500", got, total, want)
	}
	edit := []model.Chapter{{StartMS: 1000, EndMS: 6000}}
	if got := catalogMarks(bd, edit); got[0].StartMS != 1000 || got[0].EndMS != 6000 {
		t.Fatalf("an edit was moved to [%d, %d], want it as written", got[0].StartMS, got[0].EndMS)
	}
}

// A position between two marks is still in the one before it, as the
// player names the chapter while it plays there; before the first mark
// it is the first's.
func TestAPositionBetweenChaptersIsInTheOneBefore(t *testing.T) {
	marks := []ChapterMark{
		{Index: 0, Title: "One", StartMS: 5000, EndMS: 60000},
		{Index: 1, Title: "Two", StartMS: 90000, EndMS: 120000},
	}
	for _, c := range []struct {
		at   int64
		want string
	}{{0, "One"}, {5000, "One"}, {59999, "One"}, {60000, "One"}, {75000, "One"}, {89999, "One"}, {90000, "Two"}, {150000, "Two"}} {
		if ch := chapterAt(marks, c.at); ch == nil || ch.Title != c.want {
			t.Errorf("at %d the chapter is %+v, want %s", c.at, ch, c.want)
		}
	}
}
