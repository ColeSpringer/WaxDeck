// Package query stands in for waxbin's query builder.
package query

type Entity int

const (
	EntityItems Entity = iota
	EntityTracks
	EntityAlbums
)

type Query struct{}

func New(Entity) *Query { return &Query{} }
