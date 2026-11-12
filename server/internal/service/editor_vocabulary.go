package service

import (
	"github.com/colespringer/waxbin/model"
)

// editorTrackFields is the track scalar vocabulary; every track field
// has an on-disk tag form.
var editorTrackFields = []EditableFieldDTO{
	{"title", true}, {"artist", true}, {"album_artist", true}, {"album", true},
	{"composer", true}, {"composer_sort", true}, {"comment", true}, {"genre", true},
	{"year", true}, {"track_no", true}, {"track_total", true}, {"disc_no", true},
	{"disc_total", true}, {"bpm", true}, {"isrc", true}, {"mbid", true},
	{"compilation", true},
}

// editorBookFields is the book scalar vocabulary. Only the fields the
// audiobook scanner reconstructs from tags write back; the enrichment
// fields (subtitle, identifiers, publisher, edition, description, mbid)
// are database-only by upstream design.
var editorBookFields = []EditableFieldDTO{
	{"title", true}, {"author", true}, {"author_sort", true}, {"narrator", true},
	{"series", true}, {"subtitle", false}, {"genre", true}, {"year", true},
	{"asin", false}, {"isbn", false}, {"publisher", false}, {"edition", false},
	{"description", false}, {"mbid", false},
}

// editorEpisodeFields is the episode scalar vocabulary. Episodes are
// not tagged files upstream, so nothing writes back.
var editorEpisodeFields = []EditableFieldDTO{
	{"title", false}, {"description", false}, {"pinned", false}, {"season", false},
	{"episode_no", false}, {"episode_type", false}, {"explicit", false},
	{"link", false},
}

// editorMusicRoles are the track credit roles; each has a canonical tag
// key for write-back.
var editorMusicRoles = []EditableFieldDTO{
	{"composer", true}, {"lyricist", true}, {"conductor", true}, {"performer", true},
	{"remixer", true}, {"producer", true}, {"engineer", true}, {"mixer", true},
	{"arranger", true}, {"writer", true}, {"djmixer", true},
}

// editorBookRoles are the book credit roles; translator and editor have
// no round-trippable tag form and stay database-only.
var editorBookRoles = []EditableFieldDTO{
	{"author", true}, {"narrator", true}, {"translator", false}, {"editor", false},
}

// editorEntityFields is the entity edit vocabulary. Only an album's
// release identifiers, country, and sort, and an artist's sort, fan out
// to member files; entity MBIDs, release-group fields, and an album's
// media stay database-only (MEDIA is a per-medium tag, so an
// album-level fan-out would stamp one value across mixed media).
var editorEntityFields = []EntityTypeFieldsDTO{
	{EntityType: "artist", Fields: []EditableFieldDTO{{"sort", true}, {"mbid", false}}},
	{EntityType: "release-group", Fields: []EditableFieldDTO{{"sort", false}, {"mbid", false}, {"type", false}}},
	{EntityType: "album", Fields: []EditableFieldDTO{
		{"sort", true}, {"mbid", false}, {"barcode", true}, {"label", true}, {"catalog_number", true},
		{"media", false}, {"country", true},
	}},
}

// editorFieldsForKind returns the ordered scalar vocabulary for a kind.
func editorFieldsForKind(k model.Kind) []EditableFieldDTO {
	switch k {
	case model.KindBook:
		return editorBookFields
	case model.KindEpisode:
		return editorEpisodeFields
	default:
		return editorTrackFields
	}
}

// editorRolesForKind returns the credit role vocabulary for a kind.
func editorRolesForKind(k model.Kind) []EditableFieldDTO {
	switch k {
	case model.KindBook:
		return editorBookRoles
	case model.KindEpisode:
		return nil
	default:
		return editorMusicRoles
	}
}

// MetadataFieldVocabulary is the fields endpoint's payload: the scalar
// and credit vocabulary per item kind plus the entity edit vocabulary.
func (l *Editor) MetadataFieldVocabulary() MetadataFieldsDTO {
	kinds := []model.Kind{model.KindTrack, model.KindBook, model.KindEpisode}
	out := MetadataFieldsDTO{Kinds: make([]KindFieldsDTO, 0, len(kinds))}
	for _, k := range kinds {
		roles := editorRolesForKind(k)
		if roles == nil {
			roles = []EditableFieldDTO{}
		}
		out.Kinds = append(out.Kinds, KindFieldsDTO{
			Kind:        mediaTypeForKind(k),
			Fields:      editorFieldsForKind(k),
			CreditRoles: roles,
		})
	}
	out.EntityTypes = editorEntityFields
	out.ReservedTagKeys = model.ReservedTagKeys()
	return out
}
