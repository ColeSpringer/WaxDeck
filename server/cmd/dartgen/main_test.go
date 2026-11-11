package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

// go test ./cmd/dartgen/ -run TestGolden -update rewrites the goldens.
var update = flag.Bool("update", false, "rewrite testdata/golden from the generator's output")

const (
	fixtureSpec  = "testdata/fixture.yaml"
	fixtureHints = "testdata/hints.yaml"
	goldenDir    = "testdata/golden"
	// Goldens carry a suffix of their own so Dart tooling never takes
	// them for sources.
	goldenSuffix = ".golden"
)

func generateFixture(t *testing.T) map[string][]byte {
	t.Helper()
	files, err := generate(fixtureSpec, fixtureHints, "")
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	return files
}

func readGoldens(t *testing.T) map[string][]byte {
	t.Helper()
	out := map[string][]byte{}
	err := filepath.WalkDir(goldenDir, func(path string, d fs.DirEntry, err error) error {
		if errors.Is(err, fs.ErrNotExist) && path == goldenDir {
			return nil
		}
		if err != nil || d.IsDir() || !strings.HasSuffix(path, goldenSuffix) {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(goldenDir, strings.TrimSuffix(path, goldenSuffix))
		if err != nil {
			return err
		}
		out[filepath.ToSlash(rel)] = data
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func TestGolden(t *testing.T) {
	files := generateFixture(t)
	if *update {
		for rel := range readGoldens(t) {
			if err := os.Remove(filepath.Join(goldenDir, filepath.FromSlash(rel)+goldenSuffix)); err != nil {
				t.Fatal(err)
			}
		}
		for rel, data := range files {
			path := filepath.Join(goldenDir, filepath.FromSlash(rel)+goldenSuffix)
			if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, data, 0o644); err != nil {
				t.Fatal(err)
			}
		}
		return
	}
	want := readGoldens(t)
	for _, rel := range slices.Sorted(maps.Keys(files)) {
		golden, ok := want[rel]
		if !ok {
			t.Errorf("%s: produced, but has no golden (rerun with -update)", rel)
			continue
		}
		if line, w, g, differ := firstDifference(golden, files[rel]); differ {
			t.Errorf("%s:%d differs from its golden (rerun with -update to accept):\n want: %q\n  got: %q", rel, line, w, g)
		}
	}
	for _, rel := range slices.Sorted(maps.Keys(want)) {
		if _, ok := files[rel]; !ok {
			t.Errorf("%s: golden, but no longer produced (rerun with -update)", rel)
		}
	}
}

func firstDifference(want, got []byte) (line int, w, g string, differ bool) {
	if bytes.Equal(want, got) {
		return 0, "", "", false
	}
	wl, gl := strings.Split(string(want), "\n"), strings.Split(string(got), "\n")
	for i := 0; ; i++ {
		var a, b string
		if i < len(wl) {
			a = wl[i]
		}
		if i < len(gl) {
			b = gl[i]
		}
		if a != b || i >= len(wl) || i >= len(gl) {
			return i + 1, a, b, true
		}
	}
}

// The goldens pin the layout the fixture's operations decide: one file
// per tag in first-reach order, the shared file for the unreached.
func TestFilesFollowFirstReachingTag(t *testing.T) {
	files := generateFixture(t)
	for rel, class := range map[string]string{
		"models/library.g.dart":  "class ItemSummary {",
		"models/podcasts.g.dart": "class EpisodeSummary extends ItemSummary {",
		"models/shared.g.dart":   "class WsPingFrame {",
		"models/playback.g.dart": "class SessionPage {",
	} {
		if !strings.Contains(string(files[rel]), class) {
			t.Errorf("%s does not declare %q", rel, class)
		}
	}
	if strings.Contains(string(files["models/playback.g.dart"]), "class PlaybackSessionInfo") {
		t.Error("the hand class PlaybackSessionInfo was emitted")
	}
	for rel, data := range files {
		if !bytes.HasPrefix(data, []byte(header)) {
			t.Errorf("%s does not start with the generated-file header", rel)
		}
	}
}

func TestOutputHasNoValueSemantics(t *testing.T) {
	for rel, data := range generateFixture(t) {
		for _, banned := range []string{"operator ==", "get hashCode", "toString()"} {
			if bytes.Contains(data, []byte(banned)) {
				t.Errorf("%s contains %q", rel, banned)
			}
		}
	}
}

func TestOutputIsDeterministic(t *testing.T) {
	first := generateFixture(t)
	for range 3 {
		again := generateFixture(t)
		if len(again) != len(first) {
			t.Fatalf("runs produced %d and %d files", len(first), len(again))
		}
		for rel, data := range first {
			if !bytes.Equal(again[rel], data) {
				t.Fatalf("%s differs between two runs", rel)
			}
		}
	}
}

// A reflow never breaks a line inside a code span, which the analyzer
// would read as HTML once cut; with unbalanced backticks there is no span
// and words wrap as usual.
func TestDocLinesKeepCodeSpansWhole(t *testing.T) {
	lead := strings.Repeat("a", 60)
	long := "`" + strings.Repeat("b", 80) + " c`"
	for _, c := range []struct {
		name, text, indent string
		want               []string
	}{
		{"a span straddling the wrap column moves whole", lead + " `If-Range: <etag>` tail", "",
			[]string{"/// " + lead, "/// `If-Range: <etag>` tail"}},
		{"a span that fits stays on the line", "a `If-Range: <etag>` b", "  ",
			[]string{"  /// a `If-Range: <etag>` b"}},
		{"a span wider than the line stands alone", "x " + long + " y", "",
			[]string{"/// x", "/// " + long, "/// y"}},
		{"unbalanced backticks wrap as plain words", lead + " `If-Range: <etag> tail more words", "",
			[]string{"/// " + lead + " `If-Range:", "/// <etag> tail more words"}},
		{"a span opened in one paragraph does not reach the next", "`open\n\nnext` word", "",
			[]string{"/// `open", "///", "/// next` word"}},
	} {
		t.Run(c.name, func(t *testing.T) {
			got := docLines(c.text, c.indent)
			if strings.Join(got, "\n") != strings.Join(c.want, "\n") {
				t.Errorf("docLines(%q) =\n%s\nwant\n%s", c.text, strings.Join(got, "\n"), strings.Join(c.want, "\n"))
			}
		})
	}
}

func writeTemp(t *testing.T, name, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestHintErrorsNameTheKey(t *testing.T) {
	cases := []struct {
		name, hints string
		want        []string
	}{
		{"unknown key", "models:\n  User:\n    bogus: true\n", []string{"field bogus not found"}},
		{"unknown field key", "models:\n  User:\n    fields:\n      id: {renamed: x}\n", []string{"field renamed not found"}},
		{"unknown schema", "models:\n  Nope: {}\n", []string{"models.Nope: no such schema"}},
		{"unknown field", "models:\n  User:\n    fields:\n      nope: {as: x}\n", []string{"models.User.fields.nope: User has no property nope"}},
		{"unknown omit", "models:\n  User:\n    omit: [nope]\n", []string{"models.User.omit: User has no property nope"}},
		{"unknown enum", "enums:\n  Nope: {}\n", []string{"enums.Nope: no such schema Nope"}},
		{"unknown inline enum", "enums:\n  User.nope: {}\n", []string{"enums.User.nope: User has no property nope"}},
		{"not an enum", "enums:\n  User.username: {}\n", []string{"enums.User.username: User.username carries no inline enum"}},
		{"ref enum listed inline", "enums:\n  Schedule.kind: {}\n", []string{"enums.Schedule.kind: Schedule.kind is a $ref to ScheduleKind; list ScheduleKind itself"}},
		{"unknown operation", "operations:\n  nope: {}\n", []string{"operations.nope: no operation has this operationId"}},
		{"unknown hand", "hand:\n  Nope: {}\n", []string{"hand.Nope: no such schema"}},
		{"hand names no object", "hand:\n  MediaType: {}\n", []string{"hand.MediaType: MediaType is not an object schema"}},
		{"hand lacks a property", "hand:\n  SessionInfo: {covers: [id]}\n", []string{"hand.SessionInfo: SessionInfo has positionMs, listed in neither covers nor ignores; cover it in the hand-written class (hand_models.dart) and list it"}},
		{"hand covers a property the schema lacks", "hand:\n  SessionInfo: {covers: [id, positionMs, gone]}\n", []string{"hand.SessionInfo.covers: SessionInfo has no property gone"}},
		{"derived is no key", "derived:\n  ItemSummary: [titleOrderKey]\n", []string{"field derived not found"}},
		{"default duplicates the spec's", "models:\n  TargetCreate:\n    fields:\n      muted: {default: true}\n", []string{"models.TargetCreate.fields.muted.default: the spec already declares a default for TargetCreate.muted"}},
		{"map default duplicates the spec's", "models:\n  AuditEvent:\n    fields:\n      detail: {default: {}}\n", []string{"models.AuditEvent.fields.detail.default: the spec already declares a default for AuditEvent.detail"}},
		{"an empty map spelled as Dart", "models:\n  ItemMetadata:\n    fields:\n      extras:\n        default: const {}\n", []string{"models.ItemMetadata.fields.extras.default: const {} is not a Map<String, String>; write [] for an empty list, {} for an empty map"}},
		{"map default of the wrong type", "models:\n  ItemMetadata:\n    fields:\n      extras: {default: {a: 1}}\n", []string{"models.ItemMetadata.fields.extras.default: 1 is not a String"}},
		{"object default its class cannot build bare", "models:\n  ItemDetail:\n    fields:\n      artSource: {default: {}}\n", []string{"models.ItemDetail.fields.artSource.default: ArtSource requires provider, so {} cannot build it"}},
		{"object default of the wrong shape", "models:\n  ItemDetail:\n    fields:\n      artSource: {default: {provider: x}}\n", []string{"models.ItemDetail.fields.artSource.default: ", "is not a ArtSource"}},
		{"default of the wrong type", "models:\n  User:\n    fields:\n      displayName: {default: 3}\n", []string{"models.User.fields.displayName.default: 3 is not a String"}},
		{"drop reached as a single value", "enums:\n  MediaType: {fallback: drop}\n", []string{
			"enums.MediaType: fallback drop, but ItemDetail (holding it in mediaType) is decoded as a single value at the response of getItem",
			"enums.MediaType: fallback drop, but Upload (holding it in mediaType) is decoded as a single value at the response of getUpload",
		}},
		{"reserved word as a field name", "models:\n  User:\n    fields:\n      username: {as: class}\n", []string{"models.User.fields.username.as: class is a Dart reserved word"}},
		{"built-in identifier as a class name", "models:\n  User: {as: dynamic}\n", []string{"models.User.as: dynamic is a Dart built-in identifier"}},
		{"reserved word as an enum member", "enums:\n  GenreTree.source: {}\n", []string{`enums.GenreTree.source: the value "default" makes the member "default", which is a Dart reserved word`}},
		{"added member clashes", "enums:\n  MediaType: {add: [values], fallback: values}\n", []string{`enums.MediaType.add: "values" is a member every generated enum has`}},
		{"fallback names nothing", "enums:\n  MediaType: {fallback: musci}\n", []string{"enums.MediaType.fallback: musci is no value or member of MediaType (music, podcast, audiobook); add lists a member the spec lacks"}},
		{"added member the spec has", "enums:\n  MediaType: {add: [podcast]}\n", []string{"enums.MediaType.add: podcast is a member already"}},
		{"two keys make one enum differently", "enums:\n  DeleteRequest.mode: {as: Mode}\n  DeleteFilesRequest.mode: {as: Mode, fallback: trash}\n", []string{"enums.DeleteRequest.mode: makes enum Mode, which enums.DeleteFilesRequest.mode makes with other values or fallback"}},
		{"enum name clashes with a class", "enums:\n  MediaType: {as: Library}\n", []string{"take the Dart name Library"}},
		{"field hint on a base property", "models:\n  ItemDetail:\n    fields:\n      title: {as: name}\n", []string{"models.ItemDetail.fields.title: title is declared by ItemSummary; hint it there"}},
		{"hand takes no field hints", "hand:\n  User: {}\nmodels:\n  User:\n    omit: [legacyTheme]\n", []string{"models.User: User is hand-written, so only as applies"}},
		{"hand base of a generated class", "hand:\n  ItemSummary: {}\n", []string{"hand.ItemSummary: EpisodeSummary, which extends it, must be hand-written too"}},
		{"convert needs an integer", "models:\n  User:\n    fields:\n      username: {convert: durationMs}\n", []string{"models.User.fields.username.convert: durationMs needs an integer"}},
		{"convert apiError needs the Error shape", "models:\n  Upload:\n    fields:\n      id: {convert: apiError}\n", []string{"models.Upload.fields.id.convert: apiError needs"}},
		{"convert takes three values", "models:\n  Upload:\n    fields:\n      idleMs: {convert: seconds}\n", []string{`models.Upload.fields.idleMs.convert: "seconds" is not durationMs, apiError or base64Text`}},
		{"convert base64Text needs bytes", "models:\n  Upload:\n    fields:\n      id: {convert: base64Text}\n", []string{"models.Upload.fields.id.convert: base64Text needs a format byte string"}},
		{"emptyAsNull needs a nullable String", "models:\n  User:\n    fields:\n      username: {emptyAsNull: true}\n", []string{"models.User.fields.username.emptyAsNull: needs a nullable String"}},
		{"omitEmpty needs a List or an object", "models:\n  User:\n    fields:\n      username: {omitEmpty: true}\n", []string{"models.User.fields.username.omitEmpty: needs a List or an object"}},
		{"dropNullValues needs nullable values", "models:\n  ItemMetadata:\n    fields:\n      fields: {dropNullValues: true}\n", []string{"models.ItemMetadata.fields.fields.dropNullValues: needs a map whose values can be null"}},
		{"unknownAs needs a spec enum", "models:\n  User:\n    fields:\n      username: {unknownAs: x}\n", []string{"models.User.fields.username.unknownAs: needs a String"}},
		{"unknownAs on a Dart enum", "enums:\n  EntityCard.kind: {}\nmodels:\n  EntityCard:\n    fields:\n      kind: {unknownAs: album}\n", []string{"models.EntityCard.fields.kind.unknownAs: EntityCard.kind is the Dart enum EntityCardKind; give the enum a fallback instead"}},
		{"hand, skip and raw exclude each other", "operations:\n  getItem: {hand: true, raw: true}\n", []string{"operations.getItem: hand, skip and raw exclude each other"}},
		{"positional names a parameter", "models:\n  Error: {as: ApiError}\noperations:\n  getShelf: {positional: [key, nope]}\n", []string{"operations.getShelf.positional: nope is not a parameter of getShelf"}},
		{"positional takes body properties", "models:\n  Error: {as: ApiError}\noperations:\n  putSchedule: {positional: [kind, cron, bogus]}\n", []string{"operations.putSchedule.positional: bogus is not a parameter of putSchedule"}},
		{"nullOn statuses are integers", "operations:\n  getItem: {nullOn: [missing]}\n", []string{"cannot unmarshal"}},
		{"class renamed to a dart:core type", "models:\n  User: {as: Exception}\n", []string{"hints: models.User.as: Exception is a dart:core type, which an import of the models would hide"}},
		{"enum named a dart:core type", "enums:\n  MediaType: {as: Type}\n", []string{"hints: enums.MediaType: the enum name Type is a dart:core type, which an import of the models would hide"}},
		{"inline enum on a base property", "enums:\n  EpisodeDetail.fetchState: {}\n", []string{"hints: enums.EpisodeDetail.fetchState: fetchState is declared by EpisodeSummary; list it as EpisodeSummary.fetchState"}},
		{"default on an untyped property", "models:\n  Gap:\n    fields:\n      value: {default: 1}\n", []string{"hints: models.Gap.fields.value.default: Gap.value is untyped, so it takes no default"}},
		{"nullOn statuses are HTTP statuses", "operations:\n  getItem: {nullOn: [42]}\n", []string{"operations.getItem.nullOn: 42 is not an HTTP status"}},
		{"every problem is named", "models:\n  Nope: {}\noperations:\n  nope: {}\n", []string{"models.Nope", "operations.nope"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := generate(fixtureSpec, writeTemp(t, "hints.yaml", c.hints), "")
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

const miniSpecHead = `openapi: 3.0.3
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
              schema:
                $ref: "#/components/schemas/A"
components:
  schemas:
`

func TestSpecErrorsNameTheSchema(t *testing.T) {
	cases := []struct{ name, schemas, want string }{
		{"inline object", `    A:
      type: object
      properties:
        inner:
          type: object
          properties:
            x: {type: string}
`, "A.inner: an inline object has no Dart class; declare it under components/schemas"},
		{"two allOf bases", `    A:
      allOf:
        - $ref: "#/components/schemas/B"
        - $ref: "#/components/schemas/C"
    B:
      type: object
      properties:
        b: {type: string}
    C:
      type: object
      properties:
        c: {type: string}
`, "A: allOf takes exactly one $ref base, not 2"},
		{"redeclared base property", `    A:
      allOf:
        - $ref: "#/components/schemas/B"
        - type: object
          properties:
            b: {type: integer}
    B:
      type: object
      properties:
        b: {type: string}
`, "A redeclares b, which its base B declares"},
		{"oneOf", `    A:
      type: object
      properties:
        x:
          oneOf:
            - {type: string}
            - {type: integer}
`, "A.x: oneOf, anyOf and not have no Dart mapping"},
		{"binary in a model", `    A:
      type: object
      properties:
        x: {type: string, format: binary}
`, "A.x: format binary has no JSON mapping"},
		{"reserved word property", `    A:
      type: object
      properties:
        default: {type: string}
`, "A.default: default is a Dart reserved word; rename it with models.A.fields.default.as"},
		{"class named a dart:core type", `    A:
      type: object
      properties:
        e: {$ref: "#/components/schemas/Error"}
    Error:
      type: object
      properties:
        code: {type: string}
`, "schema Error: the name is a dart:core type, which an import of the models would hide; rename it with models.Error.as"},
		{"class named another dart:core type", `    A:
      type: object
      properties:
        x: {$ref: "#/components/schemas/Duration"}
    Duration:
      type: object
      properties:
        ms: {type: integer}
`, "schema Duration: the name is a dart:core type, which an import of the models would hide; rename it with models.Duration.as"},
		{"class name a generated type uses", `    A:
      type: object
      properties:
        x: {$ref: "#/components/schemas/Uint8List"}
    Uint8List:
      type: object
      properties:
        length: {type: integer}
`, "schema Uint8List: the name is a type the generated code uses; rename it with models.Uint8List.as"},
		{"class named a type the calls use", `    A:
      type: object
      properties:
        x: {$ref: "#/components/schemas/Response"}
    Response:
      type: object
      properties:
        status: {type: integer}
`, "schema Response: the name is a type the generated code uses; rename it with models.Response.as"},
		{"default on an untyped property", `    A:
      type: object
      properties:
        x: {default: 1}
`, "spec: A.x: an untyped property takes no default"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := generate(writeTemp(t, "spec.yaml", miniSpecHead+c.schemas), writeTemp(t, "hints.yaml", ""), "")
			if err == nil {
				t.Fatal("generate succeeded")
			}
			if !strings.Contains(err.Error(), c.want) {
				t.Errorf("error does not name %q:\n%v", c.want, err)
			}
		})
	}
	t.Run("operation tags", func(t *testing.T) {
		spec := strings.Replace(miniSpecHead, "tags: [a]", "tags: [a, b]", 1) + "    A:\n      type: object\n      properties:\n        x: {type: string}\n"
		_, err := generate(writeTemp(t, "spec.yaml", spec), writeTemp(t, "hints.yaml", ""), "")
		if err == nil || !strings.Contains(err.Error(), "GET /a has 2 tags; each operation takes exactly one") {
			t.Errorf("want the two-tag operation named, got %v", err)
		}
	})
}

// A drop is honoured only where a generated list holds the dropped
// object; every other place the codec decodes it fails the run.
func TestDropChecks(t *testing.T) {
	const kind = `
      type: object
      properties:
        kind: {type: string, enum: [x, y]}
`
	cases := []struct{ name, schemas, hints, want string }{
		{"in a map", `    A:
      type: object
      properties:
        m:
          type: object
          additionalProperties: {$ref: "#/components/schemas/E"}
    E:
      type: string
      enum: [x, y]
`, "enums:\n  E: {fallback: drop}\n", "enums.E: fallback drop acts on lists, and A.m holds the enum in a map"},
		{"held as a property", `    A:
      type: object
      properties:
        c: {$ref: "#/components/schemas/C"}
    C:` + kind, "enums:\n  C.kind: {fallback: drop}\n",
			"enums.C.kind: fallback drop, but C (holding it in kind) is decoded as a single value at A.c"},
		{"held as a map's value", `    A:
      type: object
      properties:
        byName:
          type: object
          additionalProperties: {$ref: "#/components/schemas/C"}
    C:` + kind, "enums:\n  C.kind: {fallback: drop}\n",
			"enums.C.kind: fallback drop, but C (holding it in kind) is decoded as a single value at A.byName"},
		{"held alone by a hand class", `    A:
      type: object
      properties:
        h: {$ref: "#/components/schemas/H"}
    H:
      type: object
      properties:
        card: {$ref: "#/components/schemas/C"}
    C:` + kind, "hand:\n  H: {covers: [card]}\nenums:\n  C.kind: {fallback: drop}\n",
			"enums.C.kind: fallback drop, but C (holding it in kind) is decoded as a single value at H.card"},
		{"decoded on its own", `    A:
      type: object
      properties:
        x: {type: string}
    F:` + kind, "enums:\n  F.kind: {fallback: drop}\n",
			"enums.F.kind: fallback drop, but F (holding it in kind) is decoded as a single value at a decode of its own (nothing reaches or holds F)"},
		{"listed by what nothing reaches", `    A:
      type: object
      properties:
        x: {type: string}
    F:
      type: object
      properties:
        items:
          type: array
          items: {$ref: "#/components/schemas/G"}
    G:` + kind, "enums:\n  G.kind: {fallback: drop}\n", ""},
		{"held by a hand class a generated list holds", `    A:
      type: object
      properties:
        hs:
          type: array
          items: {$ref: "#/components/schemas/H"}
    H:` + kind, "hand:\n  H: {covers: [kind]}\nenums:\n  H.kind: {fallback: drop}\n",
			"enums.H.kind: fallback drop, but the hand-written H holds it in kind, and A.hs lists H; a generated list drops only generated classes"},
		{"held by a hand class a hand list holds", `    A:
      type: object
      properties:
        p: {$ref: "#/components/schemas/P"}
    P:
      type: object
      properties:
        hs:
          type: array
          items: {$ref: "#/components/schemas/H"}
    H:` + kind, "hand:\n  P: {covers: [hs]}\n  H: {covers: [kind]}\nenums:\n  H.kind: {fallback: drop}\n", ""},
		// A hand list decodes each element alone: the keep predicates are
		// the codec's own.
		{"listed by a hand class", `    A:
      type: object
      properties:
        h: {$ref: "#/components/schemas/H"}
    H:
      type: object
      properties:
        gs:
          type: array
          items: {$ref: "#/components/schemas/G"}
    G:` + kind, "hand:\n  H: {covers: [gs]}\nenums:\n  G.kind: {fallback: drop}\n",
			"enums.G.kind: fallback drop, but G (holding it in kind) is decoded as a single value at H.gs"},
		{"an unreached base with a subclass", `    A:
      type: object
      properties:
        x: {type: string}
    B:` + kind + `    S:
      allOf:
        - $ref: "#/components/schemas/B"
        - type: object
          properties:
            more: {type: string}
`, "enums:\n  B.kind: {fallback: drop}\n",
			"enums.B.kind: fallback drop, but B (holding it in kind) is decoded as a single value at a decode of its own (nothing reaches or holds B)"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := generate(writeTemp(t, "spec.yaml", miniSpecHead+c.schemas), writeTemp(t, "hints.yaml", c.hints), "")
			switch {
			case c.want == "" && err != nil:
				t.Errorf("want success, got %v", err)
			case c.want == "":
			case err == nil:
				t.Error("generate succeeded")
			case !strings.Contains(err.Error(), c.want):
				t.Errorf("error does not name %q:\n%v", c.want, err)
			}
		})
	}
	// A response is decoded as a single value however its schema holds
	// the class or the enum: wrapped in allOf to carry a description, or
	// as a map's values.
	const card = "    C:" + kind + "    E:\n      type: string\n      enum: [x, y]\n"
	respond := func(schema string) string {
		return strings.Replace(miniSpecHead, `$ref: "#/components/schemas/A"`, schema, 1) + card
	}
	const wrapped = "allOf: [{$ref: \"#/components/schemas/%s\"}]\n                description: The answer."
	const mapped = "type: object\n                additionalProperties: {$ref: \"#/components/schemas/%s\"}"
	for _, c := range []struct{ name, schema, hints, want string }{
		{"a response wrapped in allOf", fmt.Sprintf(wrapped, "C"), "enums:\n  C.kind: {fallback: drop}\n",
			"enums.C.kind: fallback drop, but C (holding it in kind) is decoded as a single value at the response of getA"},
		{"a response map", fmt.Sprintf(mapped, "C"), "enums:\n  C.kind: {fallback: drop}\n",
			"enums.C.kind: fallback drop, but C (holding it in kind) is decoded as a single value at the response of getA"},
		{"an enum response wrapped in allOf", fmt.Sprintf(wrapped, "E"), "enums:\n  E: {fallback: drop}\n",
			"enums.E: fallback drop, but getA answers the enum as a single value"},
		{"an enum response map", fmt.Sprintf(mapped, "E"), "enums:\n  E: {fallback: drop}\n",
			"enums.E: fallback drop acts on lists, and the response of getA holds the enum in a map"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, respond(c.schema), c.hints)
			wantError(t, err, c.want)
		})
	}
}

// A hand class's hint lists every property of its schema, a base's too,
// as covered or ignored: a contract change to it fails the run rather
// than being decoded away.
func TestHandHintCoversTheSchema(t *testing.T) {
	const schemas = `    A:
      type: object
      properties:
        h: {$ref: "#/components/schemas/H"}
    B:
      type: object
      properties:
        id: {type: string}
    H:
      allOf:
        - $ref: "#/components/schemas/B"
        - type: object
          properties:
            name: {type: string}
            legacy: {type: string}
`
	hand := func(hint string) string { return "hand:\n  H: " + hint + "\n" }
	if _, err := generateMini(t, miniSpecHead+schemas, hand("{covers: [id, name], ignores: [legacy]}")); err != nil {
		t.Errorf("a hint listing every property: %v", err)
	}
	for _, c := range []struct{ name, hint, want string }{
		{"a property neither lists", "{covers: [id, name]}",
			"hints: hand.H: H has legacy, listed in neither covers nor ignores; cover it in the hand-written class (hand_models.dart) and list it"},
		{"a base property neither lists", "{covers: [name], ignores: [legacy]}", "hints: hand.H: H has id, listed in neither covers nor ignores"},
		{"an ignored property the schema lacks", "{covers: [id, name], ignores: [legacy, gone]}", "hints: hand.H.ignores: H has no property gone"},
		{"a property listed twice", "{covers: [id, name, name], ignores: [legacy]}", "hints: hand.H.covers: name is listed in covers already"},
		{"a property covered and ignored", "{covers: [id, name, legacy], ignores: [legacy]}", "hints: hand.H.ignores: legacy is listed in covers already"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, miniSpecHead+schemas, hand(c.hint))
			wantError(t, err, c.want)
		})
	}
}

// client.dart and the calls part of its library take these names from
// dio and dart:async; a schema of the same name would make each use
// ambiguous there. The package's own names come from its files.
func TestClassNamesTheClientLibraryTakes(t *testing.T) {
	for _, name := range strings.Fields("Dio Options InterceptorsWrapper DioExceptionType Timer") {
		t.Run(name, func(t *testing.T) {
			_, err := generateMini(t, miniSpecHead+"    A:\n      type: object\n      properties:\n        x: {$ref: \"#/components/schemas/"+name+"\"}\n"+
				"    "+name+":\n      type: object\n      properties:\n        y: {type: string}\n", "")
			wantError(t, err, "schema "+name+": the name is a type the generated code uses; rename it with models."+name+".as")
		})
	}
}

// A hand-written decode does not resolve an origin-relative URL, so a
// hand class covering a property of format uri-reference would hand the
// app an unresolved one (silently, on web): the run refuses it.
func TestHandClassCoversNoOriginRelativeURL(t *testing.T) {
	const schemas = `    A:
      type: object
      properties:
        h: {$ref: "#/components/schemas/H"}
    B:
      type: object
      properties:
        img: {type: string, format: uri-reference}
    H:
      allOf:
        - $ref: "#/components/schemas/B"
        - type: object
          properties:
            link: {type: string, format: uri-reference}
            links:
              type: array
              items: {type: string, format: uri-reference}
            name: {type: string}
`
	hand := func(hint string) string { return "hand:\n  H: " + hint + "\n" }
	if _, err := generateMini(t, miniSpecHead+schemas, hand("{covers: [name], ignores: [img, link, links]}")); err != nil {
		t.Errorf("a hint ignoring every URL: %v", err)
	}
	const remedy = " is an origin-relative URL (format uri-reference), which a generated class resolves and a hand-written decode does not"
	for _, c := range []struct{ name, hint, want string }{
		{"a property", "{covers: [name, link], ignores: [img, links]}", "hints: hand.H.covers: H.link" + remedy},
		{"a list's elements", "{covers: [name, links], ignores: [img, link]}", "hints: hand.H.covers: H.links" + remedy},
		{"a base's property", "{covers: [name, img], ignores: [link, links]}", "hints: hand.H.covers: B.img" + remedy},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, miniSpecHead+schemas, hand(c.hint))
			wantError(t, err, c.want)
		})
	}
}

