package service

import "github.com/colespringer/waxbin/query"

var tracks = query.New(query.EntityTracks)

func listing() *query.Query {
	return query.New(query.EntityItems)
}

func albums() *query.Query {
	return query.New(query.EntityAlbums)
}
