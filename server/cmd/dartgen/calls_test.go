package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fixtureModels is what the fixture needs for the model to build, so the
// operation checks after it run.
const fixtureModels = "models:\n  Error: {as: ApiError}\n"

func TestOperationHintErrorsNameTheKey(t *testing.T) {
	cases := []struct {
		name, hints string
		want        []string
	}{
		{"unknown param hint key", "operations:\n  getShelf:\n    params:\n      limit: {bogus: 1}\n", []string{"field bogus not found"}},
		{"unknown param", "operations:\n  getShelf:\n    params:\n      nope: {as: x}\n", []string{"operations.getShelf.params.nope: getShelf has no parameter or body field nope"}},
		{"param as a reserved word", "operations:\n  getShelf:\n    params:\n      limit: {as: in}\n", []string{"operations.getShelf.params.limit.as: in is a Dart reserved word"}},
		{"method as a reserved word", "operations:\n  getShelf: {as: class}\n", []string{"operations.getShelf.as: class is a Dart reserved word"}},
		{"omit a path parameter", "operations:\n  getShelf:\n    params:\n      key: {omit: true}\n", []string{"operations.getShelf.params.key.omit: a path parameter is always sent"}},
		{"omit a required field", "operations:\n  putSchedule:\n    params:\n      cron: {omit: true}\n", []string{"operations.putSchedule.params.cron.omit: cron is required"}},
		{"default on a required field", "operations:\n  putSchedule:\n    params:\n      cron: {default: x}\n", []string{"operations.putSchedule.params.cron.default: cron is required, so no default applies"}},
		{"default of the wrong type", "operations:\n  getShelf:\n    params:\n      limit: {default: lots}\n", []string{"operations.getShelf.params.limit.default: lots is not a int"}},
		{"an empty list spelled as Dart", "operations:\n  markRead:\n    params:\n      removeTags:\n        default: const <String>[]\n", []string{"operations.markRead.params.removeTags.default: const <String>[] is not a List<String>; write [] for an empty list, {} for an empty map"}},
		{"default and nullable", "operations:\n  createTarget:\n    params:\n      muted: {default: true, nullable: true}\n", []string{"operations.createTarget.params.muted.default: nullable takes no default"}},
		{"nullable with nothing to send", "operations:\n  createTarget:\n    params:\n      kind: {nullable: true}\n", []string{"operations.createTarget.params.kind.nullable: a null kind has no default to send in its place"}},
		{"nullable already", "operations:\n  getShelf:\n    params:\n      limit: {nullable: true}\n", []string{"operations.getShelf.params.limit.nullable: limit is nullable already"}},
		{"omitFalse on an int", "operations:\n  getShelf:\n    params:\n      limit: {omitFalse: true}\n", []string{"operations.getShelf.params.limit.omitFalse: needs a bool, and limit is int?"}},
		{"omitFalse on a body field", "operations:\n  createTarget:\n    params:\n      muted: {omitFalse: true}\n", []string{"operations.createTarget.params.muted.omitFalse: applies to a query or header parameter, and muted is a body field"}},
		{"omitFalse with a default", "operations:\n  searchLibraries:\n    params:\n      exact: {omitFalse: true, default: true}\n", []string{"operations.searchLibraries.params.exact.omitFalse: implies the default false; drop default"}},
		{"type on a generated method", "operations:\n  getShelf:\n    params:\n      limit: {type: String}\n", []string{"operations.getShelf.params.limit.type: only a hand operation's parameter takes a type"}},
		{"type unknown", "operations:\n  createTimeline:\n    hand: true\n    params:\n      mode: {type: Nope}\n", []string{"operations.createTimeline.params.mode.type: Nope is neither a dart:core value type nor a generated or hand class or enum"}},
		{"object default its class cannot build bare", "operations:\n  createTimeline:\n    hand: true\n    params:\n      mode: {type: ArtSource, default: {}}\n", []string{"operations.createTimeline.params.mode.default: ArtSource requires provider, so {} cannot build it"}},
		{"body without a request body", "operations:\n  getShelf: {body: x}\n", []string{"operations.getShelf.body: getShelf has no request body"}},
		{"body as a reserved word", "operations:\n  putSchedule: {body: class}\n", []string{"operations.putSchedule.body: class is a Dart reserved word"}},
		{"length on a JSON body", "operations:\n  putSchedule: {length: size}\n", []string{"operations.putSchedule.length: the body is not binary"}},
		{"length without a request body", "operations:\n  getShelf: {length: size}\n", []string{"operations.getShelf.length: getShelf has no request body"}},
		{"unwrap an unknown property", "operations:\n  getArtwork: {unwrap: nope}\n", []string{"operations.getArtwork.unwrap: Artwork has no property nope"}},
		{"unwrap no class", "operations:\n  exportNotes: {unwrap: x}\n", []string{"operations.exportNotes.unwrap: exportNotes answers no generated class to unwrap"}},
		{"named misses one", "operations:\n  searchLibraries:\n    named: [sort]\n", []string{"operations.searchLibraries.named: exact is missing; named lists every named parameter"}},
		{"named lists a positional", "operations:\n  getShelf:\n    named: [key, limit]\n", []string{"operations.getShelf.named: key is not a named parameter"}},
		{"named lists an unknown", "operations:\n  getShelf:\n    named: [limit, nope]\n", []string{"operations.getShelf.named: nope is not a parameter of getShelf"}},
		{"named lists twice", "operations:\n  getShelf:\n    named: [limit, limit]\n", []string{"operations.getShelf.named: limit is listed twice"}},
		{"positional lists twice", "operations:\n  getShelf:\n    positional: [key, key]\n", []string{"operations.getShelf.positional: key is listed twice"}},
		{"positional omitted", "operations:\n  getShelf:\n    positional: [key, limit]\n    params:\n      limit: {omit: true}\n", []string{"operations.getShelf.positional: limit is omitted"}},
		{"positional with a hinted default", "operations:\n  getShelf:\n    positional: [key, limit]\n    params:\n      limit: {default: 5}\n", []string{"operations.getShelf.positional: limit has a default, which a positional parameter cannot take"}},
		{"doc is blank", "operations:\n  getShelf: {doc: \"  \"}\n", []string{"operations.getShelf.doc: the text is blank"}},
		{"skip with a doc", "operations:\n  getArtwork: {skip: true, doc: x}\n", []string{"operations.getArtwork.doc: skip makes no method for it to shape"}},
		{"raw with a doc", "operations:\n  getArtwork: {raw: true, doc: x}\n", []string{"operations.getArtwork.doc: raw makes no method for it to shape"}},
		{"skip with another key", "operations:\n  getArtwork: {skip: true, long: true}\n", []string{"operations.getArtwork.long: skip makes no method for it to shape"}},
		{"raw with another key", "operations:\n  getArtwork: {raw: true, unwrap: url}\n", []string{"operations.getArtwork.unwrap: raw makes no method for it to shape"}},
		{"nullOn on no content", "operations:\n  bulkEdit: {nullOn: [404]}\n", []string{"operations.bulkEdit.nullOn: bulkEdit answers nothing to give null in place of"}},
		{"two methods, one name", "operations:\n  getArtwork: {as: getItem}\n", []string{"names: getItem and getArtwork both make the method getItem"}},
		{"two interfaces, one method name", "operations:\n  getEpisode: {as: getItem}\n", []string{"names: getItem and getEpisode both make the method getItem"}},
		{"two parameters, one name", "operations:\n  getShelf:\n    params:\n      limit: {as: key}\n", []string{"names: getShelf: key and limit both take the parameter name key; rename one with operations.getShelf.params.<name>.as"}},
		{"a parameter takes the answer's name", "operations:\n  getShelf:\n    params:\n      limit: {as: response}\n", []string{"names: getShelf: the parameter limit takes the name response, which its method's answer uses"}},
		{"an enum on a $ref parameter", "enums:\n  searchLibraries.mediaType: {}\n", []string{"enums.searchLibraries.mediaType: searchLibraries.mediaType is a $ref to MediaType; list MediaType itself"}},
		{"an enum on a parameter without one", "enums:\n  searchLibraries.q: {}\n", []string{"enums.searchLibraries.q: searchLibraries.q carries no inline enum"}},
		{"an enum on an unknown parameter", "enums:\n  searchLibraries.nope: {}\n", []string{"enums.searchLibraries.nope: searchLibraries has no parameter nope"}},
		{"a parameter enum that drops", "enums:\n  searchLibraries.sort: {fallback: drop}\n", []string{"enums.searchLibraries.sort: fallback drop acts on lists, and searchLibraries.sort is a parameter"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := generate(fixtureSpec, writeTemp(t, "hints.yaml", fixtureModels+c.hints), "")
			if err == nil {
				t.Fatal("generate succeeded")
			}
			for _, want := range c.want {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("error does not name %q:\n%v", want, err)
				}
			}
		})
	}
}