// A run writes its files, removes the stale ones dartgen wrote and a
// directory that leaves empty, and keeps everything else.
func TestRunWritesAndPrunes(t *testing.T) {
	out := t.TempDir()
	stale := filepath.Join(out, "models", "gone.g.dart")
	staleAlone := filepath.Join(out, "calls", "admin.g.dart")
	staleBeside := filepath.Join(out, "old", "gone.g.dart")
	kept := filepath.Join(out, "models", "notes.txt")
	keptBeside := filepath.Join(out, "old", "notes.txt")
	foreign := filepath.Join(out, "database.g.dart")
	for path, body := range map[string]string{
		stale:       header + "class Gone {}\n",
		staleAlone:  header + "mixin _AdminCalls {}\n",
		staleBeside: header + "class Gone {}\n",
		kept:        "x",
		keptBeside:  "x",
		foreign:     "// GENERATED CODE - DO NOT MODIFY BY HAND\n",
	} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := run(fixtureSpec, fixtureHints, out, "", "", nil); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{stale, staleBeside, filepath.Dir(staleAlone)} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Errorf("stale %s survived the run", path)
		}
	}
	for _, path := range []string{kept, keptBeside, foreign} {
		if _, err := os.Stat(path); err != nil {
			t.Errorf("%s, no stale file of dartgen's, was removed: %v", path, err)
		}
	}
	for rel, data := range generateFixture(t) {
		got, err := os.ReadFile(filepath.Join(out, filepath.FromSlash(rel)))
		if err != nil || !bytes.Equal(got, data) {
			t.Errorf("%s was not written as generated (%v)", rel, err)
		}
	}
	err := filepath.WalkDir(filepath.Dir(out), func(path string, d fs.DirEntry, err error) error {
		if err == nil && strings.HasPrefix(d.Name(), ".") {
			t.Errorf("temp file %s left behind", path)
		}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
}

// markFormat stands in for dart format: it changes every file it is
// handed, as dart format changes most of the raw output.
func markFormat(dir string) error {
	return filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(path, append(data, "// formatted\n"...), 0o644)
	})
}

