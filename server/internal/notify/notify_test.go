package notify

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

// sink records one delivery for shape assertions; reply, when set, is
// written back as the response body.
type sink struct {
	status  int
	reply   []byte
	method  string
	path    string
	header  http.Header
	body    []byte
	handler *httptest.Server
}

func newSink(t *testing.T, status int) *sink {
	t.Helper()
	s := &sink{status: status}
	s.handler = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.method = r.Method
		s.path = r.URL.Path
		s.header = r.Header.Clone()
		s.body, _ = io.ReadAll(r.Body)
		w.WriteHeader(s.status)
		if len(s.reply) > 0 {
			w.Write(s.reply)
		}
	}))
	t.Cleanup(s.handler.Close)
	return s
}

func (s *sink) jsonBody(t *testing.T) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(s.body, &m); err != nil {
		t.Fatalf("delivery body is not JSON: %v\n%s", err, s.body)
	}
	return m
}

func deliver(t *testing.T, kind string, config string, msg Message) error {
	t.Helper()
	p, ok := ByKind(kind)
	if !ok {
		t.Fatalf("no provider for %s", kind)
	}
	norm, _, err := p.ValidateConfig(json.RawMessage(config))
	if err != nil {
		t.Fatalf("ValidateConfig(%s) = %v", config, err)
	}
	return p.Deliver(context.Background(), http.DefaultClient, norm, msg)
}

func TestValidateConfigTable(t *testing.T) {
	cases := []struct {
		kind    string
		config  string
		wantErr string
		// wantHost is the user-pointed host the write-time private
		// check applies to; empty means the kind is exempt.
		wantHost string
	}{
		{KindPushover, `{"token":"t","userKey":"u"}`, "", ""},
		{KindPushover, `{"token":"t","userKey":"u","priority":2}`, "", ""},
		{KindPushover, `{"token":"","userKey":"u"}`, "needs a token", ""},
		{KindPushover, `{"token":"t","userKey":""}`, "needs a userKey", ""},
		{KindPushover, `{"token":"t","userKey":"u","priority":3}`, "between -2 and 2", ""},
		{KindPushover, `{"token":"t","userKey":"u","prioritty":1}`, "unknown field", ""},

		{KindNtfy, `{"topic":"waxdeck"}`, "", "ntfy.sh"},
		{KindNtfy, `{"topic":"waxdeck","serverUrl":"https://ntfy.example.net/"}`, "", "ntfy.example.net"},
		{KindNtfy, `{"topic":""}`, "needs a topic", ""},
		{KindNtfy, `{"topic":"a/b"}`, "single name", ""},
		{KindNtfy, `{"topic":"waxdeck","serverUrl":"ftp://x"}`, "http or https", ""},

		{KindGotify, `{"serverUrl":"https://gotify.example.net","token":"tok"}`, "", "gotify.example.net"},
		{KindGotify, `{"serverUrl":"","token":"tok"}`, "needs a serverUrl", ""},
		{KindGotify, `{"serverUrl":"https://g.example","token":""}`, "needs an application token", ""},
		{KindGotify, `{"serverUrl":"https://g.example","token":"t","priority":11}`, "between 0 and 10", ""},

		{KindDiscord, `{"webhookUrl":"https://discord.com/api/webhooks/1/abc"}`, "", ""},
		{KindDiscord, `{"webhookUrl":"https://discordapp.com/api/webhooks/1/abc"}`, "", ""},
		{KindDiscord, `{"webhookUrl":"http://discord.com/api/webhooks/1/abc"}`, "https", ""},
		{KindDiscord, `{"webhookUrl":"https://evil.example/api/webhooks/1/abc"}`, "discord.com or discordapp.com", ""},
		{KindDiscord, `{"webhookUrl":"https://discord.com/oops"}`, "webhook URL", ""},

		{KindWebhook, `{"url":"https://hooks.example.net/x"}`, "", "hooks.example.net"},
		{KindWebhook, `{"url":"gopher://x"}`, "http or https", ""},

		{KindApprise, `{"serverUrl":"https://apprise.example.net"}`, "", "apprise.example.net"},
		{KindApprise, `{"serverUrl":"https://apprise.example.net","targets":"pover://a@b"}`, "", "apprise.example.net"},
		{KindApprise, `{"serverUrl":""}`, "needs a serverUrl", ""},

		{KindUnifiedPush, `{"endpoint":"https://push.example.net/ep/1"}`, "", ""},
		{KindUnifiedPush, `{"endpoint":"http://push.example.net/ep/1"}`, "https", ""},
	}
	for _, tc := range cases {
		p, ok := ByKind(tc.kind)
		if !ok {
			t.Fatalf("no provider for %s", tc.kind)
		}
		norm, host, err := p.ValidateConfig(json.RawMessage(tc.config))
		if tc.wantErr == "" {
			if err != nil {
				t.Errorf("%s %s: unexpected error %v", tc.kind, tc.config, err)
				continue
			}
			if host != tc.wantHost {
				t.Errorf("%s %s: userHost = %q, want %q", tc.kind, tc.config, host, tc.wantHost)
			}
			if !json.Valid(norm) {
				t.Errorf("%s %s: normalized config is not JSON", tc.kind, tc.config)
			}
			continue
		}
		if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
			t.Errorf("%s %s: error = %v, want mention of %q", tc.kind, tc.config, err, tc.wantErr)
		}
	}
}

