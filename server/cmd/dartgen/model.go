// The Dart model the files are emitted from, built from the spec and the
// hints by these rules:
//
// Types: string is String (date-time and date DateTime, byte Uint8List,
// password String, and uri-reference, the spec's origin-relative URL, a
// String decoded resolved against the client's base URL), integer int,
// number double, boolean bool, array List<T>, an object with properties
// a class, additionalProperties: {schema} Map<String, T>, a free-form
// object Map<String, Object?>, an untyped schema Object?, a component
// alias its target's type (a string without an enum is String). A listed
// enum is a Dart enum, an unlisted one its base type. An inline object or
// allOf, oneOf, anyOf, not, format binary and additionalProperties beside
// a class's properties have no mapping and fail the run, naming where.
//
// allOf takes exactly one $ref, the base the class extends, plus inline
// object members; a generated class cannot extend a hand one, redeclare
// a base property, declare one in two of its parts, or require one the
// base leaves optional. A class renamed to its base's Dart name folds
// into the base: the base gains its properties, all optional, and every
// reference to it is the base; nothing may extend a folded class.
//
// Fields: a required property is a required parameter, nullable when the
// spec says nullable, or with a hint default a parameter defaulting to it
// (decode still requires the property); an optional one is nullable
// unless its own default: (a $ref'd property takes none from its target,
// and serverDefault leaves it to the server) or a hint default gives it a
// const default, which absent decodes to. An untyped property is Object?,
// and absent decodes null. A default is a JSON value a web build holds
// exactly: no NaN or infinity, no integer beyond 2^53 - 1.
//
// Names are the spec's or the hint's as; enum members are the wire value
// in lowerCamelCase, and an added member is named as written. A reserved
// word fails as any name, a built-in identifier or a dart:core type as a
// type name, an Object member as a field, and values, index, wireName and
// fromWire as an enum member; enum members take no rename, so such an
// enum stays unlisted.
//
// Wire: decode ignores unknown keys, and fails naming class and field on
// a required non-null property absent or null and on a value of the wrong
// shape. Encode sends every non-null field, a defaulted one always and a
// required nullable one as null; an optional null field is absent, and
// omitEmpty, omitDefault and dropNullValues leave out what they name.
//
// Paging: a generated class declaring a nullable nextCursor gets hasMore,
// whether that cursor names a next page, in the extension <Class>Paging
// beside it; one with a more property, which says so itself, gets none.
//
// Docs: a class or field carries its spec description, reflowed; an
// origin-relative URL field's gains a line saying it arrives resolved.
// Files import only what they name.
//
// Files: a class lives in models/<tag>.g.dart for the tag of the first
// operation, in bundle order, that reaches it; models/shared.g.dart holds
// the classes none reaches.
package main

import (
	"fmt"
	"maps"
	"math"
	"path"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
	"unicode"

	"github.com/getkin/kin-openapi/openapi3"
)

type typeKind int

const (
	kString typeKind = iota
	kInt
	kDouble
	kBool
	kDateTime
	kDate
	kBytes
	kAny        // Object?
	kJSONObject // Map<String, Object?>
	kList
	kMap
	kClass
	kEnum
	kDuration // convert: durationMs
	kAPIError // convert: apiError
)

// dartType is a schema as Dart sees it.
type dartType struct {
	kind typeKind
	elem *dartType // kList and kMap
	// nullable marks a list element or map value that may be null; a
	// field's own nullability is field.nullable.
	nullable bool
	class    *class
	schema   string // kClass: the schema named, whose class is its base's when it folds
	enum     *enumDef
	enumKey  string   // the enums key that made enum
	known    []string // kString: the spec enum's values, when it is no Dart enum
	knownAs  string   // the identifier the codec names its set of known after
	url      bool     // kString: an origin-relative URL, decoded resolved
}

func (t *dartType) dart() string {
	var s string
	switch t.kind {
	case kString:
		s = "String"
	case kInt:
		s = "int"
	case kDouble:
		s = "double"
	case kBool:
		s = "bool"
	case kDateTime, kDate:
		s = "DateTime"
	case kBytes:
		s = "Uint8List"
	case kAny:
		return "Object?"
	case kJSONObject:
		s = "Map<String, Object?>"
	case kList:
		s = "List<" + t.elem.dart() + ">"
	case kMap:
		s = "Map<String, " + t.elem.dart() + ">"
	case kClass:
		s = t.class.name
	case kEnum:
		s = t.enum.name
	case kDuration:
		s = "Duration"
	case kAPIError:
		s = "WaxDeckApiException"
	}
	if t.nullable {
		s += "?"
	}
	return s
}

// class is one object schema: emitted, hand-written when hand, or left
// out when skip.
type class struct {
	schema string // the spec's name
	name   string // the Dart name
	doc    string
	hand   bool
	skip   bool
	fold   bool // folded into base, which carries its fields
	base   *class
	subs   []*class
	fields []*field // own, in document order
	file   string   // the model file stem: a tag's, or shared
}

// all is every field of c, the base chain's first.
func (c *class) all() []*field {
	if c.base == nil {
		return c.fields
	}
	return append(slices.Clone(c.base.all()), c.fields...)
}

// params is c's constructor parameters in order: the base's, then c's own
// required ones, then its optional ones.
func (c *class) params() []*field {
	var out []*field
	if c.base != nil {
		out = c.base.params()
	}
	for _, f := range c.fields {
		if f.required {
			out = append(out, f)
		}
	}
	for _, f := range c.fields {
		if !f.required {
			out = append(out, f)
		}
	}
	return out
}

type field struct {
	owner    *class
	src      string // the schema declaring it: the owner's, or the folded class's it came from
	prop     string // the wire name
	name     string // the Dart name
	typ      *dartType
	required bool // the spec requires it
	nullable bool // the Dart field may be null
	def      string
	specDef  string // the spec's own default, whether or not def is it
	doc      string

	emptyAsNull, omitEmpty, omitDefault, dropNullValues bool
	unknownAs                                           *string
}

// dart is the field's declared Dart type.
func (f *field) dart() string {
	if f.nullable && f.typ.kind != kAny {
		return f.typ.dart() + "?"
	}
	return f.typ.dart()
}

type enumDef struct {
	name     string
	doc      string
	key      string   // the first enums key making it
	values   []string // wire values; the added members last
	members  []string // Dart member names, by values
	fallback string   // member an unknown value decodes to
	drop     bool
}

type model struct {
	spec    *spec
	hints   *hints
	classes map[string]*class   // by schema
	enums   map[string]*enumDef // by Dart name
	enumOf  map[string]*enumDef // by enums key
	p       problems
	alias   map[string]bool // component aliases being resolved, against cycles
	// classDefaults is the classes a field's hint default builds bare, by
	// hint key, checked once every constructor is known.
	classDefaults map[string][]*class
	ext           *extensionsFile // nil: no hand extension is checked
	hand          *handPackage    // nil: no hand-written package is checked
}

func buildModel(s *spec, h *hints, ext *extensionsFile, hand *handPackage) (*model, error) {
	m := &model{
		spec: s, hints: h, ext: ext, hand: hand,
		classes: map[string]*class{}, enums: map[string]*enumDef{}, enumOf: map[string]*enumDef{},
		alias: map[string]bool{}, classDefaults: map[string][]*class{},
	}
	checkOperations(s, h, &m.p)
	m.declareClasses()
	m.linkBases()
	m.buildEnums()
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		m.buildFields(m.classes[name])
	}
	m.foldClasses()
	m.checkSkipped()
	m.checkSentOmits()
	m.checkClassDefaults()
	m.checkNames()
	m.checkHandExports()
	m.checkMembers()
	m.placeClasses()
	m.checkDrops()
	if err := m.p.err(); err != nil {
		return nil, err
	}
	return m, nil
}

// generated is the emitted classes, by Dart name.
func (m *model) generated() []*class {
	var out []*class
	for _, c := range m.classes {
		if !c.hand && !c.fold && !c.skip {
			out = append(out, c)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].name < out[j].name })
	return out
}

func (m *model) sortedEnums() []*enumDef {
	out := make([]*enumDef, 0, len(m.enums))
	for _, name := range slices.Sorted(maps.Keys(m.enums)) {
		out = append(out, m.enums[name])
	}
	return out
}