// A formatting run compares the formatted bytes with the files there, so
// a second run over its own output rewrites nothing and no mtime moves:
// make rebuilds the web bundle from those mtimes.
func TestFormattedRunRewritesNothingUnchanged(t *testing.T) {
	for _, c := range []struct {
		name   string
		format func(dir string) error
		dart   bool
	}{{"a formatter", markFormat, false}, {"dart format", dartFormat, true}} {
		t.Run(c.name, func(t *testing.T) {
			if _, err := exec.LookPath("dart"); c.dart && err != nil {
				t.Skip("no dart on PATH")
			}
			root, out := dartPackage(t)
			if err := run(fixtureSpec, fixtureHints, out, "", "", c.format); err != nil {
				t.Fatal(err)
			}
			// What only dart format writes: the raw aggregate is one line.
			if calls, _ := os.ReadFile(filepath.Join(out, callsFile)); c.dart && !bytes.Contains(calls, []byte("_WaxDeckCalls = _WaxDeckTransport\n    with")) {
				t.Errorf("%s was not formatted:\n%.300s", callsFile, calls)
			}
			past := time.Now().Add(-time.Hour).Truncate(time.Second)
			written := map[string][]byte{}
			err := filepath.WalkDir(out, func(path string, d fs.DirEntry, err error) error {
				if err != nil || d.IsDir() {
					return err
				}
				if written[path], err = os.ReadFile(path); err != nil {
					return err
				}
				return os.Chtimes(path, past, past)
			})
			if err != nil {
				t.Fatal(err)
			}
			if err := run(fixtureSpec, fixtureHints, out, "", "", c.format); err != nil {
				t.Fatal(err)
			}
			for path, data := range written {
				st, err := os.Stat(path)
				switch {
				case err != nil:
					t.Errorf("%s: %v", path, err)
				case !st.ModTime().Equal(past):
					t.Errorf("%s was rewritten", path)
				}
				if !c.dart && !bytes.HasSuffix(data, []byte("// formatted\n")) {
					t.Errorf("%s was written unformatted", path)
				}
			}
			if len(written) == 0 {
				t.Fatal("the run wrote nothing")
			}
			wantNoStage(t, filepath.Join(root, ".dart_tool"))
		})
	}
}

