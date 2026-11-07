package service

import (
	_ "github.com/colespringer/waxbin"
	_ "github.com/colespringer/waxbin/model"
	_ "github.com/colespringer/waxbin/store/sqlite" // want `imports waxbin/store/sqlite, which nothing in WaxDeck may import`
)