func isClassSchema(v *openapi3.Schema) bool {
	if v == nil {
		return false
	}
	if len(v.AllOf) > 0 || v.Properties != nil {
		return true
	}
	closed := v.AdditionalProperties.Has != nil && !*v.AdditionalProperties.Has
	return v.Type.Is("object") && closed
}

func (m *model) declareClasses() {
	hand := map[string]bool{}
	for _, name := range slices.Sorted(maps.Keys(m.hints.Hand)) {
		switch ref := m.spec.schemas[name]; {
		case ref == nil:
			m.p.add("hints: hand.%s: no such schema", name)
		case !isClassSchema(ref.Value):
			m.p.add("hints: hand.%s: %s is not an object schema", name, name)
		}
		hand[name] = true
	}
	for _, name := range slices.Sorted(maps.Keys(m.spec.schemas)) {
		if !isClassSchema(m.spec.schemas[name].Value) {
			continue
		}
		c := &class{schema: name, name: name, hand: hand[name], skip: m.hints.Models[name].Skip}
		if as := m.hints.Models[name].As; as != "" {
			c.name = as
		}
		m.classes[name] = c
	}
	for _, name := range slices.Sorted(maps.Keys(m.hints.Models)) {
		key := "models." + name
		mh := m.hints.Models[name]
		c := m.classes[name]
		switch {
		case m.spec.schemas[name] == nil:
			m.p.add("hints: %s: no such schema", key)
		case c == nil:
			m.p.add("hints: %s: %s is not an object schema", key, name)
		case c.hand && (len(mh.Omit) > 0 || len(mh.Fields) > 0 || mh.Skip):
			m.p.add("hints: %s: %s is hand-written, so only as applies", key, name)
		case mh.Skip && (mh.As != "" || len(mh.Omit) > 0 || len(mh.Fields) > 0):
			m.p.add("hints: %s: %s is skipped, so no other key applies", key, name)
		}
	}
}

func (m *model) linkBases() {
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		c := m.classes[name]
		v := m.spec.schemas[name].Value
		if len(v.AllOf) == 0 {
			continue
		}
		var bases []string
		for i, member := range v.AllOf {
			if b, ok := componentName(member.Ref); ok {
				bases = append(bases, b)
				continue
			}
			mv := member.Value
			if member.Ref != "" || mv == nil || len(mv.AllOf)+len(mv.OneOf)+len(mv.AnyOf) > 0 || mv.Not != nil ||
				!(mv.Type == nil || mv.Type.Is("object")) {
				m.p.add("spec: %s.allOf[%d]: only a $ref base and inline object members extend a class", name, i)
			}
		}
		if len(bases) != 1 {
			m.p.add("spec: %s: allOf takes exactly one $ref base, not %d", name, len(bases))
			continue
		}
		base := m.classes[bases[0]]
		switch {
		case base == nil:
			m.p.add("spec: %s: allOf base %s is not an object schema", name, bases[0])
		case base.hand && !c.hand:
			m.p.add("hints: hand.%s: %s, which extends it, must be hand-written too", bases[0], name)
		default:
			c.base = base
			base.subs = append(base.subs, c)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		seen := map[*class]bool{}
		for c := m.classes[name]; c != nil; c = c.base {
			if seen[c] {
				m.p.add("spec: %s: allOf bases form a cycle", name)
				m.classes[name].base = nil
				break
			}
			seen[c] = true
		}
	}
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		if c := m.classes[name]; !c.hand && c.base != nil && c.name == c.base.name {
			c.fold = true
		}
	}
	// Before any fold leaves its base's subclasses: one folding into a
	// folded class extends it too.
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		if c := m.classes[name]; c.fold && len(c.subs) > 0 {
			m.p.add("hints: models.%s.as: %s folds into its base %s, so nothing may extend it, and %s does",
				name, name, c.base.schema, c.subs[0].schema)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		if c := m.classes[name]; c.fold {
			c.base.subs = slices.DeleteFunc(c.base.subs, func(s *class) bool { return s == c })
		}
	}
}

// foldClasses moves each folded class's fields into its base. Two folded
// into one base may share a property when its field comes out the same:
// one name, type, default and field hints.
func (m *model) foldClasses() {
	from := map[*field]string{} // a moved field -> the class it came from
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		c := m.classes[name]
		if !c.fold {
			continue
		}
		b := c.base
		for _, f := range c.fields {
			i := slices.IndexFunc(b.fields, func(g *field) bool { return g.prop == f.prop })
			if i < 0 {
				from[f] = name
				f.owner = b
				b.fields = append(b.fields, f)
				continue
			}
			switch g := b.fields[i]; {
			case g.name != f.name || g.dart() != f.dart() || g.def != f.def:
				m.p.add("hints: models.%s.as: %s folds %s into %s, which %s already makes %s %s",
					name, name, f.prop, b.schema, from[g], g.dart(), g.name)
			case !sameURLs(g.typ, f.typ):
				m.p.add("spec: %s and %s fold %s into %s, and differ in which strings are origin-relative URLs (format uri-reference)",
					name, from[g], f.prop, b.schema)
			case !sameHints(g, f):
				m.p.add("hints: models.%s.fields.%s: %s and %s fold %s into %s with different field hints",
					name, f.prop, name, from[g], f.prop, b.schema)
			}
		}
		c.fields = nil
	}
}

// checkSkipped fails a class, generated or hand-written, that still needs
// a skipped one: extends it, or holds it in a field it carries.
func (m *model) checkSkipped() {
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		c := m.classes[name]
		if c.skip || c.fold {
			continue
		}
		if c.base != nil && c.base.skip {
			m.p.add("hints: models.%s.skip: %s extends it", c.base.schema, c.schema)
		}
		for _, p := range m.carried(c) {
			if s := skippedIn(p.typ); s != nil {
				m.p.add("hints: models.%s.skip: %s.%s needs it", s.schema, p.owner, p.prop)
			}
		}
	}
}

// carriedProp is a property a class's decode and encode carry: owner the
// class holding it, src the schema declaring it (a folded class's, when it
// came from one).
type carriedProp struct {
	owner, src, prop string
	typ              *dartType
}

// carried is the properties c's decode and encode carry of its own: a
// generated class's fields, or the ones a hand class covers (what it
// ignores it leaves out).
func (m *model) carried(c *class) []carriedProp {
	var out []carriedProp
	if c.hand {
		covers := m.hints.Hand[c.schema].Covers
		for _, p := range m.handProps(c) {
			if slices.Contains(covers, p.prop) {
				out = append(out, carriedProp{c.schema, c.schema, p.prop, p.typ})
			}
		}
		return out
	}
	for _, f := range c.fields {
		out = append(out, carriedProp{f.owner.schema, f.src, f.prop, f.typ})
	}
	return out
}

// skippedIn is the skipped class t is, or holds in a list or map, or nil.
func skippedIn(t *dartType) *class {
	switch t.kind {
	case kClass:
		if t.class.skip {
			return t.class
		}
	case kList, kMap:
		return skippedIn(t.elem)
	}
	return nil
}

// checkSentOmits fails an omit of a property a schema requires where an
// operation's request body sends the schema: its encode never writes it.
// A schema is sent by name, so a class folded into its base is sent where
// its own schema is, not where the base's is, and with it only the
// properties it declares.
func (m *model) checkSentOmits() {
	sent := map[string]string{} // a schema -> the first operation sending it
	var walk func(t *dartType, op string)
	walk = func(t *dartType, op string) {
		switch t.kind {
		case kClass:
			for c := m.classes[t.schema]; c != nil; c = c.base {
				if _, ok := sent[c.schema]; ok {
					return
				}
				sent[c.schema] = op
				// A folded class's fields are its base's.
				host := c
				if c.fold {
					host = c.base
				}
				for _, p := range m.carried(host) {
					if p.src == c.schema {
						walk(p.typ, op)
					}
				}
			}
		case kList, kMap:
			walk(t.elem, op)
		}
	}
	for _, op := range m.spec.ops {
		rb := op.op.RequestBody
		if m.hints.Operations[op.id].Skip || rb == nil || rb.Value == nil {
			continue
		}
		for _, ref := range jsonSchemas(rb.Value.Content) {
			if t, err := m.typeOf(ref, op.id+" request body", ""); err == nil {
				walk(t, op.id)
			}
		}
	}
	for _, name := range slices.Sorted(maps.Keys(m.hints.Models)) {
		c := m.classes[name]
		if c == nil || c.hand {
			continue
		}
		op, ok := sent[name]
		if !ok {
			continue
		}
		required := m.own(name).required
		for _, prop := range m.hints.Models[name].Omit {
			if required[prop] {
				m.p.add("hints: models.%s.omit: %s is required, and %s sends %s, so every request would lack it", name, prop, op, name)
			}
		}
	}
}