// dartPackage is a package root holding a pubspec.yaml, and the output
// directory in it the generator writes to.
func dartPackage(t *testing.T) (root, out string) {
	t.Helper()
	root = t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "pubspec.yaml"), []byte("name: fixture\nenvironment:\n  sdk: ^3.12.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	out = filepath.Join(root, "lib", "src", "gen")
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		t.Fatal(err)
	}
	return root, out
}

// wantNoStage fails when dir holds a formatting stage.
func wantNoStage(t *testing.T, dir string) {
	t.Helper()
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".dartgen-") {
			t.Errorf("%s holds the stage %s", dir, e.Name())
		}
	}
}

// -format stages its run in the package's .dart_tool, which git and the
// web build ignore, and first removes a stage an interrupted run left:
// one old enough that no run can still own it, never a concurrent run's.
func TestFormatStagesUnderDartTool(t *testing.T) {
	root, out := dartPackage(t)
	tool := filepath.Join(root, ".dart_tool")
	leave := func(name string, age time.Duration) string {
		t.Helper()
		dir := filepath.Join(tool, name)
		file := filepath.Join(dir, "models", "gone.g.dart")
		if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte("class Gone {}\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		when := time.Now().Add(-age)
		if err := os.Chtimes(dir, when, when); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	old := leave(".dartgen-old", 2*time.Hour)
	live := leave(".dartgen-live", time.Minute)
	var staged string
	format := func(dir string) error {
		staged = dir
		return markFormat(dir)
	}
	if err := run(fixtureSpec, fixtureHints, out, "", "", format); err != nil {
		t.Fatal(err)
	}
	if rel, err := filepath.Rel(tool, staged); err != nil || strings.HasPrefix(rel, "..") {
		t.Errorf("the run staged in %s, outside the package's .dart_tool", staged)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Errorf("the stage an interrupted run left hours ago stayed (%v)", err)
	}
	if _, err := os.Stat(live); err != nil {
		t.Errorf("a stage a run made a minute ago, perhaps a concurrent run's live one, was removed (%v)", err)
	}
	if err := os.RemoveAll(live); err != nil {
		t.Fatal(err)
	}
	wantNoStage(t, tool)
	wantNoStage(t, filepath.Join(root, "lib", "src"))
}

// A formatter that fails fails the run, which writes nothing and leaves
// no staging copy behind.
func TestFailedFormatWritesNothing(t *testing.T) {
	root, out := dartPackage(t)
	err := run(fixtureSpec, fixtureHints, out, "", "", func(string) error { return errors.New("no formatter") })
	if err == nil || !strings.Contains(err.Error(), "no formatter") {
		t.Fatalf("want the formatter's error, got %v", err)
	}
	if _, err := os.Stat(out); !os.IsNotExist(err) {
		t.Errorf("a failed format wrote %s (%v)", out, err)
	}
	wantNoStage(t, filepath.Join(root, ".dart_tool"))
	wantNoStage(t, filepath.Join(root, "lib", "src"))
}

func TestFailedRunWritesNothing(t *testing.T) {
	out := t.TempDir()
	before := filepath.Join(out, "codec.g.dart")
	if err := os.WriteFile(before, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := run(fixtureSpec, writeTemp(t, "hints.yaml", "models:\n  Nope: {}\n"), out, "", "", nil)
	if err == nil {
		t.Fatal("run succeeded")
	}
	entries, err := os.ReadDir(out)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Errorf("a failed run changed the output directory: %d entries", len(entries))
	}
	if got, _ := os.ReadFile(before); string(got) != "old" {
		t.Errorf("a failed run rewrote codec.g.dart: %q", got)
	}
}

// generateMini runs a mini spec with hints and answers the emitted files
// joined, or the run's error.
func generateMini(t *testing.T, spec, hints string) (string, error) {
	t.Helper()
	files, err := generate(writeTemp(t, "spec.yaml", spec), writeTemp(t, "hints.yaml", hints), "")
	if err != nil {
		return "", err
	}
	var all strings.Builder
	for _, rel := range slices.Sorted(maps.Keys(files)) {
		all.Write(files[rel])
	}
	return all.String(), nil
}

func wantContains(t *testing.T, out string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(out, want) {
			t.Errorf("output does not contain %q", want)
		}
	}
}

func wantError(t *testing.T, err error, want string) {
	t.Helper()
	switch {
	case err == nil:
		t.Errorf("generate succeeded; want an error naming %q", want)
	case !strings.Contains(err.Error(), want):
		t.Errorf("error does not name %q:\n%v", want, err)
	}
}

// A hint default on a required property is the constructor's: the wire
// still requires the property.
func TestRequiredPropertyDefaultIsTheConstructors(t *testing.T) {
	const schemas = `    A:
      type: object
      required: [n, tags, p]
      properties:
        n: {type: integer}
        tags:
          type: array
          items: {type: string}
        p: {$ref: "#/components/schemas/P"}
        q: {$ref: "#/components/schemas/Q"}
    B:
      allOf:
        - $ref: "#/components/schemas/A"
        - type: object
          properties:
            extra: {type: string}
    P:
      type: object
      required: [x]
      properties:
        x: {type: string}
    Q:
      type: object
      required: [y]
      properties:
        y: {type: string}
`
	out, err := generateMini(t, miniSpecHead+schemas,
		"models:\n  A:\n    fields:\n      n: {default: 0}\n      tags: {default: []}\n      p: {default: {}}\n      q: {default: {}}\n"+
			"  P:\n    fields:\n      x: {default: ''}\n  Q:\n    fields:\n      y: {default: ''}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out,
		"    this.n = 0,\n", "    this.tags = const [],\n", "    this.p = const P(),\n", "    this.q = const Q(),\n",
		"  final int n;\n", "  final List<String> tags;\n",
		"n: readRequired(json, 'n', type, wireInt),\n",
		"p: readRequired(json, 'p', type, (v, at) => decodeP(wireObject(v, at), ctx)),\n",
		"q: readOptional(json, 'q', type, (v, at) => decodeQ(wireObject(v, at), ctx)) ?? const Q(),\n",
		"  const B({\n    super.n,\n    super.tags,\n    super.p,\n    super.q,\n    this.extra,\n  });\n")
	if strings.Contains(out, "readRequired(json, 'n', type, wireInt) ??") {
		t.Error("a required property decodes to its constructor default")
	}
	if strings.Contains(out, "required super.") {
		t.Error("a subclass requires a base property its hint defaults")
	}
	_, err = generateMini(t, miniSpecHead+schemas, "models:\n  A:\n    fields:\n      q: {default: {}}\n")
	wantError(t, err, "hints: models.A.fields.q.default: Q requires y, so {} cannot build it")
	_, err = generateMini(t, miniSpecHead+strings.Replace(schemas, "n: {type: integer}", "n: {type: integer, default: 1}", 1),
		"models:\n  A:\n    fields:\n      n: {default: 0}\n")
	wantError(t, err, "hints: models.A.fields.n.default: the spec already declares a default for A.n")
}

// A {} inside a list or map default builds its class bare too, so the
// class must allow it there as well.
func TestObjectDefaultsInsideCollections(t *testing.T) {
	const spec = `openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: postA
      tags: [a]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/A"}
      responses:
        "204": {description: done}
components:
  schemas:
    A:
      type: object
      properties:
        foos:
          type: array
          items: {$ref: "#/components/schemas/Foo"}
        byKey:
          type: object
          additionalProperties: {$ref: "#/components/schemas/Foo"}
        bars:
          type: array
          items: {$ref: "#/components/schemas/Bar"}
    Foo:
      type: object
      required: [x]
      properties:
        x: {type: string}
    Bar:
      type: object
      properties:
        y: {type: string}
`
	out, err := generateMini(t, spec, "models:\n  A:\n    fields:\n      foos: {default: []}\n      bars: {default: [{}]}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out, "    this.foos = const [],\n", "    this.bars = const [Bar()],\n")
	for _, c := range []struct{ name, hints, want string }{
		{"a list field", "models:\n  A:\n    fields:\n      foos: {default: [{}]}\n",
			"hints: models.A.fields.foos.default: Foo requires x, so {} cannot build it"},
		{"a map field", "models:\n  A:\n    fields:\n      byKey: {default: {k: {}}}\n",
			"hints: models.A.fields.byKey.default: Foo requires x, so {} cannot build it"},
		{"a list parameter", "operations:\n  postA:\n    params:\n      foos: {default: [{}]}\n",
			"hints: operations.postA.params.foos.default: Foo requires x, so {} cannot build it"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, spec, c.hints)
			wantError(t, err, c.want)
		})
	}
}