const opSpecHead = `openapi: 3.0.3
info: {title: t, version: "1"}
paths:
`

const opSpecTail = `components:
  schemas:
    A:
      type: object
      properties:
        x: {type: string}
    B:
      type: object
      properties:
        y: {type: integer}
`

func TestOperationSpecErrorsNameTheOperation(t *testing.T) {
	ok := "      responses:\n        \"204\": {description: done}\n"
	cases := []struct{ name, paths, want string }{
		{"two answer types by a status range", `  /a:
    get:
      operationId: getA
      tags: [a]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/A"}
        "2XX":
          description: later
          content:
            application/json:
              schema: {$ref: "#/components/schemas/B"}
`, "spec: getA answers 2xx statuses of different types, and the status range 2XX cannot say which to accept"},
		{"cookie parameter", "  /a:\n    get:\n      operationId: getA\n      tags: [a]\n      parameters:\n        - {name: c, in: cookie, schema: {type: string}}\n" + ok,
			"spec: getA: the cookie parameter c has no mapping"},
		{"array query parameter", "  /a:\n    get:\n      operationId: getA\n      tags: [a]\n      parameters:\n        - {name: ids, in: query, schema: {type: array, items: {type: string}}}\n" + ok,
			"spec: getA.ids: a List<String> parameter has no query encoding; carry it in a JSON body or as one delimited string, or skip the operation with operations.getA.skip"},
		{"parameter name a reserved word", "  /a:\n    get:\n      operationId: getA\n      tags: [a]\n      parameters:\n        - {name: in, in: query, schema: {type: string}}\n" + ok,
			"spec: getA: the parameter name in makes in, which is a Dart reserved word"},
		{"raw call names clash", "  /a:\n    post:\n      operationId: postA\n      tags: [a]\n      parameters:\n        - {name: body, in: query, schema: {type: string}}\n      requestBody:\n        required: true\n        content:\n          application/json:\n            schema: {$ref: \"#/components/schemas/A\"}\n" + ok,
			"spec: postA: two parameters of its raw call take the name body"},
		{"text body", "  /a:\n    post:\n      operationId: postA\n      tags: [a]\n      requestBody:\n        required: true\n        content:\n          text/plain:\n            schema: {type: string}\n" + ok,
			"spec: postA request body: a text/plain body is neither JSON nor format binary, and has no mapping"},
		{"optional binary body", "  /a:\n    post:\n      operationId: postA\n      tags: [a]\n      requestBody:\n        content:\n          application/octet-stream:\n            schema: {type: string, format: binary}\n" + ok,
			"spec: postA request body: an optional binary body has no mapping"},
		{"operationId no identifier", "  /a:\n    get:\n      operationId: get-a\n      tags: [a]\n" + ok,
			"spec: get-a: the operationId makes no Dart name for its raw call"},
		{"two tags, one interface", "  /a:\n    get:\n      operationId: getA\n      tags: [AB]\n" + ok + "  /b:\n    get:\n      operationId: getB\n      tags: [a-b]\n" + ok,
			"spec: tags \"AB\" and \"a-b\" both make the interface ABApi"},
		{"operationId a reserved word", "  /a:\n    get:\n      operationId: default\n      tags: [a]\n" + ok,
			"spec: default: the operationId is a Dart reserved word; rename the method with operations.default.as"},
		{"interface named like the aggregate", "  /a:\n    get:\n      operationId: getA\n      tags: [WaxDeck]\n" + ok,
			"spec: tag \"WaxDeck\" makes the interface WaxDeckApi, which is a type the generated code uses"},
		{"interface named like a model", "  /a:\n    get:\n      operationId: getA\n      tags: [b]\n      responses:\n        \"200\":\n          description: ok\n          content:\n            application/json:\n              schema: {$ref: \"#/components/schemas/BApi\"}\n",
			"names: the interface of tag \"b\" and a model type both take the Dart name BApi"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			tail := opSpecTail
			if strings.Contains(c.paths, "BApi") {
				tail += "    BApi:\n      type: object\n      properties:\n        z: {type: string}\n"
			}
			_, err := generate(writeTemp(t, "spec.yaml", opSpecHead+c.paths+tail), writeTemp(t, "hints.yaml", ""), "")
			if err == nil {
				t.Fatal("generate succeeded")
			}
			if !strings.Contains(err.Error(), c.want) {
				t.Errorf("error does not name %q:\n%v", c.want, err)
			}
		})
	}
	// Each operation answering such a list is named, whatever its
	// operationId spells.
	t.Run("a top-level list whose elements drop", func(t *testing.T) {
		list := func(path, id, items string) string {
			return "  " + path + ":\n    get:\n      operationId: " + id + "\n      tags: [a]\n      responses:\n        \"200\":\n          description: ok\n" +
				"          content:\n            application/json:\n              schema:\n                type: array\n                items: " + items + "\n"
		}
		paths := list("/a", "listA", `{$ref: "#/components/schemas/K"}`) + list("/b", "listB", `{$ref: "#/components/schemas/K"}`) +
			list("/c", "listNested", `{type: array, items: {$ref: "#/components/schemas/K"}}`) +
			list("/d", "listKinds", `{$ref: "#/components/schemas/Kind"}`) + list("/e", "list_known_a", `{$ref: "#/components/schemas/A"}`)
		tail := opSpecTail + "    K:\n      type: object\n      properties:\n        kind: {type: string, enum: [p, q]}\n" +
			"    Kind:\n      type: string\n      enum: [p, q]\n"
		_, err := generate(writeTemp(t, "spec.yaml", opSpecHead+paths+tail), writeTemp(t, "hints.yaml", "enums:\n  K.kind: {fallback: drop}\n  Kind: {fallback: drop}\n"), "")
		for _, id := range []string{"listA", "listB", "listNested", "listKinds"} {
			wantError(t, err, "spec: "+id+" answers a top-level list whose elements drop, which only a class's field can decode; wrap it in an object")
		}
		if err != nil && strings.Contains(err.Error(), "list_known_a") {
			t.Errorf("a list of A, which drops nothing, is named:\n%v", err)
		}
	})
}