// resolvesURLs says whether reading t resolves an origin-relative URL,
// t's own or an element's.
func (t *dartType) resolvesURLs() bool {
	return t != nil && (t.url || t.elem.resolvesURLs())
}

// sameURLs says whether two types of one Dart type resolve the same
// strings, theirs and their elements'.
func sameURLs(a, b *dartType) bool {
	if a.url != b.url {
		return false
	}
	return a.elem == nil || sameURLs(a.elem, b.elem)
}

// sameHints says whether two fields of one Dart type read and write
// alike.
func sameHints(g, f *field) bool {
	if g.emptyAsNull != f.emptyAsNull || g.omitEmpty != f.omitEmpty || g.omitDefault != f.omitDefault ||
		g.dropNullValues != f.dropNullValues || (g.unknownAs == nil) != (f.unknownAs == nil) {
		return false
	}
	if g.unknownAs == nil {
		return true
	}
	// unknownAs reads against the spec enum's values, which the Dart
	// type does not show.
	gt, ft := g.typ, f.typ
	if gt.kind == kList {
		gt, ft = gt.elem, ft.elem
	}
	return *g.unknownAs == *f.unknownAs && slices.Equal(gt.known, ft.known)
}

// checkClassDefaults fails a {} default whose class the constructor
// cannot build with no arguments.
func (m *model) checkClassDefaults() {
	for _, hk := range slices.Sorted(maps.Keys(m.classDefaults)) {
		for _, c := range m.classDefaults[hk] {
			for _, p := range c.needs() {
				m.p.add("hints: %s.default: %s requires %s, so {} cannot build it", hk, c.name, p.name)
			}
		}
	}
}

// needs is the constructor parameters of c that a {} default cannot give:
// the required ones without a default.
func (c *class) needs() []*field {
	var out []*field
	for _, p := range c.params() {
		if p.required && p.def == "" {
			out = append(out, p)
		}
	}
	return out
}

// ownProps is the properties a class schema declares itself: its inline
// allOf members' and its own.
type ownProps struct {
	names    []string
	schemas  map[string]*openapi3.SchemaRef
	required map[string]bool
	doc      string
	twice    []string // what two of its parts declare
}

func (m *model) own(schema string) ownProps {
	v := m.spec.schemas[schema].Value
	o := ownProps{schemas: map[string]*openapi3.SchemaRef{}, required: map[string]bool{}, doc: v.Description}
	addPart := func(part *openapi3.Schema, path ...string) {
		for _, name := range m.spec.ordered(part.Properties, path...) {
			if _, dup := o.schemas[name]; dup {
				o.twice = append(o.twice, name)
			} else {
				o.names = append(o.names, name)
			}
			o.schemas[name] = part.Properties[name]
		}
		for _, name := range part.Required {
			o.required[name] = true
		}
	}
	for i, member := range v.AllOf {
		if member.Ref == "" && member.Value != nil {
			addPart(member.Value, "components", "schemas", schema, "allOf", strconv.Itoa(i), "properties")
			if o.doc == "" {
				o.doc = member.Value.Description
			}
		}
	}
	addPart(v, "components", "schemas", schema, "properties")
	return o
}

// inherited maps each property c's bases declare to the schema declaring
// it, and says whether that schema requires it.
func (m *model) inherited(c *class) (map[string]string, map[string]bool) {
	from, required := map[string]string{}, map[string]bool{}
	for b := c.base; b != nil; b = b.base {
		o := m.own(b.schema)
		for _, name := range o.names {
			if _, ok := from[name]; !ok {
				from[name] = b.schema
				required[name] = o.required[name]
			}
		}
	}
	return from, required
}

