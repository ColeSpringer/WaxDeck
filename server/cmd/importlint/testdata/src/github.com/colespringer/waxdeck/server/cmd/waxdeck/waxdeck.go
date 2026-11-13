package main

import (
	_ "github.com/colespringer/waxbin" // want `imports the waxbin facade outside the service layer`
	_ "github.com/colespringer/waxbin/enrich"
	_ "github.com/colespringer/waxbin/model" // want `imports waxbin/model; cmd/waxdeck may import only waxbin/source, waxbin/enrich`
	_ "github.com/colespringer/waxbin/source"
	_ "github.com/colespringer/waxbin/source/sub"
	_ "github.com/colespringer/waxbin/sourcex"      // want `imports waxbin/sourcex; cmd/waxdeck may import only waxbin/source, waxbin/enrich`
	_ "github.com/colespringer/waxbin/store/sqlite" // want `imports waxbin/store/sqlite, which nothing in WaxDeck may import`
)