// A generated call reads its answer whole, so an event stream reaches its
// caller only once it ends: such an operation is skipped or written by
// hand.
func TestEventStreamsAreSkippedOrHand(t *testing.T) {
	paths := `  /events:
    get:
      operationId: streamEvents
      tags: [a]
      responses:
        "200":
          description: The events as they happen.
          content:
            text/event-stream:
              schema: {type: string}
`
	spec := writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail)
	const want = "spec: streamEvents answers text/event-stream, which a generated call reads whole once the stream ends; skip it with operations.streamEvents.skip, or write it by hand with operations.streamEvents.hand"
	for _, hints := range []string{"", "operations:\n  streamEvents: {raw: true}\n"} {
		_, err := generate(spec, writeTemp(t, "hints.yaml", hints), "")
		wantError(t, err, want)
	}
	for _, hints := range []string{"operations:\n  streamEvents: {skip: true}\n", "operations:\n  streamEvents: {hand: true}\n"} {
		if _, err := generate(spec, writeTemp(t, "hints.yaml", hints), ""); err != nil {
			t.Errorf("%q: %v", hints, err)
		}
	}
}

// nullOn names statuses the operation declares, exactly or by their
// range; a default answer declares none.
func TestNullOnNamesDeclaredStatuses(t *testing.T) {
	paths := `  /a:
    get:
      operationId: getA
      tags: [a]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/A"}
        "404": {description: none}
        "5XX": {description: down}
        default: {description: anything else}
`
	spec := writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail)
	if _, err := generate(spec, writeTemp(t, "hints.yaml", "operations:\n  getA: {nullOn: [404, 503]}\n"), ""); err != nil {
		t.Errorf("declared statuses: %v", err)
	}
	_, err := generate(spec, writeTemp(t, "hints.yaml", "operations:\n  getA: {nullOn: [404, 410]}\n"), "")
	wantError(t, err, "hints: operations.getA.nullOn: getA declares no 410 answer")
}

