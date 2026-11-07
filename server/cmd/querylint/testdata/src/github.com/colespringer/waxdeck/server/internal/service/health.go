package service

import "github.com/colespringer/waxbin/query"

func SweepHealth() *query.Query {
	return query.New(query.EntityItems)
}