func TestPushoverPayloadAndTruncation(t *testing.T) {
	s := newSink(t, 200)
	old := pushoverMessageURL
	pushoverMessageURL = s.handler.URL + "/1/messages.json"
	t.Cleanup(func() { pushoverMessageURL = old })

	long := strings.Repeat("é", 2000)
	err := deliver(t, KindPushover, `{"token":"tok","userKey":"key","priority":2}`,
		Message{Event: "test", Title: long, Body: long})
	if err != nil {
		t.Fatal(err)
	}
	form, err := url.ParseQuery(string(s.body))
	if err != nil {
		t.Fatal(err)
	}
	if form.Get("token") != "tok" || form.Get("user") != "key" {
		t.Fatalf("credentials = %q/%q", form.Get("token"), form.Get("user"))
	}
	if got := utf8.RuneCountInString(form.Get("title")); got != pushoverTitleMax {
		t.Fatalf("title runes = %d, want %d", got, pushoverTitleMax)
	}
	if got := utf8.RuneCountInString(form.Get("message")); got != pushoverBodyMax {
		t.Fatalf("message runes = %d, want %d", got, pushoverBodyMax)
	}
	// Emergency priority carries the retry cadence the service demands.
	if form.Get("priority") != "2" || form.Get("retry") != "60" || form.Get("expire") != "3600" {
		t.Fatalf("priority trio = %q/%q/%q", form.Get("priority"), form.Get("retry"), form.Get("expire"))
	}
}

func TestNtfyJSONPublishAndBearer(t *testing.T) {
	s := newSink(t, 200)
	err := deliver(t, KindNtfy,
		`{"topic":"waxdeck","serverUrl":"`+s.handler.URL+`","accessToken":"tk_secret"}`,
		Message{Event: "episode-downloaded", Title: "Tïtle", Body: "Bödy"})
	if err != nil {
		t.Fatal(err)
	}
	if s.path != "/" {
		t.Fatalf("publish path = %q, want the server root (JSON mode)", s.path)
	}
	if got := s.header.Get("Authorization"); got != "Bearer tk_secret" {
		t.Fatalf("auth header = %q", got)
	}
	body := s.jsonBody(t)
	if body["topic"] != "waxdeck" || body["title"] != "Tïtle" || body["message"] != "Bödy" {
		t.Fatalf("publish body = %v", body)
	}
}

