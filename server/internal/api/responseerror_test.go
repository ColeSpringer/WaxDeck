package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"testing"
)

// recordingLog keeps what the server warned about.
type recordingLog struct {
	mu    sync.Mutex
	warns []string
}

func (l *recordingLog) Info(string, ...any) {}

func (l *recordingLog) Warn(msg string, args ...any) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.warns = append(l.warns, msg+" "+fmt.Sprint(args...))
}

// failingBody is a writer whose body cannot be written. With hangUp set
// it is a listener gone, as net/http reports one: the write fails and the
// request's context ends with it.
type failingBody struct {
	header   http.Header
	statuses []int
	hangUp   context.CancelFunc
}

func (w *failingBody) Header() http.Header  { return w.header }
func (w *failingBody) WriteHeader(code int) { w.statuses = append(w.statuses, code) }

func (w *failingBody) Write([]byte) (int, error) {
	if w.hangUp != nil {
		w.hangUp()
	}
	return 0, errors.New("write: broken pipe")
}

// cutShort runs serve and reports whether it ended the way a handler
// cuts its connection.
func cutShort(serve func()) (cut bool) {
	defer func() {
		switch r := recover(); r {
		case nil:
		case http.ErrAbortHandler:
			cut = true
		default:
			panic(r)
		}
	}()
	serve()
	return false
}

// publicJSONRoute answers 200 with a JSON body from a server holding
// nothing at all.
const publicJSONRoute = "/api/v1/auth/oidc/providers"

// A listener gone mid-body is not answered a second time. The error that
// ends the body arrives after the status went out, and a second status is
// one net/http refuses and logs as the server's own bug.
func TestAListenerGoneMidBodyIsNotAnsweredTwice(t *testing.T) {
	t.Parallel()
	log := &recordingLog{}
	srv := NewServer("test", Options{Logger: log})
	ctx, hangUp := context.WithCancel(context.Background())
	defer hangUp()
	w := &failingBody{header: http.Header{}, hangUp: hangUp}
	cut := cutShort(func() {
		srv.Handler().ServeHTTP(w, httptest.NewRequestWithContext(ctx, "GET", publicJSONRoute, nil))
	})
	// Cut here too: a request can be over with its connection still up (a
	// server stopping), and a body ended cleanly then would read as whole.
	if !cut {
		t.Error("the handler returned as if the answer were whole")
	}
	if !slices.Equal(w.statuses, []int{http.StatusOK}) {
		t.Errorf("statuses written = %v, want the one 200", w.statuses)
	}
	if len(log.warns) != 0 {
		t.Errorf("a listener going away was logged: %v", log.warns)
	}
}

// An answer that fails once it is under way, its listener still there, is
// cut and logged. Finished instead, a short body would read as a whole one.
func TestAnAnswerThatFailsUnderWayIsCut(t *testing.T) {
	t.Parallel()
	log := &recordingLog{}
	srv := NewServer("test", Options{Logger: log})
	w := &failingBody{header: http.Header{}}
	cut := cutShort(func() {
		srv.Handler().ServeHTTP(w, httptest.NewRequest("GET", publicJSONRoute, nil))
	})
	if !cut {
		t.Error("the handler returned as if the answer were whole")
	}
	if !slices.Equal(w.statuses, []int{http.StatusOK}) {
		t.Errorf("statuses written = %v, want the one 200", w.statuses)
	}
	if len(log.warns) != 1 || !strings.Contains(log.warns[0], publicJSONRoute) {
		t.Errorf("warnings = %v, want one naming the route", log.warns)
	}
}
