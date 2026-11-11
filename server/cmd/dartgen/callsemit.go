// Emission of the operation side's files; calls.go states the rules.
package main

import (
	"fmt"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// The operation side's files beside the per-tag interfaces, relative to
// -out, and the hand-written client the calls file is a part of.
const (
	apiBarrelFile = "api.g.dart"   // every interface, and apiAggregate over them
	callsFile     = "calls.g.dart" // every tag's calls, and callsAggregate over them
	clientFile    = "../client.dart"
)

// The aggregates' names: the interface implementing every tag's, and the
// transport with every tag's calls, which WaxDeckClient extends; and the
// transport's, which client.dart declares.
const (
	apiAggregate   = "WaxDeckApi"
	callsAggregate = "_WaxDeckCalls"
	transportClass = "_WaxDeckTransport"
)

func interfaceFile(stem string) string { return "api/" + stem + "_api.g.dart" }

func mixinName(tag string) string { return "_" + strings.TrimSuffix(apiName(tag), "Api") + "Calls" }

// emit builds every interface, the calls file, and their aggregates.
func (cs *calls) emit() map[string][]byte {
	out := map[string][]byte{}
	if len(cs.tags) == 0 {
		return out
	}
	barrel := newDartFile(apiBarrelFile)
	var apis []string
	for _, tag := range cs.tags {
		api := cs.interfaceDecl(tag)
		out[api.path] = api.bytes()
		barrel.use(api.path)
		barrel.exports = append(barrel.exports, dartExport{uri: api.path})
		apis = append(apis, apiName(tag))
	}
	slices.SortFunc(barrel.exports, func(a, b dartExport) int { return strings.Compare(a.uri, b.uri) })
	slices.Sort(apis)
	barrel.decls = append(barrel.decls, fmt.Sprintf("/// Every interface the API spec's tags make.\nabstract interface class %s implements %s {}\n",
		apiAggregate, strings.Join(apis, ", ")))
	out[barrel.path] = barrel.bytes()
	out[callsFile] = cs.callsDecl()
	return out
}

func (cs *calls) interfaceDecl(tag string) *dartFile {
	f := newDartFile(interfaceFile(fileStem(tag)))
	f.viaBarrel = true
	var b strings.Builder
	if t := cs.m.spec.doc.Tags.Get(tag); t != nil {
		writeLines(&b, docLines(t.Description, ""))
	}
	fmt.Fprintf(&b, "abstract interface class %s {\n", apiName(tag))
	first := true
	for _, c := range cs.byTag[tag] {
		mt := c.method
		if mt == nil {
			continue
		}
		if !first {
			b.WriteString("\n")
		}
		first = false
		writeLines(&b, methodDoc(c))
		fmt.Fprintf(&b, "  Future<%s> %s%s;\n", mt.ret, mt.name, paramList(mt))
		for _, t := range c.signatureTypes() {
			f.useType(t)
		}
		if mt.ret == "Uint8List" || mt.ret == "Uint8List?" {
			f.use("dart:typed_data")
		}
	}
	b.WriteString("}\n")
	f.decls = append(f.decls, b.String())
	return f
}

func methodDoc(c *call) []string {
	text := c.hint.Doc
	if text == "" {
		summary := strings.TrimSpace(c.op.op.Summary)
		if summary != "" && !strings.ContainsAny(summary[len(summary)-1:], ".!?") {
			summary += "."
		}
		text = "`" + c.op.method + " " + c.op.path + "`"
		if summary != "" {
			text += ": " + summary
		}
		if d := strings.TrimSpace(c.op.op.Description); d != "" {
			text += "\n\n" + d
		}
	}
	if n := len(c.hint.NullOn); n > 0 {
		statuses := make([]string, n)
		for i, s := range c.hint.NullOn {
			statuses[i] = strconv.Itoa(s)
		}
		list := statuses[n-1]
		if n > 1 {
			list = strings.Join(statuses[:n-1], ", ") + " or " + list
		}
		text += "\n\nAnswers null where the server answers " + list + "."
	}
	return docLines(text, "  ")
}

// paramList is mt's parenthesized parameter list.
func paramList(mt *method) string {
	var pos, named []string
	for _, p := range mt.positional {
		pos = append(pos, p.typ+" "+p.name)
	}
	for _, p := range mt.named {
		decl := p.typ + " " + p.name
		if p.required {
			decl = "required " + decl
		}
		if p.def != "" {
			decl += " = " + p.def
		}
		named = append(named, decl)
	}
	return paramLayout(pos, named)
}

// callsDecl is the calls file: callsAggregate, then each tag's mixin in
// the order it applies them.
func (cs *calls) callsDecl() []byte {
	tags := slices.SortedFunc(slices.Values(cs.tags), func(a, b string) int {
		return strings.Compare(mixinName(a), mixinName(b))
	})
	var mixins []string
	for _, tag := range tags {
		mixins = append(mixins, mixinName(tag))
	}
	var b strings.Builder
	b.WriteString(header)
	fmt.Fprintf(&b, "\npart of '%s';\n\n", relativeURI(path.Dir(callsFile), clientFile))
	fmt.Fprintf(&b, "/// The transport with every tag's calls.\nabstract class %s = %s with %s;\n",
		callsAggregate, transportClass, strings.Join(mixins, ", "))
	for _, tag := range tags {
		fmt.Fprintf(&b, "\nmixin %s on %s implements %s {\n", mixinName(tag), transportClass, apiName(tag))
		for i, c := range cs.byTag[tag] {
			if i > 0 {
				b.WriteString("\n")
			}
			b.WriteString(cs.rawDecl(c))
			if c.method != nil && !c.hint.Hand {
				b.WriteString("\n")
				b.WriteString(cs.methodDecl(c))
			}
		}
		b.WriteString("}\n")
	}
	return []byte(b.String())
}

func (cs *calls) rawDecl(c *call) string {
	var pos, named []string
	for _, a := range c.path {
		pos = append(pos, a.t.dart()+" "+a.name)
	}
	for _, a := range c.named {
		switch {
		case a.required:
			named = append(named, "required "+a.t.dart()+" "+a.name)
		case a.def != "":
			named = append(named, a.t.dart()+"? "+a.name+" = "+a.def)
		default:
			named = append(named, a.t.dart()+"? "+a.name)
		}
	}
	if b := c.body; b != nil {
		switch {
		case b.binary:
			named = append(named, "required Stream<List<int>> body", "required int length")
		case b.required:
			named = append(named, "required "+b.t.dart()+" body")
		case b.t.kind == kAny:
			named = append(named, "Object? body")
		default:
			named = append(named, b.t.dart()+"? body")
		}
	}
	if c.knobs {
		named = append(named, "CancelToken? cancelToken", "ProgressCallback? onSendProgress",
			"bool Function(int?)? validateStatus", "Map<String, Object?>? extra")
	}
	var args []string
	if q := cs.mapLiteral(c, "query"); q != "" {
		args = append(args, "query: "+q)
	}
	headers := cs.mapEntries(c, "header")
	if b := c.body; b != nil {
		var enc string
		if !b.binary {
			enc = cs.g.write(b.t, "body", 0)
			if sendsText(b.t) {
				enc = "jsonEncode(" + enc + ")"
			}
		}
		switch {
		case b.binary:
			args = append(args, "body: body")
			headers = append(headers, "Headers.contentLengthHeader: '$length'")
		case b.required || isIdentity(b.t) && !sendsText(b.t):
			args = append(args, "body: "+enc)
		default:
			args = append(args, "body: body == null ? null : "+enc)
		}
		args = append(args, "contentType: "+dartString(b.mime))
	}
	if len(headers) > 0 {
		args = append(args, "headers: "+literalMap(headers, "    "))
	}
	switch {
	case c.hint.Long && c.knobs:
		args = append(args, "extra: {_longOperation: true, ...?extra}")
	case c.hint.Long:
		args = append(args, "extra: const {_longOperation: true}")
	case c.knobs:
		args = append(args, "extra: extra")
	}
	if c.knobs {
		args = append(args, "cancelToken: cancelToken", "onSendProgress: onSendProgress", "validateStatus: validateStatus")
	}
	if len(c.accept) > 0 {
		var is []string
		for _, s := range c.accept {
			is = append(is, "status == "+s)
		}
		args = append(args, "validateStatus: (status) => "+strings.Join(is, " || "))
	}
	switch c.result {
	case textResult:
		args = append(args, "responseType: ResponseType.plain")
	case bytesResult:
		args = append(args, "responseType: ResponseType.bytes")
	}
	var b strings.Builder
	fmt.Fprintf(&b, "  Future<Response<Object?>> %s%s => _send(", c.rawName(), paramLayout(pos, named))
	head := []string{dartString(c.op.method), cs.pathExpr(c)}
	if len(args) == 0 {
		fmt.Fprintf(&b, "%s);\n", strings.Join(head, ", "))
		return b.String()
	}
	b.WriteString("\n")
	for _, a := range append(head, args...) {
		fmt.Fprintf(&b, "    %s,\n", a)
	}
	b.WriteString("  );\n")
	return b.String()
}

// sendsText says whether a JSON body of t may encode to a Dart String,
// which Dio sends as the text itself, unquoted, where it encodes any
// other value as JSON.
func sendsText(t *dartType) bool {
	switch t.kind {
	case kString, kEnum, kDateTime, kDate, kBytes, kAny:
		return true
	}
	return false
}

// paramLayout is the parenthesized parameter list of the positional
// and the named declarations given.
func paramLayout(pos, named []string) string {
	if len(pos)+len(named) == 0 {
		return "()"
	}
	var b strings.Builder
	if len(pos) == 0 {
		b.WriteString("({\n")
	} else {
		b.WriteString("(\n")
	}
	for i, p := range pos {
		fmt.Fprintf(&b, "    %s", p)
		if i == len(pos)-1 && len(named) > 0 {
			b.WriteString(", {\n")
		} else {
			b.WriteString(",\n")
		}
	}
	for _, p := range named {
		fmt.Fprintf(&b, "    %s,\n", p)
	}
	if len(named) > 0 {
		b.WriteString("  })")
	} else {
		b.WriteString("  )")
	}
	return b.String()
}

// pathExpr is the request path as a Dart string, each path parameter
// encoded.
func (cs *calls) pathExpr(c *call) string {
	byName := map[string]*rawArg{}
	for _, a := range c.path {
		byName[a.spec] = a
	}
	var b strings.Builder
	b.WriteByte('\'')
	rest := c.op.path
	for {
		loc := pathParam.FindStringSubmatchIndex(rest)
		if loc == nil {
			break
		}
		b.WriteString(stringBody(rest[:loc[0]]))
		a := byName[rest[loc[2]:loc[3]]]
		rest = rest[loc[1]:]
		switch a.t.kind {
		case kInt, kDouble, kBool:
			if rest != "" && isIdentByte(rest[0]) {
				fmt.Fprintf(&b, "${%s}", a.name)
			} else {
				fmt.Fprintf(&b, "$%s", a.name)
			}
		default:
			fmt.Fprintf(&b, "${Uri.encodeComponent(%s)}", cs.g.write(a.t, a.name, 0))
		}
	}
	b.WriteString(stringBody(rest))
	b.WriteByte('\'')
	return b.String()
}

// stringBody is s as the inside of a single-quoted Dart string literal:
// dartString without its own quotes, an escaped one at either edge kept.
func stringBody(s string) string {
	q := dartString(s)
	return q[1 : len(q)-1]
}

// mapEntries is the query or header map's entries, each sent when
// non-null.
func (cs *calls) mapEntries(c *call, in string) []string {
	var out []string
	for _, a := range c.named {
		if a.in != in {
			continue
		}
		k := dartString(a.spec)
		enc := cs.g.write(a.t, a.name, 0)
		switch {
		case a.required:
			out = append(out, k+": "+enc)
		case isIdentity(a.t):
			out = append(out, k+": ?"+a.name)
		case strings.HasPrefix(enc, a.name+"."):
			out = append(out, k+": ?"+a.name+"?"+strings.TrimPrefix(enc, a.name))
		default:
			out = append(out, fmt.Sprintf("if (%s != null) %s: %s", a.name, k, enc))
		}
	}
	return out
}

func (cs *calls) mapLiteral(c *call, in string) string {
	entries := cs.mapEntries(c, in)
	if len(entries) == 0 {
		return ""
	}
	return literalMap(entries, "    ")
}

func literalMap(entries []string, indent string) string {
	return "{\n" + indent + "  " + strings.Join(entries, ",\n"+indent+"  ") + ",\n" + indent + "}"
}

func (cs *calls) methodDecl(c *call) string {
	mt := c.method
	var args []string
	byRaw := map[*rawArg]*methodParam{}
	for _, p := range mt.params {
		if p.raw != nil {
			byRaw[p.raw] = p
		}
	}
	for _, a := range c.path {
		args = append(args, byRaw[a].name)
	}
	if c.body != nil {
		args = append(args, cs.bodyArgs(c)...)
	}
	for _, a := range c.named {
		p := byRaw[a]
		if p == nil || p.omit {
			continue
		}
		v := p.name
		if p.ifTrue {
			v += " ? true : null"
		}
		args = append(args, a.name+": "+v)
	}
	callExpr := c.rawName() + "(" + strings.Join(args, ", ") + ")"
	if len(args) > 0 {
		callExpr = c.rawName() + "(\n      " + strings.Join(args, ",\n      ") + ",\n    )"
	}
	decode := fmt.Sprintf("_decode(%s, %s, %s)", responseVar, dartString(c.op.id), mt.read)
	var b strings.Builder
	fmt.Fprintf(&b, "  @override\n  Future<%s> %s%s => _guard(() async {\n", mt.ret, mt.name, paramList(mt))
	switch {
	case c.result == noContent:
		fmt.Fprintf(&b, "    await %s;\n", callExpr)
	case len(c.hint.NullOn) > 0:
		// Only the request is tried: _decode throws no DioException.
		fmt.Fprintf(&b, "    final Response<Object?> %s;\n    try {\n      %s = await %s;\n", responseVar, responseVar, indentMore(callExpr))
		b.WriteString("    } on DioException catch (e) {\n")
		var statuses []string
		for _, s := range c.hint.NullOn {
			statuses = append(statuses, strconv.Itoa(s))
		}
		if len(statuses) == 1 {
			fmt.Fprintf(&b, "      if (e.response?.statusCode == %s) return null;\n", statuses[0])
		} else {
			fmt.Fprintf(&b, "      if (e.response?.statusCode case %s) return null;\n", strings.Join(statuses, " || "))
		}
		fmt.Fprintf(&b, "      rethrow;\n    }\n    return %s;\n", decode)
	default:
		fmt.Fprintf(&b, "    final %s = await %s;\n    return %s;\n", responseVar, callExpr, decode)
	}
	b.WriteString("  });\n")
	return b.String()
}

func indentMore(s string) string { return strings.ReplaceAll(s, "\n", "\n  ") }

// bodyArgs is what the method passes as the raw call's body.
func (cs *calls) bodyArgs(c *call) []string {
	mt := c.method
	var body *methodParam
	for _, p := range mt.params {
		if p.in == "body" {
			body = p
		}
	}
	switch {
	case mt.flatten != nil:
		var fields []string
		for _, p := range mt.params {
			if p.in != "field" || p.omit {
				continue
			}
			v := p.name
			if p.orElse != "" {
				v += " ?? " + p.orElse
			}
			fields = append(fields, p.field.name+": "+v)
		}
		if len(fields) == 0 {
			return []string{"body: const " + mt.flatten.name + "()"}
		}
		return []string{"body: " + mt.flatten.name + "(\n        " + strings.Join(fields, ",\n        ") + ",\n      )"}
	case mt.stream != nil:
		return []string{"body: " + body.name + "()", "length: " + mt.stream.name}
	case c.body.binary:
		return []string{"body: Stream.value(" + body.name + ")", "length: " + body.name + ".length"}
	}
	return []string{"body: " + body.name}
}

// clientParts checks that client (its source src) takes the calls file,
// the one part the run writes, and no other part from out, and that the
// part names client back.
func clientParts(client, out, src string) error {
	var p problems
	client, err := filepath.Abs(client)
	if err != nil {
		return err
	}
	if out, err = filepath.Abs(out); err != nil {
		return err
	}
	if named := filepath.Join(out, filepath.FromSlash(clientFile)); named != client {
		p.add("client: the calls part says part of %s, not %s", named, client)
	}
	want := filepath.Join(out, callsFile)
	found := false
	for _, m := range partDirective.FindAllStringSubmatch(withoutComments(src), -1) {
		target := filepath.Join(filepath.Dir(client), filepath.FromSlash(m[1]))
		if rel, err := filepath.Rel(out, target); err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			continue
		}
		if target == want {
			found = true
		} else {
			p.add("client: %s has part '%s', which this run does not write", client, m[1])
		}
	}
	if !found {
		rel, err := filepath.Rel(filepath.Dir(client), want)
		if err != nil {
			rel = want
		}
		p.add("client: %s lacks part '%s'", client, filepath.ToSlash(rel))
	}
	return p.err()
}