// The goldens pin what each mode leaves: skip nothing, raw the raw call
// alone, hand the interface method and the raw call but no override.
func TestModesShapeTheOutput(t *testing.T) {
	files := generateFixture(t)
	has := func(rel, s string) bool { return strings.Contains(string(files[rel]), s) }
	for _, c := range []struct {
		rel, text string
		want      bool
	}{
		{"calls.g.dart", "_setRating", false},
		{"api/users_api.g.dart", "setRating", false},
		{"calls.g.dart", "Future<Response<Object?>> _getRule(\n    String pid, {\n    CancelToken? cancelToken,", true},
		{"api/playlists_api.g.dart", "getRule", false},
		{"api/playback_api.g.dart", "Future<SessionPage> listSessions();", true},
		{"calls.g.dart", "Future<Response<Object?>> _listSessions(", true},
		{"calls.g.dart", "Future<SessionPage> listSessions()", false},
		{"calls.g.dart", "validateStatus: validateStatus,", true},
		{"calls.g.dart", "validateStatus: (status) => status == 201,", true},
		{"api/playback_api.g.dart", "Future<Schedule> previewTimeline();", true},
	} {
		if has(c.rel, c.text) != c.want {
			t.Errorf("%s: containing %q is %v, want %v", c.rel, c.text, !c.want, c.want)
		}
	}
}

// doc replaces the whole generated comment, the VERB /path line
// included, on a generated and on a hand method alike.
func TestDocHintReplacesTheGeneratedComment(t *testing.T) {
	files := generateFixture(t)
	api := string(files["api/playback_api.g.dart"])
	want := "  /// `GET /sessions` or `GET /sessions/active`: every session, or only the live\n" +
		"  /// ones.\n  ///\n" +
		"  /// Which of the two is asked for is the hand method's call.\n" +
		"  Future<SessionPage> listSessions();"
	if !strings.Contains(api, want) {
		t.Errorf("playback_api lacks the hinted doc:\n%s", api)
	}
	if strings.Contains(api, "`GET /sessions`:") {
		t.Errorf("the generated doc line survives the hint:\n%s", api)
	}

	paths := `  /a:
    get:
      operationId: getA
      tags: [a]
      summary: Reads A
      description: Longer words.
      responses:
        "204": {description: done}
`
	hints := writeTemp(t, "hints.yaml", "operations:\n  getA:\n    doc: Reads A or B.\n")
	got, err := generate(writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail), hints, "")
	if err != nil {
		t.Fatal(err)
	}
	if a := string(got["api/a_api.g.dart"]); !strings.Contains(a, "  /// Reads A or B.\n  Future<void> getA();") ||
		strings.Contains(a, "Reads A.") || strings.Contains(a, "Longer words") || strings.Contains(a, "GET /a") {
		t.Errorf("a generated method keeps part of its own doc:\n%s", a)
	}
}

// A nullOn method's doc says which statuses answer null, a hinted doc's
// too.
func TestNullOnIsDocumented(t *testing.T) {
	paths := `  /a:
    get:
      operationId: getA
      tags: [a]
      summary: Reads A
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/A"}
        "404": {description: none}
  /b:
    get:
      operationId: getB
      tags: [a]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/B"}
        "4XX": {description: refused}
`
	hints := "operations:\n  getA: {nullOn: [404]}\n  getB: {nullOn: [404, 409, 410], doc: Reads B.}\n"
	files, err := generate(writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail), writeTemp(t, "hints.yaml", hints), "")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, string(files["api/a_api.g.dart"]),
		"  /// `GET /a`: Reads A.\n  ///\n  /// Answers null where the server answers 404.\n  Future<A?> getA();\n",
		"  /// Reads B.\n  ///\n  /// Answers null where the server answers 404, 409 or 410.\n  Future<B?> getB();\n")
}

