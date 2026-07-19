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

// icyStreamTitle extracts StreamTitle from a metadata block. ok means
// the block carried the key at all; an ok empty title is the station
// clearing it. Titles may contain apostrophes, so the value ends at
// the '; pair (or the block's trailing quote), per the de facto
// protocol. Stations predating UTF-8 send Latin-1; invalid UTF-8 is
// decoded that way instead of surfacing replacement noise.
func icyStreamTitle(block []byte) (string, bool) {
	s := bytes.TrimRight(block, "\x00")
	const key = "StreamTitle='"
	i := bytes.Index(s, []byte(key))
	if i < 0 {
		return "", false
	}
	rest := s[i+len(key):]
	j := bytes.Index(rest, []byte("';"))
	if j < 0 {
		if len(rest) > 0 && rest[len(rest)-1] == '\'' {
			j = len(rest) - 1
		} else {
			return "", false
		}
	}
	raw := rest[:j]
	if len(raw) > 300 {
		raw = raw[:300]
		// The cut can land inside a multi-byte rune; dropping at most
		// a partial rune keeps a long valid-UTF-8 title out of the
		// Latin-1 fallback below.
		for i := 0; i < utf8.UTFMax-1 && len(raw) > 0 && !utf8.Valid(raw); i++ {
			raw = raw[:len(raw)-1]
		}
	}
	title := string(raw)
	if !utf8.Valid(raw) {
		var b strings.Builder
		for _, c := range raw {
			b.WriteRune(rune(c))
		}
		title = b.String()
	}
	return strings.TrimSpace(title), true
}
