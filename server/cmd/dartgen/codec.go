package main

import (
	"fmt"
	"maps"
	"slices"
	"strconv"
	"strings"
)

// codecGen writes codec.g.dart: decodeX and encodeX per generated class,
// over the helpers of wire.dart. Its read, reader and write are the
// type-level expression builders; the field-level ones add the hints.
type codecGen struct {
	f     *dartFile
	ctx   string              // the WireContext expression a class decode takes
	known map[string][]string // const set name -> wire values
	keeps map[string]*class   // keep predicate name -> the list element it checks
}

func (m *model) codec() *dartFile {
	g := &codecGen{f: newDartFile(codecFile), ctx: "ctx", known: map[string][]string{}, keeps: map[string]*class{}}
	classes := m.generated()
	if len(classes) == 0 {
		return g.f
	}
	g.f.use(wireFile)
	g.f.use(barrelFile)
	for _, c := range classes {
		g.f.decls = append(g.f.decls, g.decodeDecl(c), g.encodeDecl(c))
	}
	for _, name := range slices.Sorted(maps.Keys(g.keeps)) {
		g.f.decls = append(g.f.decls, g.keepDecl(name, g.keeps[name]))
	}
	for _, name := range slices.Sorted(maps.Keys(g.known)) {
		values := make([]string, len(g.known[name]))
		for i, v := range g.known[name] {
			values[i] = dartString(v)
		}
		g.f.decls = append(g.f.decls, fmt.Sprintf("const %s = {%s};\n", name, strings.Join(values, ", ")))
	}
	return g.f
}

