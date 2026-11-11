package main

import (
	"slices"
	"strings"
	"testing"
)

// The hand extensions' members on a generated class are read from
// model_extensions.dart itself: no generated field may take one's name,
// none may repeat the generated hasMore, and a copyWith takes every field
// of its class, an inherited one too, so a field the contract adds cannot
// be copied away.
func TestExtensionsHoldToTheModel(t *testing.T) {
	const schemas = `    A:
      type: object
      required: [x]
      properties:
        x: {type: string}
        y: {type: integer}
        b: {$ref: "#/components/schemas/B"}
    B:
      type: object
      properties:
        id: {type: string}
    C:
      allOf:
        - $ref: "#/components/schemas/B"
        - type: object
          properties:
            z: {type: string}
    P:
      type: object
      properties:
        nextCursor: {type: string}
`
	const ax = `extension AX on A {
  String get label => x;

  A copyWith({String? x, int? Function()? y, B? b, bool clearB = false}) =>
      A(x: x ?? this.x, y: y == null ? this.y : y(), b: clearB ? null : (b ?? this.b));
}
`
	const cx = `
extension CX on C {
  C copyWith({String? id, String? z}) => C(id: id ?? this.id, z: z ?? this.z);
}

extension StringX on String {
  bool get blank => trim().isEmpty;
}
`
	check := func(t *testing.T, src string) (string, error) {
		t.Helper()
		ext := writeTemp(t, "model_extensions.dart", src)
		_, err := generate(writeTemp(t, "spec.yaml", miniSpecHead+schemas), writeTemp(t, "hints.yaml", ""), ext)
		return ext, err
	}
	if _, err := check(t, ax+cx); err != nil {
		t.Errorf("extensions holding to the model: %v", err)
	}
	block := strings.Replace(cx, "=> C(id: id ?? this.id, z: z ?? this.z);", "{\n    final copy = C(id: id ?? this.id, z: z ?? this.z);\n    return copy;\n  }", 1)
	if _, err := check(t, ax+block); err != nil {
		t.Errorf("a block-bodied copyWith: %v", err)
	}
	// The constructor the copyWith returns is the copy, whatever else it
	// builds, and an import prefix does not hide it.
	const params = "{String? x, int? Function()? y, B? b, bool clearB = false}"
	const built = "A(x: x ?? this.x, y: y == null ? this.y : y(), b: clearB ? null : (b ?? this.b))"
	earlier := "extension AX on A {\n  A copyWith(" + params + ") {\n    final blank = A(x: '');\n    return " + built + ";\n  }\n}\n"
	if _, err := check(t, earlier+cx); err != nil {
		t.Errorf("a copyWith building another A before the copy: %v", err)
	}
	// A local set in a nested block is no top-level initializer; the first
	// call stands.
	branched := "extension AX on A {\n  A copyWith(" + params + ") {\n    final A copy;\n    if (clearB) {\n      copy = A(x: x ?? this.x, y: y == null ? this.y : y(), b: null);\n" +
		"    } else {\n      copy = " + built + ";\n    }\n    return copy;\n  }\n}\n"
	if _, err := check(t, branched+cx); err != nil {
		t.Errorf("a copyWith returning a local set in branches: %v", err)
	}
	prefixed := "extension AX on m.A {\n  m.A copyWith(" + params + ") =>\n      m." + built + ";\n}\n"
	if _, err := check(t, prefixed+cx); err != nil {
		t.Errorf("a copyWith on a prefixed class: %v", err)
	}
	// No generated field takes a private name, so a helper takes none.
	private := strings.Replace(ax, "  String get label => x;", "  String get label => _label;\n\n  String get _label => x;", 1)
	if _, err := check(t, private+cx); err != nil {
		t.Errorf("an extension with a private helper: %v", err)
	}
	for _, c := range []struct{ name, src, want string }{
		{"a copyWith without a field", strings.Replace(ax, " int? Function()? y,", "", 1) + cx,
			"extensions: copyWith in extension AX on A in %s has no parameter y, so a copy loses that field of A"},
		{"a copyWith without an inherited field", ax + strings.Replace(cx, "String? id, ", "", 1),
			"extensions: copyWith in extension CX on C in %s has no parameter id, so a copy loses that field of C"},
		{"a member a field takes", ax + cx + "\nextension AY on A {\n  int get y => 0;\n}\n",
			"extensions: extension AY on A in %s declares y, which is a generated field of A (A.y)"},
		{"a member a subclass field takes", ax + cx + "\nextension on B {\n  String get z => '';\n}\n",
			"extensions: an unnamed extension on B in %s declares z, which is a generated field of C (C.z)"},
		{"a member a base field takes", ax + cx + "\nextension CY on C {\n  String get id => '';\n}\n",
			"extensions: extension CY on C in %s declares id, which is a generated field of B (B.id)"},
		{"a hasMore the generator writes", ax + cx + "\nextension PX on P {\n  bool get hasMore => nextCursor != null;\n}\n",
			"extensions: extension PX on P in %s declares hasMore, which the generated PPaging declares; delete it"},
		{"the generated extension's name", ax + cx + "\nextension PPaging on P {\n  bool get done => nextCursor == null;\n}\n",
			"extensions: extension PPaging on P in %s takes the name of the generated extension on P"},
		{"a copyWith dropping a field's forward", strings.Replace(ax, " y: y == null ? this.y : y(),", "", 1) + cx,
			"extensions: copyWith in extension AX on A in %s builds A without y, so a copy loses that field"},
		{"a copyWith dropping an inherited field's forward", ax + strings.Replace(cx, "id: id ?? this.id, ", "", 1),
			"extensions: copyWith in extension CX on C in %s builds C without id, so a copy loses that field"},
		{"a copyWith building no copy", ax + strings.Replace(cx, "=> C(id: id ?? this.id, z: z ?? this.z);", "=> this;", 1),
			"extensions: copyWith in extension CX on C in %s calls no C constructor, so nothing shows it copies every field"},
		{"a member after a block-bodied operator", ax + cx + "\nextension AZ on A {\n  void operator []=(int i, String v) {\n    print(v);\n  }\n\n  int get y => 0;\n}\n",
			"extensions: extension AZ on A in %s declares y, which is a generated field of A (A.y)"},
		{"a member on the nullable class", ax + cx + "\nextension AQ on A? {\n  int get y => 0;\n}\n",
			"extensions: extension AQ on A in %s declares y, which is a generated field of A (A.y)"},
		{"a copyWith dropping a field its returned call lacks",
			"extension AX on A {\n  A copyWith(" + params + ") {\n    final full = A(x: '', y: 1, b: null);\n    return A(x: x ?? this.x, b: b ?? this.b);\n  }\n}\n" + cx,
			"extensions: copyWith in extension AX on A in %s builds A without y, so a copy loses that field"},
		{"a member of an unnamed generic extension", ax + cx + "\nextension<T> on A {\n  int get y => 0;\n}\n",
			"extensions: an unnamed extension on A in %s declares y, which is a generated field of A (A.y)"},
		{"a member of an extension with a nested bound", ax + cx + "\nextension AB<T extends Map<String, int>> on A {\n  int get y => 0;\n}\n",
			"extensions: extension AB on A in %s declares y, which is a generated field of A (A.y)"},
	} {
		t.Run(c.name, func(t *testing.T) {
			ext, err := check(t, c.src)
			wantError(t, err, strings.ReplaceAll(c.want, "%s", ext))
		})
	}
}

