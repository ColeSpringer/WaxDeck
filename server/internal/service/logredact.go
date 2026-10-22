package service

import (
	"context"
	"fmt"
	"log/slog"
	"net/url"
	"regexp"
	"strings"
)

// webAddress finds a web address inside text, whatever its scheme's case.
// It runs to whitespace, a double quote or an angle bracket, which RFC
// 3986 names as what delimits an address in text: any sub-delim, the
// apostrophe included, can sit raw in a path, query or user part.
var webAddress = regexp.MustCompile(`(?i)https?://[^\s"<>]+`)

// hostOnly cuts every web address in s down to its scheme and host. A
// feed's address can be its own credential, in its path, query or user
// part, and so can the cover, chapter, transcript and enclosure addresses
// a private feed hands out. Punctuation that ends the sentence around an
// address stays.
func hostOnly(s string) string {
	if !strings.Contains(s, "://") {
		return s
	}
	return webAddress.ReplaceAllStringFunc(s, func(raw string) string {
		addr := trimSentenceEnd(raw)
		tail := raw[len(addr):]
		scheme := addr[:strings.Index(addr, "://")+3]
		if u, err := url.Parse(addr); err == nil && u.Host != "" {
			return scheme + u.Host + tail
		}
		return scheme + tail
	})
}

// trimSentenceEnd drops the punctuation that ends a sentence after an
// address, a closing quote included. A closing bracket stays when it
// closes the address's own, the one around an IPv6 host.
func trimSentenceEnd(raw string) string {
	addr := raw
	opened, closed := strings.Count(addr, "["), strings.Count(addr, "]")
	for addr != "" {
		c := addr[len(addr)-1]
		if !strings.ContainsRune(".,;:!?)]}'", rune(c)) || (c == ']' && closed <= opened) {
			break
		}
		if c == ']' {
			closed--
		}
		addr = addr[:len(addr)-1]
	}
	return addr
}

// HostOnlyLogger is log with every web address in a line, in its message
// or any value, cut to its scheme and host. The service, the catalog and
// the API all write through it, since their lines carry addresses and
// errors that repeat them.
func HostOnlyLogger(log *slog.Logger) *slog.Logger {
	if _, ok := log.Handler().(hostOnlyHandler); ok {
		return log
	}
	return slog.New(hostOnlyHandler{log.Handler()})
}

type hostOnlyHandler struct{ next slog.Handler }

func (h hostOnlyHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.next.Enabled(ctx, level)
}

func (h hostOnlyHandler) Handle(ctx context.Context, r slog.Record) error {
	out := slog.NewRecord(r.Time, r.Level, hostOnly(r.Message), r.PC)
	r.Attrs(func(a slog.Attr) bool {
		out.AddAttrs(hostOnlyAttr(a))
		return true
	})
	return h.next.Handle(ctx, out)
}

func (h hostOnlyHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	cut := make([]slog.Attr, len(attrs))
	for i, a := range attrs {
		cut[i] = hostOnlyAttr(a)
	}
	return hostOnlyHandler{h.next.WithAttrs(cut)}
}

func (h hostOnlyHandler) WithGroup(name string) slog.Handler {
	return hostOnlyHandler{h.next.WithGroup(name)}
}

func hostOnlyAttr(a slog.Attr) slog.Attr {
	v := a.Value.Resolve()
	switch v.Kind() {
	case slog.KindString:
		return slog.String(a.Key, hostOnly(v.String()))
	case slog.KindGroup:
		group := v.Group()
		cut := make([]slog.Attr, len(group))
		for i, g := range group {
			cut[i] = hostOnlyAttr(g)
		}
		return slog.Attr{Key: a.Key, Value: slog.GroupValue(cut...)}
	case slog.KindAny:
		// fmt, not the value's own methods: it prints a typed nil as
		// <nil>, as the plain handlers do, where calling Error or String
		// on one could panic the line.
		var text string
		switch x := v.Any().(type) {
		case url.URL:
			text = x.String()
		case []byte:
			text = string(x)
		default:
			text = fmt.Sprint(x)
		}
		if strings.Contains(text, "://") {
			return slog.String(a.Key, hostOnly(text))
		}
	}
	return slog.Attr{Key: a.Key, Value: v}
}
