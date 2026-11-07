//go:build ignore

package service

import "github.com/colespringer/waxbin/query"

func elsewhere() *query.Query {
	return query.New(query.EntityTracks)
}
