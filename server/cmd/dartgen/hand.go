// The hand-written package around client.dart (read with -client): the
// Dart files in its directory tree, the output directory aside. The
// generated code shares their names. calls.g.dart is a part of
// client.dart, so no raw call may take a private name client.dart
// declares. The package exports the generated types beside its own, so
// none may take a hand-written top-level name. The generated methods land
// on the transport and on the classes taking the calls or the aggregate
// interface, so none may take a member those or their hand-written
// supertypes declare, the hand operations' own methods aside. And app
// code names a hand class through models.dart, which must export each.
package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

type handPackage struct {
	client string               // client.dart's file name
	decls  []handDecl           // every file's top-level declarations, by path
	byName map[string]*handDecl // the classes and mixins, by name
	// handExports is models.dart's exports of hand_models.dart.
	handExports []handExport
}

// handDecl is one top-level declaration of a hand-written file.
type handDecl struct {
	file    string   // slash path from client.dart's directory
	name    string   // "" for an unnamed extension
	kind    string   // class, mixin, enum, extension or typedef; "" for a function or variable
	supers  []string // what it extends, implements, mixes in or is on
	members []extMember
}

func (d handDecl) label() string {
	what := "the hand-written "
	if d.kind != "" {
		what += d.kind + " "
	}
	return what + d.name + " (" + d.file + ")"
}

// handExport is one export directive's show and hide lists.
type handExport struct {
	shows      bool
	show, hide []string
}

var (
	declKind     = words("class mixin enum extension typedef")
	directive    = words("import export part library")
	superKeyword = words("extends implements with on")
	exportOf     = regexp.MustCompile(`(?m)^\s*export\s+['"]([^'"]+)['"]([^;]*);`)
)