func TestParseExtensions(t *testing.T) {
	const src = `/// Members derived from a model's fields { not a brace }.
library;

import 'models.dart';

// extension Commented on A { bool get nope => true; }
const decoy = 'extension Fake on A {';

extension AX on A {
  /// A doc comment with a { and an extension on B { word.
  bool get ok => x == 'a}{';

  String get label {
    return x ?? '';
  }

  bool get ended => switch (x) {
    'done' || 'failed' => true,
    _ => false,
  };

  static const table = {'k': 1};

  static A empty() => const A();

  set nothing(String value) {}

  T pick<T>(T a) => a;

  @Deprecated('use label')
  String get old => x;

  @visibleForTesting (int, int) get pair => (1, 2);

  Future<int> fetch() async => 1;

  bool get notasync => true;

  bool get _hidden => true;

  String get link => '${x ?? 'http://x'}';

  bool get afterLink => true;

  String get paren => "${x ?? "("} ${{'k': '}'}['k']}";

  bool get afterParen => _hidden;

  A copyWith({
    String? x,
    Map<String, List<int>>? nested,
    int? Function()? lazy,
    bool clear = false,
    Map<String, int> weights = const {'a': 1, 'b': 2},
    void onDone(int code)?,
  }) => A(x: x ?? this.x);

  A operator +(A other) => this;
}

extension on B {
  int get twice => y * 2;
}

class NotAnExtension {
  void f() {}
}

extension Generic<T> on List<T> {
  T? get firstOrNone => isEmpty ? null : first;
}

extension Indexed on A {
  void operator []=(int i, String v) {
    print(v);
  }

  bool get ready => x == 'a';

  bool operator ==(Object other) => false;

  bool get afterEquals => true;
}

extension Maybe on m.A? {
  String get orEmpty => this?.x ?? '';
}

extension Bounded<T extends Map<String, List<int>>> on A {
  int get total => 1;
}

extension<T> on A {
  int get doubled => 2;
}

extension<T extends Map<String, List<int>>> on List<T> {
  int get count => 3;
}
`
	got := parseExtensions(src)
	want := []extension{
		{name: "AX", on: "A", members: []string{"ok", "label", "ended", "nothing", "pick", "old", "pair", "fetch", "notasync",
			"link", "afterLink", "paren", "afterParen", "copyWith"},
			copyWith: []string{"x", "nested", "lazy", "clear", "weights", "onDone"}},
		{on: "B", members: []string{"twice"}},
		{name: "Generic", on: "List<T>", members: []string{"firstOrNone"}},
		{name: "Indexed", on: "A", members: []string{"ready", "afterEquals"}},
		{name: "Maybe", on: "A", members: []string{"orEmpty"}},
		{name: "Bounded", on: "A", members: []string{"total"}},
		{on: "A", members: []string{"doubled"}},
		{on: "List<T>", members: []string{"count"}},
	}
	if len(got) != len(want) {
		t.Fatalf("parsed %d extensions, want %d: %+v", len(got), len(want), got)
	}
	for i, w := range want {
		g := got[i]
		if g.name != w.name || g.on != w.on || !slices.Equal(g.members, w.members) || !slices.Equal(g.copyWith, w.copyWith) {
			t.Errorf("extension %d:\n got %+v\nwant %+v", i, g, w)
		}
	}
}

