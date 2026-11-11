// The hints file (dartgen.yaml) says what the spec cannot. Every key
// names a schema, property, enum or operation of the spec; one that names
// nothing, or an unknown key, fails the run.
//
//	models:      # Schema -> {as, omit: [prop], fields: {prop: field hint}, skip}
//	hand:        # Schema -> {covers: [prop], ignores: [prop]}
//	enums:       # Schema, Schema.prop or operationId.param -> {as, add: [member],
//	             #   fallback: member | drop}
//	operations:  # operationId -> {as, doc, positional, named, nullOn, long, hand, skip,
//	             #   raw, body, length, unwrap, params: {name: param hint}}
//
// A model's as naming its allOf base's Dart class folds it into the base:
// the base gains its properties, all optional, and every reference to it
// is the base. omit leaves properties out of the class, which then
// neither reads nor sends them; one a request body requires cannot be.
// skip leaves the schema's class out, no other key beside it: a generated
// class holding or extending it, or a call sending or answering it, fails
// the run.
//
// A hand schema's class is hand-written (hand_models.dart, models.as its
// name). Its hint lists every property of the schema, a base's too, under
// covers (what its decode and encode carry) or ignores (what they leave
// out on purpose), so a property the contract adds or drops fails the run
// until the class and the hint follow. A property of format uri-reference
// cannot be covered: only a generated decode resolves it.
//
// Field hints, each checked against the field's Dart type:
//   - as: the Dart field name.
//   - default: a client default for an optional property the spec gives
//     none; the field is non-null and absent decodes to it. On a required
//     property it is the constructor's default only: decode still
//     requires the property. Written as the wire value (an enum's wire
//     spelling; [] or {} for an empty list or map; {} for an object is
//     its class built with no arguments, which its constructor must
//     allow).
//   - convert: durationMs (an integer of milliseconds is a Duration),
//     apiError (an Error-shaped object, code and message, is a
//     WaxDeckApiException) or base64Text (a format byte string stays its
//     base64 text, a String).
//   - emptyAsNull: a nullable String; an empty string decodes to null.
//   - omitEmpty: an optional List, or object; an empty one is not sent (an
//     object is empty when it encodes no field).
//   - omitDefault: an optional field whose default is a value, or an empty
//     list or map, is not sent while it holds it.
//   - serverDefault: an optional property's spec default is the server's
//     to apply: the field is nullable, absent decodes to null, and a null
//     is not sent.
//   - unknownAs: a String, or a List of them, whose spec enum is not a
//     Dart enum; a wire value outside it decodes to this, or with drop the
//     list drops it (see below).
//   - dropNullValues: a map whose values can be null; null entries are
//     not sent.
//
// Enums: listing one makes it a Dart enum; an unlisted spec enum is a
// String. Schema.prop names an inline enum on the property, its items or
// its map values, and operationId.param one on an operation parameter or
// its items; a $ref'd enum is listed by its own name, and several
// fields sharing it share the Dart enum, as do several inline keys giving
// one `as` the same values and fallback. add lists members the spec lacks,
// each its own wire name, after the spec's. fallback is a spec value or a
// member name, an added one included; without one an unknown value fails
// decode.
//
// drop (fallback: drop, or unknownAs: drop on a scalar) drops the object
// holding the unknown value from the list holding that object; on a list
// of the values themselves it drops the element. Decoded as a single
// value, the holding object keeps a String's wire value; an enum field
// with fallback: drop fails the run there, having no value to take. A
// class is decoded as a single value as a response, as a property of any
// class or an element of a hand class's list (a hand class's properties
// as far as the generator can type them), and on its own when nothing
// reaches or holds it. A hand class holding a drop enum fails the run
// where a generated list holds it: only generated classes drop, and only
// from generated lists.
//
// Operation hints shape the method an operation makes (calls.go has the
// rules they adjust). A parameter is named by its spec name; the body and
// length parameters by the names body and length give them.
//   - as: the method name, the operationId by default.
//   - doc: the method's doc comment, in place of the generated one (the
//     `VERB /path` line, summary and description). Its author writes the
//     `VERB /path` opening, naming every path a hand method serves. Blank
//     lines separate paragraphs.
//   - positional: every positional parameter, in order; a path parameter
//     left out is named. Absent, the path parameters in path order.
//   - named: the named parameters' order, each listed once.
//   - nullOn: statuses the operation declares (exactly or by range) that
//     the method answers with null instead of failing; its doc gains a
//     sentence saying so.
//   - long: the call may outlast the receive deadline (_longOperation).
//   - hand: the interface declares the method and its raw call exists, but
//     the method is hand-written; raw: only the raw call exists; skip:
//     neither does. Only long applies beside raw, nothing beside skip.
//   - body: the request body as one parameter of this name: a JSON object
//     body's model instead of its fields (which a field sharing a
//     parameter's name requires), or a binary or other body (whose
//     parameter is otherwise named body).
//   - length: a binary body streams, as a Stream<List<int>> Function()
//     parameter and an int parameter of this name, its length; without it
//     the body is a Uint8List.
//   - unwrap: the method answers this property of the response object,
//     which it answers whole without the hint.
//
// Param hints (a hand operation's parameters may also omit or null a
// required one: its hand-written method decides what is sent):
//   - as: the Dart name.
//   - omit: left out of the signature: never passed, so an omitted query
//     parameter keeps the raw call's spec default and a body field its
//     model's.
//   - default: a default the parameter takes, written as field defaults
//     are. Where the spec gives the parameter or body field a default, it
//     is that one.
//   - nullable: nullable although its body field has a default, which a
//     null sends in its place.
//   - omitFalse: a bool sent only when true; it defaults to false, and a
//     spec default must be false too.
//   - type: a hand operation's parameter type, for the reshape its
//     hand-written method makes; the wire type's default no longer applies.
//
// The operations section is checked against the spec before the model is
// built (the operation exists, as, doc, the modes, nullOn statuses) and
// against the model after (every other key).
package main