// Shapes the spec and hints can state but no generated Dart carries fail
// the run, naming where.
func TestShapesWithoutDartFailTheRun(t *testing.T) {
	const post = `openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: postA
      tags: [a]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/A"}
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/R"}
components:
  schemas:
    R:
      type: object
      required: [token]
      properties:
        token: {type: string}
`
	const a = `    A:
      type: object
      required: [p]
      properties:
        p: {type: string}
        n: {type: integer}
        ratio: {type: number}
        held: {$ref: "#/components/schemas/H"}
    H:
      type: object
      required: [q]
      properties:
        q: {type: string}
`
	for _, c := range []struct{ name, schemas, hints, want string }{
		{"a NaN default", a, "models:\n  A:\n    fields:\n      ratio: {default: .nan}\n",
			"hints: models.A.fields.ratio.default: NaN is no JSON number"},
		{"an infinite default", a, "models:\n  A:\n    fields:\n      ratio: {default: -.inf}\n",
			"hints: models.A.fields.ratio.default: -Inf is no JSON number"},
		{"an integer default a web build rounds", a, "models:\n  A:\n    fields:\n      n: {default: 9007199254740993}\n",
			"hints: models.A.fields.n.default: 9007199254740993 is beyond 2^53 - 1, the largest integer a web build holds exactly"},
		{"a spec integer default a web build rounds", strings.Replace(a, "n: {type: integer}", "n: {type: integer, default: 9007199254740994}", 1), "",
			"spec: A.n: default: 9007199254740994 is beyond 2^53 - 1, the largest integer a web build holds exactly"},
		{"a property two parts declare", `    A:
      allOf:
        - $ref: "#/components/schemas/H"
        - type: object
          properties:
            x: {type: string}
        - type: object
          properties:
            x: {type: integer}
    H:
      type: object
      properties:
        q: {type: string}
`, "", "spec: A declares x in two of its parts; declare it once"},
		{"a property a part and the schema declare", `    A:
      allOf:
        - $ref: "#/components/schemas/H"
        - type: object
          properties:
            x: {type: string}
      properties:
        x: {type: boolean}
    H:
      type: object
      properties:
        q: {type: string}
`, "", "spec: A declares x in two of its parts; declare it once"},
		{"omit of a required request property", a, "models:\n  A:\n    omit: [p]\n",
			"hints: models.A.omit: p is required, and postA sends A, so every request would lack it"},
		{"omit of a required property a request holds", a, "models:\n  H:\n    omit: [q]\n",
			"hints: models.H.omit: q is required, and postA sends H, so every request would lack it"},
		{"omit of a required property a hand class's covered property holds", a, "hand:\n  A: {covers: [p, n, ratio, held]}\nmodels:\n  H:\n    omit: [q]\n",
			"hints: models.H.omit: q is required, and postA sends H, so every request would lack it"},
		{"properties beside typed additionalProperties", strings.Replace(a, "    H:\n", "      additionalProperties: {type: string}\n    H:\n", 1), "",
			"spec: A: additionalProperties beside properties have no Dart mapping; hold the open part in a map property"},
		{"properties beside open additionalProperties", strings.Replace(a, "    H:\n", "      additionalProperties: true\n    H:\n", 1), "",
			"spec: A: additionalProperties beside properties have no Dart mapping; hold the open part in a map property"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, post+c.schemas, c.hints)
			wantError(t, err, c.want)
		})
	}
	// A required property only answers carry may be left out.
	if _, err := generateMini(t, post+a, "models:\n  R:\n    omit: [token]\n"); err != nil {
		t.Errorf("omit of a required property no request sends: %v", err)
	}
	// A hand class sends what it covers, not what it ignores.
	if _, err := generateMini(t, post+a, "hand:\n  A: {covers: [p, n, ratio], ignores: [held]}\nmodels:\n  H:\n    omit: [q]\n"); err != nil {
		t.Errorf("omit of a required property a hand class ignores: %v", err)
	}
}

