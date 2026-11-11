// What a public signature reaches. public.g.dart, which models.dart
// exports, names exactly those generated classes (with their paging
// extensions) and enums; the codec exports the rest (bodies a method
// flattens, envelopes it unwraps, what only the socket frames hold) to
// its callers, the client and the tests.
// The roots are the interfaces' parameters and answers, the hand
// classes' covered properties and the classes the hand extensions
// extend; a class reaches its base and its fields' types. A covered
// property counts by its spec type, so a hand class that reshapes one
// (SessionState keeps the server as a bool) exports the spec's class
// anyway: an over-export, which is safe.
package main

import (
	"maps"
	"slices"
)

const publicFile = "public.g.dart"

type publicSet struct {
	classes map[*class]bool // hand classes included
	enums   map[*enumDef]bool
}

func (cs *calls) public() publicSet {
	m := cs.m
	pub := publicSet{classes: map[*class]bool{}, enums: map[*enumDef]bool{}}
	var reach func(c *class)
	var walk func(t *dartType)
	reach = func(c *class) {
		if c == nil || pub.classes[c] {
			return
		}
		pub.classes[c] = true
		reach(c.base)
		if !c.hand {
			for _, f := range c.fields {
				walk(f.typ)
			}
			return
		}
		covered := map[string]bool{}
		for _, prop := range m.hints.Hand[c.schema].Covers {
			covered[prop] = true
		}
		for _, p := range m.handProps(c) {
			if covered[p.prop] {
				walk(p.typ)
			}
		}
	}
	walk = func(t *dartType) {
		switch t.kind {
		case kClass:
			reach(t.class)
		case kEnum:
			pub.enums[t.enum] = true
		case kList, kMap:
			walk(t.elem)
		}
	}
	for _, tag := range cs.tags {
		for _, c := range cs.byTag[tag] {
			if c.method == nil {
				continue
			}
			for _, t := range c.signatureTypes() {
				walk(t)
			}
		}
	}
	for _, name := range slices.Sorted(maps.Keys(m.classes)) {
		if c := m.classes[name]; c.hand || !c.fold && !c.skip && m.extended(c) {
			reach(c)
		}
	}
	return pub
}

// declared is what the generated class c declares: c, and its paging
// extension when it pages.
func declared(c *class) []string {
	if pages(c) {
		return []string{c.name, pagingExtension(c)}
	}
	return []string{c.name}
}

// barrel is public.g.dart.
func (pub publicSet) barrel(m *model) *dartFile {
	f := newDartFile(publicFile)
	var enums []string
	for _, e := range m.sortedEnums() {
		if pub.enums[e] {
			enums = append(enums, e.name)
		}
	}
	if len(enums) > 0 {
		f.exports = append(f.exports, dartExport{uri: enumsFile, show: enums})
	}
	byFile := map[string][]string{}
	for _, c := range m.generated() {
		if pub.classes[c] {
			byFile[c.file] = append(byFile[c.file], declared(c)...)
		}
	}
	for _, stem := range slices.Sorted(maps.Keys(byFile)) {
		f.exports = append(f.exports, dartExport{uri: modelFile(stem), show: slices.Sorted(slices.Values(byFile[stem]))})
	}
	return f
}

// internal is the generated classes and enums pub leaves out, sorted.
func (pub publicSet) internal(m *model) []string {
	var out []string
	for _, c := range m.generated() {
		if !pub.classes[c] {
			out = append(out, declared(c)...)
		}
	}
	for _, e := range m.sortedEnums() {
		if !pub.enums[e] {
			out = append(out, e.name)
		}
	}
	slices.Sort(out)
	return out
}
