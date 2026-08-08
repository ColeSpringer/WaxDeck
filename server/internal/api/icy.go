package api

import (
	"bytes"
	"strings"
	"unicode/utf8"
)

// icyRelay de-interleaves an ICY metadata stream: every metaint audio
// bytes the stream carries one length byte and length*16 bytes of
// metadata text. Audio runs flow to the caller, metadata blocks are
// consumed and reported, so the client hears clean audio while the
// server learns the current title.
type icyRelay struct {
	metaint   int
	audioLeft int
	metaLeft  int
	needLen   bool
	meta      []byte
}

func newICYRelay(metaint int) *icyRelay {
	return &icyRelay{metaint: metaint, audioLeft: metaint}
}

// feed walks one read's bytes, calling emit for each audio run and
// onBlock for each completed metadata block (possibly spanning feeds).
func (r *icyRelay) feed(p []byte, emit func([]byte), onBlock func([]byte)) {
	for len(p) > 0 {
		switch {
		case r.audioLeft > 0:
			n := min(r.audioLeft, len(p))
			emit(p[:n])
			r.audioLeft -= n
			p = p[n:]
			if r.audioLeft == 0 {
				r.needLen = true
			}
		case r.needLen:
			r.metaLeft = int(p[0]) * 16
			p = p[1:]
			r.needLen = false
			r.meta = r.meta[:0]
			if r.metaLeft == 0 {
				r.audioLeft = r.metaint
			}
		default:
			n := min(r.metaLeft, len(p))
			r.meta = append(r.meta, p[:n]...)
			r.metaLeft -= n
			p = p[n:]
			if r.metaLeft == 0 {
				onBlock(r.meta)
				r.audioLeft = r.metaint
			}
		}
	}
}

// icyValue reads one key's raw value out of a metadata block. ok means
// the block carried the key at all; an ok empty value is the station
// clearing it. Values may contain apostrophes, so a value ends at the
// '; pair (or the block's trailing quote), per the de facto protocol.
//
// The key has to begin a field rather than merely appear inside one.
// A block is a station's own text and stations invent keys freely, so
// an unanchored search is a station-controlled misread: `StreamUrl`
// found inside a vendor's `MyStreamUrl` hands this server a tracking
// beacon to fetch as artwork, and `insertionType` found inside anything
// makes an ordinary song look like an advertisement and drop off the
// face entirely. Scanning past a near-miss rather than giving up on it
// keeps the real field readable when a station sends both.
func icyValue(block []byte, key string) ([]byte, bool) {
	s := bytes.TrimRight(block, "\x00")
	k := []byte(key + "='")
	for off := 0; ; {
		i := bytes.Index(s[off:], k)
		if i < 0 {
			return nil, false
		}
		i += off
		if i != 0 && !icyFieldBoundary(s[i-1]) {
			off = i + 1
			continue
		}
		rest := s[i+len(k):]
		j := bytes.Index(rest, []byte("';"))
		if j < 0 {
			if len(rest) > 0 && rest[len(rest)-1] == '\'' {
				j = len(rest) - 1
			} else {
				return nil, false
			}
		}
		return rest[:j], true
	}
}

// icyFieldBoundary reports what may precede a key: the separator
// stations write between fields, the whitespace some of them pad with
// (a line break included - stations do wrap their blocks), and the NUL
// a block is padded out to its length with.
func icyFieldBoundary(c byte) bool {
	switch c {
	case ';', ' ', '\t', '\r', '\n', '\x00':
		return true
	}
	return false
}

