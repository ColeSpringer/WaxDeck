package service

import (
	"context"
	"net/url"
	"strings"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// How readily a better cover may replace the front standing on an entity:
// a lower rank holds against a higher one.
const (
	// artRankHeld is a person's choice: a user cover, or any locked slot.
	artRankHeld = iota + 1
	// artRankRelease is a provider's cover keyed on the exact release.
	artRankRelease
	// artRankGroup is a provider's cover keyed on the release group or
	// found by name.
	artRankGroup
	// artRankFile is a file's own art on an item that is not a download.
	artRankFile
	// artRankDownload is the picture a download arrived with, such as a
	// video thumbnail.
	artRankDownload
	// artRankGenerated is composed by the server; nobody chose it.
	artRankGenerated
	// artRankNone is no art at all.
	artRankNone
)

// artSourceAcquisition is the source a read reports for a download's
// thumbnail. The catalog keeps it as the file's (tag), so a rescan cannot
// undo the label: it is derived where it is read.
const artSourceAcquisition = "acquisition"

// artRank ranks a front cover from its attribution, whether the slot is
// locked, and the source the answering item was downloaded through
// ("" for none).
func artRank(prov *model.ArtProvenance, locked bool, downloadedFrom string) int {
	if locked {
		return artRankHeld
	}
	if prov == nil {
		return artRankNone
	}
	switch prov.Source {
	case model.SourceUser:
		return artRankHeld
	case model.SourceEnrichment:
		if releaseKeyedCover(prov.Attribution) {
			return artRankRelease
		}
		return artRankGroup
	case model.SourceGenerated:
		return artRankGenerated
	case model.SourceTag:
		if downloadedFrom != "" {
			return artRankDownload
		}
	}
	return artRankFile
}

// artVacant reports whether a cover of this rank leaves the slot open to
// the enrichment cover want and the catalog's pass.
func artVacant(rank int) bool { return rank == artRankDownload || rank == artRankNone }

// releaseKeyedCover reports whether a provider's cover was fetched by the
// exact release, which only the Cover Art Archive's release front is: its
// address is .../release/<mbid>/front[-size], where a group's is
// .../release-group/<mbid>/front[-size].
func releaseKeyedCover(a model.Attribution) bool {
	if a.Provider != enrich.ProviderCoverArt {
		return false
	}
	u, err := url.Parse(a.SourceURL)
	if err != nil {
		return false
	}
	segs := strings.Split(strings.Trim(u.Path, "/"), "/")
	n := len(segs)
	return n >= 3 && segs[n-3] == "release" && strings.HasPrefix(segs[n-1], "front")
}

// frontArtRank ranks the front cover a read of ref answers with. A read
// that fails ranks as no art, the reading the enrichment guards have
// always given it.
func (l *Ingest) frontArtRank(ctx context.Context, ref model.EntityRef, locked bool) int {
	prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront)
	if err != nil {
		prov = nil
	}
	from := model.SourceType("")
	if prov != nil {
		from = l.thumbnailDownload(ctx, ref, prov.Source, string(prov.Level), prov.Derived, prov.SourceHash)
	}
	return artRank(prov, locked, string(from))
}

// thumbnailDownload is the source a front came through when it is a
// download's thumbnail: the file's own art (tag) whose bytes are the
// picture a download landed with, known by the hash recorded then. An
// item's own front is matched against its own record; an album's front
// borrowed from a member (derived), and an item's front borrowed from
// its album or group, against the members' records: exact, by hash,
// never by guessing which member answered. Empty otherwise, so a cover
// someone put in the file since is the file's own. The record is the
// fact, whatever acquisition providers run now.
func (l *Ingest) thumbnailDownload(ctx context.Context, ref model.EntityRef, src model.ProvenanceSource, level string, derived bool, hash string) model.SourceType {
	if hash == "" || src != model.SourceTag {
		return ""
	}
	switch ref.Type {
	case model.ArtAlbum, model.ArtReleaseGroup:
		if derived {
			return l.memberThumbnail(ctx, ref, hash)
		}
		return ""
	case model.ArtTrack, model.ArtEpisode:
	default:
		return ""
	}
	if derived || level != string(ref.Type) {
		it, err := l.lib.Get(ctx, ref.PID)
		if err != nil {
			return ""
		}
		for _, up := range []model.EntityRef{
			{Type: model.ArtAlbum, PID: it.AlbumPID}, {Type: model.ArtReleaseGroup, PID: it.ReleaseGroupPID},
		} {
			if up.PID == "" {
				continue
			}
			if from := l.memberThumbnail(ctx, up, hash); from != "" {
				return from
			}
		}
		return ""
	}
	landed, from, err := l.db.AcquiredArt(ctx, string(ref.PID))
	if err != nil || landed != hash {
		return ""
	}
	return model.SourceType(from)
}

// memberThumbnail is the source a member of an album or release group
// came through when this picture is the one it arrived with.
func (l *Ingest) memberThumbnail(ctx context.Context, ref model.EntityRef, hash string) model.SourceType {
	rows, err := l.db.AcquiredArtByHash(ctx, hash)
	if err != nil {
		return ""
	}
	for _, r := range rows {
		it, err := l.lib.Get(ctx, model.PID(r.ItemPID))
		if err != nil {
			continue
		}
		if (ref.Type == model.ArtAlbum && it.AlbumPID == ref.PID) ||
			(ref.Type == model.ArtReleaseGroup && it.ReleaseGroupPID == ref.PID) {
			return model.SourceType(r.SourceType)
		}
	}
	return ""
}

// recordAcquiredArt records the front a download landed with as a new
// item, under the source it came through. An item that landed with no
// picture of its own records nothing.
func (l *Ingest) recordAcquiredArt(ctx context.Context, pid model.PID, from model.SourceType) {
	if from == "" {
		return
	}
	prov, err := l.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: pid}, model.ArtRoleFront)
	if err != nil || prov.Source != model.SourceTag || prov.Level != model.ArtTrack || prov.Derived || prov.SourceHash == "" {
		return
	}
	if err := l.db.RecordAcquiredArt(ctx, string(pid), prov.SourceHash, string(from)); err != nil {
		l.log.Warn("recording a download's picture", "item", pid, "err", err)
	}
}

// downloadMark relabels a front that is a download's thumbnail as the
// acquisition source's. It carries no address: where a download came
// from is the item's acquisition record.
func (l *Ingest) downloadMark(ctx context.Context, ref model.EntityRef, hash string, out ArtSourceDTO) ArtSourceDTO {
	from := l.thumbnailDownload(ctx, ref, model.ProvenanceSource(out.Source), out.Level, out.Derived, hash)
	if from == "" {
		return out
	}
	out.Source, out.Provider, out.SourceURL = artSourceAcquisition, string(from), ""
	return out
}