// readHandPackage reads the Dart files beside client, out's aside, and
// models.dart's exports of hand_models.dart, both where the generated
// code imports them from out.
func readHandPackage(client, out string) (*handPackage, error) {
	dir := filepath.Dir(client)
	skip, err := filepath.Abs(out)
	if err != nil {
		return nil, err
	}
	models, err := filepath.Abs(filepath.Join(out, filepath.FromSlash(modelsFile)))
	if err != nil {
		return nil, err
	}
	handModels, err := filepath.Abs(filepath.Join(out, filepath.FromSlash(handModelsFile)))
	if err != nil {
		return nil, err
	}
	hp := &handPackage{client: filepath.Base(client), byName: map[string]*handDecl{}}
	err = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		abs, err := filepath.Abs(path)
		if err != nil {
			return err
		}
		if d.IsDir() {
			if abs == skip || path != dir && strings.HasPrefix(d.Name(), ".") {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".dart") {
			return nil
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(dir, path)
		if err != nil {
			return err
		}
		hp.decls = append(hp.decls, topLevel(filepath.ToSlash(rel), codeOnly(string(src)))...)
		if abs != models {
			return nil
		}
		for _, m := range exportOf.FindAllStringSubmatch(withoutComments(string(src)), -1) {
			if filepath.Join(filepath.Dir(abs), filepath.FromSlash(m[1])) == handModels {
				hp.handExports = append(hp.handExports, combinators(m[2]))
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	for i, d := range hp.decls {
		if d.kind == "class" || d.kind == "mixin" {
			hp.byName[d.name] = &hp.decls[i]
		}
	}
	return hp, nil
}

// topLevel lists the declarations file's code makes at its top level,
// its directives aside, with the members of each class-like one.
func topLevel(file, code string) []handDecl {
	var out []handDecl
	for _, mem := range members(code) {
		ws := identWord.FindAllString(outsideGroups(mem.sig), -1)
		if len(ws) == 0 || directive[ws[0]] {
			continue
		}
		d := handDecl{file: file, name: mem.name}
		k := slices.IndexFunc(ws, func(w string) bool { return declKind[w] })
		if k >= 0 {
			d.kind = ws[k]
			rest := ws[k+1:]
			switch {
			case d.kind == "mixin" && len(rest) > 0 && rest[0] == "class":
				d.kind, rest = "class", rest[1:]
			case d.kind == "extension" && len(rest) > 0 && rest[0] == "type":
				rest = rest[1:]
			}
			switch {
			case d.kind == "typedef":
				rest = nil // memberOf named it
			case len(rest) == 0 || rest[0] == "on":
				d.name = ""
			default:
				d.name, rest = rest[0], rest[1:]
			}
			for _, w := range rest {
				if !superKeyword[w] {
					d.supers = append(d.supers, w)
				}
			}
			if body, ok := strings.CutPrefix(mem.body, "{"); ok && d.kind != "typedef" {
				d.members = members(strings.TrimSuffix(body, "}"))
			}
		}
		out = append(out, d)
	}
	return out
}

// combinators reads an export's show and hide lists.
func combinators(text string) handExport {
	var e handExport
	var into *[]string
	for _, w := range identWord.FindAllString(text, -1) {
		switch w {
		case "show":
			e.shows, into = true, &e.show
		case "hide":
			into = &e.hide
		default:
			if into != nil {
				*into = append(*into, w)
			}
		}
	}
	return e
}

// exportsHand says whether models.dart exports name from hand_models.dart.
func (hp *handPackage) exportsHand(name string) bool {
	return slices.ContainsFunc(hp.handExports, func(e handExport) bool {
		return (!e.shows || slices.Contains(e.show, name)) && !slices.Contains(e.hide, name)
	})
}

// privates is the private names client.dart declares, at its top level
// and in its classes, each with what declares it: a top-level name is its
// own, and wins over a class member of the same name.
func (hp *handPackage) privates() map[string]string {
	out := map[string]string{}
	add := func(name, what string) {
		if _, ok := out[name]; !ok && strings.HasPrefix(name, "_") {
			out[name] = what
		}
	}
	for _, d := range hp.decls {
		if d.file == hp.client {
			add(d.name, d.name)
		}
	}
	for _, d := range hp.decls {
		if d.file != hp.client {
			continue
		}
		for _, mem := range d.members {
			add(mem.name, d.name+"."+mem.name)
		}
	}
	return out
}

// publicNames is every public top-level declaration, the first of a name
// standing for it.
func (hp *handPackage) publicNames() []handDecl {
	var out []handDecl
	seen := map[string]bool{}
	for _, d := range hp.decls {
		if d.name != "" && !strings.HasPrefix(d.name, "_") && !seen[d.name] {
			seen[d.name] = true
			out = append(out, d)
		}
	}
	return out
}

// hostMembers is the public members of the declarations the generated
// methods land on, each with what declares it: the transport the calls
// are on, every hand-written declaration taking the calls or the
// aggregate interface (an extension on it too), and their hand-written
// supertypes.
func (hp *handPackage) hostMembers() map[string]string {
	var hosts []*handDecl
	seen := map[*handDecl]bool{}
	var add func(d *handDecl)
	add = func(d *handDecl) {
		if d == nil || seen[d] {
			return
		}
		seen[d] = true
		hosts = append(hosts, d)
		for _, s := range d.supers {
			add(hp.byName[s])
		}
	}
	add(hp.byName[transportClass])
	for i := range hp.decls {
		if d := &hp.decls[i]; slices.Contains(d.supers, callsAggregate) || slices.Contains(d.supers, apiAggregate) {
			add(d)
		}
	}
	out := map[string]string{}
	for _, h := range hosts {
		where := h.name + " (" + h.file + ")"
		if h.name == "" {
			where = "an unnamed extension (" + h.file + ")"
		}
		for _, mem := range h.members {
			// A constructor named for its class declares no member.
			if mem.name == "" || mem.name == h.name || mem.name == "operator" || strings.HasPrefix(mem.name, "_") {
				continue
			}
			if _, ok := out[mem.name]; !ok {
				out[mem.name] = where
			}
		}
	}
	return out
}