func (m *model) buildFields(c *class) {
	if c.skip {
		return
	}
	o := m.own(c.schema)
	c.doc = o.doc
	for _, name := range o.twice {
		m.p.add("spec: %s declares %s in two of its parts; declare it once", c.schema, name)
	}
	if c.hand {
		m.checkCovers(c, o)
		return
	}
	m.checkClosed(c)
	key := "models." + c.schema
	mh := m.hints.Models[c.schema]
	baseFrom, baseRequired := m.inherited(c)
	omit := map[string]bool{}
	for _, name := range mh.Omit {
		switch {
		case o.schemas[name] != nil:
			omit[name] = true
		case baseFrom[name] != "":
			m.p.add("hints: %s.omit: %s is declared by %s; omit it there", key, name, baseFrom[name])
		default:
			m.p.add("hints: %s.omit: %s has no property %s", key, c.schema, name)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(mh.Fields)) {
		fk := key + ".fields." + name
		switch {
		case omit[name]:
			m.p.add("hints: %s: %s is omitted", fk, name)
		case o.schemas[name] != nil:
		case baseFrom[name] != "":
			m.p.add("hints: %s: %s is declared by %s; hint it there", fk, name, baseFrom[name])
		default:
			m.p.add("hints: %s: %s has no property %s", fk, c.schema, name)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(o.required)) {
		if o.schemas[name] != nil {
			continue
		}
		switch {
		case baseFrom[name] == "":
			m.p.add("spec: %s requires %s, which it does not declare", c.schema, name)
		case !baseRequired[name]:
			m.p.add("spec: %s requires %s, which its base %s leaves optional", c.schema, name, baseFrom[name])
		}
	}
	for _, name := range o.names {
		if from := baseFrom[name]; from != "" {
			m.p.add("spec: %s redeclares %s, which its base %s declares", c.schema, name, from)
			continue
		}
		if omit[name] {
			continue
		}
		// A folded class's properties are optional on its base, which
		// decodes the base's own answers too.
		required := o.required[name] && !c.fold
		if f := m.buildField(c, name, o.schemas[name], required, mh.Fields[name]); f != nil {
			c.fields = append(c.fields, f)
		}
	}
}

// checkClosed fails additionalProperties on the generated class c's
// schema or an inline part of it: the class has no field to hold them.
func (m *model) checkClosed(c *class) {
	v := m.spec.schemas[c.schema].Value
	parts := []*openapi3.Schema{v}
	for _, member := range v.AllOf {
		if member.Ref == "" && member.Value != nil {
			parts = append(parts, member.Value)
		}
	}
	for _, part := range parts {
		if ap := part.AdditionalProperties; ap.Schema != nil || ap.Has != nil && *ap.Has {
			m.p.add("spec: %s: additionalProperties beside properties have no Dart mapping; hold the open part in a map property", c.schema)
			return
		}
	}
}

// checkCovers holds the hand class c's hint to its schema, whose own
// properties are o: covers and ignores together list every property, a
// base's included, once, and name no other.
func (m *model) checkCovers(c *class, o ownProps) {
	hk := "hand." + c.schema
	hh := m.hints.Hand[c.schema]
	props := map[string]bool{}
	for _, name := range o.names {
		props[name] = true
	}
	from, _ := m.inherited(c)
	for name := range from {
		props[name] = true
	}
	listed := map[string]string{} // property -> the key listing it
	for _, l := range []struct {
		key   string
		names []string
	}{{"covers", hh.Covers}, {"ignores", hh.Ignores}} {
		for _, name := range l.names {
			switch {
			case listed[name] != "":
				m.p.add("hints: %s.%s: %s is listed in %s already", hk, l.key, name, listed[name])
				continue
			case !props[name]:
				m.p.add("hints: %s.%s: %s has no property %s", hk, l.key, c.schema, name)
			}
			listed[name] = l.key
		}
	}
	for _, name := range slices.Sorted(maps.Keys(props)) {
		if listed[name] == "" {
			m.p.add("hints: %s: %s has %s, listed in neither covers nor ignores; cover it in the hand-written class (%s) and list it",
				hk, c.schema, name, path.Base(handModelsFile))
		}
	}
	// A hand decode does not resolve an origin-relative URL.
	for _, name := range hh.Covers {
		schema, ps := c.schema, o.schemas[name]
		if ps == nil {
			if schema = from[name]; schema == "" {
				continue
			}
			ps = m.own(schema).schemas[name]
		}
		at := schema + "." + name
		if t, err := m.typeOf(ps, at, at); err == nil && t.resolvesURLs() {
			m.p.add("hints: %s.covers: %s is an origin-relative URL (format uri-reference), which a generated class resolves and a hand-written decode does not; drop the format or list %s in ignores",
				hk, at, name)
		}
	}
}

func (m *model) buildField(c *class, prop string, ps *openapi3.SchemaRef, required bool, fh fieldHint) *field {
	at := c.schema + "." + prop
	hk := "models." + c.schema + ".fields." + prop
	t, err := m.typeOf(ps, at, at)
	if err != nil {
		m.p.add("spec: %v", err)
		return nil
	}
	// A $ref'd property's description is its target's, which documents
	// the type, not the field.
	doc := ""
	if ps.Ref == "" {
		doc = ps.Value.Description
	}
	f := &field{
		owner: c, src: c.schema, prop: prop, name: prop, typ: t, required: required, doc: doc,
		emptyAsNull: fh.EmptyAsNull, omitEmpty: fh.OmitEmpty, omitDefault: fh.OmitDefault,
		dropNullValues: fh.DropNullValues, unknownAs: fh.UnknownAs,
	}
	if fh.As != "" {
		f.name = fh.As
	}
	if msg := fieldNameProblem(f.name); msg != "" {
		if fh.As != "" {
			m.p.add("hints: %s.as: %s %s", hk, f.name, msg)
		} else {
			m.p.add("spec: %s: %s %s; rename it with %s.as", at, prop, msg, hk)
		}
	}
	// An inline enum's known values take the field's Dart names, which
	// the checks above make identifiers.
	if s := knownStrings(t); s != nil && s.knownAs == "" {
		s.knownAs = c.name + upperFirst(f.name)
	}
	switch fh.Convert {
	case "":
	case "durationMs":
		if t.kind != kInt {
			m.p.add("hints: %s.convert: durationMs needs an integer, and %s is %s", hk, at, t.dart())
		} else {
			f.typ = &dartType{kind: kDuration}
		}
	case "apiError":
		if !m.isErrorShape(ps) {
			m.p.add("hints: %s.convert: apiError needs a $ref to an object with string code and message", hk)
		} else {
			f.typ = &dartType{kind: kAPIError}
		}
	case "base64Text":
		if t.kind != kBytes {
			m.p.add("hints: %s.convert: base64Text needs a format byte string, and %s is %s", hk, at, t.dart())
		} else {
			f.typ = &dartType{kind: kString}
		}
	default:
		m.p.add("hints: %s.convert: %q is not durationMs, apiError or base64Text", hk, fh.Convert)
	}
	hintDefault := fh.Default.Kind != 0
	specDefault := ps.Ref == "" && ps.Value.Default != nil
	if specDefault && f.typ.kind != kAny {
		// A literal that fails is reported where the default applies.
		f.specDef, _ = constLiteral(f.typ, ps.Value.Default)
	}
	if fh.ServerDefault {
		switch {
		case required:
			m.p.add("hints: %s.serverDefault: %s is required, so it is always sent", hk, at)
		case hintDefault:
			m.p.add("hints: %s.serverDefault: the default is the server's; drop default", hk)
		case !specDefault:
			m.p.add("hints: %s.serverDefault: %s has no spec default", hk, at)
		}
		specDefault = false
	}
	switch {
	case f.typ.kind == kAny:
		f.nullable = true
		if specDefault {
			m.p.add("spec: %s: an untyped property takes no default", at)
		}
		if hintDefault {
			m.p.add("hints: %s.default: %s is untyped, so it takes no default", hk, at)
		}
	case required:
		f.nullable = ps.Value.Nullable
		switch {
		case hintDefault && specDefault:
			m.p.add("hints: %s.default: the spec already declares a default for %s", hk, at)
		case hintDefault:
			// The constructor's only: decode still requires it.
			f.def = m.hintDefault(f, fh, hk)
		}
	case specDefault && hintDefault:
		m.p.add("hints: %s.default: the spec already declares a default for %s", hk, at)
	case specDefault:
		if f.def, err = constLiteral(f.typ, ps.Value.Default); err != nil {
			m.p.add("spec: %s: default: %v", at, err)
		}
	case hintDefault:
		f.def = m.hintDefault(f, fh, hk)
	default:
		f.nullable = true
	}
	m.checkFieldHints(f, hk, at)
	return f
}

// knownStrings is t, or a list t's elements, where that is a String
// with a spec enum's values; else nil.
func knownStrings(t *dartType) *dartType {
	if t.kind == kList {
		t = t.elem
	}
	if t.kind == kString && len(t.known) > 0 {
		return t
	}
	return nil
}

// hintDefault is f's hint default as a Dart constant.
func (m *model) hintDefault(f *field, fh fieldHint, hk string) string {
	def, built, err := hintLiteral(f.typ, fh.Default)
	if err != nil {
		m.p.add("hints: %s.default: %v", hk, err)
		return ""
	}
	if len(built) > 0 {
		m.classDefaults[hk] = built
	}
	return def
}

func (m *model) checkFieldHints(f *field, hk, at string) {
	t := f.typ
	if f.emptyAsNull && (t.kind != kString || !f.nullable) {
		m.p.add("hints: %s.emptyAsNull: needs a nullable String, and %s is %s", hk, at, f.dart())
	}
	switch {
	case f.omitEmpty && t.kind != kList && t.kind != kClass:
		m.p.add("hints: %s.omitEmpty: needs a List or an object, and %s is %s", hk, at, f.dart())
	case f.omitEmpty && f.required:
		m.p.add("hints: %s.omitEmpty: %s is required, so it is always sent", hk, at)
	}
	if f.omitDefault {
		switch {
		case f.required:
			m.p.add("hints: %s.omitDefault: %s is required, so it is always sent", hk, at)
		case f.def == "":
			m.p.add("hints: %s.omitDefault: %s has no default to leave out", hk, at)
		case t.kind == kClass:
			m.p.add("hints: %s.omitDefault: %s defaults to an object, which has no value to compare it with; omitEmpty leaves out an empty one", hk, at)
		case isCollection(t) && f.def != "const []" && f.def != "const {}":
			m.p.add("hints: %s.omitDefault: %s defaults to a collection with entries, which has no value to compare it with", hk, at)
		}
	}
	if f.dropNullValues && t.kind != kJSONObject && (t.kind != kMap || !(t.elem.nullable || t.elem.kind == kAny)) {
		m.p.add("hints: %s.dropNullValues: needs a map whose values can be null, and %s is %s", hk, at, f.dart())
	}
	if f.unknownAs == nil {
		return
	}
	s := t
	if s.kind == kList {
		s = s.elem
	}
	switch {
	case s.kind == kEnum:
		m.p.add("hints: %s.unknownAs: %s is the Dart enum %s; give the enum a fallback instead", hk, at, s.enum.name)
	case s.kind != kString || len(s.known) == 0:
		m.p.add("hints: %s.unknownAs: needs a String, or a List of them, with a spec enum, and %s is %s", hk, at, f.dart())
	case s.url || f.emptyAsNull:
		m.p.add("hints: %s.unknownAs: does not combine with an origin-relative URL or emptyAsNull", hk)
	}
}

// isErrorShape says whether ref names an object schema with string code
// and message, the spec's Error.
func (m *model) isErrorShape(ref *openapi3.SchemaRef) bool {
	ref = refOf(ref)
	if _, ok := componentName(ref.Ref); !ok || ref.Value == nil {
		return false
	}
	for _, name := range []string{"code", "message"} {
		p := ref.Value.Properties[name]
		if p == nil || p.Value == nil || !p.Value.Type.Is("string") {
			return false
		}
	}
	return true
}

// typeOf maps a schema to its Dart type; at names the position in
// errors, and enumKey is the enums key an inline enum here is listed
// under ("" where there is none).
func (m *model) typeOf(ref *openapi3.SchemaRef, at, enumKey string) (*dartType, error) {
	if ref == nil || ref.Value == nil {
		return &dartType{kind: kAny}, nil
	}
	ref = refOf(ref)
	name, ok := componentName(ref.Ref)
	if !ok {
		if ref.Ref != "" {
			return nil, fmt.Errorf("%s: $ref %s is not a component schema", at, ref.Ref)
		}
		return m.inlineType(ref.Value, at, enumKey)
	}
	if c := m.classes[name]; c != nil {
		if c.fold {
			c = c.base
		}
		return &dartType{kind: kClass, class: c, schema: name}, nil
	}
	v := ref.Value
	if len(v.Enum) > 0 {
		if e := m.enumOf[name]; e != nil {
			return &dartType{kind: kEnum, enum: e, enumKey: name}, nil
		}
		t, err := m.inlineType(v, at, "")
		if t != nil && t.kind == kString {
			t.knownAs = identifierParts(name)
		}
		return t, err
	}
	if m.alias[name] {
		return nil, fmt.Errorf("%s: alias %s refers to itself", at, name)
	}
	m.alias[name] = true
	defer delete(m.alias, name)
	return m.inlineType(v, at, "")
}

// refOf is the $ref a schema stands for: its own, or the one member of
// the allOf wrapper that lets a $ref carry a description of its own.
func refOf(ref *openapi3.SchemaRef) *openapi3.SchemaRef {
	if ref == nil || ref.Ref != "" || ref.Value == nil {
		return ref
	}
	v := ref.Value
	if len(v.AllOf) == 1 && v.AllOf[0].Ref != "" && v.Properties == nil &&
		len(v.OneOf)+len(v.AnyOf) == 0 && v.Not == nil && (v.Type == nil || v.Type.Is("object")) {
		return v.AllOf[0]
	}
	return ref
}

func (m *model) inlineType(v *openapi3.Schema, at, enumKey string) (*dartType, error) {
	switch {
	case len(v.OneOf)+len(v.AnyOf) > 0 || v.Not != nil:
		return nil, fmt.Errorf("%s: oneOf, anyOf and not have no Dart mapping", at)
	case len(v.AllOf) > 0:
		return nil, fmt.Errorf("%s: an inline allOf has no Dart class; declare it under components/schemas", at)
	}
	types := v.Type.Slice()
	if len(types) > 1 {
		return nil, fmt.Errorf("%s: a schema of several types (%s) has no Dart mapping", at, strings.Join(types, ", "))
	}
	typ := ""
	if len(types) == 1 {
		typ = types[0]
	}
	switch typ {
	case "string":
		if len(v.Enum) > 0 && enumKey != "" {
			if e := m.enumOf[enumKey]; e != nil {
				return &dartType{kind: kEnum, enum: e, enumKey: enumKey}, nil
			}
		}
		switch v.Format {
		case "date-time":
			return &dartType{kind: kDateTime}, nil
		case "date":
			return &dartType{kind: kDate}, nil
		case "byte":
			return &dartType{kind: kBytes}, nil
		case "binary":
			return nil, fmt.Errorf("%s: format binary has no JSON mapping", at)
		}
		// An inline enum's set of known values is named for its field
		// (buildField).
		t := &dartType{kind: kString, url: v.Format == "uri-reference"}
		if len(v.Enum) > 0 {
			t.known = enumStrings(v.Enum)
		}
		return t, nil
	case "integer":
		return &dartType{kind: kInt}, nil
	case "number":
		return &dartType{kind: kDouble}, nil
	case "boolean":
		return &dartType{kind: kBool}, nil
	case "array":
		elem, err := m.typeOf(v.Items, at+"[]", enumKey)
		if err != nil {
			return nil, err
		}
		elem.nullable = v.Items != nil && v.Items.Value != nil && v.Items.Value.Nullable && elem.kind != kAny
		return &dartType{kind: kList, elem: elem}, nil
	case "object", "":
		if v.Properties != nil {
			return nil, fmt.Errorf("%s: an inline object has no Dart class; declare it under components/schemas", at)
		}
		if ap := v.AdditionalProperties.Schema; ap != nil {
			elem, err := m.typeOf(ap, at+"{}", enumKey)
			if err != nil {
				return nil, err
			}
			elem.nullable = ap.Value != nil && ap.Value.Nullable && elem.kind != kAny
			return &dartType{kind: kMap, elem: elem}, nil
		}
		if typ == "object" {
			return &dartType{kind: kJSONObject}, nil
		}
		return &dartType{kind: kAny}, nil
	}
	return nil, fmt.Errorf("%s: type %s has no Dart mapping", at, typ)
}

func enumStrings(values []any) []string {
	out := make([]string, 0, len(values))
	for _, v := range values {
		out = append(out, fmt.Sprint(v))
	}
	return out
}

func (m *model) buildEnums() {
	for _, key := range slices.Sorted(maps.Keys(m.hints.Enums)) {
		hk := "enums." + key
		v, doc, ok := m.enumSchema(key, hk)
		if !ok {
			continue
		}
		e := m.newEnum(key, hk, m.hints.Enums[key], v, doc)
		if e == nil {
			continue
		}
		if prev := m.enums[e.name]; prev != nil {
			if !slices.Equal(prev.values, e.values) || prev.fallback != e.fallback || prev.drop != e.drop {
				m.p.add("hints: %s: makes enum %s, which enums.%s makes with other values or fallback", hk, e.name, prev.key)
				continue
			}
			m.enumOf[key] = prev
			continue
		}
		m.enums[e.name] = e
		m.enumOf[key] = e
	}
}

// enumSchema resolves an enums key: a component enum, Schema.prop for an
// inline enum on the property, its items or its map values, or
// operationId.param for one on an operation parameter or its items.
func (m *model) enumSchema(key, hk string) (*openapi3.Schema, string, bool) {
	schema, prop, inline := strings.Cut(key, ".")
	ref := m.spec.schemas[schema]
	if ref == nil && inline {
		if op := m.spec.opByID(schema); op != nil {
			return m.paramEnum(op, prop, key, hk)
		}
	}
	if ref == nil {
		m.p.add("hints: %s: no such schema %s", hk, schema)
		return nil, "", false
	}
	if !inline {
		if len(ref.Value.Enum) == 0 {
			m.p.add("hints: %s: %s is not an enum", hk, schema)
			return nil, "", false
		}
		return ref.Value, ref.Value.Description, true
	}
	if m.classes[schema] == nil {
		m.p.add("hints: %s: %s is not an object schema", hk, schema)
		return nil, "", false
	}
	ps := m.own(schema).schemas[prop]
	if ps == nil {
		if from, _ := m.inherited(m.classes[schema]); from[prop] != "" {
			m.p.add("hints: %s: %s is declared by %s; list it as %s.%s", hk, prop, from[prop], from[prop], prop)
		} else {
			m.p.add("hints: %s: %s has no property %s", hk, schema, prop)
		}
		return nil, "", false
	}
	return m.inlineEnum(ps, ps.Value.Description, key, hk)
}

// paramEnum resolves operationId.param.
func (m *model) paramEnum(op *operation, name, key, hk string) (*openapi3.Schema, string, bool) {
	for _, prm := range op.params {
		if prm.Value != nil && prm.Value.Name == name {
			return m.inlineEnum(prm.Value.Schema, prm.Value.Description, key, hk)
		}
	}
	m.p.add("hints: %s: %s has no parameter %s", hk, op.id, name)
	return nil, "", false
}

// inlineEnum finds the inline enum the enums key names at ref: on the
// schema, its items or its map values, an allOf wrapper read through.
// outer is the description it takes when it has none of its own.
func (m *model) inlineEnum(ref *openapi3.SchemaRef, outer, key, hk string) (*openapi3.Schema, string, bool) {
	for r := refOf(ref); r != nil && r.Value != nil; r = refOf(r) {
		if name, ok := componentName(r.Ref); ok {
			m.p.add("hints: %s: %s is a $ref to %s; list %s itself", hk, key, name, name)
			return nil, "", false
		}
		v := r.Value
		if len(v.Enum) > 0 {
			doc := v.Description
			if doc == "" {
				doc = outer
			}
			return v, doc, true
		}
		switch {
		case v.Items != nil:
			r = v.Items
		case v.AdditionalProperties.Schema != nil:
			r = v.AdditionalProperties.Schema
		default:
			r = nil
		}
	}
	m.p.add("hints: %s: %s carries no inline enum", hk, key)
	return nil, "", false
}

func (m *model) newEnum(key, hk string, hint enumHint, v *openapi3.Schema, doc string) *enumDef {
	name := hint.As
	if name == "" {
		owner, prop, _ := strings.Cut(key, ".")
		name = upperFirst(owner) + upperFirst(prop)
	}
	if msg := typeNameProblem(name); msg != "" {
		if hint.As == "" {
			msg += "; name it with " + hk + ".as"
		}
		m.p.add("hints: %s: the enum name %s %s", hk, name, msg)
		return nil
	}
	e := &enumDef{name: name, doc: doc, key: key}
	wireOf := map[string]string{}
	for _, raw := range v.Enum {
		w, ok := raw.(string)
		if !ok {
			m.p.add("hints: %s: only string enums become Dart enums, and %v is not a string", hk, raw)
			return nil
		}
		member := lowerCamel(w)
		if msg := memberNameProblem(member); msg != "" {
			m.p.add("hints: %s: the value %q makes the member %q, which %s; enum members take no rename, so leave the enum unlisted", hk, w, member, msg)
			return nil
		}
		if prev, dup := wireOf[member]; dup {
			m.p.add("hints: %s: the values %q and %q both make the member %s", hk, prev, w, member)
			return nil
		}
		wireOf[member] = w
		e.values = append(e.values, w)
		e.members = append(e.members, member)
	}
	for _, name := range hint.Add {
		if slices.Contains(e.members, name) || slices.Contains(e.values, name) {
			m.p.add("hints: %s.add: %s is a member already", hk, name)
			return nil
		}
		if msg := memberNameProblem(name); msg != "" {
			m.p.add("hints: %s.add: %q %s", hk, name, msg)
			return nil
		}
		e.values = append(e.values, name)
		e.members = append(e.members, name)
	}
	switch fb := hint.Fallback; {
	case fb == "":
	case fb == dropValue:
		e.drop = true
	case slices.Contains(e.values, fb):
		e.fallback = e.members[slices.Index(e.values, fb)]
	case slices.Contains(e.members, fb):
		e.fallback = fb
	default:
		m.p.add("hints: %s.fallback: %s is no value or member of %s (%s); add lists a member the spec lacks",
			hk, fb, e.name, strings.Join(e.members, ", "))
		return nil
	}
	return e
}

func (m *model) checkNames() {
	owner := map[string]string{}
	claim := func(name, what string) {
		if prev, ok := owner[name]; ok {
			m.p.add("names: %s and %s both take the Dart name %s", prev, what, name)
			return
		}
		owner[name] = what
	}
	if m.hand != nil {
		handClass := map[string]bool{}
		for _, c := range m.classes {
			if c.hand {
				handClass[c.name] = true
			}
		}
		for _, d := range m.hand.publicNames() {
			if !handClass[d.name] {
				claim(d.name, d.label())
			}
		}
	}
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		c := m.classes[name]
		if c.fold || c.skip {
			continue
		}
		what := "schema " + name
		if msg := typeNameProblem(c.name); msg != "" {
			if c.name != name {
				m.p.add("hints: models.%s.as: %s %s", name, c.name, msg)
			} else {
				m.p.add("spec: schema %s: the name %s; rename it with models.%s.as", name, msg, name)
			}
		}
		claim(c.name, what)
	}
	for _, e := range m.sortedEnums() {
		claim(e.name, "enums."+e.key)
	}
	for _, c := range m.generated() {
		if pages(c) {
			claim(pagingExtension(c), "the paging extension of schema "+c.schema)
		}
	}
	for _, c := range m.generated() {
		seen := map[string]*field{}
		for _, f := range c.all() {
			if prev, ok := seen[f.name]; ok {
				m.p.add("names: %s.%s and %s.%s both make the field %s.%s", prev.owner.schema, prev.prop, f.owner.schema, f.prop, c.name, f.name)
			}
			seen[f.name] = f
		}
	}
}

// checkHandExports fails a hand class models.dart does not export: app
// code imports the models from there.
func (m *model) checkHandExports() {
	if m.hand == nil {
		return
	}
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		if c := m.classes[name]; c.hand && !m.hand.exportsHand(c.name) {
			m.p.add("hints: hand.%s: models.dart does not export %s, so app code cannot name it; add it to the show list of its export of %s",
				name, c.name, path.Base(handModelsFile))
		}
	}
}