func TestGotifyHeaderAuthAndPath(t *testing.T) {
	s := newSink(t, 200)
	err := deliver(t, KindGotify,
		`{"serverUrl":"`+s.handler.URL+`","token":"apptoken","priority":7}`,
		Message{Title: "T", Body: "B"})
	if err != nil {
		t.Fatal(err)
	}
	if s.path != "/message" {
		t.Fatalf("path = %q, want /message", s.path)
	}
	if got := s.header.Get("X-Gotify-Key"); got != "apptoken" {
		t.Fatalf("token header = %q", got)
	}
	body := s.jsonBody(t)
	if body["title"] != "T" || body["message"] != "B" || body["priority"] != float64(7) {
		t.Fatalf("body = %v", body)
	}
}

func TestDiscordEmbedShape(t *testing.T) {
	// The allowlist pins real hosts, so the payload assertion runs the
	// provider over a normalized config rewritten (test-only) to point
	// at the local sink; validation itself is asserted on real hosts.
	s := newSink(t, 204)
	p, _ := ByKind(KindDiscord)
	norm, _, err := p.ValidateConfig(json.RawMessage(`{"webhookUrl":"https://discord.com/api/webhooks/1/abc"}`))
	if err != nil {
		t.Fatal(err)
	}
	norm = json.RawMessage(strings.Replace(string(norm), "https://discord.com", s.handler.URL, 1))
	long := strings.Repeat("x", 9000)
	if err := p.Deliver(context.Background(), http.DefaultClient, norm, Message{Title: long, Body: long}); err != nil {
		t.Fatal(err)
	}
	var payload struct {
		Embeds []struct {
			Title       string `json:"title"`
			Description string `json:"description"`
		} `json:"embeds"`
	}
	if err := json.Unmarshal(s.body, &payload); err != nil || len(payload.Embeds) != 1 {
		t.Fatalf("embed payload = %s (%v)", s.body, err)
	}
	if len(payload.Embeds[0].Title) != discordTitleMax || len(payload.Embeds[0].Description) != discordBodyMax {
		t.Fatalf("embed caps = %d/%d", len(payload.Embeds[0].Title), len(payload.Embeds[0].Description))
	}
}

func TestWebhookDocumentedPayload(t *testing.T) {
	s := newSink(t, 200)
	at := time.Date(2026, 7, 22, 10, 30, 0, 0, time.FixedZone("CDT", -5*3600))
	err := deliver(t, KindWebhook, `{"url":"`+s.handler.URL+`/hook"}`,
		Message{Event: "backup-completed", Title: "T", Body: "B", Timestamp: at})
	if err != nil {
		t.Fatal(err)
	}
	body := s.jsonBody(t)
	want := map[string]any{
		"event": "backup-completed", "title": "T", "body": "B",
		"timestamp": "2026-07-22T15:30:00Z",
	}
	for k, v := range want {
		if body[k] != v {
			t.Fatalf("payload[%s] = %v, want %v", k, body[k], v)
		}
	}
	if len(body) != len(want) {
		t.Fatalf("payload = %v, want exactly the documented fields", body)
	}
}

func TestApprisePathDerivation(t *testing.T) {
	s := newSink(t, 200)
	// A bare base gains /notify.
	if err := deliver(t, KindApprise, `{"serverUrl":"`+s.handler.URL+`","targets":"pover://x@y"}`,
		Message{Title: "T", Body: "B"}); err != nil {
		t.Fatal(err)
	}
	if s.path != "/notify" {
		t.Fatalf("bare-base path = %q, want /notify", s.path)
	}
	body := s.jsonBody(t)
	if body["title"] != "T" || body["body"] != "B" || body["type"] != "info" || body["urls"] != "pover://x@y" {
		t.Fatalf("apprise body = %v", body)
	}
	// A base already naming a path (stateful key) is used as is.
	if err := deliver(t, KindApprise, `{"serverUrl":"`+s.handler.URL+`/notify/mykey"}`,
		Message{Title: "T", Body: "B"}); err != nil {
		t.Fatal(err)
	}
	if s.path != "/notify/mykey" {
		t.Fatalf("keyed path = %q, want /notify/mykey", s.path)
	}
	if body := s.jsonBody(t); body["urls"] != nil {
		t.Fatalf("empty targets must be omitted, got %v", body["urls"])
	}
}