// icyText caps a value and decodes it. Stations predating UTF-8 send
// Latin-1; invalid UTF-8 is decoded that way instead of surfacing
// replacement noise.
func icyText(raw []byte, max int) string {
	if len(raw) > max {
		raw = raw[:max]
		// The cut can land inside a multi-byte rune; dropping at most
		// a partial rune keeps a long valid-UTF-8 value out of the
		// Latin-1 fallback below.
		for i := 0; i < utf8.UTFMax-1 && len(raw) > 0 && !utf8.Valid(raw); i++ {
			raw = raw[:len(raw)-1]
		}
	}
	out := string(raw)
	if !utf8.Valid(raw) {
		var b strings.Builder
		for _, c := range raw {
			b.WriteRune(rune(c))
		}
		out = b.String()
	}
	return strings.TrimSpace(out)
}

// icyTitleMax caps an announced title. Longer than any real one, short
// enough that a station cannot spend the block on a single field.
const icyTitleMax = 300

// icyURLMax caps an announced URL. A block is at most 4080 bytes, so
// this is a sanity bound rather than a defence.
const icyURLMax = 2048

// icyStreamTitle extracts StreamTitle from a metadata block.
func icyStreamTitle(block []byte) (string, bool) {
	raw, ok := icyValue(block, "StreamTitle")
	if !ok {
		return "", false
	}
	return icyText(raw, icyTitleMax), true
}

// icyMeta is what one metadata block says.
type icyMeta struct {
	// title is the announced song, and titleOK reports the key was
	// there at all - which is what tells a block that carries no title
	// from a station clearing the one it had.
	title   string
	titleOK bool
	// artURL is the picture announced alongside the title, empty when
	// the block named none.
	artURL string
	// ad marks a block announcing a spot rather than a song.
	ad bool
}

// icyMetaOf reads everything this server wants from one block.
//
// `StreamArtwork` wins over `StreamUrl` where a station sends both: the
// second key predates anybody using it for pictures and is as often a
// homepage as a cover, so an explicit answer beats a guess. Neither is
// trusted further than a station's logo URL is - both are fetched
// through the same guarded client, capped, and sniffed.
func icyMetaOf(block []byte) icyMeta {
	meta := icyMeta{}
	meta.title, meta.titleOK = icyStreamTitle(block)
	if raw, ok := icyValue(block, "StreamArtwork"); ok {
		meta.artURL = icyText(raw, icyURLMax)
	}
	if meta.artURL == "" {
		if raw, ok := icyValue(block, "StreamUrl"); ok {
			meta.artURL = icyText(raw, icyURLMax)
		}
	}
	// The ad markers the insertion platforms set. A spot is not a song:
	// its title is an advertiser and its picture is a banner, and a
	// now-playing face is the wrong place for either. `adw_ad` carries
	// a boolean and is sent on songs too, so it is read rather than
	// merely looked for; `insertionType` is only ever sent on an
	// insertion, so its presence is the marker.
	if raw, ok := icyValue(block, "adw_ad"); ok && icyTruthy(raw) {
		meta.ad = true
	}
	if raw, ok := icyValue(block, "insertionType"); ok && icyAdInsertions[icyToken(raw)] {
		meta.ad = true
	}
	return meta
}

// icyAdInsertions are the insertionType values that name an ad break.
//
// Matched by value rather than by presence, and the asymmetry is the
// reason: the key rides ordinary programming on some platforms
// (`insertionType='live'` and house values among them), and treating any
// of it as an advertisement would take a station's titles, its announced
// artwork, and its scrobbles off the face silently for as long as it
// sent one. An unrecognised value is a song, so the worst this gets
// wrong is an advertiser's name on the face for a track - which is
// exactly what every station did before this rung existed.
var icyAdInsertions = map[string]bool{
	"preroll":    true,
	"midroll":    true,
	"postroll":   true,
	"ad":         true,
	"adbreak":    true,
	"ad_break":   true,
	"break":      true,
	"spot":       true,
	"commercial": true,
}

func icyToken(raw []byte) string {
	return strings.ToLower(string(bytes.TrimSpace(raw)))
}

func icyTruthy(raw []byte) bool {
	switch icyToken(raw) {
	case "true", "1", "yes":
		return true
	}
	return false
}
