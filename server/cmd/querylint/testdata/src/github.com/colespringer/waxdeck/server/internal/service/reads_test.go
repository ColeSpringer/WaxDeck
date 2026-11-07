package service

import "github.com/colespringer/waxbin/query"

func listingInATest() *query.Query {
	return query.New(query.EntityItems)
}