func TestUnifiedPushBudget(t *testing.T) {
	s := newSink(t, 201)
	long := strings.Repeat("ü", 4000)
	// Validation demands https; the sink is plain HTTP, so delivery
	// runs the provider over a rewritten normalized config (test-only).
	p, _ := ByKind(KindUnifiedPush)
	norm := json.RawMessage(`{"endpoint":"` + s.handler.URL + `/ep"}`)
	if err := p.Deliver(context.Background(), http.DefaultClient, norm,
		Message{Event: "episode-downloaded", Title: "T", Body: long}); err != nil {
		t.Fatal(err)
	}
	if len(s.body) > pushBodyByteBudget {
		t.Fatalf("payload = %d bytes, want at most %d", len(s.body), pushBodyByteBudget)
	}
	if !utf8.Valid(s.body) {
		t.Fatal("payload is not valid UTF-8 after truncation")
	}
	var m map[string]string
	if err := json.Unmarshal(s.body, &m); err != nil {
		t.Fatalf("payload is not JSON: %v", err)
	}
	if m["event"] != "episode-downloaded" || m["title"] != "T" || m["body"] == "" {
		t.Fatalf("payload = %v", m)
	}
}

func TestStatusClassification(t *testing.T) {
	cases := []struct {
		status    int
		permanent bool
		retryable bool
	}{
		{200, false, false},
		{204, false, false},
		{400, true, false},
		{401, true, false},
		{404, true, false},
		{408, false, true},
		{429, false, true},
		{500, false, true},
		{503, false, true},
	}
	for _, tc := range cases {
		s := newSink(t, tc.status)
		err := deliver(t, KindWebhook, `{"url":"`+s.handler.URL+`"}`, Message{Title: "T"})
		switch {
		case tc.status < 300:
			if err != nil {
				t.Errorf("status %d: error %v, want success", tc.status, err)
			}
		case tc.permanent:
			if !IsPermanent(err) {
				t.Errorf("status %d: error %v, want permanent", tc.status, err)
			}
		default:
			if err == nil || IsPermanent(err) {
				t.Errorf("status %d: error %v, want a retryable error", tc.status, err)
			}
		}
	}
}

func TestPushBodyBudget(t *testing.T) {
	// The direct unit test for the budget walker: a pathological title
	// alone forces the body-free fallback shape.
	msg := Message{Event: "e", Title: strings.Repeat("t", 4000), Body: "b"}
	raw := pushBody(msg)
	var m map[string]string
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	if _, ok := m["body"]; ok {
		t.Fatalf("oversized title must drop the body, got %v", m)
	}
	// 2334 three-byte euros (7002 bytes) force the halving loop, and
	// the first halving lands mid-rune; the payload must fit the
	// budget with no replacement characters in the delivered text.
	msg = Message{Event: "test", Title: "Budget", Body: strings.Repeat("€", 2334)}
	raw = pushBody(msg)
	if len(raw) > pushBodyByteBudget {
		t.Fatalf("payload = %d bytes, want <= %d", len(raw), pushBodyByteBudget)
	}
	var got map[string]string
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("payload does not parse: %v", err)
	}
	if got["body"] == "" {
		t.Fatal("body was dropped entirely; halving should have fit it")
	}
	if strings.ContainsRune(got["body"], '�') {
		t.Fatalf("delivered body carries a replacement character: %q", got["body"][:12])
	}
}

