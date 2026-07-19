package service

import "testing"

func TestParseTranscriptVTT(t *testing.T) {
	body := "WEBVTT\n\nNOTE styling ahead\n\n00:00.000 --> 00:01.500\n<v Ada>Hello <b>there</b></v>\n\n00:01.500 --> 00:03.000 align:start\n<c.highlight>General &amp; specific</c> <i>fixture</i>\n"
	tx, err := parseTranscript([]byte(body), "text/vtt", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if tx.Format != "vtt" || len(tx.Cues) != 2 {
		t.Fatalf("transcript = %+v", tx)
	}
	if tx.Cues[0].Speaker != "Ada" || tx.Cues[0].Text != "Hello there" {
		t.Fatalf("voice cue = %+v (markup must be stripped)", tx.Cues[0])
	}
	if tx.Cues[1].Text != "General & specific fixture" {
		t.Fatalf("styled cue = %q, want tags gone and the ampersand decoded", tx.Cues[1].Text)
	}
	if tx.Cues[1].StartMS != 1500 || tx.Cues[1].EndMS != 3000 {
		t.Fatalf("cue timing = %+v", tx.Cues[1])
	}
}

func TestParseTranscriptSRT(t *testing.T) {
	body := "1\n00:00:01,000 --> 00:00:02,500\n<i>Quiet</i> start\n\n2\n01:00:03,000 --> 01:00:04,000\nHost: welcome back\n"
	tx, err := parseTranscript([]byte(body), "", "application/srt", "")
	if err != nil {
		t.Fatal(err)
	}
	if tx.Format != "srt" || len(tx.Cues) != 2 {
		t.Fatalf("transcript = %+v", tx)
	}
	if tx.Cues[0].Text != "Quiet start" || tx.Cues[0].StartMS != 1000 {
		t.Fatalf("first cue = %+v", tx.Cues[0])
	}
	if tx.Cues[1].Speaker != "Host" || tx.Cues[1].Text != "welcome back" {
		t.Fatalf("speaker cue = %+v", tx.Cues[1])
	}
	if tx.Cues[1].StartMS != 3603000 {
		t.Fatalf("hour offset = %d, want 3603000", tx.Cues[1].StartMS)
	}
}

func TestParseTranscriptJSONAndSniffing(t *testing.T) {
	body := `{"segments":[{"startTime":1.5,"endTime":3,"speaker":"Ada","body":"Hello"},{"startTime":3,"body":"  "}]}`
	tx, err := parseTranscript([]byte(body), "", "", "https://example.com/t")
	if err != nil {
		t.Fatal(err)
	}
	if tx.Format != "json" || len(tx.Cues) != 1 {
		t.Fatalf("transcript = %+v (blank segments drop)", tx)
	}
	if tx.Cues[0].StartMS != 1500 || tx.Cues[0].EndMS != 3000 || tx.Cues[0].Speaker != "Ada" {
		t.Fatalf("json cue = %+v", tx.Cues[0])
	}

	plain, err := parseTranscript([]byte("just words, no timing"), "", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if plain.Format != "text" || len(plain.Cues) != 1 || plain.Cues[0].StartMS != 0 {
		t.Fatalf("plain transcript = %+v", plain)
	}
}

func TestStripCueMarkup(t *testing.T) {
	cases := map[string]string{
		"plain words":                         "plain words",
		"<b>bold</b> and <c.red>class</c>":    "bold and class",
		"a &lt;tag&gt; &amp; more":            "a <tag> & more",
		"<00:00:01.000>karaoke<00:00:02.000>": "karaoke",
		"<v Ada>unclosed":                     "unclosed",
	}
	for in, want := range cases {
		if got := stripCueMarkup(in); got != want {
			t.Fatalf("stripCueMarkup(%q) = %q, want %q", in, got, want)
		}
	}
}