func TestOperationShapesFromMiniSpecs(t *testing.T) {
	scoped := `  /a:
    post:
      operationId: postA
      tags: [a]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/S"}
      responses:
        "204": {description: done}
`
	scope := "    S:\n      type: object\n      properties:\n        scope: {type: string, enum: [mine, all], default: mine}\n"
	count := "    S:\n      type: object\n      required: [n]\n      properties:\n        n: {type: integer}\n"
	nested := "    S:\n      type: object\n      properties:\n        p: {$ref: \"#/components/schemas/A\"}\n"
	folded := `  /a:
    get:
      operationId: getA
      tags: [a]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/F"}
`
	fold := func(required, nullable string) string {
		return "    F:\n      allOf:\n        - $ref: \"#/components/schemas/A\"\n        - type: object\n" + required +
			"          properties:\n            n: {type: integer" + nullable + "}\n"
	}
	unwrapFolded := "models:\n  F: {as: A}\noperations:\n  getA: {unwrap: n}\n"
	single := strings.Replace(folded, "schemas/F", "schemas/A", 1)
	type check struct{ file, want string }
	cases := []struct {
		name, paths, schemas, hints, file, want string
		more                                    []check
	}{
		{"a required field with a hint default is optional", scoped, count,
			"models:\n  S:\n    fields:\n      n: {default: 0}\n",
			"api/a_api.g.dart", "Future<void> postA({\n    int n = 0,\n  });",
			[]check{
				{"calls.g.dart", "Future<void> postA({\n    int n = 0,\n  }) => _guard("},
				{"calls.g.dart", "body: S(\n        n: n,\n      ),"},
			}},
		{"an object default is its class built bare", scoped, nested,
			"operations:\n  postA:\n    params:\n      p: {default: {}}\n",
			"api/a_api.g.dart", "Future<void> postA({\n    A p = const A(),\n  });",
			[]check{
				{"calls.g.dart", "Future<void> postA({\n    A p = const A(),\n  }) => _guard("},
				{"calls.g.dart", "body: S(\n        p: p,\n      ),"},
			}},
		{"a type hint drops the model default", scoped, scope,
			"operations:\n  postA:\n    hand: true\n    params:\n      scope: {as: all, type: bool}\n",
			"api/a_api.g.dart", "Future<void> postA({\n    bool? all,\n  });", nil},
		{"a type hint takes a default of its own", scoped, scope,
			"operations:\n  postA:\n    hand: true\n    params:\n      scope: {as: all, type: bool, default: false}\n",
			"api/a_api.g.dart", "Future<void> postA({\n    bool all = false,\n  });", nil},
		{"a 2xx without content is a type of its own", `  /a:
    get:
      operationId: getA
      tags: [a]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/A"}
        "204": {description: nothing}
`, "", "", "calls.g.dart", "validateStatus: (status) => status == 200,", nil},
		{"a folded schema's required property is answered non-null", folded, fold("          required: [n]\n", ""),
			unwrapFolded, "api/a_api.g.dart", "Future<int> getA();",
			[]check{{"calls.g.dart", "(v, at) => decodeA(wireObject(v, at), _wire).n ?? (throw const FormatException('A.n: missing')));"}}},
		{"a folded schema's optional property stays nullable", folded, fold("", ""),
			unwrapFolded, "api/a_api.g.dart", "Future<int?> getA();", nil},
		{"a folded schema's required nullable property stays nullable", folded, fold("          required: [n]\n", ", nullable: true"),
			unwrapFolded, "api/a_api.g.dart", "Future<int?> getA();", nil},
		// So a property added to it changes no signature.
		{"a one-property response is answered whole", single, "", "",
			"api/a_api.g.dart", "Future<A> getA();", []check{{"calls.g.dart", "return _decode(response, 'getA', (v, at) => decodeA(wireObject(v, at), _wire));"}}},
		{"unwrap answers its property", single, "", "operations:\n  getA: {unwrap: x}\n",
			"api/a_api.g.dart", "Future<String?> getA();", []check{{"calls.g.dart", "return _decode(response, 'getA', (v, at) => decodeA(wireObject(v, at), _wire).x);"}}},
		{"an origin-relative URL answer arrives resolved", strings.Replace(single, `{$ref: "#/components/schemas/A"}`, "{type: string, format: uri-reference}", 1), "", "",
			"api/a_api.g.dart", "Future<String> getA();", []check{{"calls.g.dart", "return _decode(response, 'getA', (v, at) => resolveMediaUrl(_wire.baseUrl, wireString(v, at)));"}}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			files, err := generate(writeTemp(t, "spec.yaml", opSpecHead+c.paths+opSpecTail+c.schemas), writeTemp(t, "hints.yaml", c.hints), "")
			if err != nil {
				t.Fatal(err)
			}
			for _, k := range append([]check{{c.file, c.want}}, c.more...) {
				if got := string(files[k.file]); !strings.Contains(got, k.want) {
					t.Errorf("%s lacks %q:\n%s", k.file, k.want, got)
				}
			}
		})
	}
}