// An omit on a class folded into its base follows the folded schema: the
// base's request does not require what only the folded schema does, nor
// carry what only it holds.
func TestOmitOnAFoldedClassFollowsItsSchema(t *testing.T) {
	spec := func(sent string) string {
		return `openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: postA
      tags: [a]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/` + sent + `"}
      responses:
        "204": {description: done}
components:
  schemas:
    A:
      type: object
      required: [id]
      properties:
        id: {type: string}
    Created:
      allOf:
        - $ref: "#/components/schemas/A"
        - type: object
          required: [p]
          properties:
            p: {type: string}
            extra: {$ref: "#/components/schemas/G"}
    G:
      type: object
      required: [q]
      properties:
        q: {type: string}
`
	}
	const hints = "models:\n  Created: {as: A, omit: [p]}\n  G: {omit: [q]}\n"
	if _, err := generateMini(t, spec("A"), hints); err != nil {
		t.Errorf("the base sent, its folded class's requirement and field not: %v", err)
	}
	_, err := generateMini(t, spec("Created"), hints)
	wantError(t, err, "hints: models.Created.omit: p is required, and postA sends Created, so every request would lack it")
	wantError(t, err, "hints: models.G.omit: q is required, and postA sends G, so every request would lack it")
}

// A set of known values is named from Dart names: an inline enum's from
// its class and field, which the as hints make identifiers, a component
// enum's from the schema name's identifier parts.
func TestKnownSetsTakeDartNames(t *testing.T) {
	const schemas = `    A:
      type: object
      properties:
        x: {$ref: "#/components/schemas/My-Schema"}
        media-type: {type: string, enum: [audio, video]}
        order: {$ref: "#/components/schemas/sort-order"}
        orders:
          type: array
          items: {$ref: "#/components/schemas/sort.order"}
    My-Schema:
      type: object
      properties:
        kind: {type: string, enum: [p, q]}
    sort-order:
      type: string
      enum: [asc, desc]
    sort.order:
      type: string
      enum: [up, down]
`
	const hints = `models:
  A:
    fields:
      media-type: {as: mediaType, unknownAs: audio}
      order: {unknownAs: asc}
      orders: {unknownAs: up}
  My-Schema:
    as: MySchema
    fields:
      kind: {unknownAs: p}
`
	out, err := generateMini(t, miniSpecHead+schemas, hints)
	if err != nil {
		t.Fatal(err)
	}
	_, err = generateMini(t, miniSpecHead+schemas, "enums:\n  A.media-type: {}\n")
	wantError(t, err, "hints: enums.A.media-type: the enum name AMedia-type is not a Dart identifier; name it with enums.A.media-type.as")
	wantContains(t, out,
		"mediaType: readOptional(json, 'media-type', type, (v, at) => wireKnownOr(v, at, _knownAMediaType, 'audio')),\n",
		"const _knownAMediaType = {'audio', 'video'};\n",
		"const _knownMySchemaKind = {'p', 'q'};\n",
		"const _knownsortOrder = {'asc', 'desc'};\n",
		"const _knownsortOrder2 = {'up', 'down'};\n")
}

// fromWire takes the spelling as wire, so a fallback member of that name
// is named through its enum.
func TestEnumFallbackNamedLikeTheParameter(t *testing.T) {
	out, err := generateMini(t, miniSpecHead+"    A:\n      type: object\n      properties:\n        k: {$ref: \"#/components/schemas/Kind\"}\n"+
		"    Kind:\n      type: string\n      enum: [wire, cable]\n", "enums:\n  Kind: {fallback: wire}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out, "  /// The member [wire] spells; any other spelling reads as [Kind.wire].\n",
		"  static Kind? fromWire(String? wire) {\n", "    return Kind.wire;\n")
}

// The hints are one YAML document; a second would be read by nothing.
func TestHintsAreOneDocument(t *testing.T) {
	_, err := generate(fixtureSpec, writeTemp(t, "hints.yaml", "models:\n  Error: {as: ApiError}\n---\nmodels:\n  User: {as: Person}\n"), "")
	wantError(t, err, "a second YAML document follows the first; the hints are one document")
}

// A class renamed to its base's Dart name folds into the base.
func TestFoldIntoTheBase(t *testing.T) {
	const schemas = `    A:
      type: object
      required: [id]
      properties:
        id: {type: string}
    Created:
      allOf:
        - $ref: "#/components/schemas/A"
        - type: object
          properties:
            warning: {type: string}
            started: {type: boolean}
    Changed:
      allOf:
        - $ref: "#/components/schemas/A"
        - type: object
          required: [started]
          properties:
            started: {type: boolean}
    Holder:
      type: object
      properties:
        made: {$ref: "#/components/schemas/Created"}
`
	out, err := generateMini(t, miniSpecHead+schemas, "models:\n  Created: {as: A}\n  Changed: {as: A}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out,
		"class A {\n", "    required this.id,\n", "    this.warning,\n", "    this.started,\n",
		"  final String? warning;\n", "  final bool? started;\n",
		"started: readOptional(json, 'started', type, wireBool),\n",
		"  final A? made;\n", "made: readOptional(json, 'made', type, (v, at) => decodeA(wireObject(v, at), ctx)),\n")
	for _, gone := range []string{"class Created", "class Changed", "decodeCreated", "decodeChanged", " extends A"} {
		if strings.Contains(out, gone) {
			t.Errorf("a folded class left %q behind", gone)
		}
	}

	const clash = `    Other:
      allOf:
        - $ref: "#/components/schemas/A"
        - type: object
          properties:
            started: {type: string}
`
	_, err = generateMini(t, miniSpecHead+schemas+clash, "models:\n  Created: {as: A}\n  Changed: {as: A}\n  Other: {as: A}\n")
	wantError(t, err, "hints: models.Other.as: Other folds started into A, which Changed already makes bool? started")

	const members = `        - type: object
          properties:
            note: {type: string}
            labels:
              type: array
              items: {type: string}
            extras:
              type: object
              additionalProperties: {type: string, nullable: true}
            state: {type: string, enum: [up, down]}
`
	twins := func(right string) string {
		return "    Left:\n      allOf:\n        - $ref: \"#/components/schemas/A\"\n" + members +
			"    Right:\n      allOf:\n        - $ref: \"#/components/schemas/A\"\n" + right
	}
	foldHints := func(prop, left, right string) string {
		return fmt.Sprintf("models:\n  Left:\n    as: A\n    fields:\n      %s: %s\n  Right:\n    as: A\n    fields:\n      %s: %s\n",
			prop, left, prop, right)
	}
	for _, c := range []struct{ name, prop, left, right, rightMembers string }{
		{"emptyAsNull", "note", "{emptyAsNull: true}", "{}", members},
		{"omitEmpty", "labels", "{omitEmpty: true}", "{}", members},
		{"dropNullValues", "extras", "{dropNullValues: true}", "{}", members},
		{"unknownAs value", "state", "{unknownAs: up}", "{unknownAs: down}", members},
		{"unknownAs over other spec values", "state", "{unknownAs: up}", "{unknownAs: up}",
			strings.Replace(members, "[up, down]", "[up, down, sideways]", 1)},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, miniSpecHead+schemas+twins(c.rightMembers), foldHints(c.prop, c.left, c.right))
			wantError(t, err, "hints: models.Right.fields."+c.prop+": Right and Left fold "+c.prop+" into A with different field hints")
		})
	}
	if _, err = generateMini(t, miniSpecHead+schemas+twins(members), foldHints("note", "{emptyAsNull: true}", "{emptyAsNull: true}")); err != nil {
		t.Errorf("two folds hinting a property alike: %v", err)
	}
	for _, c := range []struct{ name, right string }{
		{"a string", strings.Replace(members, "note: {type: string}", "note: {type: string, format: uri-reference}", 1)},
		{"a list's elements", strings.Replace(members, "items: {type: string}", "items: {type: string, format: uri-reference}", 1)},
	} {
		t.Run("origin-relative URLs in "+c.name, func(t *testing.T) {
			_, err := generateMini(t, miniSpecHead+schemas+twins(c.right), "models:\n  Left: {as: A}\n  Right: {as: A}\n")
			wantError(t, err, "spec: Right and Left fold ")
			wantError(t, err, " into A, and differ in which strings are origin-relative URLs (format uri-reference)")
		})
	}

	const extended = `    Later:
      allOf:
        - $ref: "#/components/schemas/Created"
        - type: object
          properties:
            more: {type: string}
`
	_, err = generateMini(t, miniSpecHead+schemas+extended, "models:\n  Created: {as: A}\n")
	wantError(t, err, "hints: models.Created.as: Created folds into its base A, so nothing may extend it, and Later does")
	// A class folding into a folded one extends it too, whichever of the
	// two names sorts first.
	for _, name := range []string{"Later", "Alater"} {
		t.Run("a fold chain through "+name, func(t *testing.T) {
			chain := strings.Replace(extended, "Later:", name+":", 1)
			_, err := generateMini(t, miniSpecHead+schemas+chain, "models:\n  Created: {as: A}\n  Changed: {as: A}\n  "+name+": {as: A}\n")
			wantError(t, err, "hints: models.Created.as: Created folds into its base A, so nothing may extend it, and "+name+" does")
		})
	}
}