// pagingMember is the member the generated paging extension declares.
const pagingMember = "hasMore"

// pages says whether c gets the generated paging extension: it declares
// a nullable nextCursor, and no more of its own says whether more
// follows. Both are spec properties, whatever their fields are named.
func pages(c *class) bool {
	if c.hand || c.fold || c.skip {
		return false
	}
	f := cursorField(c)
	return f != nil && f.nullable && !slices.ContainsFunc(c.all(), func(f *field) bool { return f.prop == "more" })
}

// cursorField is the field of the nextCursor c declares, or nil.
func cursorField(c *class) *field {
	if i := slices.IndexFunc(c.fields, func(f *field) bool { return f.prop == "nextCursor" }); i >= 0 {
		return c.fields[i]
	}
	return nil
}

func pagingExtension(c *class) string { return c.name + "Paging" }

// extended says whether a hand extension (model_extensions.dart) extends
// the generated class c.
func (m *model) extended(c *class) bool {
	return m.ext != nil && slices.ContainsFunc(m.ext.list, func(e extension) bool { return e.on == c.name })
}

// fieldNamed is the field of c, its bases or its subclasses that takes
// name, or nil.
func fieldNamed(c *class, name string) *field {
	for _, f := range c.all() {
		if f.name == name {
			return f
		}
	}
	for _, sub := range c.subs {
		for _, f := range sub.fields {
			if f.name == name {
				return f
			}
		}
		if f := fieldNamed(sub, name); f != nil {
			return f
		}
	}
	return nil
}

