package metrics

import (
	"bytes"
	"net/http"
	"slices"
	"strconv"
	"strings"
)

// contentType is the Prometheus text exposition format, version 0.0.4.
const contentType = "text/plain; version=0.0.4; charset=utf-8"

// Handler returns an http.Handler that renders the registry in the
// Prometheus text format. Mount it wherever the server routes HTTP
// (conventionally /metrics).
func (r *Registry) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		var buf bytes.Buffer
		r.writeText(&buf)
		h := w.Header()
		h.Set("Content-Type", contentType)
		h.Set("Content-Length", strconv.Itoa(buf.Len()))
		_, _ = w.Write(buf.Bytes())
	})
}

// writeText renders every family, sorted by name, into buf.
func (r *Registry) writeText(buf *bytes.Buffer) {
	r.scrapeSeq.Add(1)
	r.mu.Lock()
	fams := make([]*family, 0, len(r.families))
	for _, f := range r.families {
		fams = append(fams, f)
	}
	r.mu.Unlock()
	slices.SortFunc(fams, func(a, b *family) int { return strings.Compare(a.name, b.name) })
	for _, f := range fams {
		f.writeText(buf)
	}
}

func (f *family) writeText(b *bytes.Buffer) {
	b.WriteString("# HELP ")
	b.WriteString(f.name)
	if f.help != "" {
		b.WriteByte(' ')
		b.WriteString(helpEscaper.Replace(f.help))
	}
	b.WriteByte('\n')
	b.WriteString("# TYPE ")
	b.WriteString(f.name)
	b.WriteByte(' ')
	b.WriteString(f.typ.String())
	b.WriteByte('\n')

	switch {
	case f.counter != nil:
		writeSample(b, f.name, nil, nil, f.counter.value())
	case f.gauge != nil:
		writeSample(b, f.name, nil, nil, f.gauge.value())
	case f.fn != nil:
		writeSample(b, f.name, nil, nil, f.fn())
	case f.cvec != nil:
		for _, ch := range f.cvec.v.children() {
			writeSample(b, f.name, f.cvec.v.labels, ch.vals, ch.c.value())
		}
	case f.gvec != nil:
		for _, ch := range f.gvec.v.children() {
			writeSample(b, f.name, f.gvec.v.labels, ch.vals, ch.c.value())
		}
	case f.hist != nil:
		upper, cum, count, sum := f.hist.snapshot()
		for i, ub := range upper {
			writeSample(b, f.name+"_bucket", leLabel, []string{formatFloat(ub)}, float64(cum[i]))
		}
		writeSample(b, f.name+"_bucket", leLabel, []string{"+Inf"}, float64(count))
		writeSample(b, f.name+"_sum", nil, nil, sum)
		writeSample(b, f.name+"_count", nil, nil, float64(count))
	}
}

var leLabel = []string{"le"}

func writeSample(b *bytes.Buffer, name string, labels, vals []string, v float64) {
	b.WriteString(name)
	if len(labels) > 0 {
		b.WriteByte('{')
		for i, ln := range labels {
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(ln)
			b.WriteString(`="`)
			b.WriteString(labelEscaper.Replace(vals[i]))
			b.WriteByte('"')
		}
		b.WriteByte('}')
	}
	b.WriteByte(' ')
	b.WriteString(formatFloat(v))
	b.WriteByte('\n')
}

// formatFloat renders values with strconv's shortest 'g' representation.
// Whole numbers therefore print as integers ("3", not "3.0") consistently
// across all sample lines, and the special values render as +Inf, -Inf,
// and NaN, which the text format expects.
func formatFloat(v float64) string {
	return strconv.FormatFloat(v, 'g', -1, 64)
}

var (
	// The text format escapes backslash and newline in HELP text, and
	// additionally the double quote in label values.
	helpEscaper  = strings.NewReplacer(`\`, `\\`, "\n", `\n`)
	labelEscaper = strings.NewReplacer(`\`, `\\`, "\n", `\n`, `"`, `\"`)
)
