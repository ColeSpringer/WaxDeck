// The hand extensions (model_extensions.dart, read with -extensions):
// the public members of one on a generated class are names no generated
// field of the class, its bases or its subclasses may take, and a
// copyWith among them takes a parameter for every field of its class, a
// base's included, and passes each to the constructor call it returns.
// Each extension's public instance members, and copyWith's parameters
// and that call's named arguments, are read from the Dart source as
// closely as checkMembers needs.
package main

import (
	"regexp"
	"strings"
)

type extensionsFile struct {
	path string
	list []extension
}

type extension struct {
	name     string   // "" for an unnamed one
	on       string   // the type extended, less a trailing ? and an import prefix
	prefix   string   // the import prefix on had, or ""
	members  []string // public instance members, in source order
	copyWith []string // copyWith's parameter names, when it declares one
	// copied is the named arguments copyWith's body passes the call of
	// on's constructor it returns, and builds whether there is one.
	copied []string
	builds bool
}

func (e extension) label() string {
	if e.name == "" {
		return "an unnamed extension"
	}
	return "extension " + e.name
}

var identWord = regexp.MustCompile(`[A-Za-z_$][\w$]*`)

// parseExtensions lists the top-level extensions src declares.
func parseExtensions(src string) []extension {
	code := codeOnly(src)
	var out []extension
	depth := 0
	for i := 0; i < len(code); i++ {
		switch code[i] {
		case '{':
			depth++
			continue
		case '}':
			depth--
			continue
		}
		if depth != 0 || !wordAt(code, i, "extension") {
			continue
		}
		name, on, prefix, open, ok := extensionHead(code, i)
		if !ok {
			continue
		}
		e := extension{name: name, on: on, prefix: prefix}
		end := closingBrace(code, open)
		for _, mem := range members(code[open+1 : end]) {
			// A private member reserves nothing: no generated field takes
			// a name starting with _.
			if mem.static || mem.name == "" || mem.name == "operator" || strings.HasPrefix(mem.name, "_") {
				continue
			}
			e.members = append(e.members, mem.name)
			if mem.name == "copyWith" && mem.method {
				e.copyWith = paramNames(mem.params)
				e.copied, e.builds = constructorArgs(mem.body, e.on, e.prefix)
			}
		}
		out = append(out, e)
		i = end
	}
	return out
}

// extensionHead reads the extension declared at code[i]: its name (""
// for an unnamed one), the type it is on, less a trailing ? and an import
// prefix (which it answers apart), and the index of the brace opening its
// body. ok is false where no extension on a type starts (an extension
// type).
func extensionHead(code string, i int) (name, on, prefix string, open int, ok bool) {
	j := skipSpace(code, i+len("extension"))
	if word := identAt(code, j); word != "" && word != "on" {
		name = word
		j = skipSpace(code, j+len(word))
	}
	if j < len(code) && code[j] == '<' {
		if j = closingAngle(code, j); j < 0 {
			return "", "", "", 0, false
		}
		j = skipSpace(code, j+1)
	}
	if !wordAt(code, j, "on") {
		return "", "", "", 0, false
	}
	j += len("on")
	k := strings.IndexAny(code[j:], "{;")
	if k < 0 || code[j+k] != '{' {
		return "", "", "", 0, false
	}
	open = j + k
	on = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(code[j:open]), "?"))
	if !strings.ContainsAny(on, "<(") {
		if dot := strings.LastIndexByte(on, '.'); dot >= 0 {
			prefix, on = strings.TrimSpace(on[:dot]), strings.TrimSpace(on[dot+1:])
		}
	}
	return name, on, prefix, open, on != ""
}

// identAt is the identifier starting at code[i], or "".
func identAt(code string, i int) string {
	j := i
	for j < len(code) && isIdentByte(code[j]) {
		j++
	}
	if j == i || code[i] >= '0' && code[i] <= '9' {
		return ""
	}
	return code[i:j]
}

// wordAt says whether the identifier word stands whole at code[i].
func wordAt(code string, i int, word string) bool {
	end := i + len(word)
	return strings.HasPrefix(code[i:], word) && (i == 0 || !isIdentByte(code[i-1])) &&
		(end == len(code) || !isIdentByte(code[end]))
}

func skipSpace(code string, i int) int {
	for i < len(code) && strings.IndexByte(" \t\r\n", code[i]) >= 0 {
		i++
	}
	return i
}

