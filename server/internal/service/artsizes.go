package service

import waxart "github.com/colespringer/waxbin/art"

// The art sizes WaxDeck asks the catalog for.
//
// Every one is a rung of the catalog's own ladder (waxbin/art.Rungs). A
// resolve at a rung answers a derivative the store already holds or
// mints one it will hold; a resolve at anything else rounds up to the
// rung above and mints a bespoke row nothing else will ever ask for
// again. So the ladder is the contract, and these are the rungs of it
// this server picks.
//
// Here rather than beside each caller because the callers cannot see
// the ladder: only `internal/service` and below may import waxbin, so
// the HTTP layer and the Subsonic adapter had a copy of the number
// each, with the ladder named in a comment and read by nothing.
// [ArtSizeOnLadder] is what reads it, and `artsizes_test.go` is what
// fails when the two disagree.
const (
	// ArtSizeCast is the longest edge minted media-art URLs ask for.
	// Cast receivers and DLNA renderers paint album art on a television
	// or a small panel, so the original is wasted bytes over a LAN.
	ArtSizeCast = 512

	// ArtSizeShare is the public share page's cover. The same rung as
	// [ArtSizeCast] on purpose: two surfaces asking for one derivative
	// rather than each rounding into one of its own.
	ArtSizeShare = 512

	// ArtSizeMosaic is the square a generated playlist cover is drawn
	// into, four tiles to a side.
	ArtSizeMosaic = 1024

	// ArtSizeToolCover is the cover the tag tool writes into a file
	// when the stored original is a format no player paints. Near the
	// top of the ladder: a picture somebody attached by hand should
	// survive the trip into the tags at something close to its size.
	ArtSizeToolCover = 2048

	// ArtSizeMax is the largest size any endpoint accepts, and the top
	// of the ladder. Past it a request is asking for an enlargement,
	// which the resolver does not do.
	ArtSizeMax = 2048
)

// ArtSizeOnLadder reports whether size names a rung exactly, rather
// than a number that would round up to one.
func ArtSizeOnLadder(size int) bool { return size > 0 && waxart.Rung(size) == size }