// checkMembers holds the members extending a generated class to its
// fields: no field of the class, its bases or its subclasses takes the
// name of one the generated paging extension or a hand extension
// (model_extensions.dart) declares, no hand member repeats the generated
// one, and a hand copyWith takes a parameter for every field of its
// class and passes each to the constructor it calls.
func (m *model) checkMembers() {
	byName := map[string]*class{}
	for _, c := range m.generated() {
		byName[c.name] = c
		if !pages(c) {
			continue
		}
		if f := fieldNamed(c, pagingMember); f != nil {
			m.p.add("spec: %s.%s makes the field %s, which the generated %s declares; rename it with models.%s.fields.%s.as",
				f.owner.schema, f.prop, f.name, pagingExtension(c), f.owner.schema, f.prop)
		}
	}
	if m.ext == nil {
		return
	}
	for _, e := range m.ext.list {
		c := byName[e.on]
		if c == nil {
			continue
		}
		where := fmt.Sprintf("%s on %s in %s", e.label(), e.on, m.ext.path)
		if pages(c) && e.name == pagingExtension(c) {
			m.p.add("extensions: %s takes the name of the generated extension on %s", where, c.name)
		}
		for _, member := range e.members {
			if f := fieldNamed(c, member); f != nil {
				m.p.add("extensions: %s declares %s, which is a generated field of %s (%s.%s)", where, member, f.owner.name, f.owner.schema, f.prop)
			}
			if member == pagingMember && pages(c) {
				m.p.add("extensions: %s declares %s, which the generated %s declares; delete it", where, member, pagingExtension(c))
			}
		}
		if !slices.Contains(e.members, "copyWith") {
			continue
		}
		for _, f := range c.all() {
			if !slices.Contains(e.copyWith, f.name) {
				m.p.add("extensions: copyWith in %s has no parameter %s, so a copy loses that field of %s", where, f.name, c.name)
			}
		}
		if !e.builds {
			m.p.add("extensions: copyWith in %s calls no %s constructor, so nothing shows it copies every field", where, c.name)
			continue
		}
		for _, f := range c.all() {
			if !slices.Contains(e.copied, f.name) {
				m.p.add("extensions: copyWith in %s builds %s without %s, so a copy loses that field", where, c.name, f.name)
			}
		}
	}
}

