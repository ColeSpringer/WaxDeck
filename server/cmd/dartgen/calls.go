// The operation side. Per tag, api/<tag>_api.g.dart declares the
// interface, abstract interface class <Tag>Api, and calls.g.dart, the one
// part of the package's client.dart, the mixin _<Tag>Calls making its
// calls over the transport client.dart defines: _WaxDeckTransport's
// _send, _guard, _decode and _wire, and the const _longOperation.
// api.g.dart exports every interface and declares WaxDeckApi, which
// implements them all; calls.g.dart also declares _WaxDeckCalls, the
// transport with every mixin applied, which WaxDeckClient extends. A new
// tag needs no hand edit there.
//
// Raw calls: every operation not skipped has _<operationId>, the request
// as the spec states it. Path parameters are positional in path order, a
// string's text (an enum's wire name, a date's) through
// Uri.encodeComponent, a number's or bool's as is; query and header
// parameters are named, take the spec default as their Dart default (a
// parameter's schema's own, else, a $ref or an allOf wrapper around one,
// its target's) and are sent whenever non-null; the body is named body, a
// JSON one through the codec, then through jsonEncode where its value may
// be a string, which Dio would send unquoted (nullable when the spec makes
// it optional), a binary one a Stream<List<int>> plus its length, sent as
// Content-Length (a stream body is sent chunked unless the length is
// declared, and the server checks its room and its cap against what the
// request says it is sending). Names are the spec's in lowerCamelCase. A
// non-JSON response asks for bytes when its schema is format binary, else
// for text; an event stream, read whole once it ends, takes skip or hand.
// Where 2xx responses carry different types, the raw call of a method's
// operation accepts only the statuses of the first's type, so another 2xx
// fails as the error it is rather than decoding as the wrong type. The raw
// calls of hand and raw operations instead take cancelToken,
// onSendProgress, validateStatus and extra, which the hand-written code
// calling them needs.
//
// Methods: every operation neither raw nor skipped has one on the
// interface and, unless hand, its override in the mixin: _guard around
// the raw call, and _decode reading the answer with the codec's reader
// (an unwrapped property read inside it). Its signature,
// before the hints adjust it: path parameters positional in path order;
// then named the body (a JSON object body flattened into its model's
// fields: a defaulted one taking the model's default, the other required
// ones required, the rest nullable, and one sharing a parameter's name
// failing the run; any other body, or a hand class's, as one parameter),
// then the query and header parameters, nullable and without a default
// unless required. Every argument is passed on explicitly, so an omitted
// one stays unsent. It answers the first 2xx response's type (an object
// whole, however few its properties), text as String, bytes as Uint8List,
// no content as void. An unwrapped property the response's schema
// requires is non-null even where a fold leaves its field optional on the
// base.
package main

import (
	"fmt"
	"maps"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/getkin/kin-openapi/openapi3"
)

// responseVar is the local a method keeps the raw call's answer in.
const responseVar = "response"

// opByID is the operation of that operationId, or nil.
func (s *spec) opByID(id string) *operation {
	for _, op := range s.ops {
		if op.id == id {
			return op
		}
	}
	return nil
}

// rawArg is one path, query or header parameter of a raw call.
type rawArg struct {
	spec     string
	name     string
	in       string // path, query or header
	t        *dartType
	required bool
	def      string // the spec default (query and header)
}

type callBody struct {
	binary   bool
	t        *dartType // a JSON body's type
	required bool
	mime     string
}

type resultKind int

const (
	noContent resultKind = iota
	jsonResult
	textResult
	bytesResult
)

type call struct {
	op     *operation
	hint   operationHint
	key    string // operations.<id>
	path   []*rawArg
	named  []*rawArg // query then header, in document order
	body   *callBody
	result resultKind
	rt     *dartType // a JSON result's type
	rs     string    // the component schema a JSON result names, if it names one
	accept []string  // the statuses a split answer accepts; nil accepts every 2xx
	knobs  bool
	method *method // nil for a raw operation
}

func (c *call) rawName() string { return "_" + c.op.id }

// signatureTypes is the types c's method names in its signature: its
// parameters', the omitted ones aside, and its answer's.
func (c *call) signatureTypes() []*dartType {
	mt := c.method
	var out []*dartType
	for _, p := range mt.params {
		if !p.omit && p.t != nil {
			out = append(out, p.t)
		}
	}
	switch {
	case mt.unwrap != nil:
		out = append(out, mt.unwrap.typ)
	case c.result == jsonResult:
		out = append(out, c.rt)
	}
	return out
}

