package flow

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/url"
	"slices"
	"strconv"

	"github.com/colespringer/waxflow/client"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// One item's encode as an HLS presentation, for a player that seeks HLS
// itself and cannot seek a live encode: ExoPlayer restarts an unranged
// stream from its head on any seek. The engine signs the master, which
// stays in the timeline stash under the rendering's key; the client gets
// a /media/hls URL under a token that names the item, so every fetch
// re-checks it as a stream's does, and binds the rendering, which every
// child names again in its own descriptor. Fetches share the listener's
// one HLS slot with their timelines.

// hlsMimeType is the media type of an HLS playlist.
const hlsMimeType = "application/vnd.apple.mpegurl"

// itemKeyPrefix keeps a rendering's stash key apart from a timeline's,
// which starts with a digest far longer than this.
const itemKeyPrefix = "it/"

func itemKey(rendering string) string { return itemKeyPrefix + rendering }

// itemShape is the token shape that binds a rendering: its key, so a
// token opens that rendering's playlists and segments and no other's;
// the purpose keeps it off every other route.
func itemShape(rendering string) string { return url.Values{"it": {rendering}}.Encode() }

// descriptor is an engine HLS descriptor, a v parameter: base64url JSON,
// covered by the URL's signature, holding everything that decides what
// plays. It names one source's encode, or a timeline's digest (Tl).
type descriptor struct {
	Src      string  `json:"src"`
	ID       string  `json:"id"`
	Tl       string  `json:"tl"`
	Format   string  `json:"format"`
	Bitrate  int     `json:"bitrate"`
	HEv2     bool    `json:"hev2"`
	Bits     int     `json:"bits"`
	Rate     int     `json:"rate"`
	Ch       int     `json:"ch"`
	Gain     string  `json:"gain"`
	Dynamics string  `json:"dynamics"`
	SegDur   float64 `json:"segDur"`
	From     int64   `json:"from"`
	To       int64   `json:"to"`
}

// decodeDescriptor reads a v parameter; false, and the zero descriptor,
// when it is none.
func decodeDescriptor(v string) (descriptor, bool) {
	raw, err := base64.RawURLEncoding.DecodeString(v)
	if err != nil {
		return descriptor{}, false
	}
	var d descriptor
	if json.Unmarshal(raw, &d) != nil {
		return descriptor{}, false
	}
	return d, true
}

// rendering answers the key of the one-source rendering d names: a digest
// of everything in it that decides what plays. A one-rung master and every
// child it lists carry the same values. Empty for a timeline's descriptor
// or none.
func (d descriptor) rendering() string {
	if d.Src == "" || d.Tl != "" {
		return ""
	}
	canonical, err := json.Marshal(d)
	if err != nil {
		return ""
	}
	sum := sha256.Sum256(canonical)
	return base64.RawURLEncoding.EncodeToString(sum[:16])
}

// itemRendering answers the rendering key of a v parameter, false for a
// timeline's descriptor or anything else.
func itemRendering(v string) (string, bool) {
	d, _ := decodeDescriptor(v)
	key := d.rendering()
	return key, key != ""
}

// stashedDescriptor answers the descriptor of the signed master stashed
// under key, the zero one where nothing is.
func (b *Bridge) stashedDescriptor(key string) descriptor {
	ts := b.timelines()
	ts.mu.Lock()
	st := ts.stash[key]
	ts.mu.Unlock()
	u, err := url.Parse(st.signedMaster)
	if err != nil {
		return descriptor{}
	}
	d, _ := decodeDescriptor(u.Query().Get("v"))
	return d
}

// ceilingDropped reports whether a rendering's encode, d, is lossy at a
// rate the account's live ceiling no longer allows: above it, or the
// engine's own where a ceiling now applies. A lossless one plays out, as
// a lossless stream started before a ceiling does.
func (b *Bridge) ceilingDropped(ctx context.Context, user string, d descriptor) bool {
	if b.gate == nil || !lossyBitrateFormats[d.Format] {
		return false
	}
	ceiling := b.gate.MaxBitrateKbps(ctx, user)
	return ceiling > 0 && (d.Bitrate == 0 || d.Bitrate > ceiling)
}

// hlsFormatFor answers the segmented format a rendering of shape takes:
// the shape's own where the engine segments it, FLAC for a lossless one
// (the lossless form every engine here decodes), and for any other lossy
// one the first of AAC and Opus the engine segments. Empty when none
// keeps the shape's intent: a lossless stream is never handed back lossy.
func hlsFormatFor(shape Shape, caps *client.Caps) string {
	if caps == nil || !caps.Delivery.HLS {
		return ""
	}
	segmented := func(f string) bool { return slices.Contains(caps.Delivery.HLSFormats, f) }
	if lossless(shape.Format) {
		if segmented("flac") {
			return "flac"
		}
		return ""
	}
	if segmented(shape.Format) {
		return shape.Format
	}
	for _, f := range []string{"aac", "opus"} {
		if segmented(f) {
			return f
		}
	}
	return ""
}

// itemRenderingFor mints src as one item's HLS presentation in format,
// carrying the encode its live stream would have had: the cap, the boost
// and a carved track's window. ok is false, and the reason logged, when
// the engine will not render it, so the caller mints the live stream.
func (b *Bridge) itemRenderingFor(ctx context.Context, user, apiItemPID string, src Source, opts PlayOptions,
	format string, capKbps int, gainDB float64, boost bool) (PlayInfo, bool) {
	ref, err := b.srcRef(src.Path)
	if err != nil {
		b.log.Warn("item rendering: no engine reference", "pid", apiItemPID, "err", err)
		return PlayInfo{}, false
	}
	params := url.Values{}
	params.Set("src", ref)
	params.Set("format", format)
	if capKbps > 0 && lossyBitrateFormats[format] {
		params.Set("bitrate", strconv.Itoa(capKbps))
	}
	if boost {
		params.Set("dynamics", "voice")
		params.Set("gain", strconv.FormatFloat(gainDB, 'f', 1, 64))
	}
	setWindow(params, src)
	sign := map[string]string{}
	for k := range params {
		sign[k] = params.Get(k)
	}
	ttl := max(renderingTTL(src.DurationMS), opts.TTL)
	signed, err := b.client.Sign(ctx, client.SignRequest{
		Path: "/hls/master.m3u8", Params: sign, TTLSeconds: int64(ttl.Seconds()),
	})
	if err != nil {
		b.log.Warn("item rendering: signing the master", "pid", apiItemPID, "err", err)
		return PlayInfo{}, false
	}
	rendering, ok := "", false
	if u, err := url.Parse(signed.URL); err == nil {
		rendering, ok = itemRendering(u.Query().Get("v"))
	}
	if !ok {
		b.log.Warn("item rendering: the signed master names no single source", "pid", apiItemPID)
		return PlayInfo{}, false
	}
	token, exp := b.tokens.MintFor(auth.MediaClaims{
		User: user, Cred: opts.Cred, Purpose: auth.PurposeHLS, PID: apiItemPID, Shape: itemShape(rendering),
	}, ttl)
	b.stashRendering(ctx, user, itemKey(rendering), signed.URL, exp)
	return PlayInfo{
		URL:                "/media/hls/master.m3u8?it=" + url.QueryEscape(rendering) + "&mt=" + url.QueryEscape(token),
		MimeType:           hlsMimeType,
		DurationMS:         src.DurationMS,
		Seekable:           true,
		ExpiresAt:          exp,
		VoiceBoost:         boost,
		AppliedBitrateKbps: capKbps,
	}, true
}