import (
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"
)

type hints struct {
	Models     map[string]modelHint     `yaml:"models"`
	Hand       map[string]handHint      `yaml:"hand"`
	Enums      map[string]enumHint      `yaml:"enums"`
	Operations map[string]operationHint `yaml:"operations"`
}

type handHint struct {
	Covers  []string `yaml:"covers"`
	Ignores []string `yaml:"ignores"`
}

type modelHint struct {
	As     string               `yaml:"as"`
	Omit   []string             `yaml:"omit"`
	Fields map[string]fieldHint `yaml:"fields"`
	Skip   bool                 `yaml:"skip"`
}

type fieldHint struct {
	As             string    `yaml:"as"`
	Default        yaml.Node `yaml:"default"`
	Convert        string    `yaml:"convert"`
	EmptyAsNull    bool      `yaml:"emptyAsNull"`
	OmitEmpty      bool      `yaml:"omitEmpty"`
	OmitDefault    bool      `yaml:"omitDefault"`
	ServerDefault  bool      `yaml:"serverDefault"`
	UnknownAs      *string   `yaml:"unknownAs"`
	DropNullValues bool      `yaml:"dropNullValues"`
}

type enumHint struct {
	As       string   `yaml:"as"`
	Add      []string `yaml:"add"`
	Fallback string   `yaml:"fallback"`
}

type operationHint struct {
	As  string `yaml:"as"`
	Doc string `yaml:"doc"`
	// Positional is nil when absent and empty when given as [].
	Positional []string             `yaml:"positional"`
	Named      []string             `yaml:"named"`
	NullOn     []int                `yaml:"nullOn"`
	Long       bool                 `yaml:"long"`
	Hand       bool                 `yaml:"hand"`
	Skip       bool                 `yaml:"skip"`
	Raw        bool                 `yaml:"raw"`
	Body       string               `yaml:"body"`
	Length     string               `yaml:"length"`
	Unwrap     string               `yaml:"unwrap"`
	Params     map[string]paramHint `yaml:"params"`
}

type paramHint struct {
	As        string    `yaml:"as"`
	Omit      bool      `yaml:"omit"`
	Default   yaml.Node `yaml:"default"`
	Nullable  bool      `yaml:"nullable"`
	OmitFalse bool      `yaml:"omitFalse"`
	Type      string    `yaml:"type"`
}

const dropValue = "drop"

// hintLiteral is a field's or parameter's default hint as a Dart constant
// of t, and the classes the constant builds with no arguments, which
// their constructors must allow.
func hintLiteral(t *dartType, node yaml.Node) (string, []*class, error) {
	var v any
	if err := node.Decode(&v); err != nil {
		return "", nil, err
	}
	lit, err := constLiteral(t, v)
	if err != nil {
		return "", nil, err
	}
	return lit, builtBare(t, v), nil
}

// builtBare is the classes the default v of t builds with no arguments:
// each {} standing for one, at any depth of lists and maps.
func builtBare(t *dartType, v any) []*class {
	var out []*class
	switch x := v.(type) {
	case map[string]any:
		if t.kind == kClass {
			return []*class{t.class}
		}
		if t.kind == kMap {
			for _, k := range slices.Sorted(maps.Keys(x)) {
				out = append(out, builtBare(t.elem, x[k])...)
			}
		}
	case []any:
		if t.kind == kList {
			for _, item := range x {
				out = append(out, builtBare(t.elem, item)...)
			}
		}
	}
	return out
}

func parseHints(path string) (*hints, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	dec := yaml.NewDecoder(f)
	dec.KnownFields(true)
	var h hints
	if err := dec.Decode(&h); err != nil && !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("hints %s: %w", path, err)
	}
	var next yaml.Node
	if err := dec.Decode(&next); !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("hints %s: a second YAML document follows the first; the hints are one document", path)
	}
	return &h, nil
}

// checkOperations validates what the operations section says of the spec
// alone; buildCalls checks the rest against the model.
func checkOperations(s *spec, h *hints, p *problems) {
	for _, id := range slices.Sorted(maps.Keys(h.Operations)) {
		hint := h.Operations[id]
		key := "operations." + id
		op := s.opByID(id)
		if op == nil {
			p.add("hints: %s: no operation has this operationId", key)
			continue
		}
		if hint.As != "" {
			if msg := fieldNameProblem(hint.As); msg != "" {
				p.add("hints: %s.as: %s %s", key, hint.As, msg)
			}
		}
		if hint.Doc != "" && strings.TrimSpace(hint.Doc) == "" {
			p.add("hints: %s.doc: the text is blank", key)
		}
		modes := 0
		for _, on := range []bool{hint.Hand, hint.Skip, hint.Raw} {
			if on {
				modes++
			}
		}
		if modes > 1 {
			p.add("hints: %s: hand, skip and raw exclude each other", key)
		}
		for _, status := range hint.NullOn {
			switch {
			case status < 100 || status > 599:
				p.add("hints: %s.nullOn: %d is not an HTTP status", key, status)
			case !op.declares(status):
				p.add("hints: %s.nullOn: %s declares no %d answer", key, id, status)
			}
		}
	}
}