// A parameter's hint default restates the spec's, where the spec gives
// one; a type hint's default is its own.
func TestParamDefaultsAgreeWithTheSpec(t *testing.T) {
	paths := `  /a:
    post:
      operationId: postA
      tags: [a]
      parameters:
        - {name: n, in: query, schema: {type: integer, default: 5}}
        - {name: mode, in: query, schema: {type: string, default: fast}}
        - {name: strict, in: query, schema: {type: boolean, default: true}}
        - {name: loose, in: query, schema: {type: boolean, default: false}}
        - {name: role, in: query, schema: {$ref: "#/components/schemas/Role"}}
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/S"}
      responses:
        "204": {description: done}
`
	schemas := `    S:
      type: object
      properties:
        m: {type: integer, default: 1}
        tags:
          type: array
          default: []
          items: {type: string}
        free: {type: integer}
    Role:
      type: string
      enum: [front, back]
      default: front
`
	gen := func(t *testing.T, params string) error {
		t.Helper()
		_, err := generate(writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail+schemas), writeTemp(t, "hints.yaml", "operations:\n  postA:\n"+params), "")
		return err
	}
	if err := gen(t, "    params:\n      n: {default: 5}\n      mode: {default: fast}\n      m: {default: 1}\n"+
		"      tags: {default: []}\n      free: {default: 3}\n      loose: {omitFalse: true}\n      role: {default: front}\n"); err != nil {
		t.Errorf("defaults equal to the spec's: %v", err)
	}
	if err := gen(t, "    hand: true\n    params:\n      mode: {type: bool, default: false}\n"); err != nil {
		t.Errorf("a type hint's default: %v", err)
	}
	for _, c := range []struct{ name, param, want string }{
		{"a query parameter", "n: {default: 6}", "hints: operations.postA.params.n.default: 6 differs from the spec's default, 5"},
		{"a string query parameter", "mode: {default: slow}", "hints: operations.postA.params.mode.default: 'slow' differs from the spec's default, 'fast'"},
		{"a $ref'd parameter, whose default is its target's", "role: {default: back}", "hints: operations.postA.params.role.default: 'back' differs from the spec's default, 'front'"},
		{"a body field", "m: {default: 2}", "hints: operations.postA.params.m.default: 2 differs from the spec's default, 1"},
		{"a list body field", "tags: {default: [x]}", "hints: operations.postA.params.tags.default: const ['x'] differs from the spec's default, const []"},
		{"omitFalse over a true default", "strict: {omitFalse: true}", "hints: operations.postA.params.strict.omitFalse: implies the default false, and the spec's is true"},
	} {
		t.Run(c.name, func(t *testing.T) {
			wantError(t, gen(t, "    params:\n      "+c.param+"\n"), c.want)
		})
	}
}

// A parameter's schema wrapping a $ref in allOf, to describe it, takes
// its own default, and its target's only when it states none.
func TestWrappedParameterTakesItsOwnDefault(t *testing.T) {
	paths := `  /a:
    get:
      operationId: getA
      tags: [a]
      parameters:
        - name: role
          in: query
          schema:
            allOf: [{$ref: "#/components/schemas/Role"}]
            description: Which art.
            default: back
        - name: plain
          in: query
          schema:
            allOf: [{$ref: "#/components/schemas/Role"}]
            description: Which other art.
      responses:
        "204": {description: done}
`
	spec := writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail+"    Role:\n      type: string\n      enum: [front, back]\n      default: front\n")
	files, err := generate(spec, writeTemp(t, "hints.yaml", ""), "")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, string(files[callsFile]), "    String? role = 'back',\n", "    String? plain = 'front',\n")
	_, err = generate(spec, writeTemp(t, "hints.yaml", "operations:\n  getA:\n    params:\n      role: {default: front}\n"), "")
	wantError(t, err, "hints: operations.getA.params.role.default: 'front' differs from the spec's default, 'back'")
}

// A body field sharing a parameter's name fails the run rather than
// changing the method's shape; body takes the body whole.
func TestClashingBodyFieldFailsTheRun(t *testing.T) {
	paths := `  /a/{y}:
    post:
      operationId: postA
      tags: [a]
      parameters:
        - {name: y, in: path, required: true, schema: {type: string}}
        - {name: x, in: query, schema: {type: string}}
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/AB"}
      responses:
        "204": {description: done}
`
	spec := writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail+
		"    AB:\n      type: object\n      properties:\n        x: {type: string}\n        y: {type: string}\n")
	_, err := generate(spec, writeTemp(t, "hints.yaml", ""), "")
	wantError(t, err, "spec: postA: the query parameter x and the body field x share a name; take the body whole with operations.postA.body, or rename one in the spec")
	wantError(t, err, "spec: postA: the path parameter y and the body field y share a name; take the body whole with operations.postA.body, or rename one in the spec")
	files, err := generate(spec, writeTemp(t, "hints.yaml", "operations:\n  postA: {body: body}\n"), "")
	if err != nil {
		t.Fatal(err)
	}
	if api := string(files["api/a_api.g.dart"]); !strings.Contains(api, "Future<void> postA(\n    String y, {\n    required AB body,\n    String? x,\n  });") {
		t.Errorf("body did not take the body whole:\n%s", api)
	}
}