// methodParam is one parameter of a method.
type methodParam struct {
	key      string // its spec name, or the name body or length gives it
	name     string
	in       string // path, query, header, field, body or length
	typ      string // as declared
	t        *dartType
	required bool // a required named parameter
	def      string
	hinted   bool // def came from a hint, not the model
	omit     bool
	ifTrue   bool   // omitFalse
	orElse   string // what a null sends instead (nullable)
	raw      *rawArg
	field    *field
}

type method struct {
	name       string
	ret        string
	positional []*methodParam
	named      []*methodParam
	params     []*methodParam // every parameter, the omitted ones included
	flatten    *class         // the body's model when its fields are parameters
	stream     *methodParam   // a streamed binary body's length parameter
	unwrap     *field
	read       string // the WireRead _decode reads the answer's body with
}

type calls struct {
	m     *model
	g     *codecGen
	byTag map[string][]*call
	tags  []string
	p     problems
	// private is the private names client.dart declares, which no raw
	// call may take; nil when no hand-written package is checked.
	private map[string]string
}

func buildCalls(m *model) (*calls, error) {
	// The call side's codec has no keep predicates or known sets: result
	// refuses a decode that would need them.
	cs := &calls{
		m:     m,
		g:     &codecGen{f: newDartFile(codecFile), ctx: "_wire"},
		byTag: map[string][]*call{},
	}
	if m.hand != nil {
		cs.private = m.hand.privates()
	}
	for _, op := range m.spec.ops {
		hint := m.hints.Operations[op.id]
		c := &call{op: op, hint: hint, key: "operations." + op.id}
		if hint.Skip {
			cs.checkModeOnly(c, "skip")
			continue
		}
		if !cs.buildRaw(c) {
			continue
		}
		if hint.Raw {
			cs.checkModeOnly(c, "raw")
		} else {
			c.method = cs.buildMethod(c)
		}
		if _, ok := cs.byTag[op.tag]; !ok {
			cs.tags = append(cs.tags, op.tag)
		}
		cs.byTag[op.tag] = append(cs.byTag[op.tag], c)
	}
	cs.checkSkipped()
	cs.checkNames()
	if err := cs.p.err(); err != nil {
		return nil, err
	}
	return cs, nil
}

// checkSkipped fails a call that sends or answers a skipped class.
func (cs *calls) checkSkipped() {
	for _, tag := range cs.tags {
		for _, c := range cs.byTag[tag] {
			for _, t := range c.uses() {
				if s := skippedIn(t); s != nil {
					cs.p.add("hints: models.%s.skip: %s needs it", s.schema, c.op.id)
				}
			}
		}
	}
}

// uses is the types c's raw call encodes and its method names or
// decodes.
func (c *call) uses() []*dartType {
	var out []*dartType
	if b := c.body; b != nil && !b.binary {
		out = append(out, b.t)
	}
	if c.method != nil {
		out = append(out, c.signatureTypes()...)
		if c.result == jsonResult {
			out = append(out, c.rt)
		}
	}
	return out
}

// checkModeOnly fails the keys that shape a method on an operation that
// makes none.
func (cs *calls) checkModeOnly(c *call, mode string) {
	h := c.hint
	var keys []string
	add := func(on bool, k string) {
		if on {
			keys = append(keys, k)
		}
	}
	add(h.As != "", "as")
	add(h.Doc != "", "doc")
	add(h.Positional != nil, "positional")
	add(h.Named != nil, "named")
	add(len(h.NullOn) > 0, "nullOn")
	add(h.Long && mode == "skip", "long")
	add(h.Body != "", "body")
	add(h.Length != "", "length")
	add(h.Unwrap != "", "unwrap")
	add(len(h.Params) > 0, "params")
	for _, k := range keys {
		cs.p.add("hints: %s.%s: %s makes no method for it to shape", c.key, k, mode)
	}
}

