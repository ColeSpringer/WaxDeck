package castv2

import (
	"context"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

type staticAnnouncer struct {
	online chan string
}

func (a *staticAnnouncer) EndpointOnline(_ context.Context, _, deviceKey, _, _ string, _, _ bool, _ connect.DialFunc) (connect.Endpoint, error) {
	select {
	case a.online <- deviceKey:
	default:
	}
	return connect.Endpoint{ID: "pe-" + deviceKey}, nil
}

func (a *staticAnnouncer) EndpointOffline(context.Context, string) {}

// Disabling discovery must mean no multicast at all: static devices
// still announce, but the query hook is never invoked.
func TestStaticOnlyNeverQueries(t *testing.T) {
	ann := &staticAnnouncer{online: make(chan string, 1)}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	queried := make(chan struct{}, 1)
	cfg := DiscoveryConfig{
		Announce:   ann,
		Group:      supervise.NewGroup(nil),
		Interval:   10 * time.Millisecond,
		StaticOnly: true,
		Static:     []Device{{Host: "192.0.2.9", Port: 8009, Name: "Static"}},
		query: func(context.Context) ([]Device, error) {
			select {
			case queried <- struct{}{}:
			default:
			}
			return nil, nil
		},
	}
	done := make(chan struct{})
	go func() {
		RunDiscovery(ctx, cfg)
		close(done)
	}()
	select {
	case <-ann.online:
	case <-time.After(2 * time.Second):
		t.Fatal("static device never announced")
	}
	// Let several sweep intervals pass; the query hook must stay cold.
	time.Sleep(100 * time.Millisecond)
	cancel()
	<-done
	select {
	case <-queried:
		t.Fatal("multicast query ran with discovery disabled")
	default:
	}
}