// checkDrops fails a fallback: drop the codec cannot honour: an enum
// field of a class the codec decodes as a single value somewhere (a
// hand-written list decodes each element so), a drop enum a hand class
// holds where a generated list holds that class, and a drop enum inside a
// map.
func (m *model) checkDrops() {
	single := map[string][]string{}
	note := func(c *class, where string) {
		if !slices.Contains(single[c.schema], where) {
			single[c.schema] = append(single[c.schema], where)
		}
	}
	handProps := map[*class][]typedProp{}
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		if c := m.classes[name]; c.hand {
			handProps[c] = m.handProps(c)
		}
	}
	held := map[*class]bool{}
	var walk func(t *dartType, inList bool, where string, generated bool)
	walk = func(t *dartType, inList bool, where string, generated bool) {
		switch t.kind {
		case kClass:
			held[t.class] = true
			if !inList {
				note(t.class, where)
			}
		case kList:
			if e := t.elem; generated && e.kind == kClass && e.class.hand {
				m.checkHandHolder(e.class, handProps, where)
			}
			// A hand-written list decodes each element alone.
			walk(t.elem, generated, where, generated)
		case kMap:
			walk(t.elem, false, where, generated)
			if e := t.elem; e.kind == kEnum && e.enum.drop {
				m.p.add("hints: enums.%s: fallback drop acts on lists, and %s holds the enum in a map", e.enumKey, where)
			}
		}
	}
	for _, c := range m.generated() {
		for _, f := range c.fields {
			walk(f.typ, false, c.schema+"."+f.prop, true)
		}
	}
	// Whatever a hand class holds, its hand decode decodes through the
	// codec.
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		c := m.classes[name]
		for _, p := range handProps[c] {
			walk(p.typ, false, c.schema+"."+p.prop, false)
		}
	}
	// An answer decodes as a single value however its schema holds the
	// class: a $ref, an allOf wrapper around one, a map's values.
	for _, op := range m.spec.ops {
		for _, ref := range op.responseSchemas() {
			t, err := m.typeOf(ref, op.id+" response", "")
			if err != nil {
				continue // buildCalls names one a call decodes
			}
			if t.kind == kEnum && t.enum.drop {
				m.p.add("hints: enums.%s: fallback drop, but %s answers the enum as a single value", t.enumKey, op.id)
			}
			walk(t, false, "the response of "+op.id, true)
		}
	}
	// A class no operation reaches and nothing holds, a base included, is
	// decoded on its own: the socket frames.
	for _, c := range m.generated() {
		if c.file == sharedFile && !held[c] {
			note(c, "a decode of its own (nothing reaches or holds "+c.schema+")")
		}
	}
	for _, c := range m.generated() {
		for _, f := range c.all() {
			if f.typ.kind != kEnum || !f.typ.enum.drop {
				continue
			}
			if where := single[c.schema]; len(where) > 0 {
				sort.Strings(where)
				m.p.add("hints: enums.%s: fallback drop, but %s (holding it in %s) is decoded as a single value at %s",
					f.typ.enumKey, c.schema, f.prop, strings.Join(where, ", "))
			}
		}
	}
}

// checkHandHolder fails a drop enum the hand class h holds, itself or
// through its bases, when the generated list at where holds h: only a
// generated class has the keep predicate a list drops by.
func (m *model) checkHandHolder(h *class, handProps map[*class][]typedProp, where string) {
	for b := h; b != nil; b = b.base {
		props := handProps[b]
		if !b.hand {
			props = nil
			for _, f := range b.fields {
				props = append(props, typedProp{f.prop, f.typ})
			}
		}
		for _, p := range props {
			if p.typ.kind == kEnum && p.typ.enum.drop {
				m.p.add("hints: enums.%s: fallback drop, but the hand-written %s holds it in %s, and %s lists %s; a generated list drops only generated classes",
					p.typ.enumKey, h.schema, p.prop, where, h.schema)
			}
		}
	}
}

type typedProp struct {
	prop string
	typ  *dartType
}

// handProps types a hand schema's own properties for the drop checks.
// One the generator cannot type is left out: nothing generated decodes
// inside it.
func (m *model) handProps(c *class) []typedProp {
	o := m.own(c.schema)
	var out []typedProp
	for _, name := range o.names {
		at := c.schema + "." + name
		if t, err := m.typeOf(o.schemas[name], at, at); err == nil {
			out = append(out, typedProp{name, t})
		}
	}
	return out
}

const sharedFile = "shared"

func (m *model) placeClasses() {
	tagOfFile := map[string]string{}
	for _, op := range m.spec.ops {
		stem := fileStem(op.tag)
		switch prev, seen := tagOfFile[stem]; {
		case stem == "":
			m.p.add("spec: tag %q makes no file name", op.tag)
		case stem == sharedFile:
			m.p.add("spec: tag %q would share models/%s.g.dart with the schemas no operation reaches", op.tag, sharedFile)
		case seen && prev != op.tag:
			m.p.add("spec: tags %q and %q both make models/%s.g.dart", prev, op.tag, stem)
		}
		tagOfFile[stem] = op.tag
	}
	tags := m.spec.tagOf()
	for _, c := range m.classes {
		c.file = sharedFile
		if tag, ok := tags[c.schema]; ok {
			c.file = fileStem(tag)
		}
	}
}

// fileStem is a tag as a snake_case file name.
func fileStem(tag string) string {
	var b strings.Builder
	lower := false
	for _, r := range tag {
		switch {
		case r >= 'A' && r <= 'Z':
			if lower {
				b.WriteByte('_')
			}
			b.WriteRune(unicode.ToLower(r))
			lower = false
		case r >= 'a' && r <= 'z' || r >= '0' && r <= '9':
			b.WriteRune(r)
			lower = true
		default:
			if b.Len() > 0 && !strings.HasSuffix(b.String(), "_") {
				b.WriteByte('_')
			}
			lower = false
		}
	}
	return strings.Trim(b.String(), "_")
}

// constLiteral is v, a default from the spec or the hints, as a Dart
// constant of t.
func constLiteral(t *dartType, v any) (string, error) {
	s, err := literal(t, v)
	if err != nil {
		return "", err
	}
	switch t.kind {
	case kList, kMap, kJSONObject, kDuration, kClass:
		return "const " + s, nil
	}
	return s, nil
}

