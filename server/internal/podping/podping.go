// Package podping watches the Hive blockchain for Podping notifications
// and reports the feeds they name.
//
// Podping is how a podcast host says "this feed just changed" without
// every subscriber polling it: the host asks a podping.cloud writer to
// put a `custom_json` operation on Hive naming the feed, and anyone
// reading the chain learns within a block or two. It is a floor-lowering
// signal, never a replacement for polling - a host that does not
// publish, a writer having an afternoon, and a node this server cannot
// reach all end the same way, with the scheduled refresh finding the
// episode a few minutes later.
//
// The watcher is deliberately narrow. It reads blocks and reports iris;
// it holds no catalog, resolves no subscription, and syncs nothing. What
// a named feed means is the caller's business, which is what keeps the
// chain vocabulary out of the service and the catalog out of here.
package podping

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// DefaultNode is the public Hive API node the watcher reads when the
// operator names none. Hive has many interchangeable public nodes; this
// one is the reference implementation's default.
const DefaultNode = "https://api.hive.blog"

// DefaultUserAgent identifies this server to a public Hive node, which
// is the polite minimum for reading somebody else's infrastructure once
// every three seconds.
const DefaultUserAgent = "WaxDeck/1.0 (+https://github.com/colespringer/waxdeck)"

// DefaultWriterAccount is the Hive account whose follow list publishes
// the podping.cloud writer set.
//
// Podping's own consumers resolve the allow-list this way rather than
// carrying a hardcoded roster: writers are added and retired without
// notice, and a list compiled into a release goes stale silently - which
// on this feature means a watcher that reads every block and recognises
// nobody. Deriving it from the chain is the same trust footing as the
// pings themselves.
const DefaultWriterAccount = "podping"

// Legacy and current custom_json ids. Current podping ids are
// `pp_<medium>_<reason>` (`pp_podcast_update`, `pp_music_live`, ...);
// `podping` is the pre-1.0 id, still emitted by older writers.
const (
	idPrefix = "pp_"
	idLegacy = "podping"
)

// maxBodyBytes bounds one node response. A block range is the largest
// thing read here and runs to a few megabytes; the cap is what stops a
// hostile or broken node from being an allocation.
const maxBodyBytes = 32 << 20

// Ping is one feed a writer said had changed.
type Ping struct {
	// IRI is the feed address, exactly as the writer published it.
	IRI string
	// Reason is why it changed: `update` (new episode), `live`, `liveEnd`,
	// or a word this build has not seen. Open set.
	Reason string
	// Medium is what the feed carries (`podcast`, `music`, `audiobook`),
	// from the id or the payload. Open set; empty where neither said.
	Medium string
	// Block is the Hive block the notification rode in, for logs.
	Block int64
}

// Config configures a Client. Zero values take the documented defaults.
type Config struct {
	// NodeURL defaults to DefaultNode.
	NodeURL string
	// HTTPClient defaults to a 30s-timeout client. A block range is a
	// large body from a public node, so the timeout is the generous one
	// rather than the enrichment clients' fifteen seconds.
	HTTPClient *http.Client
	// UserAgent identifies this server to the node.
	UserAgent string
	// WriterAccount defaults to DefaultWriterAccount.
	WriterAccount string
}

// Client speaks the subset of Hive's JSON-RPC the watcher needs. No
// dependency: a Hive node is JSON-RPC 2.0 over HTTP POST.
type Client struct {
	node    string
	http    *http.Client
	agent   string
	writers string
}

