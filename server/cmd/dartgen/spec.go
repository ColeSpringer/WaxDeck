package main

import (
	"context"
	"fmt"
	"maps"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/getkin/kin-openapi/openapi3"
	"gopkg.in/yaml.v3"
)

const schemaRefPrefix = "#/components/schemas/"

// spec is the loaded bundle: kin-openapi's resolved document, plus the
// bundle parsed again as YAML for the document order kin-openapi's maps
// drop (paths, methods, properties).
type spec struct {
	doc     *openapi3.T
	root    *yaml.Node
	schemas map[string]*openapi3.SchemaRef
	ops     []*operation
}

// operation is one path operation, in bundle order.
type operation struct {
	id     string
	method string // upper case
	path   string
	tag    string
	op     *openapi3.Operation
	// params is the path item's parameters then the operation's; an
	// operation parameter replaces a path one of the same name and place.
	params openapi3.Parameters
}

func loadSpec(path string) (*spec, error) {
	loader := openapi3.NewLoader()
	doc, err := loader.LoadFromFile(path)
	if err != nil {
		return nil, fmt.Errorf("spec %s: %w", path, err)
	}
	if err := doc.Validate(context.Background()); err != nil {
		return nil, fmt.Errorf("spec %s: %w", path, err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var root yaml.Node
	if err := yaml.Unmarshal(raw, &root); err != nil {
		return nil, fmt.Errorf("spec %s: %w", path, err)
	}
	s := &spec{doc: doc, root: &root, schemas: map[string]*openapi3.SchemaRef{}}
	if doc.Components != nil {
		for name, ref := range doc.Components.Schemas {
			s.schemas[name] = ref
		}
	}
	var p problems
	for _, path := range s.keys("paths") {
		item := doc.Paths.Value(path)
		if item == nil {
			continue
		}
		for _, key := range s.keys("paths", path) {
			method := strings.ToUpper(key)
			op := item.GetOperation(method)
			if op == nil {
				continue
			}
			where := method + " " + path
			if op.OperationID == "" {
				p.add("spec: %s has no operationId", where)
			}
			if len(op.Tags) != 1 {
				p.add("spec: %s has %d tags; each operation takes exactly one", where, len(op.Tags))
				continue
			}
			s.ops = append(s.ops, &operation{
				id: op.OperationID, method: method, path: path, tag: op.Tags[0],
				op: op, params: mergeParams(item.Parameters, op.Parameters),
			})
		}
	}
	if err := p.err(); err != nil {
		return nil, err
	}
	return s, nil
}

func mergeParams(item, op openapi3.Parameters) openapi3.Parameters {
	var out openapi3.Parameters
	for _, p := range item {
		if p.Value != nil && op.GetByInAndName(p.Value.In, p.Value.Name) == nil {
			out = append(out, p)
		}
	}
	return append(out, op...)
}

// componentName is the schema a component $ref names.
func componentName(ref string) (string, bool) {
	name, ok := strings.CutPrefix(ref, schemaRefPrefix)
	return name, ok && name != ""
}

// node is the YAML node at path: mapping keys, or decimal sequence
// indexes. Nil when the document has none there.
func (s *spec) node(path ...string) *yaml.Node {
	n := s.root
	if n.Kind == yaml.DocumentNode && len(n.Content) > 0 {
		n = n.Content[0]
	}
	for _, key := range path {
		n = child(n, key)
		if n == nil {
			return nil
		}
	}
	return n
}

func child(n *yaml.Node, key string) *yaml.Node {
	for n.Kind == yaml.AliasNode {
		n = n.Alias
	}
	switch n.Kind {
	case yaml.MappingNode:
		for i := 0; i+1 < len(n.Content); i += 2 {
			if n.Content[i].Value == key {
				return n.Content[i+1]
			}
		}
	case yaml.SequenceNode:
		if i, err := strconv.Atoi(key); err == nil && i >= 0 && i < len(n.Content) {
			return n.Content[i]
		}
	}
	return nil
}

// keys lists the keys of the mapping at path in document order.
func (s *spec) keys(path ...string) []string {
	n := s.node(path...)
	if n == nil || n.Kind != yaml.MappingNode {
		return nil
	}
	out := make([]string, 0, len(n.Content)/2)
	for i := 0; i < len(n.Content); i += 2 {
		out = append(out, n.Content[i].Value)
	}
	return out
}

// ordered lists the names of props in the document order recorded at
// path; any the document does not list there follow, sorted.
func (s *spec) ordered(props openapi3.Schemas, path ...string) []string {
	var out []string
	seen := map[string]bool{}
	for _, k := range s.keys(path...) {
		if _, ok := props[k]; ok && !seen[k] {
			out = append(out, k)
			seen[k] = true
		}
	}
	var rest []string
	for k := range props {
		if !seen[k] {
			rest = append(rest, k)
		}
	}
	sort.Strings(rest)
	return append(out, rest...)
}

// jsonSchemas is the schema of each JSON media type in content.
func jsonSchemas(content openapi3.Content) []*openapi3.SchemaRef {
	var out []*openapi3.SchemaRef
	for _, mime := range slices.Sorted(maps.Keys(content)) {
		if isJSON(mime) && content[mime].Schema != nil {
			out = append(out, content[mime].Schema)
		}
	}
	return out
}

func isJSON(mime string) bool {
	mime, _, _ = strings.Cut(mime, ";")
	mime = strings.TrimSpace(mime)
	return mime == "application/json" || strings.HasSuffix(mime, "+json")
}

// isEventStream says whether mime is a server-sent event stream.
func isEventStream(mime string) bool {
	mime, _, _ = strings.Cut(mime, ";")
	return strings.EqualFold(strings.TrimSpace(mime), "text/event-stream")
}

// declares says whether op states an answer for status, exactly or by its
// range (4XX); a default answer states none.
func (op *operation) declares(status int) bool {
	if op.op.Responses == nil {
		return false
	}
	code := strconv.Itoa(status)
	for key := range op.op.Responses.Map() {
		if key == code || strings.EqualFold(key, code[:1]+"XX") {
			return true
		}
	}
	return false
}

// responseSchemas is every JSON response schema op declares, by status
// in sorted order.
func (op *operation) responseSchemas() []*openapi3.SchemaRef {
	if op.op.Responses == nil {
		return nil
	}
	m := op.op.Responses.Map()
	var out []*openapi3.SchemaRef
	for _, status := range slices.Sorted(maps.Keys(m)) {
		if r := m[status]; r != nil && r.Value != nil {
			out = append(out, jsonSchemas(r.Value.Content)...)
		}
	}
	return out
}

// reached is every component schema op reaches through its parameters,
// request body and responses, sorted.
func (s *spec) reached(op *operation) []string {
	seen := map[string]bool{}
	var walk func(ref *openapi3.SchemaRef)
	walk = func(ref *openapi3.SchemaRef) {
		if ref == nil {
			return
		}
		if name, ok := componentName(ref.Ref); ok {
			if seen[name] {
				return
			}
			seen[name] = true
		}
		v := ref.Value
		if v == nil {
			return
		}
		for _, p := range v.Properties {
			walk(p)
		}
		walk(v.Items)
		walk(v.AdditionalProperties.Schema)
		for _, list := range []openapi3.SchemaRefs{v.AllOf, v.OneOf, v.AnyOf} {
			for _, member := range list {
				walk(member)
			}
		}
		walk(v.Not)
	}
	for _, p := range op.params {
		if p.Value == nil {
			continue
		}
		walk(p.Value.Schema)
		for _, mt := range p.Value.Content {
			walk(mt.Schema)
		}
	}
	if op.op.RequestBody != nil && op.op.RequestBody.Value != nil {
		for _, mt := range op.op.RequestBody.Value.Content {
			walk(mt.Schema)
		}
	}
	if op.op.Responses != nil {
		for _, r := range op.op.Responses.Map() {
			if r.Value == nil {
				continue
			}
			for _, mt := range r.Value.Content {
				walk(mt.Schema)
			}
		}
	}
	return slices.Sorted(maps.Keys(seen))
}

// tagOf maps each schema some operation reaches to the tag of the first
// one, in bundle order, that does.
func (s *spec) tagOf() map[string]string {
	out := map[string]string{}
	for _, op := range s.ops {
		for _, name := range s.reached(op) {
			if _, ok := out[name]; !ok {
				out[name] = op.tag
			}
		}
	}
	return out
}

// problems collects a run's spec and hints errors, so one run names them
// all.
type problems struct{ list []string }

func (p *problems) add(format string, args ...any) {
	p.list = append(p.list, fmt.Sprintf(format, args...))
}

func (p *problems) err() error {
	if len(p.list) == 0 {
		return nil
	}
	sort.Strings(p.list)
	var out []string
	for i, s := range p.list {
		if i == 0 || s != p.list[i-1] {
			out = append(out, s)
		}
	}
	return fmt.Errorf("%s", strings.Join(out, "\n"))
}