// operationId.param lists an inline enum on a parameter.
func TestParameterEnum(t *testing.T) {
	spec := strings.Replace(miniSpecHead, "      tags: [a]\n", `      tags: [a]
      parameters:
        - name: mode
          in: query
          description: Which ones.
          schema:
            type: string
            enum: [latest, in-progress]
        - name: kinds
          in: query
          schema:
            type: array
            items:
              type: string
              enum: [x, y]
        - name: cursor
          in: query
          schema: {type: string}
        - name: kind
          in: query
          schema: {$ref: "#/components/schemas/Kind"}
`, 1) + "    A:\n      type: object\n      properties:\n        x: {type: string}\n" +
		"    Kind:\n      type: string\n      enum: [p, q]\n"
	// An array parameter has no query encoding, so getA is skipped; its
	// enums are the model's alone.
	out, err := generateMini(t, spec, "enums:\n  getA.mode: {as: Mode}\n  getA.kinds: {}\noperations:\n  getA: {skip: true}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out, "/// Which ones.\nenum Mode {\n  latest('latest'),\n  inProgress('in-progress');\n", "enum GetAKinds {\n")
	_, err = generateMini(t, spec, "enums:\n  getA.nope: {}\n")
	wantError(t, err, "hints: enums.getA.nope: getA has no parameter nope")
	_, err = generateMini(t, spec, "enums:\n  getA.cursor: {}\n")
	wantError(t, err, "hints: enums.getA.cursor: getA.cursor carries no inline enum")
	_, err = generateMini(t, spec, "enums:\n  getA.kind: {}\n")
	wantError(t, err, "hints: enums.getA.kind: getA.kind is a $ref to Kind; list Kind itself")
}

// convert: base64Text keeps a format byte string as its text.
func TestBase64Text(t *testing.T) {
	out, err := generateMini(t, miniSpecHead+"    A:\n      type: object\n      properties:\n        x: {type: string, format: byte}\n",
		"models:\n  A:\n    fields:\n      x: {convert: base64Text}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out, "  final String? x;\n", "x: readOptional(json, 'x', type, wireString),\n", "'x': ?value.x,\n")
	if strings.Contains(out, "Uint8List") || strings.Contains(out, "dart:typed_data") {
		t.Error("base64Text left the bytes type in")
	}
}

// A string of format uri-reference, the spec's origin-relative URL,
// decodes resolved against the client's base wherever it sits.
func TestOriginRelativeURLs(t *testing.T) {
	out, err := generateMini(t, miniSpecHead+`    A:
      type: object
      required: [art]
      properties:
        art: {type: string, format: uri-reference}
        arts:
          type: array
          items: {type: string, format: uri-reference}
        maybe: {type: string, format: uri-reference}
        plain: {type: string}
`, "models:\n  A:\n    fields:\n      maybe: {emptyAsNull: true}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out,
		"  /// Arrives resolved against the client's base URL.\n  final String art;\n",
		"art: readRequired(json, 'art', type, (v, at) => resolveMediaUrl(ctx.baseUrl, wireString(v, at))),\n",
		"arts: readOptional(json, 'arts', type, (v, at) => wireList(v, at, (e, at) => resolveMediaUrl(ctx.baseUrl, wireString(e, at)))),\n",
		"maybe: readOptional(json, 'maybe', type, (v, at) => switch (wireNonEmpty(v, at)) {\n      final s? => resolveMediaUrl(ctx.baseUrl, s),\n",
		"plain: readOptional(json, 'plain', type, wireString),\n",
		"'art': value.art,\n",
	)
}

// omitDefault leaves out a field holding its default, and omitEmpty an
// object that encodes no field.
func TestOmitDefault(t *testing.T) {
	const schemas = `    A:
      type: object
      required: [id]
      properties:
        id: {type: string}
        n: {type: integer, default: 0}
        ratio: {type: number, default: 0.4}
        flag: {type: boolean, default: false}
        lock: {type: boolean, default: true}
        mode: {type: string, enum: [trash, permanent], default: trash}
        kind: {$ref: "#/components/schemas/Kind"}
        label: {type: string}
        tags:
          type: array
          default: []
          items: {type: string}
        more:
          type: array
          default: [x]
          items: {type: string}
        sets:
          type: object
          additionalProperties: {type: string}
        filter: {$ref: "#/components/schemas/F"}
        shape: {$ref: "#/components/schemas/F"}
    F:
      type: object
      properties:
        include:
          type: array
          items: {type: string}
    Kind:
      type: string
      enum: [up, down]
`
	const fields = "      n: {omitDefault: true}\n      ratio: {omitDefault: true}\n      flag: {omitDefault: true}\n" +
		"      lock: {omitDefault: true}\n      mode: {omitDefault: true}\n      kind: {default: up, omitDefault: true}\n" +
		"      label: {default: '', omitDefault: true}\n      tags: {omitDefault: true}\n" +
		"      sets: {default: {}, omitDefault: true}\n      filter: {omitEmpty: true}\n      shape: {default: {}, omitEmpty: true}\n"
	out, err := generateMini(t, miniSpecHead+schemas,
		"enums:\n  Kind: {}\nmodels:\n  A:\n    fields:\n"+fields+"  F:\n    fields:\n      include: {omitEmpty: true}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out,
		"  if (value.n != 0) 'n': value.n,\n",
		"  if (value.ratio != 0.4) 'ratio': value.ratio,\n",
		"  if (value.flag) 'flag': value.flag,\n",
		"  if (!value.lock) 'lock': value.lock,\n",
		"  if (value.mode != 'trash') 'mode': value.mode,\n",
		"  if (value.kind != Kind.up) 'kind': value.kind.wireName,\n",
		"  if (value.label != '') 'label': value.label,\n",
		"  if (value.tags.isNotEmpty) 'tags': value.tags,\n",
		"  'more': value.more,\n",
		"  if (value.sets.isNotEmpty) 'sets': value.sets,\n",
		"  if (value.filter case final v?)\n    if (encodeF(v) case final e when e.isNotEmpty) 'filter': e,\n",
		"  if (encodeF(value.shape) case final e when e.isNotEmpty) 'shape': e,\n",
		// Decode keeps the default for an absent field.
		"n: readOptional(json, 'n', type, wireInt) ?? 0,\n",
	)
	for _, c := range []struct{ name, field, want string }{
		{"a required field", "id: {omitDefault: true}", "hints: models.A.fields.id.omitDefault: A.id is required, so it is always sent"},
		{"no default", "label: {omitDefault: true}", "hints: models.A.fields.label.omitDefault: A.label has no default to leave out"},
		{"an object default", "shape: {default: {}, omitDefault: true}", "hints: models.A.fields.shape.omitDefault: A.shape defaults to an object, which has no value to compare it with; omitEmpty leaves out an empty one"},
		{"a collection default with entries", "more: {omitDefault: true}", "hints: models.A.fields.more.omitDefault: A.more defaults to a collection with entries, which has no value to compare it with"},
		{"omitEmpty on a scalar", "label: {omitEmpty: true}", "hints: models.A.fields.label.omitEmpty: needs a List or an object, and A.label is String?"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, miniSpecHead+schemas, "enums:\n  Kind: {}\nmodels:\n  A:\n    fields:\n      "+c.field+"\n")
			wantError(t, err, c.want)
		})
	}
	t.Run("omitEmpty on a required field", func(t *testing.T) {
		_, err := generateMini(t, miniSpecHead+strings.Replace(schemas, "required: [id]", "required: [id, tags, filter]", 1),
			"models:\n  A:\n    fields:\n      tags: {omitEmpty: true}\n      filter: {omitEmpty: true}\n")
		wantError(t, err, "hints: models.A.fields.tags.omitEmpty: A.tags is required, so it is always sent")
		wantError(t, err, "hints: models.A.fields.filter.omitEmpty: A.filter is required, so it is always sent")
	})
}