// Dio sends a String body as the text itself, so a JSON body whose value
// is a string goes as its JSON encoding; an object or number Dio encodes.
func TestJSONTextBodiesAreEncoded(t *testing.T) {
	put := func(path, id, required, schema string) string {
		return "  " + path + ":\n    put:\n      operationId: " + id + "\n      tags: [a]\n      requestBody:\n" + required +
			"        content:\n          application/json:\n            schema: " + schema + "\n" +
			"      responses:\n        \"204\": {description: done}\n"
	}
	const req = "        required: true\n"
	paths := put("/s", "putString", req, "{type: string}") +
		put("/e", "putKind", req, `{$ref: "#/components/schemas/Kind"}`) +
		put("/u", "putUnlisted", req, `{$ref: "#/components/schemas/Unlisted"}`) +
		put("/t", "putTime", req, "{type: string, format: date-time}") +
		put("/o", "putMaybe", "", "{type: string}") +
		put("/x", "putAny", req, "{}") +
		put("/n", "putCount", req, "{type: integer}") +
		put("/m", "putA", req, `{$ref: "#/components/schemas/A"}`)
	schemas := "    Kind:\n      type: string\n      enum: [up, down]\n    Unlisted:\n      type: string\n      enum: [p, q]\n"
	files, err := generate(writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail+schemas), writeTemp(t, "hints.yaml", "enums:\n  Kind: {}\n"), "")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, string(files[callsFile]),
		"'/s',\n    body: jsonEncode(body),\n",
		"'/e',\n    body: jsonEncode(body.wireName),\n",
		"'/u',\n    body: jsonEncode(body),\n",
		"'/t',\n    body: jsonEncode(body.toUtc().toIso8601String()),\n",
		"'/o',\n    body: body == null ? null : jsonEncode(body),\n",
		"'/x',\n    body: jsonEncode(body),\n",
		"'/n',\n    body: body,\n",
		"'/m',\n    body: encodeA(body),\n")
}

// A quote at either edge of a path's literal text stays escaped, so it
// neither escapes the interpolation after it nor the closing quote.
func TestPathLiteralsKeepTheirQuotes(t *testing.T) {
	get := func(path, id, params string) string {
		return "  " + path + ":\n    get:\n      operationId: " + id + "\n      tags: [a]\n" + params +
			"      responses:\n        \"204\": {description: done}\n"
	}
	param := func(name, typ string) string {
		return "      parameters:\n        - {name: " + name + ", in: path, required: true, schema: {type: " + typ + "}}\n"
	}
	paths := get(`"/a'{id}"`, "getA", param("id", "string")) +
		get(`"/x'"`, "getX", "") +
		get(`"/n'{n}"`, "getN", param("n", "integer")) +
		get(`"/y/{id}/'"`, "getY", param("id", "string")) +
		get(`"/z/'$"`, "getZ", "")
	files, err := generate(writeTemp(t, "spec.yaml", opSpecHead+paths+opSpecTail), writeTemp(t, "hints.yaml", ""), "")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, string(files[callsFile]),
		`_send('GET', '/a\'${Uri.encodeComponent(id)}');`,
		`_send('GET', '/x\'');`,
		`_send('GET', '/n\'$n');`,
		`_send('GET', '/y/${Uri.encodeComponent(id)}/\'');`,
		`_send('GET', '/z/\'\$');`)
}

