// Package outside is not the service, so it may build any query.
package outside

import "github.com/colespringer/waxbin/query"

func listing() *query.Query {
	return query.New(query.EntityItems)
}