func (cs *calls) buildRaw(c *call) bool {
	op, at := c.op, c.op.id
	c.knobs = c.hint.Hand || c.hint.Raw
	ok := true
	switch what, taken := cs.private[c.rawName()]; {
	case !identifier.MatchString(op.id):
		cs.p.add("spec: %s: the operationId makes no Dart name for its raw call", at)
		ok = false
	case taken:
		cs.p.add("spec: %s: its raw call %s would take the name of %s, which client.dart declares; rename one of them", at, c.rawName(), what)
		ok = false
	}
	for _, name := range pathNames(op.path) {
		v := op.params.GetByInAndName("path", name)
		if v == nil {
			cs.p.add("spec: %s: the path names {%s}, which no path parameter declares", at, name)
			ok = false
			continue
		}
		if a := cs.rawArg(op, v); a != nil {
			c.path = append(c.path, a)
		} else {
			ok = false
		}
	}
	for _, in := range []string{"query", "header"} {
		for _, prm := range op.params {
			if v := prm.Value; v != nil && v.In == in {
				if a := cs.rawArg(op, v); a != nil {
					c.named = append(c.named, a)
				} else {
					ok = false
				}
			}
		}
	}
	for _, prm := range op.params {
		if v := prm.Value; v != nil && v.In == "cookie" {
			cs.p.add("spec: %s: the cookie parameter %s has no mapping", at, v.Name)
			ok = false
		}
	}
	if !cs.rawBody(c) || !cs.rawResult(c) {
		ok = false
	}
	seen := map[string]bool{}
	names := []string{}
	for _, a := range append(slices.Clone(c.path), c.named...) {
		names = append(names, a.name)
	}
	if c.body != nil {
		names = append(names, "body")
		if c.body.binary {
			names = append(names, "length")
		}
	}
	if c.knobs {
		names = append(names, "cancelToken", "onSendProgress", "validateStatus", "extra")
	}
	for _, n := range names {
		if seen[n] {
			cs.p.add("spec: %s: two parameters of its raw call take the name %s", at, n)
			ok = false
		}
		seen[n] = true
	}
	return ok
}

func pathNames(p string) []string {
	var out []string
	for _, m := range pathParam.FindAllStringSubmatch(p, -1) {
		out = append(out, m[1])
	}
	return out
}

var pathParam = regexp.MustCompile(`\{([^{}]+)\}`)

func (cs *calls) rawArg(op *operation, v *openapi3.Parameter) *rawArg {
	at := op.id + "." + v.Name
	a := &rawArg{spec: v.Name, name: lowerCamel(v.Name), in: v.In, required: v.Required || v.In == "path"}
	if msg := fieldNameProblem(a.name); msg != "" {
		cs.p.add("spec: %s: the parameter name %s makes %s, which %s", op.id, v.Name, a.name, msg)
		return nil
	}
	if v.Schema == nil {
		cs.p.add("spec: %s: the parameter has no schema", at)
		return nil
	}
	t, err := cs.m.typeOf(v.Schema, at, at)
	if err != nil {
		cs.p.add("spec: %v", err)
		return nil
	}
	if !scalar(t) {
		cs.p.add("spec: %s: a %s parameter has no %s encoding; carry it in a JSON body or as one delimited string, or skip the operation with operations.%s.skip",
			at, t.dart(), v.In, op.id)
		return nil
	}
	if t.kind == kEnum && t.enum.drop {
		cs.p.add("hints: enums.%s: fallback drop acts on lists, and %s is a parameter", t.enumKey, at)
		return nil
	}
	a.t = t
	// The schema's own default, else (a $ref, or an allOf wrapper around
	// one) its target's.
	def := v.Schema.Value.Default
	if def == nil {
		def = refOf(v.Schema).Value.Default
	}
	if !a.required && def != nil {
		if a.def, err = constLiteral(t, def); err != nil {
			cs.p.add("spec: %s: default: %v", at, err)
			return nil
		}
	}
	return a
}

func scalar(t *dartType) bool {
	switch t.kind {
	case kString, kInt, kDouble, kBool, kDateTime, kDate, kEnum:
		return true
	}
	return false
}