// client.dart takes every tag's calls through its one part line into
// the output, calls.g.dart, so a new tag needs no hand edit there.
func TestClientTakesTheOneCallsPart(t *testing.T) {
	write := func(t *testing.T, src string) (client, out string) {
		root := t.TempDir()
		client = filepath.Join(root, "lib", "src", "client.dart")
		if err := os.MkdirAll(filepath.Dir(client), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(client, []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
		// The fixture's hand class, as app code names it.
		models := "export 'hand_models.dart' show PlaybackSessionInfo;\n"
		if err := os.WriteFile(filepath.Join(filepath.Dir(client), "models.dart"), []byte(models), 0o644); err != nil {
			t.Fatal(err)
		}
		return client, filepath.Join(root, "lib", "src", "gen")
	}
	const part = "part 'gen/calls.g.dart';\n"
	all := "import 'package:dio/dio.dart';\n\npart 'other.g.dart';\n" + part
	t.Run("the one part", func(t *testing.T) {
		client, out := write(t, all)
		if err := run(fixtureSpec, fixtureHints, out, client, "", nil); err != nil {
			t.Fatal(err)
		}
		calls, err := os.ReadFile(filepath.Join(out, "calls.g.dart"))
		if err != nil {
			t.Fatal(err)
		}
		wantContains(t, string(calls), "part of '../client.dart';\n",
			"abstract class _WaxDeckCalls = _WaxDeckTransport with _AdminCalls, ",
			"mixin _LibraryCalls on _WaxDeckTransport implements LibraryApi {\n",
			"mixin _UsersCalls on _WaxDeckTransport implements UsersApi {\n")
		if _, err := os.Stat(filepath.Join(out, "calls")); !os.IsNotExist(err) {
			t.Errorf("the run wrote a calls directory beside calls.g.dart (%v)", err)
		}
	})
	// Comments hide a directive, and a comment opener inside a string
	// opens none.
	t.Run("directives in comments are not read", func(t *testing.T) {
		client, out := write(t, all+"/*\npart 'gen/gone.g.dart';\n*/\n// part 'gen/gone.g.dart';\n/* a /* nested */\npart 'gen/gone.g.dart'; */\n")
		if err := run(fixtureSpec, fixtureHints, out, client, "", nil); err != nil {
			t.Fatal(err)
		}
	})
	t.Run("a comment opener in a string opens none", func(t *testing.T) {
		src := "const a = 'x/*';\nconst b = r'\\'; const d = '/*';\nconst c = '''\n/* ''';\nfinal e = '${x ?? '/*'}';\n" + all
		client, out := write(t, src)
		if err := run(fixtureSpec, fixtureHints, out, client, "", nil); err != nil {
			t.Fatal(err)
		}
	})
	for _, c := range []struct{ name, src, want string }{
		{"the part missing", strings.Replace(all, part, "", 1), "lacks part 'gen/calls.g.dart'"},
		{"a part the run does not write", all + "part \"gen/calls/library.g.dart\";\n", "has part 'gen/calls/library.g.dart', which this run does not write"},
		{"the part in a block comment", strings.Replace(all, part, "/*\n"+part+"*/\n", 1), "lacks part 'gen/calls.g.dart'"},
		{"the part in a nested block comment", strings.Replace(all, part, "/* /* */\n"+part+"*/\n", 1), "lacks part 'gen/calls.g.dart'"},
		{"the part in a line comment", strings.Replace(all, part, "// "+part, 1), "lacks part 'gen/calls.g.dart'"},
	} {
		t.Run(c.name, func(t *testing.T) {
			client, out := write(t, c.src)
			err := run(fixtureSpec, fixtureHints, out, client, "", nil)
			if err == nil || !strings.Contains(err.Error(), c.want) {
				t.Fatalf("want %q, got %v", c.want, err)
			}
			if _, err := os.Stat(out); !os.IsNotExist(err) {
				t.Errorf("a failed check wrote %s", out)
			}
		})
	}
	t.Run("a client the generated part does not name", func(t *testing.T) {
		client, _ := write(t, all)
		out := filepath.Join(filepath.Dir(client), "elsewhere", "gen")
		err := run(fixtureSpec, fixtureHints, out, client, "", nil)
		if err == nil || !strings.Contains(err.Error(), "client: the calls part says part of "+filepath.Join(filepath.Dir(out), "client.dart")+", not "+client) {
			t.Fatalf("want the part of mismatch named, got %v", err)
		}
	})
}

// The public barrel names what a public signature reaches; the codec
// exports the rest, so its callers can name every class it decodes.
func TestPublicBarrelNamesWhatSignaturesReach(t *testing.T) {
	paths := `  /a:
    post:
      operationId: postA
      tags: [a]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/Body"}
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Envelope"}
`
	schemas := `components:
  schemas:
    Body:
      type: object
      properties:
        part: {$ref: "#/components/schemas/Part"}
        mode: {$ref: "#/components/schemas/Mode"}
    Envelope:
      type: object
      properties:
        items:
          type: array
          items: {$ref: "#/components/schemas/Item"}
    Base:
      type: object
      properties:
        id: {type: string}
    Item:
      allOf:
        - $ref: "#/components/schemas/Base"
        - type: object
          properties:
            extra: {type: string}
    Part:
      type: object
      properties:
        x: {type: string}
    Mode:
      type: string
      enum: [up, down]
    Frame:
      type: object
      properties:
        held: {$ref: "#/components/schemas/Held"}
    Held:
      type: object
      properties:
        y: {type: string}
    H:
      type: object
      properties:
        inner: {$ref: "#/components/schemas/Inner"}
        secret: {$ref: "#/components/schemas/Secret"}
    Inner:
      type: object
      properties:
        z: {type: string}
    Secret:
      type: object
      properties:
        w: {type: string}
    D:
      type: object
      properties:
        v: {type: string}
`
	hints := "operations:\n  postA: {unwrap: items}\nenums:\n  Mode: {}\nhand:\n  H: {covers: [inner], ignores: [secret]}\n"
	ext := writeTemp(t, "model_extensions.dart", "extension DX on D {\n  String get label => v ?? '';\n}\n")
	files, err := generate(writeTemp(t, "spec.yaml", opSpecHead+paths+schemas), writeTemp(t, "hints.yaml", hints), ext)
	if err != nil {
		t.Fatal(err)
	}
	want := header + "\nexport 'enums.g.dart' show Mode;\nexport 'models/a.g.dart' show Base, Item, Part;\nexport 'models/shared.g.dart' show D, Inner;\n"
	if got := string(files[publicFile]); got != want {
		t.Errorf("public.g.dart:\n%s\nwant\n%s", got, want)
	}
	if codec := string(files[codecFile]); !strings.Contains(codec, "\nexport 'models.g.dart' show Body, Envelope, Frame, Held, Secret;\n") {
		t.Errorf("the codec does not export exactly what the barrel leaves out:\n%s", codec)
	}
}