// serverDefault leaves an optional property's spec default to the
// server: the field is nullable, and a method's null is not sent.
func TestServerDefault(t *testing.T) {
	const spec = `openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: postA
      tags: [a]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/A"}
      responses:
        "204": {description: done}
components:
  schemas:
    A:
      type: object
      required: [id]
      properties:
        id: {type: string, default: x}
        ratio: {type: number, default: 0.4}
        label: {type: string}
`
	out, err := generateMini(t, spec, "models:\n  A:\n    fields:\n      ratio: {serverDefault: true}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out,
		"  final double? ratio;\n",
		"ratio: readOptional(json, 'ratio', type, wireDouble),\n",
		"  'ratio': ?value.ratio,\n",
		"    double? ratio,\n",
		"        ratio: ratio,\n",
	)
	if strings.Contains(out, "0.4") {
		t.Error("the spec default reached the client")
	}
	for _, c := range []struct{ name, hints, want string }{
		{"no spec default", "label: {serverDefault: true}", "hints: models.A.fields.label.serverDefault: A.label has no spec default"},
		{"a required property", "id: {serverDefault: true}", "hints: models.A.fields.id.serverDefault: A.id is required, so it is always sent"},
		{"a client default beside it", "ratio: {serverDefault: true, default: 0.5}", "hints: models.A.fields.ratio.serverDefault: the default is the server's; drop default"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, spec, "models:\n  A:\n    fields:\n      "+c.hints+"\n")
			wantError(t, err, c.want)
		})
	}
}

// A class declaring a nullable nextCursor gets hasMore from the
// generator, in an extension exported beside it. A subclass reads its
// base's, and a class whose more says whether more follows, or whose
// cursor is always there, gets none.
func TestPagingExtension(t *testing.T) {
	const schemas = `    A:
      type: object
      properties:
        pages:
          type: array
          items: {$ref: "#/components/schemas/Page"}
        sub: {$ref: "#/components/schemas/SubPage"}
        sync: {$ref: "#/components/schemas/Sync"}
        always: {$ref: "#/components/schemas/Always"}
    Page:
      type: object
      properties:
        nextCursor: {type: string}
    SubPage:
      allOf:
        - $ref: "#/components/schemas/Page"
        - type: object
          properties:
            extra: {type: string}
    Sync:
      type: object
      properties:
        nextCursor: {type: string}
        more: {type: boolean}
    Always:
      type: object
      required: [nextCursor]
      properties:
        nextCursor: {type: string}
`
	files, err := generate(writeTemp(t, "spec.yaml", miniSpecHead+schemas), writeTemp(t, "hints.yaml", ""), "")
	if err != nil {
		t.Fatal(err)
	}
	model := string(files["models/a.g.dart"])
	wantContains(t, model, "\n/// Keyset paging over [Page].\nextension PagePaging on Page {\n"+
		"  /// Whether [nextCursor] names a next page.\n  bool get hasMore => nextCursor != null;\n}\n")
	for _, none := range []string{"on SubPage", "on Sync", "on Always"} {
		if strings.Contains(model, none) {
			t.Errorf("an extension %s was generated", none)
		}
	}
	wantContains(t, string(files[publicFile]), " show A, Always, Page, PagePaging, SubPage, Sync;\n")

	clash := strings.Replace(schemas, "        nextCursor: {type: string}\n    SubPage:", "        nextCursor: {type: string}\n        hasMore: {type: boolean}\n    SubPage:", 1)
	_, err = generateMini(t, miniSpecHead+clash, "")
	wantError(t, err, "spec: Page.hasMore makes the field hasMore, which the generated PagePaging declares; rename it with models.Page.fields.hasMore.as")
}

// Paging reads the spec's properties, whatever the hints name their
// fields: a renamed cursor still pages, and a renamed more still says so
// itself.
func TestPagingFollowsTheSpecProperties(t *testing.T) {
	const schemas = `    A:
      type: object
      properties:
        renamed: {$ref: "#/components/schemas/Renamed"}
        stated: {$ref: "#/components/schemas/Stated"}
    Renamed:
      type: object
      properties:
        nextCursor: {type: string}
    Stated:
      type: object
      properties:
        nextCursor: {type: string}
        more: {type: boolean}
`
	out, err := generateMini(t, miniSpecHead+schemas,
		"models:\n  Renamed:\n    fields:\n      nextCursor: {as: cursor}\n  Stated:\n    fields:\n      more: {as: hasNext}\n")
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out, "extension RenamedPaging on Renamed {\n  /// Whether [cursor] names a next page.\n  bool get hasMore => cursor != null;\n}\n")
	if strings.Contains(out, "on Stated") {
		t.Error("a page stating its own more got a generated hasMore")
	}
}

// skip leaves a schema's class out of the output; whatever generated
// class or call would still need it fails the run, naming it.
func TestSkippedSchema(t *testing.T) {
	const schemas = `    A:
      type: object
      properties:
        refusal: {$ref: "#/components/schemas/Error"}
    Error:
      type: object
      required: [code, message]
      properties:
        code: {type: string}
        message: {type: string}
`
	const skip = "models:\n  Error: {skip: true}\n"
	const converted = "  A:\n    fields:\n      refusal: {convert: apiError}\n"
	out, err := generateMini(t, miniSpecHead+schemas, skip+converted)
	if err != nil {
		t.Fatal(err)
	}
	wantContains(t, out, "  final WaxDeckApiException? refusal;\n")
	for _, gone := range []string{"class Error", "decodeError", "encodeError"} {
		if strings.Contains(out, gone) {
			t.Errorf("a skipped schema left %q behind", gone)
		}
	}
	answer := func(schema string) string {
		return strings.Replace(miniSpecHead, `$ref: "#/components/schemas/A"`, schema, 1)
	}
	const sent = `openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: postA
      tags: [a]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/Error"}
      responses:
        "204": {description: done}
components:
  schemas:
`
	const handHolder = "    B:\n      type: object\n      properties:\n        errors:\n          type: array\n          items: {$ref: \"#/components/schemas/Error\"}\n"
	for _, c := range []struct{ name, spec, hints, want string }{
		{"a field holding it", miniSpecHead + schemas, skip, "hints: models.Error.skip: A.refusal needs it"},
		{"a list holding it", miniSpecHead + schemas + "    B:\n      type: object\n      properties:\n        errors:\n          type: array\n          items: {$ref: \"#/components/schemas/Error\"}\n",
			skip + converted, "hints: models.Error.skip: B.errors needs it"},
		{"a class extending it", miniSpecHead + schemas + "    S:\n      allOf:\n        - $ref: \"#/components/schemas/Error\"\n        - type: object\n          properties:\n            extra: {type: string}\n",
			skip + converted, "hints: models.Error.skip: S extends it"},
		{"a call answering it", answer(`$ref: "#/components/schemas/Error"`) + schemas, skip + converted, "hints: models.Error.skip: getA needs it"},
		{"a call sending it", sent + schemas, skip + converted, "hints: models.Error.skip: postA needs it"},
		{"a hand class extending it", miniSpecHead + schemas + "    S:\n      allOf:\n        - $ref: \"#/components/schemas/Error\"\n        - type: object\n          properties:\n            extra: {type: string}\n",
			skip + converted + "hand:\n  S: {covers: [code, message, extra]}\n", "hints: models.Error.skip: S extends it"},
		{"a hand class covering a property holding it", miniSpecHead + schemas + handHolder,
			skip + converted + "hand:\n  B: {covers: [errors]}\n", "hints: models.Error.skip: B.errors needs it"},
		{"another key beside it", miniSpecHead + schemas, "models:\n  Error: {skip: true, as: ApiError}\n" + converted,
			"hints: models.Error: Error is skipped, so no other key applies"},
		{"a hand schema", miniSpecHead + schemas, skip + converted + "hand:\n  Error: {covers: [code, message]}\n",
			"hints: models.Error: Error is hand-written, so only as applies"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, err := generateMini(t, c.spec, c.hints)
			wantError(t, err, c.want)
		})
	}
	// A hand class that ignores the property needs nothing of the class.
	if _, err := generateMini(t, miniSpecHead+schemas+handHolder, skip+converted+"hand:\n  B: {ignores: [errors]}\n"); err != nil {
		t.Errorf("a hand class ignoring a property holding a skipped schema: %v", err)
	}
}