func (cs *calls) rawBody(c *call) bool {
	rb := c.op.op.RequestBody
	if rb == nil || rb.Value == nil || len(rb.Value.Content) == 0 {
		return true
	}
	at := c.op.id + " request body"
	for _, mime := range slices.Sorted(maps.Keys(rb.Value.Content)) {
		if isJSON(mime) {
			t, err := cs.m.typeOf(rb.Value.Content[mime].Schema, at, "")
			if err != nil {
				cs.p.add("spec: %v", err)
				return false
			}
			c.body = &callBody{t: t, required: rb.Value.Required, mime: mime}
			return true
		}
	}
	mime := slices.Sorted(maps.Keys(rb.Value.Content))[0]
	if s := rb.Value.Content[mime].Schema; s == nil || s.Value == nil || !s.Value.Type.Is("string") || s.Value.Format != "binary" {
		cs.p.add("spec: %s: a %s body is neither JSON nor format binary, and has no mapping", at, mime)
		return false
	}
	if !rb.Value.Required {
		cs.p.add("spec: %s: an optional binary body has no mapping", at)
		return false
	}
	c.body = &callBody{binary: true, required: true, mime: mime}
	return true
}

func (cs *calls) rawResult(c *call) bool {
	if c.op.op.Responses == nil {
		return true
	}
	all := c.op.op.Responses.Map()
	type answer struct{ status, dart string }
	var answers []answer
	for _, status := range slices.Sorted(maps.Keys(all)) {
		r := all[status]
		if !strings.HasPrefix(status, "2") || r == nil || r.Value == nil {
			continue
		}
		kind, t, rs := noContent, (*dartType)(nil), ""
		if mimes := slices.Sorted(maps.Keys(r.Value.Content)); len(mimes) > 0 {
			if slices.ContainsFunc(mimes, isEventStream) && !c.hint.Hand {
				cs.p.add("spec: %s answers text/event-stream, which a generated call reads whole once the stream ends; skip it with %s.skip, or write it by hand with %s.hand",
					c.op.id, c.key, c.key)
				return false
			}
			kind = textResult
			if s := r.Value.Content[mimes[0]].Schema; s != nil && s.Value != nil && s.Value.Format == "binary" {
				kind = bytesResult
			}
			for _, mime := range mimes {
				if isJSON(mime) {
					var err error
					s := r.Value.Content[mime].Schema
					if t, err = cs.m.typeOf(s, c.op.id+" response "+status, ""); err != nil {
						cs.p.add("spec: %v", err)
						return false
					}
					kind = jsonResult
					if s != nil {
						rs, _ = componentName(refOf(s).Ref)
					}
					break
				}
			}
		}
		dart := map[resultKind]string{noContent: "void", textResult: "String", bytesResult: "Uint8List"}[kind]
		if t != nil {
			dart = t.dart()
		}
		if len(answers) == 0 {
			c.result, c.rt, c.rs = kind, t, rs
		}
		answers = append(answers, answer{status, dart})
	}
	if c.knobs || !slices.ContainsFunc(answers, func(a answer) bool { return a.dart != answers[0].dart }) {
		return true
	}
	for _, a := range answers {
		if _, err := strconv.Atoi(a.status); err != nil || len(a.status) != 3 {
			cs.p.add("spec: %s answers 2xx statuses of different types, and the status range %s cannot say which to accept", c.op.id, a.status)
			return false
		}
		if a.dart == answers[0].dart {
			c.accept = append(c.accept, a.status)
		}
	}
	return true
}

