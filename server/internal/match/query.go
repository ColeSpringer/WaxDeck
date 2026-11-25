package match

import (
	"maps"
	"slices"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/sourcenoise"
)

// SuggestedQuery is the artist and title accept-best judges a source title
// as (judgedQuery), so a suggestion taken as is files the cut the upload
// names, where the search's wider cleaning would file it as the plain song.
// The derivation only: a typed query has no business changing a suggestion.
func SuggestedQuery(t Track) (artist, title string, ok bool) {
	artist, title = judgedQuery(t)
	if title == "" {
		return "", "", false
	}
	return artist, title, true
}

// recordingQuery builds a MusicBrainz recording search for a track: what
// somebody typed for it where they typed something, and what its tags imply
// everywhere else. title is the song alone (CoreTitle), typed or derived: a
// note, a cut mark, a version tail or a group naming the recording, often
// pre-filled from the suggestion, only keeps the phrase from matching. named
// is the title as judged, with what names the recording kept, for picking
// among the hits; "" when that is the song itself. A typed title is never
// split into an artist. ok is false when no usable title survives.
func recordingQuery(t Track) (artist, title, named string, ok bool) {
	artist, title = DerivedQuery(t)
	_, named = judgedQuery(t)
	if q := t.Query; q != nil {
		if v := strings.TrimSpace(q.Artist); v != "" {
			artist = v
		}
		if v := sourcenoise.CoreTitle(q.Title); v != "" {
			title, named = v, judgedTitle(sourcenoise.VersionTails(q.Title))
		}
	}
	if title == "" {
		return "", "", "", false
	}
	if sourcenoise.SameTitle(named, title) {
		named = ""
	}
	return artist, title, named, true
}

// DerivedQuery reads a search out of a track's tags. It targets the shape
// acquired and mislabeled files take: the descriptive title carries
// "Artist - Track", and the artist tag is often a channel or uploader rather
// than the performer.
func DerivedQuery(t Track) (artist, title string) {
	artist, title, _ = splitTags(t)
	return artist, sourcenoise.CoreTitle(title)
}

// splitTags reads the artist and the uncleaned title a track's tags imply,
// with the version tails dropped on the way, last first. An "Artist - Track"
// descriptive title overrides the artist tag: acquired content routinely tags
// the channel as the artist and packs the real performer into the title. A
// version tail ("Track - Remastered 2011") is not a track name, so it is
// dropped rather than split on, except for a VEVO uploader, which is never
// the performer: its whole title splits and nothing is dropped.
func splitTags(t Track) (artist, title string, tails []string) {
	title = strings.TrimSpace(t.Tags["TITLE"])
	artist = strings.TrimSpace(t.Tags["ARTIST"])
	if artist == "" {
		artist = strings.TrimSpace(t.Tags["ALBUMARTIST"])
	}
	head, dropped := sourcenoise.VersionTails(title)
	if a, tr, split := sourcenoise.SplitArtistTitle(head); split {
		artist, title, tails = a, tr, dropped
	} else if a, tr, split := sourcenoise.SplitArtistTitle(title); split && isVevo(artist) {
		artist, title = a, tr
	} else {
		title, tails = head, dropped
	}
	artist = sourcenoise.StripTopicSuffix(artist)
	artist = sourcenoise.StripTrailingParenthetical(artist)
	return artist, title, tails
}

// isVevo reports whether an artist tag is a VEVO channel ("AdeleVEVO").
func isVevo(artist string) bool {
	return strings.HasSuffix(strings.ToLower(artist), "vevo")
}

// judgedQuery is the artist and title accept-best judges a track as: the
// split artist, and the title as judgedTitle reads it with its dropped
// version tails.
func judgedQuery(t Track) (artist, title string) {
	artist, title, tails := splitTags(t)
	return artist, judgedTitle(title, tails)
}

// judgedTitle is a title with upload and remaster notes removed but a cut
// kept ("(Clean)", "(8D Audio)": CleanCutTitle), and each dropped version
// tail (last first) naming another recording (a live take, an edit, a demo)
// put back as a group, since accept-best judges identity and the search only
// needed to find the song. A tail's own cut follows its group ("Live (Clean)"
// reads "(Live) (Clean)"), and a tail that is the same recording but for a
// cut ("2015 Remaster (Clean)") puts back the cut alone.
func judgedTitle(title string, tails []string) string {
	title = sourcenoise.CleanCutTitle(title)
	if title == "" {
		return ""
	}
	for _, tail := range slices.Backward(tails) {
		rest, cuts := sourcenoise.SplitCutGroups(tail)
		if rest != "" && !sourcenoise.SameRecordingTail(rest) {
			title += " (" + rest + ")"
		}
		if cuts != "" {
			title += " " + cuts
		}
	}
	return title
}

// judgedTrack is t with judgedQuery's artist and title and without a DATE
// that is only its upload's (UploadDated: no evidence of a release), for
// judging a one-track unit. ok is false when that changes nothing.
func judgedTrack(t Track) (Track, bool) {
	artist, title := judgedQuery(t)
	retitled := title != "" &&
		(title != strings.TrimSpace(t.Tags["TITLE"]) || artist != strings.TrimSpace(t.Tags["ARTIST"]))
	undated := t.UploadDated && t.Tags["DATE"] != ""
	if !retitled && !undated {
		return t, false
	}
	tags := maps.Clone(t.Tags)
	if retitled {
		tags["TITLE"] = title
		if artist != "" {
			tags["ARTIST"] = artist
		}
	}
	if undated {
		delete(tags, "DATE")
	}
	t.Tags = tags
	return t, true
}