// New builds a client from cfg. An unusable node URL falls back to the
// default rather than failing: the watcher is an optional signal on top
// of polling, and refusing to start over a typo would take the podcast
// subsystem down with it. The substitution is the caller's to log.
func New(cfg Config) *Client {
	node := strings.TrimSuffix(strings.TrimSpace(cfg.NodeURL), "/")
	if !usableNode(node) {
		node = DefaultNode
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	agent := cfg.UserAgent
	if agent == "" {
		agent = DefaultUserAgent
	}
	writers := cfg.WriterAccount
	if writers == "" {
		writers = DefaultWriterAccount
	}
	return &Client{node: node, http: client, agent: agent, writers: writers}
}

// usableNode reports whether a configured node address is one this
// client could ever reach: an absolute http(s) URL with a host. A
// relative path or a bare hostname would otherwise fail on every
// request, forever, at Debug.
func usableNode(raw string) bool {
	if raw == "" {
		return false
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return false
	}
	return u.Scheme == "http" || u.Scheme == "https"
}

// Node is the node this client reads, for a log line that has to name
// it: a mistyped address is otherwise indistinguishable from an outage.
func (c *Client) Node() string { return c.node }

// call makes one JSON-RPC request and decodes the result into out.
func (c *Client) call(ctx context.Context, method string, params any, out any) error {
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
		"id":      1,
	})
	if err != nil {
		return fmt.Errorf("podping: encoding %s: %w", method, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.node, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", c.agent)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("podping: %s: status %d", method, resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxBodyBytes))
	if err != nil {
		return err
	}
	var envelope struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(raw, &envelope); err != nil {
		return fmt.Errorf("podping: decoding %s: %w", method, err)
	}
	if envelope.Error != nil {
		return fmt.Errorf("podping: %s: %s", method, envelope.Error.Message)
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(envelope.Result, out)
}

// LastIrreversible answers the newest block the chain will not reorganize.
//
// The watcher reads to here rather than to the head. An irreversible
// block is final, so a feed named in one was really named; a head block
// can be orphaned, and a sync triggered by a ping that never happened is
// a request to somebody else's server for nothing.
func (c *Client) LastIrreversible(ctx context.Context) (int64, error) {
	var props struct {
		LastIrreversible int64 `json:"last_irreversible_block_num"`
	}
	if err := c.call(ctx, "database_api.get_dynamic_global_properties", map[string]any{}, &props); err != nil {
		return 0, err
	}
	if props.LastIrreversible <= 0 {
		return 0, fmt.Errorf("podping: node reported no irreversible block")
	}
	return props.LastIrreversible, nil
}

// Writers answers the accounts whose podpings are trusted: the follow
// list of the writer account.
func (c *Client) Writers(ctx context.Context) (map[string]bool, error) {
	// condenser_api takes positional parameters: [account, start, type,
	// limit]. The 1000 cap is the API's own.
	var following []struct {
		Following string `json:"following"`
	}
	params := []any{c.writers, "", "blog", 1000}
	if err := c.call(ctx, "condenser_api.get_following", params, &following); err != nil {
		return nil, err
	}
	if len(following) == 0 {
		return nil, fmt.Errorf("podping: %s follows no writers", c.writers)
	}
	out := make(map[string]bool, len(following)+1)
	for _, f := range following {
		if f.Following != "" {
			out[f.Following] = true
		}
	}
	// The publisher of the list is a writer itself, and does not follow
	// itself.
	out[c.writers] = true
	return out, nil
}

// hiveBlock is the shape of one block, narrowed to the operations. The
// `type`/`value` envelope is the appbase form every current node
// answers `block_api` in.
type hiveBlock struct {
	Transactions []struct {
		Operations []struct {
			Type  string `json:"type"`
			Value struct {
				ID                   string   `json:"id"`
				RequiredPostingAuths []string `json:"required_posting_auths"`
				RequiredAuths        []string `json:"required_auths"`
				JSON                 string   `json:"json"`
			} `json:"value"`
		} `json:"operations"`
	} `json:"transactions"`
}

// payload is a podping custom_json body. Current writers publish `iris`;
// pre-1.0 writers published `urls`, and both are read because the older
// ones are still on the chain.
type payload struct {
	Version string   `json:"version"`
	Medium  string   `json:"medium"`
	Reason  string   `json:"reason"`
	IRIs    []string `json:"iris"`
	URLs    []string `json:"urls"`
	// The pre-1.0 single-feed form.
	URL string `json:"url"`
}

// Pings reads count blocks from `from` and returns every podping in
// them whose posting authority is trusted, plus the first block after
// the range.
//
// The writers set is passed in rather than fetched here so a caller
// refreshing it on its own cadence is not making a second network call
// per block range.
func (c *Client) Pings(ctx context.Context, from int64, count int, writers map[string]bool) ([]Ping, int64, error) {
	if count <= 0 {
		return nil, from, nil
	}
	var result struct {
		Blocks []hiveBlock `json:"blocks"`
	}
	params := map[string]any{"starting_block_num": from, "count": count}
	if err := c.call(ctx, "block_api.get_block_range", params, &result); err != nil {
		return nil, from, err
	}
	var out []Ping
	for i, block := range result.Blocks {
		number := from + int64(i)
		for _, tx := range block.Transactions {
			for _, op := range tx.Operations {
				if op.Type != "custom_json_operation" {
					continue
				}
				medium, ok := podpingID(op.Value.ID)
				if !ok {
					continue
				}
				// The posting authority, not the active one: podping is
				// published with a posting key, and an operation signed
				// some other way is not one of these writers speaking.
				if !trusted(op.Value.RequiredPostingAuths, writers) {
					continue
				}
				var body payload
				if err := json.Unmarshal([]byte(op.Value.JSON), &body); err != nil {
					// A writer's malformed body is that writer's problem
					// and says nothing about the next operation.
					continue
				}
				if body.Medium != "" {
					medium = body.Medium
				}
				for _, iri := range feedsOf(body) {
					out = append(out, Ping{
						IRI: iri, Reason: body.Reason, Medium: medium, Block: number,
					})
				}
			}
		}
	}
	// The next block to read is one past the last one the node actually
	// answered with, not one past the range asked for: a node that
	// returned short has not been read past.
	return out, from + int64(len(result.Blocks)), nil
}

// podpingID reports whether an operation id is a podping, and the medium
// its id names.
func podpingID(id string) (medium string, ok bool) {
	if id == idLegacy {
		return "", true
	}
	rest, found := strings.CutPrefix(id, idPrefix)
	if !found {
		return "", false
	}
	// `pp_<medium>_<reason>`. A medium with no reason after it is not a
	// shape any writer emits, so it is left unnamed rather than guessed.
	medium, _, found = strings.Cut(rest, "_")
	if !found {
		return "", true
	}
	return medium, true
}

// trusted reports whether any posting authority is in the writer set.
func trusted(auths []string, writers map[string]bool) bool {
	for _, account := range auths {
		if writers[account] {
			return true
		}
	}
	return false
}

// feedsOf reads the feeds out of a payload across its three shapes.
func feedsOf(body payload) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(body.IRIs)+len(body.URLs)+1)
	for _, list := range [][]string{body.IRIs, body.URLs, {body.URL}} {
		for _, raw := range list {
			iri := strings.TrimSpace(raw)
			// http(s) only: podping's iri space is wider than what a feed
			// subscription can be, and anything else here cannot match a
			// catalog row anyway.
			if iri == "" || seen[iri] {
				continue
			}
			if !strings.HasPrefix(iri, "http://") && !strings.HasPrefix(iri, "https://") {
				continue
			}
			seen[iri] = true
			out = append(out, iri)
		}
	}
	return out
}
