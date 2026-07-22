package service

import (
	"strings"

	"github.com/colespringer/waxbin/model"
)

// API-surface PID prefixes. WaxBin PIDs are bare ULIDs; the type prefix
// exists only at the API boundary, where it makes identifiers
// self-describing and lets the server reject a PID used against the
// wrong entity.
const (
	PrefixTrack        = "tr"
	PrefixAlbum        = "al"
	PrefixArtist       = "ar"
	PrefixPodcast      = "pc"
	PrefixEpisode      = "ep"
	PrefixBook         = "bk"
	PrefixJob          = "jb"
	PrefixLibrary      = "lb"
	PrefixAppPassword  = "ap"
	PrefixPlaylist     = "pl"
	PrefixRadioStation = "rs"
	PrefixNotifyTarget = "nt"
	PrefixInvite       = "iv"
	PrefixBackup       = "bu"
	PrefixTrash        = "th"
	PrefixShare        = "sh"
)

// prefixForKind maps an item kind to its API prefix.
func prefixForKind(k model.Kind) string {
	switch k {
	case model.KindBook:
		return PrefixBook
	case model.KindEpisode:
		return PrefixEpisode
	default:
		return PrefixTrack
	}
}

// mediaTypeForKind maps an item kind to the API media type.
func mediaTypeForKind(k model.Kind) string {
	switch k {
	case model.KindBook:
		return "audiobook"
	case model.KindEpisode:
		return "podcast"
	default:
		return "music"
	}
}

// kindForMediaType maps an API media type to the item kind it selects.
func kindForMediaType(mt string) (model.Kind, bool) {
	switch mt {
	case "music":
		return model.KindTrack, true
	case "podcast":
		return model.KindEpisode, true
	case "audiobook":
		return model.KindBook, true
	default:
		return "", false
	}
}

// apiPID renders a bare catalog PID with its API prefix.
func apiPID(prefix string, pid model.PID) string {
	return prefix + "-" + string(pid)
}

// itemAPIPID renders an item's PID with the prefix its kind implies.
func itemAPIPID(it *model.ItemView) string {
	return apiPID(prefixForKind(it.Kind), it.PID)
}

// parseAPIPID splits an API PID into prefix and bare catalog PID. The
// ULID itself is validated; unknown prefixes are the caller's to judge.
func parseAPIPID(s string) (prefix string, pid model.PID, ok bool) {
	prefix, rest, found := strings.Cut(s, "-")
	if !found || len(prefix) != 2 {
		return "", "", false
	}
	pid = model.PID(rest)
	if !pid.Valid() {
		return "", "", false
	}
	return prefix, pid, true
}

// itemPrefix reports whether prefix names a playable item type.
func itemPrefix(prefix string) bool {
	return prefix == PrefixTrack || prefix == PrefixEpisode || prefix == PrefixBook
}