func (cs *calls) buildMethod(c *call) *method {
	op, h, key := c.op, c.hint, c.key
	mt := &method{name: op.id}
	if h.As != "" {
		mt.name = h.As
	} else if msg := fieldNameProblem(op.id); msg != "" {
		cs.p.add("spec: %s: the operationId %s; rename the method with %s.as", op.id, msg, key)
	}
	bySpec := map[string]*methodParam{}
	addParam := func(p *methodParam) {
		mt.params = append(mt.params, p)
		bySpec[p.key] = p
	}
	for _, a := range c.path {
		addParam(&methodParam{key: a.spec, name: a.name, in: "path", t: a.t, typ: a.t.dart(), required: true, raw: a})
	}
	if b := c.body; b != nil {
		mt.flatten = cs.flattenable(c)
		switch {
		case mt.flatten != nil:
			for _, f := range mt.flatten.all() {
				// A default makes even a required field's parameter optional,
				// as in the model's constructor.
				addParam(&methodParam{key: f.prop, name: f.name, in: "field", t: f.typ, typ: f.dart(), required: f.required && f.def == "", def: f.def, field: f})
			}
		case b.binary && h.Length != "":
			if msg := fieldNameProblem(h.Length); msg != "" {
				cs.p.add("hints: %s.length: %s %s", key, h.Length, msg)
			}
			mt.stream = &methodParam{key: h.Length, name: h.Length, in: "length", typ: "int", t: &dartType{kind: kInt}, required: true}
			addParam(mt.stream)
			addParam(&methodParam{key: bodyName(h), name: bodyName(h), in: "body", typ: "Stream<List<int>> Function()", required: true})
		case b.binary:
			addParam(&methodParam{key: bodyName(h), name: bodyName(h), in: "body", typ: "Uint8List", t: &dartType{kind: kBytes}, required: true})
		default:
			p := &methodParam{key: bodyName(h), name: bodyName(h), in: "body", t: b.t, typ: b.t.dart(), required: b.required}
			if !b.required && b.t.kind != kAny {
				p.typ += "?"
			}
			addParam(p)
		}
		if h.Body != "" {
			if msg := fieldNameProblem(h.Body); msg != "" {
				cs.p.add("hints: %s.body: %s %s", key, h.Body, msg)
			}
		}
		if h.Length != "" && !b.binary {
			cs.p.add("hints: %s.length: the body is not binary", key)
		}
	} else {
		if h.Body != "" {
			cs.p.add("hints: %s.body: %s has no request body", key, op.id)
		}
		if h.Length != "" {
			cs.p.add("hints: %s.length: %s has no request body", key, op.id)
		}
	}
	for _, a := range c.named {
		p := &methodParam{key: a.spec, name: a.name, in: a.in, t: a.t, typ: a.t.dart(), required: a.required, raw: a}
		if !a.required {
			p.typ += "?"
		}
		addParam(p)
	}
	for _, name := range slices.Sorted(maps.Keys(h.Params)) {
		p := bySpec[name]
		if p == nil || p.in == "body" || p.in == "length" {
			cs.p.add("hints: %s.params.%s: %s has no parameter or body field %s", key, name, op.id, name)
			continue
		}
		cs.applyParamHint(c, p, h.Params[name])
	}
	cs.arrange(c, mt, bySpec)
	cs.result(c, mt)
	return mt
}

func bodyName(h operationHint) string {
	if h.Body != "" {
		return h.Body
	}
	return "body"
}

// flattenable is the body's model when its fields become the method's
// parameters: a generated class, unless body takes it whole. A field
// sharing a parameter's spec name fails the run, the two having one key.
func (cs *calls) flattenable(c *call) *class {
	b := c.body
	if b.binary || c.hint.Body != "" || b.t.kind != kClass || b.t.class.hand {
		return nil
	}
	taken := map[string]*rawArg{}
	for _, a := range append(slices.Clone(c.path), c.named...) {
		taken[a.spec] = a
	}
	clash := false
	for _, f := range b.t.class.all() {
		if a := taken[f.prop]; a != nil {
			cs.p.add("spec: %s: the %s parameter %s and the body field %s share a name; take the body whole with %s.body, or rename one in the spec",
				c.op.id, a.in, a.spec, f.prop, c.key)
			clash = true
		}
	}
	if clash {
		return nil
	}
	return b.t.class
}