// closingAngle is the index of the > closing the < at code[open], or -1.
func closingAngle(code string, open int) int {
	depth := 0
	for i := open; i < len(code); i++ {
		switch code[i] {
		case '<':
			depth++
		case '>':
			if depth--; depth == 0 {
				return i
			}
		case '{', ';':
			return -1
		}
	}
	return -1
}

// codeOnly is src with its comments and the text of its string literals
// blanked, line breaks kept, so no brace or quote of theirs is read.
func codeOnly(src string) string {
	b := []byte(withoutComments(src))
	for i := 0; i < len(b); {
		if b[i] != '\'' && b[i] != '"' {
			i++
			continue
		}
		end := skipString(b, i)
		for j := i + 1; j < end-1; j++ {
			if b[j] != '\n' {
				b[j] = ' '
			}
		}
		i = end
	}
	return string(b)
}

// closingBrace is the index of the brace closing the one at open, or
// len(code) when none does.
func closingBrace(code string, open int) int {
	depth := 0
	for i := open; i < len(code); i++ {
		switch code[i] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return len(code)
}

type extMember struct {
	name   string
	static bool
	method bool   // its signature ends in a parameter list
	params string // the parameter list, its parentheses' contents
	sig    string // the signature itself
	body   string // what follows the signature: a body or an initializer
}

// members splits a class-like body, or a file's top level, into its
// declarations, naming each from its signature: what precedes its body,
// =>, an initializer's =, a constructor's initializer list or the ;
// ending it.
func members(body string) []extMember {
	var out []extMember
	for i := skipAnnotations(body, 0); i < len(body); i = skipAnnotations(body, i) {
		start, depth, sig := i, 0, -1
		initializers := false
	scan:
		for ; i < len(body); i++ {
			if depth == 0 && sig < 0 && wordAt(body, i, "operator") {
				// Its token, []= or == among them, has no initializer's =.
				i = skipOperator(body, i+len("operator")) - 1
				continue
			}
			switch body[i] {
			case '(', '[':
				depth++
			case ')', ']':
				depth--
			case '=':
				if depth == 0 && sig < 0 {
					sig = i
				}
			case ':':
				// A constructor's initializer list, its body perhaps after.
				if depth == 0 && sig < 0 {
					sig, initializers = i, true
				}
			case '{':
				if depth == 0 && (sig < 0 || initializers && opensBody(body, i)) {
					if sig < 0 {
						sig = i
					}
					i = closingBrace(body, i) + 1
					break scan
				}
				depth++
			case '}':
				depth--
			case ';':
				if depth == 0 {
					if sig < 0 {
						sig = i
					}
					i++
					break scan
				}
			}
		}
		if sig < 0 {
			sig = len(body)
		}
		mem := memberOf(body[start:sig])
		mem.sig, mem.body = body[start:sig], body[sig:i]
		out = append(out, mem)
	}
	return out
}

// opensBody says whether the { at code[i], in a constructor's initializer
// list, opens the constructor's body: it follows an expression's end,
// where a literal's { follows an operator or an opening bracket. A
// postfix !, ++ or -- and the > closing a type's arguments (y as
// Map<String, int>) end one; a > after = is an arrow, and one closing a
// literal's own type arguments (<String, int>{}) starts a literal.
func opensBody(code string, i int) bool {
	j := i - 1
	for j >= 0 && strings.IndexByte(" \t\r\n", code[j]) >= 0 {
		j--
	}
	if j < 0 {
		return false
	}
	switch c := code[j]; c {
	case '!':
		// A negated literal is no expression, so this is the postfix.
		return true
	case '+', '-':
		return j > 0 && code[j-1] == c
	case '>':
		if j > 0 && code[j-1] == '=' {
			return false
		}
		return namesType(code, j)
	}
	return strings.IndexByte("=,(:?[{&|<*/%~^", code[j]) < 0
}

// namesType says whether the > at code[end] closes the type arguments of a
// type's name, as opposed to a literal's own (<String, int>{}, const
// <int>{}).
func namesType(code string, end int) bool {
	depth := 0
	for k := end; k >= 0; k-- {
		switch code[k] {
		case '>':
			depth++
		case '<':
			if depth--; depth > 0 {
				continue
			}
			k--
			for k >= 0 && strings.IndexByte(" \t\r\n", code[k]) >= 0 {
				k--
			}
			if k < 0 || !isIdentByte(code[k]) {
				return false
			}
			start := k
			for start > 0 && isIdentByte(code[start-1]) {
				start--
			}
			return code[start:k+1] != "const"
		case ';', '{', '}':
			return false
		}
	}
	return false
}

// operatorTokens is every operator a class can declare, each before any
// it starts with.
var operatorTokens = []string{"[]=", "[]", ">>>", ">>", ">=", "<<", "<=", "==", "~/", "<", ">", "+", "-", "*", "/", "%", "&", "|", "^", "~"}

// skipOperator is the index after the operator token an operator
// declaration names at or after body[i].
func skipOperator(body string, i int) int {
	i = skipSpace(body, i)
	for _, tok := range operatorTokens {
		if strings.HasPrefix(body[i:], tok) {
			return i + len(tok)
		}
	}
	return i
}

// skipAnnotations is the index of the first code at or after i that is
// neither space nor an annotation: @name or @a.b, with an argument list
// when one follows at once.
func skipAnnotations(body string, i int) int {
	for {
		for i < len(body) && strings.IndexByte(" \t\r\n", body[i]) >= 0 {
			i++
		}
		if i >= len(body) || body[i] != '@' {
			return i
		}
		i++
		for i < len(body) && (isIdentByte(body[i]) || body[i] == '.') {
			i++
		}
		if i < len(body) && body[i] == '(' {
			for depth := 0; i < len(body); i++ {
				switch body[i] {
				case '(':
					depth++
				case ')':
					depth--
				}
				if depth == 0 {
					i++
					break
				}
			}
		}
	}
}

// memberOf names the member a signature declares: a getter or setter by
// the word after get or set, a method by the last word before the
// parameter list ending its signature, anything else by its last word.
// Words inside a type's parentheses or angle brackets do not count.
func memberOf(sig string) extMember {
	var mem extMember
	sig = strings.TrimSpace(sig)
	for _, modifier := range []string{"async*", "async", "sync*"} {
		rest, ok := strings.CutSuffix(sig, modifier)
		if ok && (strings.HasSuffix(rest, " ") || strings.HasSuffix(rest, ")")) {
			sig = strings.TrimSpace(rest)
			break
		}
	}
	if strings.HasSuffix(sig, ")") {
		if open := openingParen(sig); open >= 0 {
			mem.method, mem.params = true, sig[open+1:len(sig)-1]
			sig = sig[:open]
		}
	}
	words := identWord.FindAllString(outsideGroups(sig), -1)
	if len(words) == 0 {
		return mem
	}
	mem.static, mem.name = words[0] == "static", words[len(words)-1]
	for i, w := range words[:len(words)-1] {
		switch w {
		case "get", "set":
			mem.name = words[i+1]
		case "operator":
			mem.name = w
		}
	}
	return mem
}

// outsideGroups is s with each parenthesized or angle-bracketed group a
// space.
func outsideGroups(s string) string {
	var b strings.Builder
	depth := 0
	for i := 0; i < len(s); i++ {
		switch c := s[i]; {
		case c == '(' || c == '<':
			if depth == 0 {
				b.WriteByte(' ')
			}
			depth++
		case (c == ')' || c == '>') && depth > 0:
			depth--
		case depth == 0:
			b.WriteByte(c)
		}
	}
	return b.String()
}

// openingParen is the index of the ( matching the ) s ends with, or -1.
func openingParen(s string) int {
	depth := 0
	for i := len(s) - 1; i >= 0; i-- {
		switch s[i] {
		case ')':
			depth++
		case '(':
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

// constructorArgs is the named arguments the call of class's constructor
// that body returns passes, and whether body has one; prefix is the import
// prefix class is known by, "" for none. Where what body returns holds no
// such call (an unusual shape), its first one stands.
func constructorArgs(body, class, prefix string) ([]string, bool) {
	for _, expr := range []string{returned(body), body} {
		for i := range expr {
			if !callsConstructor(expr, i, class, prefix) {
				continue
			}
			var named []string
			for _, arg := range splitArgs(expr[skipSpace(expr, i+len(class))+1:]) {
				if m := namedArg.FindStringSubmatch(arg); m != nil {
					named = append(named, m[1])
				}
			}
			return named, true
		}
	}
	return nil, false
}

// callsConstructor says whether expr[i:] starts a call of class's
// constructor: the name, whole, then an argument list; qualified only by
// the import prefix class is known by.
func callsConstructor(expr string, i int, class, prefix string) bool {
	if !wordAt(expr, i, class) {
		return false
	}
	if i > 0 && expr[i-1] == '.' {
		at := i - 1 - len(prefix)
		if prefix == "" || at < 0 || expr[at:i-1] != prefix || at > 0 && (isIdentByte(expr[at-1]) || expr[at-1] == '.') {
			return false
		}
	}
	open := skipSpace(expr, i+len(class))
	return open < len(expr) && expr[open] == '('
}

var localName = regexp.MustCompile(`^[A-Za-z_$][\w$]*$`)

// returned is the expression body hands back: an arrow body's, or the last
// return statement at the top level of a block body's, read through the
// local it names when it names one. A body returning nothing it can read
// is itself.
func returned(body string) string {
	b := strings.TrimSpace(body)
	if rest, ok := strings.CutPrefix(b, "=>"); ok {
		return untilSemicolon(rest)
	}
	block, ok := strings.CutPrefix(b, "{")
	if !ok {
		return body
	}
	block = strings.TrimSuffix(block, "}")
	ret := -1
	depth := 0
	for i := 0; i < len(block); i++ {
		switch block[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
		default:
			if depth == 0 && wordAt(block, i, "return") {
				ret = i + len("return")
			}
		}
	}
	if ret < 0 {
		return body
	}
	expr := untilSemicolon(block[ret:])
	if name := strings.TrimSpace(expr); localName.MatchString(name) {
		if init, ok := initializerOf(block, name); ok {
			return init
		}
	}
	return expr
}

// initializerOf is what the top-level declaration or assignment of name
// in block gives it, up to the ; ending it.
func initializerOf(block, name string) (string, bool) {
	depth := 0
	for i := 0; i < len(block); i++ {
		switch block[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
		default:
			if depth != 0 || !wordAt(block, i, name) || i > 0 && block[i-1] == '.' {
				continue
			}
			j := skipSpace(block, i+len(name))
			if j+1 < len(block) && block[j] == '=' && block[j+1] != '=' && block[j+1] != '>' {
				return untilSemicolon(block[j+1:]), true
			}
		}
	}
	return "", false
}

// untilSemicolon is s up to the first ; outside any bracket.
func untilSemicolon(s string) string {
	depth := 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
		case ';':
			if depth == 0 {
				return s[:i]
			}
		}
	}
	return s
}

var namedArg = regexp.MustCompile(`^\s*([A-Za-z_$][\w$]*)\s*:`)

// splitArgs splits the argument list that list starts with, up to the )
// closing it, at its top-level commas.
func splitArgs(list string) []string {
	var out []string
	depth, start := 0, 0
	for i := 0; i < len(list); i++ {
		switch list[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			if depth == 0 {
				return append(out, list[start:i])
			}
			depth--
		case ',':
			if depth == 0 {
				out = append(out, list[start:i])
				start = i + 1
			}
		}
	}
	return append(out, list[start:])
}

// paramNames lists the names a parameter list declares: positional ones,
// then those of its one optional or named section.
func paramNames(list string) []string {
	var out []string
	var cur strings.Builder
	flush := func() {
		p := cur.String()
		cur.Reset()
		if i := strings.IndexByte(p, '='); i >= 0 {
			p = p[:i]
		}
		// An old-style function parameter: int f(int x), nullable or not.
		if q := strings.TrimSuffix(strings.TrimSpace(p), "?"); strings.HasSuffix(q, ")") {
			if open := openingParen(q); open >= 0 {
				p = q[:open]
			}
		}
		if words := identWord.FindAllString(p, -1); len(words) > 0 {
			out = append(out, words[len(words)-1])
		}
	}
	depth := 0
	section := false
	for i := 0; i < len(list); i++ {
		c := list[i]
		switch {
		case depth == 0 && c == ',':
			flush()
			continue
		case depth == 0 && !section && (c == '{' || c == '['):
			flush()
			section = true
			continue
		case depth == 0 && section && (c == '}' || c == ']'):
			flush()
			section = false
			continue
		case strings.IndexByte("({[<", c) >= 0:
			depth++
		case strings.IndexByte(")}]>", c) >= 0:
			depth--
		}
		cur.WriteByte(c)
	}
	flush()
	return out
}