func (g *codecGen) decodeDecl(c *class) string {
	fields := c.all()
	sig := fmt.Sprintf("%s decode%s(Map<String, Object?> json, WireContext ctx)", c.name, c.name)
	if len(fields) == 0 {
		return fmt.Sprintf("%s =>\n    const %s();\n", sig, c.name)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s {\n", sig)
	if slices.ContainsFunc(fields, func(f *field) bool { return f.typ.kind != kAny }) {
		fmt.Fprintf(&b, "  const type = %s;\n", dartString(c.name))
	}
	fmt.Fprintf(&b, "  return %s(\n", c.name)
	for _, f := range fields {
		fmt.Fprintf(&b, "    %s: %s,\n", f.name, g.fieldRead(f))
	}
	b.WriteString("  );\n}\n")
	return b.String()
}

func (g *codecGen) encodeDecl(c *class) string {
	fields := c.all()
	sig := fmt.Sprintf("Map<String, Object?> encode%s(%s value)", c.name, c.name)
	if len(fields) == 0 {
		return sig + " => {};\n"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s => {\n", sig)
	for _, f := range fields {
		fmt.Fprintf(&b, "  %s,\n", g.fieldWrite(f))
	}
	b.WriteString("};\n")
	return b.String()
}

// keepDecl is the predicate a list of c's objects keeps an element by: it
// drops one whose drop field holds a value this build does not know.
func (g *codecGen) keepDecl(name string, c *class) string {
	var checks []string
	for _, f := range c.all() {
		if set := g.dropSet(f); set != "" {
			checks = append(checks, fmt.Sprintf("wireKnown(element[%s], %s)", dartString(f.prop), set))
		}
	}
	cond := strings.Join(checks, " && ")
	if len(checks) > 1 {
		cond = "(" + cond + ")"
	}
	return fmt.Sprintf("bool %s(Object? element) =>\n    element is! Map<String, Object?> || %s;\n", name, cond)
}

// drops says whether f's unknown value drops the object holding it from
// a list.
func drops(f *field) bool {
	t := f.typ
	return t.kind == kEnum && t.enum.drop ||
		t.kind == kString && f.unknownAs != nil && *f.unknownAs == dropValue
}

func (g *codecGen) dropSet(f *field) string {
	if !drops(f) {
		return ""
	}
	if f.typ.kind == kEnum {
		return g.enumSet(f.typ.enum)
	}
	return g.stringSet(f.typ)
}

func (g *codecGen) enumSet(e *enumDef) string { return g.set(e.name, e.values) }

func (g *codecGen) stringSet(t *dartType) string { return g.set(t.knownAs, t.known) }

// set names the const set of values, registering it for emission.
func (g *codecGen) set(base string, values []string) string {
	name := "_known" + base
	for n := 2; ; n++ {
		prev, taken := g.known[name]
		if !taken {
			g.known[name] = values
			return name
		}
		if slices.Equal(prev, values) {
			return name
		}
		name = "_known" + base + strconv.Itoa(n)
	}
}

// keepsBy says whether a list of e keeps its elements by a predicate:
// generated objects with a drop field, or drop enums.
func keepsBy(e *dartType) bool {
	return e.kind == kClass && !e.class.hand && slices.ContainsFunc(e.class.all(), drops) ||
		e.kind == kEnum && e.enum.drop
}

// keepOf is the predicate a list of e keeps its elements by (keepsBy),
// registered for emission.
func (g *codecGen) keepOf(e *dartType) string {
	if e.kind == kEnum {
		return fmt.Sprintf("(e) => wireKnown(e, %s)", g.enumSet(e.enum))
	}
	name := "_keep" + e.class.name
	g.keeps[name] = e.class
	return name
}

// fieldRead is the expression decoding f from json.
func (g *codecGen) fieldRead(f *field) string {
	key := dartString(f.prop)
	if f.typ.kind == kAny {
		return "json[" + key + "]"
	}
	read := g.fieldReader(f)
	switch {
	case f.required && !f.nullable:
		return fmt.Sprintf("readRequired(json, %s, type, %s)", key, read)
	case f.def != "" && !f.required:
		return fmt.Sprintf("readOptional(json, %s, type, %s) ?? %s", key, read, f.def)
	}
	return fmt.Sprintf("readOptional(json, %s, type, %s)", key, read)
}

// fieldReader is the WireRead f decodes through: its type's, with the
// field hints applied.
func (g *codecGen) fieldReader(f *field) string {
	t := f.typ
	switch {
	case f.unknownAs != nil:
		value := *f.unknownAs
		if t.kind != kList {
			if value == dropValue {
				// Decoded alone it keeps the wire value; a list of the
				// holding objects drops it through the keep predicate.
				return "wireString"
			}
			return fmt.Sprintf("(v, at) => wireKnownOr(v, at, %s, %s)", g.stringSet(t), dartString(value))
		}
		set := g.stringSet(t.elem)
		if value == dropValue {
			return fmt.Sprintf("(v, at) => wireList(v, at, wireString, keep: (e) => wireKnown(e, %s))", set)
		}
		return fmt.Sprintf("(v, at) => wireList(v, at, (e, at) => wireKnownOr(e, at, %s, %s))", set, dartString(value))
	case t.url && f.emptyAsNull:
		return "(v, at) => switch (wireNonEmpty(v, at)) {\n      final s? => resolveMediaUrl(" + g.ctx + ".baseUrl, s),\n      null => null,\n    }"
	case f.emptyAsNull:
		return "wireNonEmpty"
	}
	return g.reader(t, 0)
}

var tearOffs = map[typeKind]string{
	kString: "wireString", kInt: "wireInt", kDouble: "wireDouble", kBool: "wireBool",
	kDateTime: "wireDateTime", kDate: "wireDate", kBytes: "wireBytes", kJSONObject: "wireObject",
	kDuration: "wireMilliseconds", kAPIError: "wireApiError",
}

// reader is t's read as a WireRead function value: a helper's tear-off
// where one fits, else a closure. depth names the closure parameters of
// nested collections apart.
func (g *codecGen) reader(t *dartType, depth int) string {
	if name := tearOffs[t.kind]; name != "" && !t.nullable && !t.url {
		return name
	}
	v := "v"
	if depth > 0 {
		v = "e"
		if depth > 1 {
			v += strconv.Itoa(depth)
		}
	}
	body := g.read(t, v, "at", depth)
	if t.nullable && t.kind != kAny {
		body = v + " == null ? null : " + body
	}
	return "(" + v + ", at) => " + body
}

// read is the expression decoding JSON value v (an Object? expression)
// as t, at naming it in errors.
func (g *codecGen) read(t *dartType, v, at string, depth int) string {
	if t.url {
		return fmt.Sprintf("resolveMediaUrl(%s.baseUrl, wireString(%s, %s))", g.ctx, v, at)
	}
	if name := tearOffs[t.kind]; name != "" {
		return name + "(" + v + ", " + at + ")"
	}
	switch t.kind {
	case kAny:
		return v
	case kEnum:
		return fmt.Sprintf("wireEnum(%s, %s, %s.fromWire)", v, at, t.enum.name)
	case kClass:
		if t.class.hand {
			g.f.use(handModelsFile)
		}
		return fmt.Sprintf("decode%s(wireObject(%s, %s), %s)", t.class.name, v, at, g.ctx)
	case kList:
		keep := ""
		if keepsBy(t.elem) {
			keep = ", keep: " + g.keepOf(t.elem)
		}
		return fmt.Sprintf("wireList(%s, %s, %s%s)", v, at, g.reader(t.elem, depth+1), keep)
	case kMap:
		return fmt.Sprintf("wireMap(%s, %s, %s)", v, at, g.reader(t.elem, depth+1))
	}
	panic(fmt.Sprintf("read: unhandled kind %d", t.kind))
}

// fieldWrite is f's entry in its class's encoded map.
func (g *codecGen) fieldWrite(f *field) string {
	key := dartString(f.prop)
	acc := "value." + f.name
	enc := func(x string) string { return g.write(f.typ, x, 0) }
	identity := isIdentity(f.typ)
	if f.dropNullValues {
		value := f.typ.elem
		if f.typ.kind == kJSONObject {
			value = &dartType{kind: kAny}
		}
		enc = func(x string) string {
			if isIdentity(value) {
				return fmt.Sprintf("{for (final e in %s.entries) e.key: ?e.value}", x)
			}
			return fmt.Sprintf("{for (final e in %s.entries) if (e.value case final x?) e.key: %s}", x, g.write(value, "x", 1))
		}
		identity = false
	}
	switch {
	case f.typ.kind == kAny && f.required:
		return key + ": " + acc
	case f.omitDefault && isCollection(f.typ):
		return fmt.Sprintf("if (%s.isNotEmpty) %s: %s", acc, key, enc(acc))
	case f.omitDefault && f.typ.kind == kBool && f.def == "false":
		return fmt.Sprintf("if (%s) %s: %s", acc, key, acc)
	case f.omitDefault && f.typ.kind == kBool:
		return fmt.Sprintf("if (!%s) %s: %s", acc, key, acc)
	case f.omitDefault:
		return fmt.Sprintf("if (%s != %s) %s: %s", acc, f.def, key, enc(acc))
	case f.omitEmpty && f.typ.kind == kClass && f.nullable:
		return fmt.Sprintf("if (%s case final v?)\n    if (%s case final e when e.isNotEmpty) %s: e", acc, enc("v"), key)
	case f.omitEmpty && f.typ.kind == kClass:
		return fmt.Sprintf("if (%s case final e when e.isNotEmpty) %s: e", enc(acc), key)
	case !f.nullable && f.omitEmpty:
		return fmt.Sprintf("if (%s.isNotEmpty) %s: %s", acc, key, enc(acc))
	case !f.nullable:
		return key + ": " + enc(acc)
	case f.required && identity:
		return key + ": " + acc
	case f.required:
		return fmt.Sprintf("%s: switch (%s) {\n    final v? => %s,\n    null => null,\n  }", key, acc, enc("v"))
	case f.omitEmpty:
		return fmt.Sprintf("if (%s case final v? when v.isNotEmpty) %s: %s", acc, key, enc("v"))
	case identity:
		return key + ": ?" + acc
	}
	return fmt.Sprintf("if (%s case final v?) %s: %s", acc, key, enc("v"))
}

func isCollection(t *dartType) bool {
	return t.kind == kList || t.kind == kMap || t.kind == kJSONObject
}

// isIdentity says whether t's Dart value is already its JSON.
func isIdentity(t *dartType) bool {
	switch t.kind {
	case kString, kInt, kDouble, kBool, kAny, kJSONObject:
		return true
	case kList, kMap:
		return isIdentity(t.elem)
	}
	return false
}

// write is the expression encoding x, a non-null Dart value of t, as
// JSON.
func (g *codecGen) write(t *dartType, x string, depth int) string {
	switch t.kind {
	case kString, kInt, kDouble, kBool, kAny, kJSONObject:
		return x
	case kDateTime:
		return x + ".toUtc().toIso8601String()"
	case kDate:
		return "writeDate(" + x + ")"
	case kBytes:
		return "writeBytes(" + x + ")"
	case kEnum:
		return x + ".wireName"
	case kClass:
		if t.class.hand {
			g.f.use(handModelsFile)
		}
		return "encode" + t.class.name + "(" + x + ")"
	case kDuration:
		return x + ".inMilliseconds"
	case kAPIError:
		return "writeApiError(" + x + ")"
	}
	if isIdentity(t) {
		return x
	}
	e := "e"
	if depth > 0 {
		e += strconv.Itoa(depth)
	}
	if t.kind == kList {
		return fmt.Sprintf("[for (final %s in %s) %s]", e, x, g.writeNullable(t.elem, e, depth+1))
	}
	return fmt.Sprintf("{for (final %s in %s.entries) %s.key: %s}", e, x, e, g.writeNullable(t.elem, e+".value", depth+1))
}

func (g *codecGen) writeNullable(t *dartType, x string, depth int) string {
	if !t.nullable || isIdentity(t) {
		return g.write(t, x, depth)
	}
	n := "n"
	if depth > 1 {
		n += strconv.Itoa(depth)
	}
	return fmt.Sprintf("switch (%s) { final %s? => %s, null => null }", x, n, g.write(t, n, depth))
}
