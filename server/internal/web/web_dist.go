//go:build withweb

package web

import (
	"embed"
	"io/fs"
)

// dist/ is produced by `make web` (Flutter web build). Building with
// -tags withweb without running `make web` first is a compile error by
// design: never ship a stale or empty UI silently.
//
//go:embed all:dist
var distEmbed embed.FS

func init() {
	sub, err := fs.Sub(distEmbed, "dist")
	if err != nil {
		panic(err)
	}
	distFS = sub
}