func (cs *calls) applyParamHint(c *call, p *methodParam, ph paramHint) {
	hand := c.hint.Hand
	pk := c.key + ".params." + p.key
	fail := func(k, format string, args ...any) {
		cs.p.add("hints: %s.%s: %s", pk, k, fmt.Sprintf(format, args...))
	}
	if ph.As != "" {
		if msg := fieldNameProblem(ph.As); msg != "" {
			fail("as", "%s %s", ph.As, msg)
		}
		p.name = ph.As
	}
	if ph.Type != "" {
		switch t := cs.namedType(ph.Type); {
		case !hand:
			fail("type", "only a hand operation's parameter takes a type, for the reshape its hand-written method makes")
		case t == nil:
			fail("type", "%s is neither a dart:core value type nor a generated or hand class or enum", ph.Type)
		default:
			// The model's default is the wire type's, not this one's.
			p.t, p.typ, p.def = t, t.dart(), ""
			if !p.required && p.in != "path" {
				p.typ += "?"
			}
		}
	}
	required := p.required || p.in == "path"
	if ph.Omit {
		switch {
		case p.in == "path":
			fail("omit", "a path parameter is always sent")
		case required && !hand:
			fail("omit", "%s is required", p.key)
		}
		p.omit = true
	}
	if ph.OmitFalse {
		switch {
		case p.in != "query" && p.in != "header":
			fail("omitFalse", "applies to a query or header parameter, and %s is a %s", p.key, inName(p.in))
		case p.t.kind != kBool:
			fail("omitFalse", "needs a bool, and %s is %s", p.key, p.typ)
		case required:
			fail("omitFalse", "%s is required", p.key)
		case ph.Default.Kind != 0:
			fail("omitFalse", "implies the default false; drop default")
		}
		if spec := p.specDefault(); spec != "" && spec != "false" && ph.Type == "" {
			fail("omitFalse", "implies the default false, and the spec's is %s", spec)
		}
		p.ifTrue, p.def, p.hinted, p.typ = true, "false", true, "bool"
	}
	if ph.Default.Kind != 0 {
		switch {
		case required:
			fail("default", "%s is required, so no default applies", p.key)
		case ph.Nullable:
			fail("default", "nullable takes no default")
		default:
			def, built, err := hintLiteral(p.t, ph.Default)
			if err != nil {
				fail("default", "%v", err)
			}
			// Where the spec has a default this restates it; a type
			// hint's default is its own.
			if spec := p.specDefault(); spec != "" && def != "" && ph.Type == "" && def != spec {
				fail("default", "%s differs from the spec's default, %s", def, spec)
			}
			// A class's default is {}, built bare as a field default's is.
			for _, bare := range built {
				for _, f := range bare.needs() {
					fail("default", "%s requires %s, so {} cannot build it", bare.name, f.name)
				}
			}
			p.def, p.hinted, p.typ = def, true, strings.TrimSuffix(p.typ, "?")
			if p.t.kind == kAny {
				fail("default", "%s is untyped, so it takes no default", p.key)
			}
		}
	}
	if ph.Nullable {
		switch {
		case strings.HasSuffix(p.typ, "?"):
			fail("nullable", "%s is nullable already", p.key)
		case p.field != nil && p.field.def != "":
			p.orElse, p.def = p.field.def, ""
		case !hand:
			fail("nullable", "a null %s has no default to send in its place", p.key)
		}
		p.typ += "?"
		p.required = false
	}
}

// specDefault is the default the spec gives p's parameter or body field,
// as a Dart constant of its wire type, or "".
func (p *methodParam) specDefault() string {
	switch {
	case p.raw != nil:
		return p.raw.def
	case p.field != nil:
		return p.field.specDef
	}
	return ""
}

func inName(in string) string {
	if in == "field" {
		return "body field"
	}
	return in + " parameter"
}

// namedType resolves a type hint: a dart:core value type, or a generated
// or hand class or enum by its Dart name.
func (cs *calls) namedType(name string) *dartType {
	switch name {
	case "String":
		return &dartType{kind: kString}
	case "int":
		return &dartType{kind: kInt}
	case "double":
		return &dartType{kind: kDouble}
	case "bool":
		return &dartType{kind: kBool}
	case "DateTime":
		return &dartType{kind: kDateTime}
	}
	// A folded class shares its base's name; skipping it keeps the match
	// independent of map iteration order.
	for _, c := range cs.m.classes {
		if c.name == name && !c.fold && !c.skip {
			return &dartType{kind: kClass, class: c}
		}
	}
	if e := cs.m.enums[name]; e != nil {
		return &dartType{kind: kEnum, enum: e}
	}
	return nil
}

