package api

import (
	"bytes"
	"encoding/binary"
	"net/http"
	"net/url"
	"sync"
	"time"
)

// The probe stream: one second of 44.1 kHz 16-bit mono silence. Every
// cast receiver and every renderer plays WAV, which is the whole
// requirement - what is being measured is whether the device can fetch
// this origin at all, so the audio is the least interesting part of it
// and silence is what a listener standing next to the speaker should
// hear from a connection check.
const (
	probeRate     = 44100
	probeChannels = 1
	probeBits     = 16
	probeSeconds  = 1
	// probePID is what a probe token binds instead of an item pid. It
	// is not a pid, and no pid parses this way, so a token minted for
	// the probe reaches the probe and nothing in anybody's library.
	probePID = "probe"
)

// mediaProbeURL builds the origin-relative tokenized probe URL. The
// marker names which of a run's candidate addresses this URL is for,
// so a request arriving here says which one the device could reach.
func mediaProbeURL(token, marker string) string {
	return "/media/probe.wav?mt=" + url.QueryEscape(token) +
		"&b=" + url.QueryEscape(marker)
}

// probeWAV renders the silence, header and all. Generated rather than
// vendored: a WAV of silence is a header and a run of zeroes, and the
// repo keeps no binary media in git.
func probeWAV() []byte {
	const blockAlign = probeChannels * probeBits / 8
	dataLen := probeRate * probeSeconds * blockAlign
	out := make([]byte, 0, 44+dataLen)
	u32 := func(v uint32) { out = binary.LittleEndian.AppendUint32(out, v) }
	u16 := func(v uint16) { out = binary.LittleEndian.AppendUint16(out, v) }

	out = append(out, "RIFF"...)
	u32(uint32(36 + dataLen))
	out = append(out, "WAVEfmt "...)
	u32(16) // the PCM format chunk's length
	u16(1)  // PCM, uncompressed
	u16(probeChannels)
	u32(probeRate)
	u32(probeRate * blockAlign) // bytes per second
	u16(blockAlign)
	u16(probeBits)
	out = append(out, "data"...)
	u32(uint32(dataLen))
	// Zeroes are silence in signed PCM, so the samples need no writing.
	return append(out, make([]byte, dataLen)...)
}

// probeFetches records which of a probe run's addresses a device
// actually fetched through.
//
// This is the evidence a device probe's verdict rests on. What a
// device says about itself is not: a cast receiver reports BUFFERING
// while it is still resolving a name it will never resolve, so a base
// that can never work would otherwise pass in a couple of hundred
// milliseconds - the exact failure the check exists to catch. A
// request that arrived here is not open to interpretation.
//
// Only a run in flight is recorded, so an old token cannot grow this.
type probeFetches struct {
	mu   sync.Mutex
	runs map[string]map[string]bool
}

func newProbeFetches() *probeFetches {
	return &probeFetches{runs: make(map[string]map[string]bool)}
}

func (p *probeFetches) begin(token string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.runs[token] = make(map[string]bool)
}

func (p *probeFetches) end(token string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	delete(p.runs, token)
}

func (p *probeFetches) mark(token, marker string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if run, ok := p.runs[token]; ok {
		run[marker] = true
	}
}

func (p *probeFetches) fetched(token, marker string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.runs[token][marker]
}

// ServeProbeAudio serves the connection-check stream under a media
// token, for the devices a device probe drives.
//
// Token-bound like every other /media route, and for the same reason:
// the consumer is a cast receiver or a renderer, which can carry no
// credential but the one in the URL. Binding it to `probe` rather than
// to a pid keeps the grant to this endpoint - a probe token opens
// nothing in the library - and keeps the endpoint out of reach of an
// unauthenticated LAN peer, who would otherwise have found a free
// second of silence to fetch in a loop.
//
// Served through ServeContent rather than written whole: devices HEAD
// before they GET and routinely ask for a range, and several refuse a
// 200 that does not advertise ranges at all. A probe the device turns
// down over its response shape would be reported as an address it
// could not reach.
func (s *Server) ServeProbeAudio(w http.ResponseWriter, r *http.Request) {
	if s.media == nil {
		writeError(w, http.StatusNotImplemented, "internal", "media tokens are not configured on this server")
		return
	}
	q := r.URL.Query()
	token := q.Get("mt")
	if _, err := s.media.Verify(token, probePID); err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
		return
	}
	// Recorded before the bytes go out, and on a HEAD too: the device
	// reached this server through this address, which is the whole
	// question. A range request for the tail counts the same.
	s.probes.mark(token, q.Get("b"))
	w.Header().Set("Content-Type", "audio/wav")
	// The URL carries its own credential and lives for minutes; there
	// is nothing here an intermediary should keep a copy of.
	w.Header().Set("Cache-Control", "no-store")
	http.ServeContent(w, r, "probe.wav", time.Time{}, bytes.NewReader(probeWAV()))
}
