package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// handDir writes files (paths from lib/src, where client.dart is) into a
// package and answers client.dart's path and the output directory.
func handDir(t *testing.T, files map[string]string) (client, out string) {
	t.Helper()
	src := filepath.Join(t.TempDir(), "lib", "src")
	for rel, body := range files {
		path := filepath.Join(src, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return filepath.Join(src, "client.dart"), filepath.Join(src, "gen")
}

const handSpec = `openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getA
      tags: [a]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/A"}
  /login:
    post:
      operationId: login
      tags: [a]
      responses:
        "204": {description: done}
components:
  schemas:
    A:
      type: object
      properties:
        h: {$ref: "#/components/schemas/H"}
        kind: {type: string, enum: [p, q]}
    H:
      type: object
      properties:
        x: {type: string}
`

const handHints = "hand:\n  H: {covers: [x]}\noperations:\n  login: {hand: true}\n"

// The hand-written package around client.dart: its own names stay its own.
func handFiles() map[string]string {
	return map[string]string{
		"client.dart": `import 'package:dio/dio.dart';

part 'gen/calls.g.dart';

const String _longOperation = 'waxdeck-long-operation';

abstract class _WaxDeckTransport {
  _WaxDeckTransport(this._baseUrl, this._dio)
    : _wire = WireContext(baseUrl: _baseUrl) {
    _dio.options.baseUrl = '$_baseUrl/api/v1';
  }

  final String _baseUrl;
  final Dio _dio;
  final WireContext _wire;

  Future<Response<Object?>> _send(String method, String path) =>
      _dio.request(path, options: Options(method: method));
}

abstract interface class WaxDeckRepository implements WaxDeckApi, MediaUrlsApi {
  String get baseUrl;
}

class WaxDeckClient extends _WaxDeckCalls implements WaxDeckRepository {
  WaxDeckClient._(super.baseUrl, super.dio);

  static const longOperationBudget = Duration(minutes: 30);

  @override
  String get baseUrl => _baseUrl;

  @override
  Future<void> login() async {
    await _login();
  }
}
`,
		"models.dart":             "export 'gen/public.g.dart';\nexport 'hand_models.dart' show H;\n\nclass ExitRequest {}\n",
		"hand_models.dart":        "class H {\n  const H();\n}\n",
		"wire.dart":               "class WireContext {\n  const WireContext({required this.baseUrl});\n\n  final String baseUrl;\n}\n",
		"api/media_urls_api.dart": "abstract interface class MediaUrlsApi {\n  String artUrlFor(String pid);\n}\n",
	}
}

// The generated code shares the hand-written package's names: no raw call
// takes a private name client.dart declares, no generated type a public
// name the package declares, no method a member of the classes it lands
// on, and models.dart exports every hand class.
func TestHandWrittenNamesStayTheirOwn(t *testing.T) {
	get := func(path, id, tag string) string {
		return "  " + path + ":\n    get:\n      operationId: " + id + "\n      tags: [" + tag + "]\n      responses:\n        \"204\": {description: done}\n"
	}
	withPath := func(paths string) string {
		return strings.Replace(handSpec, "components:\n", paths+"components:\n", 1)
	}
	gen := func(t *testing.T, spec, hints string, files map[string]string) error {
		t.Helper()
		client, out := handDir(t, files)
		return run(writeTemp(t, "spec.yaml", spec), writeTemp(t, "hints.yaml", hints), out, client, "", nil)
	}
	if err := gen(t, handSpec, handHints, handFiles()); err != nil {
		t.Fatalf("a package holding to the generated names: %v", err)
	}
	refExit := strings.Replace(handSpec, "        kind: {type: string, enum: [p, q]}\n",
		"        kind: {type: string, enum: [p, q]}\n        exit: {$ref: \"#/components/schemas/ExitRequest\"}\n", 1) +
		"    ExitRequest:\n      type: object\n      properties:\n        path: {type: string}\n"
	unshown := handFiles()
	unshown["models.dart"] = "export 'hand_models.dart' show Other;\n"
	hidden := handFiles()
	hidden["models.dart"] = "export 'hand_models.dart' hide H;\n"
	for _, c := range []struct{ name, spec, hints, want string }{
		{"a raw call taking a transport member", withPath(get("/dio", "dio", "a")), handHints,
			"spec: dio: its raw call _dio would take the name of _WaxDeckTransport._dio, which client.dart declares; rename one of them"},
		{"a raw call taking a transport method", withPath(get("/send", "send", "a")), handHints,
			"spec: send: its raw call _send would take the name of _WaxDeckTransport._send, which client.dart declares; rename one of them"},
		{"a raw call taking a top-level private", withPath(get("/long", "longOperation", "a")), handHints,
			"spec: longOperation: its raw call _longOperation would take the name of _longOperation, which client.dart declares; rename one of them"},
		{"a class taking a hand-written name", refExit, handHints,
			"names: the hand-written class ExitRequest (models.dart) and schema ExitRequest both take the Dart name ExitRequest"},
		{"an enum taking a hand-written name", handSpec, handHints + "enums:\n  A.kind: {as: WireContext}\n",
			"names: the hand-written class WireContext (wire.dart) and enums.A.kind both take the Dart name WireContext"},
		{"an interface taking a hand-written name", withPath(get("/urls", "getUrls", "MediaUrls")), handHints,
			"names: the interface of tag \"MediaUrls\" and the hand-written class MediaUrlsApi (api/media_urls_api.dart) both take the Dart name MediaUrlsApi"},
		{"a method taking a repository member", withPath(get("/base", "getBaseUrl", "a")), handHints + "  getBaseUrl: {as: baseUrl}\n",
			"names: getBaseUrl makes the method baseUrl, which WaxDeckRepository (client.dart) declares; rename it with operations.getBaseUrl.as"},
		{"a method taking an interface member", withPath(get("/art", "artUrlFor", "a")), handHints,
			"names: artUrlFor makes the method artUrlFor, which MediaUrlsApi (api/media_urls_api.dart) declares; rename it with operations.artUrlFor.as"},
		{"a method taking a static member", withPath(get("/budget", "getBudget", "a")), handHints + "  getBudget: {as: longOperationBudget}\n",
			"names: getBudget makes the method longOperationBudget, which WaxDeckClient (client.dart) declares; rename it with operations.getBudget.as"},
	} {
		t.Run(c.name, func(t *testing.T) {
			wantError(t, gen(t, c.spec, c.hints, handFiles()), c.want)
		})
	}
	// The mixins and the aggregate are top-level private names in the
	// client's library.
	for _, c := range []struct{ name, decl, want string }{
		{"a tag's mixin", "\nclass _ACalls {}\n",
			"spec: tag \"a\": its calls mixin _ACalls would take the name of _ACalls, which client.dart declares; rename one of them"},
		{"the aggregate", "\nclass _WaxDeckCalls {}\n",
			"names: the calls aggregate _WaxDeckCalls would take the name of _WaxDeckCalls, which client.dart declares; rename it"},
	} {
		t.Run("a hand declaration taking "+c.name, func(t *testing.T) {
			files := handFiles()
			files["client.dart"] += c.decl
			wantError(t, gen(t, handSpec, handHints, files), c.want)
		})
	}
	// A member of a class is no top-level name.
	member := handFiles()
	member["client.dart"] += "\nclass Other {\n  int _ACalls = 0;\n}\n"
	if err := gen(t, handSpec, handHints, member); err != nil {
		t.Errorf("a class member named like a mixin: %v", err)
	}
	for name, files := range map[string]map[string]string{"left off the show list": unshown, "hidden": hidden} {
		t.Run("a hand class "+name, func(t *testing.T) {
			wantError(t, gen(t, handSpec, handHints, files),
				"hints: hand.H: models.dart does not export H, so app code cannot name it; add it to the show list of its export of hand_models.dart")
		})
	}
}