// arrange orders the parameters: positional, then named.
func (cs *calls) arrange(c *call, mt *method, bySpec map[string]*methodParam) {
	key := c.key
	var live []*methodParam
	for _, p := range mt.params {
		if !p.omit {
			live = append(live, p)
		}
	}
	positional := map[*methodParam]bool{}
	if c.hint.Positional != nil {
		for _, name := range c.hint.Positional {
			p := bySpec[name]
			switch {
			case p == nil:
				cs.p.add("hints: %s.positional: %s is not a parameter of %s", key, name, c.op.id)
				continue
			case p.omit:
				cs.p.add("hints: %s.positional: %s is omitted", key, name)
				continue
			case positional[p]:
				cs.p.add("hints: %s.positional: %s is listed twice", key, name)
				continue
			}
			positional[p] = true
			mt.positional = append(mt.positional, p)
		}
	} else {
		for _, p := range live {
			if p.in == "path" {
				positional[p] = true
				mt.positional = append(mt.positional, p)
			}
		}
	}
	// A positional parameter is required: a model default does not apply
	// to it, and a hinted one cannot.
	for _, p := range mt.positional {
		if p.hinted {
			cs.p.add("hints: %s.positional: %s has a default, which a positional parameter cannot take", key, p.key)
		}
		p.def = ""
	}
	order := map[string]int{"path": 0, "length": 1, "body": 2, "field": 2, "query": 3, "header": 4}
	var named []*methodParam
	for _, p := range live {
		if !positional[p] {
			named = append(named, p)
		}
	}
	slices.SortStableFunc(named, func(a, b *methodParam) int { return order[a.in] - order[b.in] })
	if c.hint.Named != nil {
		want := map[string]*methodParam{}
		for _, p := range named {
			want[p.key] = p
		}
		var listed []*methodParam
		for _, name := range c.hint.Named {
			p := want[name]
			switch {
			case p == nil && bySpec[name] != nil && bySpec[name].omit:
				cs.p.add("hints: %s.named: %s is omitted", key, name)
			case p == nil && bySpec[name] != nil:
				cs.p.add("hints: %s.named: %s is not a named parameter", key, name)
			case p == nil:
				cs.p.add("hints: %s.named: %s is not a parameter of %s", key, name, c.op.id)
			case slices.Contains(listed, p):
				cs.p.add("hints: %s.named: %s is listed twice", key, name)
			default:
				listed = append(listed, p)
			}
		}
		for _, p := range named {
			if !slices.Contains(listed, p) {
				cs.p.add("hints: %s.named: %s is missing; named lists every named parameter", key, p.key)
			}
		}
		named = listed
	}
	mt.named = named
	for _, p := range named {
		if p.in == "path" {
			p.required = true
		}
	}
}

func (cs *calls) result(c *call, mt *method) {
	h, key := c.hint, c.key
	if len(h.NullOn) > 0 && c.result == noContent {
		cs.p.add("hints: %s.nullOn: %s answers nothing to give null in place of", key, c.op.id)
	}
	if h.Unwrap != "" {
		var fields []*field
		if c.result == jsonResult && c.rt.kind == kClass && !c.rt.class.hand {
			fields = c.rt.class.all()
		}
		for _, f := range fields {
			if f.prop == h.Unwrap {
				mt.unwrap = f
			}
		}
		switch {
		case fields == nil:
			cs.p.add("hints: %s.unwrap: %s answers no generated class to unwrap", key, c.op.id)
		case mt.unwrap == nil:
			cs.p.add("hints: %s.unwrap: %s has no property %s", key, c.rt.class.schema, h.Unwrap)
		}
	}
	switch c.result {
	case noContent:
		mt.ret = "void"
	case textResult:
		mt.ret, mt.read = "String", "wireString"
	case bytesResult:
		mt.ret = "Uint8List"
		mt.read = "(v, at) => switch (v) {\n      final Uint8List bytes => bytes,\n      final List<int> bytes => Uint8List.fromList(bytes),\n" +
			"      final other => throw FormatException('$at: expected bytes, got ${other.runtimeType}'),\n    }"
	case jsonResult:
		mt.ret = c.rt.dart()
		if listDrops(c.rt) {
			cs.p.add("spec: %s answers a top-level list whose elements drop, which only a class's field can decode; wrap it in an object", c.op.id)
			return
		}
		f := mt.unwrap
		if f == nil {
			mt.read = cs.g.reader(c.rt, 0)
			break
		}
		// The unwrap reads inside the decode, so a missing property fails
		// as the rest of the answer would.
		body := cs.g.read(c.rt, "v", "at", 0) + "." + f.name
		mt.ret = f.dart()
		if f.nullable && cs.foldRequires(c.rs, f.prop) {
			mt.ret = strings.TrimSuffix(mt.ret, "?")
			body += " ?? (throw const FormatException(" + dartString(c.rt.class.name+"."+f.prop+": missing") + "))"
		}
		mt.read = "(v, at) => " + body
	}
	if len(h.NullOn) > 0 && !strings.HasSuffix(mt.ret, "?") {
		mt.ret += "?"
	}
}