func literal(t *dartType, v any) (string, error) {
	if v == nil && t.nullable {
		return "null", nil
	}
	if f, ok := v.(float64); ok && (math.IsNaN(f) || math.IsInf(f, 0)) {
		return "", fmt.Errorf("%v is no JSON number", f)
	}
	if (t.kind == kInt || t.kind == kDuration) && beyondSafeInt(v) {
		return "", fmt.Errorf("%s is beyond 2^53 - 1, the largest integer a web build holds exactly", numberText(v))
	}
	bad := fmt.Errorf("%v is not a %s", v, t.dart())
	switch t.kind {
	case kBool:
		if b, ok := v.(bool); ok {
			return strconv.FormatBool(b), nil
		}
	case kInt:
		if n, ok := wholeNumber(v); ok {
			return strconv.FormatInt(n, 10), nil
		}
	case kDouble:
		if f, ok := number(v); ok {
			return dartDouble(f), nil
		}
	case kString:
		if s, ok := v.(string); ok {
			return dartString(s), nil
		}
	case kEnum:
		if s, ok := v.(string); ok {
			e := t.enum
			if i := slices.Index(e.values, s); i >= 0 {
				return e.name + "." + e.members[i], nil
			}
			if slices.Contains(e.members, s) {
				return e.name + "." + s, nil
			}
		}
	case kDuration:
		if n, ok := wholeNumber(v); ok {
			return fmt.Sprintf("Duration(milliseconds: %d)", n), nil
		}
	case kList:
		if items, ok := v.([]any); ok {
			parts := make([]string, 0, len(items))
			for _, item := range items {
				s, err := literal(t.elem, item)
				if err != nil {
					return "", err
				}
				parts = append(parts, s)
			}
			return "[" + strings.Join(parts, ", ") + "]", nil
		}
	case kMap, kJSONObject:
		if entries, ok := v.(map[string]any); ok {
			elem := t.elem
			if t.kind == kJSONObject {
				elem = &dartType{kind: kAny}
			}
			parts := make([]string, 0, len(entries))
			for _, k := range slices.Sorted(maps.Keys(entries)) {
				s, err := literal(elem, entries[k])
				if err != nil {
					return "", err
				}
				parts = append(parts, dartString(k)+": "+s)
			}
			return "{" + strings.Join(parts, ", ") + "}", nil
		}
	case kClass:
		// {}: the class built with no arguments, which its constructor
		// must allow (checkClassDefaults).
		if entries, ok := v.(map[string]any); ok && len(entries) == 0 && !t.class.hand {
			return t.class.name + "()", nil
		}
		if t.class.hand {
			return "", fmt.Errorf("the hand-written %s takes no default", t.class.name)
		}
	case kAny:
		switch x := v.(type) {
		case nil:
			return "null", nil
		case bool:
			return strconv.FormatBool(x), nil
		case string:
			return dartString(x), nil
		}
		if n, ok := wholeNumber(v); ok {
			return strconv.FormatInt(n, 10), nil
		}
		if f, ok := number(v); ok {
			return dartDouble(f), nil
		}
	default:
		return "", fmt.Errorf("a %s takes no default", t.dart())
	}
	if _, spelled := v.(string); spelled && (t.kind == kList || t.kind == kMap || t.kind == kJSONObject) {
		return "", fmt.Errorf("%w; write [] for an empty list, {} for an empty map", bad)
	}
	return "", bad
}

// maxSafeInt is the largest integer a web build's int, a JavaScript
// number, holds exactly.
const maxSafeInt int64 = 1<<53 - 1

// beyondSafeInt says whether the number v is beyond maxSafeInt either way.
func beyondSafeInt(v any) bool {
	switch n := v.(type) {
	case int:
		return int64(n) > maxSafeInt || int64(n) < -maxSafeInt
	case int64:
		return n > maxSafeInt || n < -maxSafeInt
	case uint64:
		return n > uint64(maxSafeInt)
	case float64:
		return math.Abs(n) > float64(maxSafeInt)
	}
	return false
}

// numberText is the number v as written, a float64 without an exponent.
func numberText(v any) string {
	if f, ok := v.(float64); ok {
		return strconv.FormatFloat(f, 'f', -1, 64)
	}
	return fmt.Sprint(v)
}

func number(v any) (float64, bool) {
	switch n := v.(type) {
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	case uint64:
		return float64(n), true
	case float64:
		return n, true
	}
	return 0, false
}

func wholeNumber(v any) (int64, bool) {
	switch n := v.(type) {
	case int:
		return int64(n), true
	case int64:
		return n, true
	case uint64:
		return int64(n), n <= 1<<63-1
	case float64:
		if n == float64(int64(n)) {
			return int64(n), true
		}
	}
	return 0, false
}

func dartDouble(f float64) string {
	s := strconv.FormatFloat(f, 'g', -1, 64)
	if !strings.ContainsAny(s, ".eEn") {
		s += ".0"
	}
	return s
}

// dartString is s as a single-quoted Dart string literal, ASCII only.
func dartString(s string) string {
	var b strings.Builder
	b.WriteByte('\'')
	for _, r := range s {
		switch {
		case r == '\\' || r == '\'' || r == '$':
			b.WriteByte('\\')
			b.WriteRune(r)
		case r == '\n':
			b.WriteString(`\n`)
		case r == '\r':
			b.WriteString(`\r`)
		case r == '\t':
			b.WriteString(`\t`)
		case r < 0x20 || r > 0x7e:
			fmt.Fprintf(&b, `\u{%x}`, r)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('\'')
	return b.String()
}

// lowerCamel is a wire value as an enum member name: recently-added is
// recentlyAdded, as-is asIs, an all-capitals word lowercased.
func lowerCamel(w string) string {
	parts := strings.FieldsFunc(w, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
	var b strings.Builder
	for i, part := range parts {
		if strings.ToUpper(part) == part {
			part = strings.ToLower(part)
		}
		r := []rune(part)
		if i == 0 {
			r[0] = unicode.ToLower(r[0])
		} else {
			r[0] = unicode.ToUpper(r[0])
		}
		b.WriteString(string(r))
	}
	return b.String()
}

// identifierParts is name with each run of what no Dart identifier holds
// dropped and the part after it capitalized: sort-order is sortOrder.
func identifierParts(name string) string {
	parts := strings.FieldsFunc(name, func(r rune) bool {
		return !(r == '_' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9')
	})
	for i := 1; i < len(parts); i++ {
		parts[i] = upperFirst(parts[i])
	}
	return strings.Join(parts, "")
}

func upperFirst(s string) string {
	if s == "" {
		return s
	}
	r := []rune(s)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

var (
	identifier   = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]*$`)
	reservedWord = words("assert break case catch class const continue default do else enum extends false final finally " +
		"for if in is new null rethrow return super switch this throw true try var void while with")
	builtInIdentifier = words("abstract as covariant deferred dynamic export extension external factory Function get " +
		"implements import interface late library mixin operator part required set static typedef")
	objectMember = words("hashCode runtimeType toString noSuchMethod")
	enumMember   = words("values index wireName fromWire")
	// dart:core's public names, as the Dart 3.13 analyzer lists its export
	// namespace. A class or enum taking one would hide the core one, with
	// no diagnostic, in every library importing the models.
	dartCoreType = words("ArgumentError AssertionError BigInt Comparable Comparator ConcurrentModificationError " +
		"DateTime DateTimeCopyWith Deprecated Duration Enum EnumByName EnumName Error Exception Expando Finalizer " +
		"FormatException Function Future FutureExtensions FutureIterable FutureRecord2 FutureRecord3 FutureRecord4 " +
		"FutureRecord5 FutureRecord6 FutureRecord7 FutureRecord8 FutureRecord9 IndexError " +
		"IntegerDivisionByZeroException Invocation Iterable IterableExtensions Iterator List Map MapEntry Match " +
		"NoSuchMethodError Null NullableIterableExtensions Object OutOfMemoryError ParallelWaitError Pattern " +
		"RangeError Record RegExp RegExpMatch RuneIterator Runes Set Sink StackOverflowError StackTrace StateError " +
		"Stopwatch Stream String StringBuffer StringSink Symbol Type TypeError UnimplementedError UnsupportedError " +
		"Uri UriData WeakReference bool double int num pragma")
	// The other types emitted code names from outside the package
	// (dart:typed_data, and dio and dart:async in client.dart's library),
	// and the interface aggregating the tags'. The package's own names
	// come from its files (-client).
	emittedType = words("Uint8List Dio Response Options InterceptorsWrapper CancelToken ProgressCallback ResponseType Headers " +
		"DioException DioExceptionType Timer " + apiAggregate)
)

func words(s string) map[string]bool {
	out := map[string]bool{}
	for _, w := range strings.Fields(s) {
		out[w] = true
	}
	return out
}

func typeNameProblem(name string) string {
	switch {
	case !identifier.MatchString(name):
		return "is not a Dart identifier"
	case reservedWord[name]:
		return "is a Dart reserved word"
	case builtInIdentifier[name]:
		return "is a Dart built-in identifier, which cannot name a type"
	case dartCoreType[name]:
		return "is a dart:core type, which an import of the models would hide"
	case emittedType[name]:
		return "is a type the generated code uses"
	}
	return ""
}

func fieldNameProblem(name string) string {
	switch {
	case !identifier.MatchString(name):
		return "is not a Dart identifier"
	case reservedWord[name]:
		return "is a Dart reserved word"
	case objectMember[name]:
		return "is a member of Object"
	}
	return ""
}

func memberNameProblem(name string) string {
	if msg := fieldNameProblem(name); msg != "" {
		return msg
	}
	if enumMember[name] {
		return "is a member every generated enum has"
	}
	return ""
}
