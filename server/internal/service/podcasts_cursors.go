package service

import (
	"fmt"
	"strconv"
	"strings"
)

func encodeTitleCursor(title, pid string) string {
	return encodeOpaqueCursor(fmt.Sprintf("t1|%d|%s|%s", len(title), title, pid))
}

func decodeTitleCursor(s string) (title, pid string, ok bool) {
	raw, ok := decodeOpaqueCursor(s)
	if !ok {
		return "", "", false
	}
	rest, found := strings.CutPrefix(raw, "t1|")
	if !found {
		return "", "", false
	}
	i := strings.IndexByte(rest, '|')
	if i < 0 {
		return "", "", false
	}
	n := 0
	if _, err := fmt.Sscanf(rest[:i], "%d", &n); err != nil || n < 0 || i+1+n+1 > len(rest) {
		return "", "", false
	}
	title = rest[i+1 : i+1+n]
	if rest[i+1+n] != '|' {
		return "", "", false
	}
	return title, rest[i+1+n+1:], true
}

func encodePubCursor(pubNS int64, pid string) string {
	return encodeOpaqueCursor(fmt.Sprintf("p1|%d|%s", pubNS, pid))
}

func decodePubCursor(s string) (pubNS int64, pid string, ok bool) {
	raw, ok := decodeOpaqueCursor(s)
	if !ok {
		return 0, "", false
	}
	parts := strings.SplitN(raw, "|", 3)
	if len(parts) != 3 || parts[0] != "p1" {
		return 0, "", false
	}
	pubNS, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return 0, "", false
	}
	return pubNS, parts[2], true
}