var partDirective = regexp.MustCompile(`(?m)^\s*part\s+['"]([^'"]+)['"]\s*;`)

// withoutComments is src with its comments blanked and its line breaks
// kept, so a directive written inside one is not read. Dart block
// comments nest; a string literal is skipped whole, so a // or /* inside
// one opens nothing.
func withoutComments(src string) string {
	b := []byte(src)
	for i := 0; i < len(b); {
		switch {
		case b[i] == '/' && i+1 < len(b) && b[i+1] == '/':
			for ; i < len(b) && b[i] != '\n'; i++ {
				b[i] = ' '
			}
		case b[i] == '/' && i+1 < len(b) && b[i+1] == '*':
			i = blankBlockComment(b, i)
		case b[i] == '\'' || b[i] == '"':
			i = skipString(b, i)
		default:
			i++
		}
	}
	return string(b)
}

// blankBlockComment blanks the block comment opening at b[i] and returns
// the index after its close, or len(b) when it never closes.
func blankBlockComment(b []byte, i int) int {
	blank := func(n int) {
		for j := i; j < i+n; j++ {
			if b[j] != '\n' {
				b[j] = ' '
			}
		}
		i += n
	}
	for depth := 0; i < len(b); {
		switch {
		case b[i] == '/' && i+1 < len(b) && b[i+1] == '*':
			depth++
			blank(2)
		case b[i] == '*' && i+1 < len(b) && b[i+1] == '/':
			depth--
			blank(2)
			if depth == 0 {
				return i
			}
		default:
			blank(1)
		}
	}
	return i
}