// listDrops says whether t, decoded outside a class, holds a list (through
// any lists and maps) that keeps its elements by a predicate (keepsBy).
// The predicates are the model codec's own, so only a class's field can
// decode one.
func listDrops(t *dartType) bool {
	switch t.kind {
	case kList:
		return keepsBy(t.elem) || listDrops(t.elem)
	case kMap:
		return listDrops(t.elem)
	}
	return false
}

// foldRequires says whether schema folds into its base and itself
// requires prop, which the base holds optional: the answer is the
// folded schema's, so its property is there.
func (cs *calls) foldRequires(schema, prop string) bool {
	if c := cs.m.classes[schema]; c == nil || !c.fold {
		return false
	}
	o := cs.m.own(schema)
	ps := o.schemas[prop]
	return o.required[prop] && ps != nil && ps.Value != nil && !ps.Value.Nullable
}

// checkNames fails an interface taking a model type's Dart name, a
// hand-written one or another tag's, two methods taking one name (the
// client implements every interface, so across interfaces too), a method
// taking a member of the hand-written classes the methods land on, and
// two parameters of one method taking one.
func (cs *calls) checkNames() {
	types := map[string]bool{}
	for _, c := range cs.m.classes {
		if !c.skip {
			types[c.name] = true
		}
	}
	for name := range cs.m.enums {
		types[name] = true
	}
	hand, members := map[string]handDecl{}, map[string]string{}
	if cs.m.hand != nil {
		for _, d := range cs.m.hand.publicNames() {
			hand[d.name] = d
		}
		members = cs.m.hand.hostMembers()
		// A hand operation's method is implemented there by design.
		for _, tag := range cs.tags {
			for _, c := range cs.byTag[tag] {
				if c.method != nil && c.hint.Hand {
					delete(members, c.method.name)
				}
			}
		}
	}
	if what, taken := cs.private[callsAggregate]; taken && what == callsAggregate && len(cs.tags) > 0 {
		cs.p.add("names: the calls aggregate %s would take the name of %s, which client.dart declares; rename it", callsAggregate, what)
	}
	interfaces := map[string]string{}
	methods := map[string]string{}
	for _, tag := range cs.tags {
		name := apiName(tag)
		if msg := typeNameProblem(name); msg != "" {
			cs.p.add("spec: tag %q makes the interface %s, which %s", tag, name, msg)
		}
		if prev, ok := interfaces[name]; ok {
			cs.p.add("spec: tags %q and %q both make the interface %s", prev, tag, name)
		}
		interfaces[name] = tag
		if what, taken := cs.private[mixinName(tag)]; taken && what == mixinName(tag) {
			cs.p.add("spec: tag %q: its calls mixin %s would take the name of %s, which client.dart declares; rename one of them", tag, mixinName(tag), what)
		}
		if types[name] {
			cs.p.add("names: the interface of tag %q and a model type both take the Dart name %s", tag, name)
		}
		if d, ok := hand[name]; ok {
			cs.p.add("names: the interface of tag %q and %s both take the Dart name %s", tag, d.label(), name)
		}
		for _, c := range cs.byTag[tag] {
			mt := c.method
			if mt == nil {
				continue
			}
			if prev, ok := methods[mt.name]; ok {
				cs.p.add("names: %s and %s both make the method %s", prev, c.op.id, mt.name)
			}
			methods[mt.name] = c.op.id
			if where, ok := members[mt.name]; ok {
				cs.p.add("names: %s makes the method %s, which %s declares; rename it with %s.as", c.op.id, mt.name, where, c.key)
			}
			seen := map[string]string{}
			for _, p := range mt.params {
				if p.omit {
					continue
				}
				if prev, ok := seen[p.name]; ok {
					cs.p.add("names: %s: %s and %s both take the parameter name %s; rename one with %s.params.<name>.as",
						c.op.id, prev, p.key, p.name, c.key)
				}
				seen[p.name] = p.key
				if p.name == responseVar && c.result != noContent {
					cs.p.add("names: %s: the parameter %s takes the name %s, which its method's answer uses; rename it with %s.params.%s.as",
						c.op.id, p.key, responseVar, c.key, p.key)
				}
			}
		}
	}
}

// apiName is a tag's interface name: admin is AdminApi.
func apiName(tag string) string {
	var b strings.Builder
	for _, part := range strings.FieldsFunc(tag, func(r rune) bool {
		return !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9')
	}) {
		b.WriteString(upperFirst(part))
	}
	return b.String() + "Api"
}