func TestPinnedHostErrorDetailSurfaced(t *testing.T) {
	// Pushover's fixed host means the response can only be the
	// service's own error document; its text rides the error onto the
	// health fields instead of a bare 400.
	s := newSink(t, 400)
	s.reply = []byte(`{"errors":["application token is invalid"],"status":0}`)
	old := pushoverMessageURL
	pushoverMessageURL = s.handler.URL + "/1/messages.json"
	t.Cleanup(func() { pushoverMessageURL = old })
	err := deliver(t, KindPushover, `{"token":"bad","userKey":"key"}`, Message{Title: "T"})
	if !IsPermanent(err) {
		t.Fatalf("pushover 400 = %v, want permanent", err)
	}
	if !strings.Contains(err.Error(), "status 400") || !strings.Contains(err.Error(), "application token is invalid") {
		t.Fatalf("pushover error = %v, want the service's own text", err)
	}

	// Discord shapes its errors as a message field.
	d := newSink(t, 400)
	d.reply = []byte(`{"message":"Invalid Webhook Token","code":50027}`)
	p, _ := ByKind(KindDiscord)
	norm, _, err := p.ValidateConfig(json.RawMessage(`{"webhookUrl":"https://discord.com/api/webhooks/1/abc"}`))
	if err != nil {
		t.Fatal(err)
	}
	norm = json.RawMessage(strings.Replace(string(norm), "https://discord.com", d.handler.URL, 1))
	err = p.Deliver(context.Background(), http.DefaultClient, norm, Message{Title: "T"})
	if err == nil || !strings.Contains(err.Error(), "Invalid Webhook Token") {
		t.Fatalf("discord error = %v, want the service's own text", err)
	}
}

func TestUserPointedResponsesNeverSurfaced(t *testing.T) {
	// User-pointed destinations must not become a response-content
	// oracle: a webhook's or push endpoint's reply body stays out of
	// the error no matter what it says.
	for _, kind := range []string{KindWebhook, KindUnifiedPush} {
		s := newSink(t, 404)
		s.reply = []byte("internal-banner: build 7.3.1 secret")
		p, _ := ByKind(kind)
		config := json.RawMessage(`{"url":"` + s.handler.URL + `"}`)
		if kind == KindUnifiedPush {
			config = json.RawMessage(`{"endpoint":"` + s.handler.URL + `"}`)
		}
		err := p.Deliver(context.Background(), http.DefaultClient, config, Message{Title: "T"})
		if err == nil || !strings.Contains(err.Error(), "status 404") {
			t.Fatalf("%s 404 = %v, want the status", kind, err)
		}
		if strings.Contains(err.Error(), "internal-banner") {
			t.Fatalf("%s error leaked the response body: %v", kind, err)
		}
	}
}

func TestErrorSnippetShapes(t *testing.T) {
	cases := []struct {
		body string
		want string
	}{
		{`{"errors":["token invalid","user invalid"],"status":0}`, "token invalid, user invalid"},
		{`{"message":"Invalid Webhook Token","code":50027}`, "Invalid Webhook Token"},
		{`{"error":"unauthorized"}`, "unauthorized"},
		{`{"status":0}`, `{"status":0}`},
		{"plain text\nwith\tcontrol chars", "plain text with control chars"},
		{"", ""},
		{"bad\xffutf8", "badutf8"},
	}
	for _, tc := range cases {
		if got := errorSnippet(strings.NewReader(tc.body)); got != tc.want {
			t.Errorf("errorSnippet(%q) = %q, want %q", tc.body, got, tc.want)
		}
	}
	// Oversize bodies cap at one short line.
	long := errorSnippet(strings.NewReader(strings.Repeat("x", 5000)))
	if len(long) > 256 {
		t.Fatalf("snippet length = %d, want capped", len(long))
	}
}

func TestPushBodyToleratesInvalidUTF8Input(t *testing.T) {
	// A body that was invalid to begin with still delivers: the cut
	// repair only backs off over the cut itself, never giving up on
	// the whole string. Short invalid input passes through untouched.
	raw := pushBody(Message{Event: "e", Title: "t", Body: "\xffhello"})
	var m map[string]string
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(m["body"], "hello") {
		t.Fatalf("short invalid body = %q, want the text kept", m["body"])
	}
	// Long invalid-prefixed input truncates to budget without dropping
	// the body outright.
	raw = pushBody(Message{Event: "e", Title: "t", Body: "\xff" + strings.Repeat("é", 4000)})
	if len(raw) > pushBodyByteBudget {
		t.Fatalf("payload = %d bytes, want within budget", len(raw))
	}
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	if len(m["body"]) < 64 {
		t.Fatalf("body = %q, want a real truncation, not a drop", m["body"])
	}
}