// A constructor's initializer list ends where its body opens: a { after an
// expression's end (a postfix !, ++ or --, or the > closing a type's
// arguments) opens it, a { starting a literal (typed or not) does not, so
// the next member keeps its own name.
func TestMembersEndAtTheirBodies(t *testing.T) {
	const body = `
  Posted(int a) : _b = a! {
    run();
  }

  int get afterBang => 1;

  Cast(Object y) : x = y as Map<String, List<int>> {
    run();
  }

  int get afterCast => 2;

  Counted(int j) : i = j++ {
    run();
  }

  int get afterCount => 3;

  Down(int j) : i = j-- {
    run();
  }

  int get afterDown => 4;

  const Literal(int a)
    : m = <String, int>{'a': 1},
      s = const <int>{1, 2},
      t = a > 1 ? {1} : {2},
      u = a != 1 ? {} : {a + 1},
      f = (() => {a}),
      h = () => {a},
      g = (a - 1) {
    run();
  }

  int get afterLiteral => 5;

  Spaced(int a) : n = a ! {
    run();
  }

  int get afterSpaced => 6;
`
	var got []string
	for _, mem := range members(body) {
		got = append(got, mem.name)
	}
	want := []string{"Posted", "afterBang", "Cast", "afterCast", "Counted", "afterCount", "Down", "afterDown",
		"Literal", "afterLiteral", "Spaced", "afterSpaced"}
	if !slices.Equal(got, want) {
		t.Errorf("members read as\n got %v\nwant %v", got, want)
	}
}