// skipString returns the index after the string literal opening at b[i]:
// a raw one (r'...') has no escapes or interpolations, a triple-quoted
// one may span lines, any other ends at its closing quote or its line.
// An interpolation's ${...} is code, so a quote inside it ends nothing.
func skipString(b []byte, i int) int {
	q := b[i]
	raw := i > 0 && b[i-1] == 'r' && (i == 1 || !isIdentByte(b[i-2]))
	triple := i+2 < len(b) && b[i+1] == q && b[i+2] == q
	if triple {
		i += 3
	} else {
		i++
	}
	for i < len(b) {
		switch {
		case b[i] == '\\' && !raw:
			i += 2
		case b[i] == '$' && !raw && i+1 < len(b) && b[i+1] == '{':
			i = skipInterpolation(b, i+2)
		case b[i] == q && !triple:
			return i + 1
		case b[i] == q && i+2 < len(b) && b[i+1] == q && b[i+2] == q:
			return i + 3
		case b[i] == '\n' && !triple:
			return i
		default:
			i++
		}
	}
	return len(b)
}

// skipInterpolation returns the index after the } closing an
// interpolation whose code starts at b[i]; its braces nest, and its
// string literals are skipped whole.
func skipInterpolation(b []byte, i int) int {
	for depth := 1; i < len(b); {
		switch b[i] {
		case '\'', '"':
			i = skipString(b, i)
			continue
		case '{':
			depth++
		case '}':
			if depth--; depth == 0 {
				return i + 1
			}
		}
		i++
	}
	return len(b)
}

func isIdentByte(c byte) bool {
	return c == '_' || c == '$' || c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
}
