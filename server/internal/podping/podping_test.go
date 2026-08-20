package podping

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeNode stands in for a Hive API node, answering the three methods
// the watcher calls in the shapes a real node answers them in. The
// request trace is what the tests assert on: the point of the watcher
// is that it reads a public node politely and correctly, and a fake
// that answers whatever it is asked would prove neither.
type fakeNode struct {
	ts *httptest.Server

	mu           sync.Mutex
	calls        []string
	ranges       []struct{ from, count int64 }
	irreversible int64
	following    []string
	// blocks maps a block number to its operations. A number with no
	// entry answers an empty block, which is most of the chain.
	blocks map[int64][]operation
	// failNext, when set, is the status the next call answers with.
	failNext int
}

// operation is one custom_json in a block, in the appbase envelope.
type operation struct {
	id    string
	auths []string
	body  string
}

func newFakeNode(t *testing.T) *fakeNode {
	t.Helper()
	node := &fakeNode{
		irreversible: 1000,
		following:    []string{"podping.aaa", "podping.bbb"},
		blocks:       map[int64][]operation{},
	}
	node.ts = httptest.NewServer(http.HandlerFunc(node.serve))
	t.Cleanup(node.ts.Close)
	return node
}

func (n *fakeNode) serve(w http.ResponseWriter, r *http.Request) {
	raw, _ := io.ReadAll(r.Body)
	var req struct {
		Method string          `json:"method"`
		Params json.RawMessage `json:"params"`
	}
	if err := json.Unmarshal(raw, &req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	n.mu.Lock()
	n.calls = append(n.calls, req.Method)
	if code := n.failNext; code != 0 {
		n.failNext = 0
		n.mu.Unlock()
		http.Error(w, "upstream is having an afternoon", code)
		return
	}
	n.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	switch req.Method {
	case "database_api.get_dynamic_global_properties":
		n.mu.Lock()
		head := n.irreversible
		n.mu.Unlock()
		fmt.Fprintf(w, `{"jsonrpc":"2.0","id":1,"result":{"head_block_number":%d,"last_irreversible_block_num":%d}}`,
			head+20, head)
	case "condenser_api.get_following":
		n.mu.Lock()
		rows := make([]map[string]string, 0, len(n.following))
		for _, account := range n.following {
			rows = append(rows, map[string]string{"follower": "podping", "following": account})
		}
		n.mu.Unlock()
		body, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": 1, "result": rows})
		w.Write(body)
	case "block_api.get_block_range":
		var params struct {
			From  int64 `json:"starting_block_num"`
			Count int64 `json:"count"`
		}
		json.Unmarshal(req.Params, &params)
		n.mu.Lock()
		n.ranges = append(n.ranges, struct{ from, count int64 }{params.From, params.Count})
		blocks := make([]any, 0, params.Count)
		for i := int64(0); i < params.Count; i++ {
			blocks = append(blocks, blockJSON(n.blocks[params.From+i]))
		}
		n.mu.Unlock()
		body, _ := json.Marshal(map[string]any{
			"jsonrpc": "2.0", "id": 1,
			"result": map[string]any{"blocks": blocks},
		})
		w.Write(body)
	default:
		body, _ := json.Marshal(map[string]any{
			"jsonrpc": "2.0", "id": 1,
			"error": map[string]any{"message": "unknown method " + req.Method},
		})
		w.Write(body)
	}
}

// blockJSON renders one block the way block_api does: transactions, each
// with operations in the `type`/`value` envelope.
func blockJSON(ops []operation) map[string]any {
	txs := make([]any, 0, len(ops))
	for _, op := range ops {
		txs = append(txs, map[string]any{
			"operations": []any{
				map[string]any{
					"type": "custom_json_operation",
					"value": map[string]any{
						"id":                     op.id,
						"required_auths":         []string{},
						"required_posting_auths": op.auths,
						"json":                   op.body,
					},
				},
			},
		})
	}
	return map[string]any{"transactions": txs}
}

func (n *fakeNode) methodCalls(method string) int {
	n.mu.Lock()
	defer n.mu.Unlock()
	count := 0
	for _, call := range n.calls {
		if call == method {
			count++
		}
	}
	return count
}

func (n *fakeNode) client() *Client {
	return New(Config{NodeURL: n.ts.URL, HTTPClient: n.ts.Client()})
}

func TestWritersComeFromTheChain(t *testing.T) {
	t.Parallel()
	node := newFakeNode(t)
	writers, err := node.client().Writers(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"podping.aaa", "podping.bbb", "podping"} {
		if !writers[want] {
			t.Errorf("writer set is missing %q: %v", want, writers)
		}
	}
	// A set nobody publishes into is an error, not an empty set: with no
	// writers every operation is untrusted, and a watcher that read the
	// whole chain to recognise nobody would look like it was working.
	node.mu.Lock()
	node.following = nil
	node.mu.Unlock()
	if _, err := node.client().Writers(context.Background()); err == nil {
		t.Error("an empty follow list answered a writer set")
	}
}

func TestPingsReadWhatWritersPublish(t *testing.T) {
	t.Parallel()
	node := newFakeNode(t)
	node.blocks[100] = []operation{
		// The current shape: pp_<medium>_<reason>, iris, a trusted writer.
		{
			id:    "pp_podcast_update",
			auths: []string{"podping.aaa"},
			body:  `{"version":"1.1","medium":"podcast","reason":"update","iris":["https://example.com/feed.xml"]}`,
		},
		// The pre-1.0 shape, still on the chain: the bare id and `urls`.
		{
			id:    "podping",
			auths: []string{"podping.bbb"},
			body:  `{"version":"0.3","reason":"update","urls":["https://old.example.com/rss"]}`,
		},
	}
	node.blocks[101] = []operation{
		// A stranger publishing the same shape. Anybody may write to
		// Hive, so the posting authority is the whole of the trust
		// decision: without this check the feature is "sync whatever any
		// account on a public chain names".
		{
			id:    "pp_podcast_update",
			auths: []string{"impostor.xyz"},
			body:  `{"medium":"podcast","reason":"update","iris":["https://evil.example.com/feed.xml"]}`,
		},
		// A trusted writer with a body that is not JSON. Its problem,
		// not the next operation's.
		{id: "pp_podcast_update", auths: []string{"podping.aaa"}, body: `{not json`},
		// A trusted writer naming something that is not a feed URL.
		{
			id:    "pp_podcast_update",
			auths: []string{"podping.aaa"},
			body:  `{"reason":"update","iris":["mailto:someone@example.com"]}`,
		},
	}
	// An operation that is not a podping at all, which is nearly every
	// custom_json on the chain.
	node.blocks[102] = []operation{
		{id: "ssc-mainnet-hive", auths: []string{"podping.aaa"}, body: `{"contractName":"tokens"}`},
	}

	writers, err := node.client().Writers(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	pings, next, err := node.client().Pings(context.Background(), 100, 3, writers)
	if err != nil {
		t.Fatal(err)
	}
	if next != 103 {
		t.Errorf("next block = %d, want one past the range read", next)
	}
	got := make([]string, 0, len(pings))
	for _, ping := range pings {
		got = append(got, ping.IRI)
	}
	want := []string{"https://example.com/feed.xml", "https://old.example.com/rss"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("iris = %v, want %v", got, want)
	}
	if pings[0].Medium != "podcast" || pings[0].Reason != "update" {
		t.Errorf("first ping = %+v, want the medium and reason it published", pings[0])
	}
	if pings[0].Block != 100 {
		t.Errorf("block = %d, want the block it rode in", pings[0].Block)
	}
}

// TestUnusableNodeFallsBackToTheDefault: a node address that could
// never be reached is substituted rather than kept. Kept, it would fail
// on every request for the life of the process, and the watcher logs a
// node failure at Warn once and Debug thereafter - so a typo'd
// --podping-node would look exactly like a public node having a bad
// day, forever.
func TestUnusableNodeFallsBackToTheDefault(t *testing.T) {
	t.Parallel()
	for _, raw := range []string{
		"", "   ", "api.hive.blog", "/hive", "ftp://api.hive.blog", "://nonsense",
	} {
		if got := New(Config{NodeURL: raw}).Node(); got != DefaultNode {
			t.Errorf("New(%q).Node() = %q, want the default", raw, got)
		}
	}
	// A usable one is kept, trailing slash and surrounding space and all.
	for _, raw := range []string{"https://hive.example/", " https://hive.example "} {
		if got := New(Config{NodeURL: raw}).Node(); got != "https://hive.example" {
			t.Errorf("New(%q).Node() = %q, want the configured node", raw, got)
		}
	}
}

func TestPodpingIDVocabulary(t *testing.T) {
	t.Parallel()
	cases := []struct {
		id     string
		medium string
		ok     bool
	}{
		{"pp_podcast_update", "podcast", true},
		{"pp_music_live", "music", true},
		{"pp_audiobook_liveEnd", "audiobook", true},
		{"podping", "", true},
		// A prefix with no reason after the medium is not a shape any
		// writer emits; it stays a podping with no medium named rather
		// than one whose medium is invented.
		{"pp_podcast", "", true},
		{"ssc-mainnet-hive", "", false},
		{"", "", false},
	}
	for _, c := range cases {
		medium, ok := podpingID(c.id)
		if ok != c.ok || medium != c.medium {
			t.Errorf("podpingID(%q) = (%q, %v), want (%q, %v)", c.id, medium, ok, c.medium, c.ok)
		}
	}
}

// runWatcher drives a watcher against the node for passes waits, with
// the block wait stubbed out: the real one is three seconds a block, and
// a test that waited it would take a minute to read a minute of chain.
// between, when set, runs after each wait, so a test can move the chain
// on under the watcher.
func runWatcher(t *testing.T, node *fakeNode, pin []string, passes int, between func(n int)) []Ping {
	t.Helper()
	var (
		mu   sync.Mutex
		seen []Ping
	)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	watcher := NewWatcher(node.client(), slog.New(slog.DiscardHandler), func(_ context.Context, p Ping) {
		mu.Lock()
		seen = append(seen, p)
		mu.Unlock()
	})
	watcher.PinWriters(pin)
	waited := 0
	watcher.sleep = func(context.Context, time.Duration) bool {
		waited++
		if between != nil {
			between(waited)
		}
		if waited >= passes {
			cancel()
			return false
		}
		return true
	}
	if err := watcher.Run(ctx); err != nil {
		t.Fatalf("the watcher reported %v; it is never fatal by design", err)
	}
	mu.Lock()
	defer mu.Unlock()
	return append([]Ping(nil), seen...)
}

func TestWatcherStartsAtTheFrontRatherThanReplaying(t *testing.T) {
	t.Parallel()
	node := newFakeNode(t)
	// A ping well behind the head. A watcher that started from block one
	// - or from any backlog - would replay hours of chain and spend a
	// request per feed to learn what the scheduled refresh already knows.
	node.blocks[10] = []operation{
		{
			id:    "pp_podcast_update",
			auths: []string{"podping.aaa"},
			body:  `{"reason":"update","iris":["https://example.com/old.xml"]}`,
		},
	}
	seen := runWatcher(t, node, []string{"podping.aaa"}, 1, nil)
	if len(seen) != 0 {
		t.Fatalf("replayed the backlog: %+v", seen)
	}
	node.mu.Lock()
	ranges := append([]struct{ from, count int64 }(nil), node.ranges...)
	node.mu.Unlock()
	if len(ranges) != 1 || ranges[0].from != 1000 {
		t.Fatalf("read %v, want one range starting at the irreversible head", ranges)
	}
	// And it does not resolve the writer set over the chain when the
	// operator pinned one.
	if got := node.methodCalls("condenser_api.get_following"); got != 0 {
		t.Errorf("resolved the writer set %d times over a pinned one", got)
	}
}

func TestWatcherReportsWhatItWalksPast(t *testing.T) {
	t.Parallel()
	node := newFakeNode(t)
	node.irreversible = 1000
	node.blocks[1000] = []operation{
		{
			id:    "pp_podcast_update",
			auths: []string{"podping.aaa"},
			body:  `{"reason":"update","iris":["https://example.com/feed.xml"]}`,
		},
	}
	seen := runWatcher(t, node, []string{"podping.aaa"}, 1, nil)
	if len(seen) != 1 || seen[0].IRI != "https://example.com/feed.xml" {
		t.Fatalf("seen = %+v, want the one ping in the block it started on", seen)
	}
}

func TestWatcherSkipsForwardRatherThanReplayingHours(t *testing.T) {
	t.Parallel()
	node := newFakeNode(t)
	node.irreversible = 1000
	// The chain runs away between the first pass and the second, the way
	// it does for a server that was asleep or unplugged. Replaying the
	// gap would be a request to somebody else's host per feed named in
	// it, for news the scheduled refresh has already collected.
	runWatcher(t, node, []string{"podping.aaa"}, 2, func(pass int) {
		if pass == 1 {
			node.mu.Lock()
			node.irreversible = 50_000
			node.mu.Unlock()
		}
	})
	node.mu.Lock()
	ranges := append([]struct{ from, count int64 }(nil), node.ranges...)
	node.mu.Unlock()
	if len(ranges) < 2 {
		t.Fatalf("read %v, want a range on each pass", ranges)
	}
	if ranges[0].from != 1000 {
		t.Fatalf("first range from %d, want the head", ranges[0].from)
	}
	// Not from where it left off (1001), and not from the new head: from
	// exactly the lag bound behind it, so the recent past is still read.
	if want := int64(50_000 - maxLagBlocks); ranges[1].from != want {
		t.Fatalf("second range from %d, want %d (the lag bound behind the new head)",
			ranges[1].from, want)
	}
}

func TestWatcherSurvivesANodeHavingAnAfternoon(t *testing.T) {
	t.Parallel()
	node := newFakeNode(t)
	node.failNext = http.StatusBadGateway
	// A node error backs off and the run ends on the stubbed wait, which
	// is the property: no panic, no error out of Run, and the supervisor
	// never sees a failed worker for somebody else's outage.
	seen := runWatcher(t, node, []string{"podping.aaa"}, 1, nil)
	if len(seen) != 0 {
		t.Fatalf("seen = %+v, want nothing past a node error", seen)
	}
	if got := node.methodCalls("block_api.get_block_range"); got != 0 {
		t.Errorf("read %d block ranges without a chain head", got)
	}
}

func TestWatcherWaitsForAWriterSetItCannotResolve(t *testing.T) {
	t.Parallel()
	node := newFakeNode(t)
	node.mu.Lock()
	node.following = nil
	node.mu.Unlock()
	// Nothing pinned, and the chain publishes no writers: the walk would
	// read every block to trust nobody, so it waits for the list instead
	// of spending the requests.
	seen := runWatcher(t, node, nil, 1, nil)
	if len(seen) != 0 {
		t.Fatalf("seen = %+v", seen)
	}
	if got := node.methodCalls("block_api.get_block_range"); got != 0 {
		t.Errorf("read %d block ranges with no trusted writer", got)
	}
}
