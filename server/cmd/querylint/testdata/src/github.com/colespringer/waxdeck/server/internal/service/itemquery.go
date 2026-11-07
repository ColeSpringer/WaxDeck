package service

import "github.com/colespringer/waxbin/query"

func visibleItems() *query.Query {
	return query.New(query.EntityItems)
}
