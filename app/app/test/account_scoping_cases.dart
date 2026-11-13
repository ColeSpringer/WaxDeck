import 'package:flutter_test/flutter_test.dart';

import 'account_scoping_fixtures.dart';
import 'analysis_host.dart';

/// The scan's rule, case by case, on fixture libraries laid over the
/// package of the host [host] returns.
void accountScopingCases(AnalysisHost Function() host) {
  final fixtures = ScanFixtures(host);

  group('which providers', () {
    test('every top-level variable of a provider type, whatever its name, '
        'declared type or family', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
final lists = FutureProvider<Object>((ref) => $read);

final FutureProvider<Object> typedProvider = FutureProvider((ref) => $read);

late final lateProvider = FutureProvider<Object>((ref) => $read);

final firstProvider = FutureProvider<Object>((ref) => $read),
    secondProvider = FutureProvider<Object>((ref) => $read);

final familyProvider = FutureProvider.family<Object, int>(
  (ref, id) => $read,
);

final streamProvider = StreamProvider<Object>(
  (ref) => Stream.fromFuture($read),
);
''',
        }),
        [
          unkeyed('lists'),
          unkeyed('typedProvider'),
          unkeyed('lateProvider'),
          unkeyed('firstProvider'),
          unkeyed('secondProvider'),
          unkeyed('familyProvider'),
          unkeyed('streamProvider'),
        ],
      );
    });

    test(
      'not a variable of another type, nor a provider a class holds',
      () async {
        expect(
          await fixtures.scan({
            'a.dart':
                '''
final reader = (Ref ref) => $read;

final readers = [FutureProvider<Object>((ref) => $read)];

class Holder {
  static final heldProvider = FutureProvider<Object>((ref) => $read);
}
''',
          }),
          isEmpty,
        );
      },
    );

    test('a provider created through autoDispose, in every spelling, is not '
        'kept alive', () async {
      expect(
        await fixtures.scan({
          'b.dart':
              '''
class Lists extends AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

class Item extends AsyncNotifier<Object> {
  Item(this.id);
  final int id;

  @override
  Future<Object> build() => $read;
}

class Count extends Notifier<int> {
  @override
  int build() {
    $read;
    return 0;
  }
}
''',
          'a.dart':
              '''
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;

import 'b.dart';

final aProvider = FutureProvider.autoDispose<Object>((ref) => $read);
final bProvider = FutureProvider.autoDispose.family<Object, int>(
  (ref, id) => $read,
);
final cProvider = FutureProvider.family.autoDispose<Object, int>(
  (ref, id) => $read,
);
final dProvider = FutureProvider<Object>((ref) => $read, isAutoDispose: true);
final eProvider = FutureProvider.family<Object, int>(
  (ref, id) => $read,
  isAutoDispose: true,
);
final fProvider = Provider.autoDispose<Object>((ref) => $read);
final gProvider = StreamProvider.autoDispose<Object>(
  (ref) => Stream.fromFuture($read),
);
final hProvider = AsyncNotifierProvider.autoDispose<Lists, Object>(Lists.new);
final iProvider = AsyncNotifierProvider.autoDispose.family<Item, Object, int>(
  Item.new,
);
final jProvider = NotifierProvider.autoDispose<Count, int>(Count.new);
final kProvider = rp.FutureProvider.autoDispose<Object>((ref) => $read);
final lProvider = AsyncNotifierProvider<Lists, Object>(
  Lists.new,
  isAutoDispose: true,
);
''',
        }),
        isEmpty,
      );
    });

    test('an autoDispose provider whose build can keep it alive is kept '
        'alive', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
void _hold(Ref ref) => ref.keepAlive();

final heldProvider = FutureProvider.autoDispose<Object>((ref) {
  ref.keepAlive();
  return $read;
});
final helperProvider = FutureProvider.autoDispose<Object>((ref) {
  _hold(ref);
  return $read;
});
final freeProvider = FutureProvider.autoDispose<Object>((ref) => $read);
''',
        }),
        [unkeyed('heldProvider'), unkeyed('helperProvider')],
      );
    });

    test('the word autoDispose anywhere else keeps a provider alive', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
const autoDispose = true;

void log(String message) {}

int autoDisposeCount() => 0;

// A comment saying autoDispose.
final aProvider = FutureProvider<Object>((ref) {
  log('not autoDispose');
  autoDisposeCount();
  return $read;
});

final bProvider = FutureProvider<Object>(
  (ref) => $read,
  isAutoDispose: autoDispose,
);

final cProvider = FutureProvider<Object>((ref) => $read, isAutoDispose: false);
''',
          'b.dart':
              '''
import 'package:flutter_riverpod/flutter_riverpod.dart' as autoDispose;

final dProvider = autoDispose.FutureProvider.family<Object, int>(
  (ref, id) => $read,
);
''',
        }),
        [
          unkeyed('aProvider'),
          unkeyed('bProvider'),
          unkeyed('cProvider'),
          unkeyed('dProvider', file: 'b.dart'),
        ],
      );
    });

    test('a provider under lib/src/l10n is scanned', () async {
      expect(
        await fixtures.scan({
          'scan_fixture.dart':
              'final countProvider = '
              'FutureProvider<Object>((ref) => $read);',
        }, dir: 'lib/src/l10n'),
        [unkeyed('countProvider', file: 'scan_fixture.dart')],
      );
    });

    test('generated files are not', () async {
      expect(
        await fixtures.scan({
          'scan_fixture.dart':
              'final countProvider = '
              'FutureProvider<Object>((ref) => $read);',
        }, dir: 'lib/src/l10n/gen'),
        isEmpty,
      );
      expect(
        await fixtures.scan({
          'a.g.dart':
              'final countProvider = '
              'FutureProvider<Object>((ref) => $read);',
        }),
        isEmpty,
      );
    });

    test('a part in a subdirectory is scanned as its own file', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
part 'parts/b.dart';

Future<Object> _load(Ref ref) => $read;
''',
          'parts/b.dart': '''
part of '../a.dart';

final countProvider = FutureProvider<Object>(_load);
''',
        }),
        [unkeyed('countProvider', file: 'parts/b.dart')],
      );
    });

    test(
      'an exemption hides a breach, and goes stale when nothing needs it',
      () async {
        expect(
          await fixtures.scan(
            {
              'a.dart':
                  '''
final countProvider = FutureProvider<Object>((ref) => $read);

final keyedProvider = FutureProvider<Object>((ref) {
  $watch;
  return $read;
});
''',
            },
            exempt: {'countProvider', 'keyedProvider', 'goneProvider'},
          ),
          [
            'keyedProvider is exempt, but it is not a kept-alive provider that '
                'reads the repository unkeyed (any more): drop the entry',
            'goneProvider is exempt, but it is not a kept-alive provider that '
                'reads the repository unkeyed (any more): drop the entry',
          ],
        );
      },
    );

    test('an exempt provider whose build the scan cannot determine has that '
        'line only', () async {
      expect(
        await fixtures.scan(
          {
            'a.dart':
                '''
final _make = (Ref ref) => $read;

final variableProvider = FutureProvider<Object>(_make);
''',
          },
          exempt: {'variableProvider'},
        ),
        [undetermined('variableProvider')],
      );
    });

    test('an exemption fails when more than one library declares a provider '
        'of its name', () async {
      const source =
          'final countProvider = FutureProvider<Object>((ref) => $read);';
      expect(
        await fixtures.scan(
          {'a.dart': source, 'b.dart': source},
          exempt: {'countProvider'},
        ),
        [
          'countProvider is exempt, but more than one library declares a '
              'provider of that name (a.dart, b.dart): an entry covers one '
              'provider',
        ],
      );
    });

    test('a library that does not compile fails on its first error', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              'final countProvider = FutureProvider<Object>((ref) => missing);',
        }, compiles: false),
        [
          allOf(
            startsWith('a.dart:5: '),
            contains('missing'),
            endsWith('(an audit cannot read code that does not compile)'),
          ),
        ],
      );
    });
  });

  group('what build is', () {
    test('a function provider\'s closure or the function it names', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
Future<Object> loadCount(Ref ref) => $read;

Future<Object> _loadCount(Ref ref) => $read;

class Loader {
  static Future<Object> load(Ref ref) => $read;
}

final calledProvider = FutureProvider<Object>((ref) => loadCount(ref));
final publicProvider = FutureProvider<Object>(loadCount);
final privateProvider = FutureProvider<Object>(_loadCount);
final staticProvider = FutureProvider<Object>(Loader.load);
''',
        }),
        [
          unkeyed('calledProvider'),
          unkeyed('publicProvider'),
          unkeyed('privateProvider'),
          unkeyed('staticProvider'),
        ],
      );
    });

    test(
      'a constructor torn off inside a function provider is not its build',
      () async {
        expect(
          await fixtures.scan({
            'a.dart':
                '''
class Row {
  Row(this.name);
  final String name;
}

final rowsProvider = FutureProvider<List<Row>>((ref) async {
  final fields = await $read;
  return ['\$fields'].map(Row.new).toList();
});
''',
          }),
          [unkeyed('rowsProvider')],
        );
      },
    );

    test('a constructor named as the callback is the build: what constructing '
        'runs', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
class Reads {
  Reads(this.ref) : rows = ref.watch(repositoryProvider).getRuleFields();
  final Ref ref;
  final Future<Object> rows;
}

class Starts {
  Starts(this.ref) {
    $read;
  }
  final Ref ref;
}

class Holds {
  Holds(this.ref);
  final Ref ref;
  late final Future<Object> rows = ref.watch(repositoryProvider).getRuleFields();
}

final readsProvider = Provider<Reads>(Reads.new);
final startsProvider = Provider<Starts>(Starts.new);
final holdsProvider = Provider<Holds>(Holds.new);
''',
        }),
        [
          unkeyed('readsProvider'),
          unkeyed('startsProvider'),
          unkeyed('holdsProvider'),
        ],
      );
    });

    test(
      'a provider whose callback or creation the scan cannot read fails',
      () async {
        expect(
          await fixtures.scan({
            'a.dart':
                '''
final _make = (Ref ref) => $read;

FutureProvider<Object> make() => FutureProvider((ref) => $read);

final variableProvider = FutureProvider<Object>(_make);
final helperProvider = make();
final aliasProvider = variableProvider;

FutureProvider<Object> wrap(Future<Object> Function(Ref) create) =>
    FutureProvider(create);

final wrappedProvider = wrap((ref) => $read);
''',
          }),
          [
            undetermined('variableProvider'),
            undetermined('helperProvider'),
            undetermined('aliasProvider'),
            undetermined('wrappedProvider'),
          ],
        );
      },
    );

    test('a notifier is the class its callback constructs', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
class Lists extends AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

final tornProvider = AsyncNotifierProvider<Lists, Object>(Lists.new);
final arrowProvider = AsyncNotifierProvider<Lists, Object>(() => Lists());
final blockProvider = AsyncNotifierProvider<Lists, Object>(() {
  return Lists();
});
''',
        }),
        [
          unkeyed('tornProvider'),
          unkeyed('arrowProvider'),
          unkeyed('blockProvider'),
        ],
      );
    });

    test(
      'a constructor torn off in a notifier\'s arguments is not the notifier',
      () async {
        expect(
          await fixtures.scan({
            'a.dart':
                '''
class Row {
  Row(this.name);
  final String name;
}

class Lists extends AsyncNotifier<Object> {
  Lists(this.make);
  final Row Function(String) make;

  @override
  Future<Object> build() => $read;
}

final listsProvider = AsyncNotifierProvider<Lists, Object>(
  () => Lists(Row.new),
);
''',
          }),
          [unkeyed('listsProvider')],
        );
      },
    );

    test('the constructed class decides over the type argument', () async {
      const classes =
          '''
class Quiet extends AsyncNotifier<Object> {
  @override
  Future<Object> build() async => 0;
}

class Loud extends Quiet {
  @override
  Future<Object> build() => $read;
}
''';
      expect(
        await fixtures.scan({
          'a.dart':
              '''
$classes
final loudProvider = AsyncNotifierProvider<Quiet, Object>(() => Loud());
final tornProvider = AsyncNotifierProvider<Quiet, Object>(Loud.new);
''',
        }),
        [unkeyed('loudProvider'), unkeyed('tornProvider')],
      );
      expect(
        await fixtures.scan({
          'a.dart':
              '''
$classes
final quietProvider = AsyncNotifierProvider<Quiet, Object>(Quiet.new);
final nestedProvider = AsyncNotifierProvider<Quiet, Object>(() {
  Loud loud() {
    return Loud();
  }

  loud;
  return Quiet();
});
''',
        }),
        isEmpty,
      );
    });

    test('a callback that constructs nothing the scan sees falls back on the '
        'type argument', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
class Lists extends AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

Lists _make() => Lists();

final calledProvider = AsyncNotifierProvider<Lists, Object>(() => _make());
''',
        }),
        [unkeyed('calledProvider')],
      );
    });

    test('a callback that names a function is the class the function\'s '
        'returns create', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
class Quiet extends AsyncNotifier<Object> {
  @override
  Future<Object> build() async => 0;
}

class Loud extends Quiet {
  @override
  Future<Object> build() => $read;
}

Loud _loud() => Loud();

Quiet _held() {
  final loud = Loud();
  return loud;
}

final namedProvider = AsyncNotifierProvider<Quiet, Object>(_loud);
final localProvider = AsyncNotifierProvider<Quiet, Object>(_held);
''',
        }),
        [unkeyed('namedProvider'), unkeyed('localProvider')],
      );
    });

    test('a callback that builds more than one class, or goes through a '
        'factory, fails', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
const loud = true;

class Quiet extends AsyncNotifier<Object> {
  Quiet();
  factory Quiet.pick() => loud ? Loud() : Quiet();

  @override
  Future<Object> build() async => 0;
}

class Loud extends Quiet {
  @override
  Future<Object> build() => $read;
}

final pickedProvider = AsyncNotifierProvider<Quiet, Object>(() {
  if (loud) return Loud();
  return Quiet();
});
final factoryProvider = AsyncNotifierProvider<Quiet, Object>(Quiet.pick);
''',
        }),
        [undetermined('pickedProvider'), undetermined('factoryProvider')],
      );
    });

    test(
      'a redirecting factory constructs the class it redirects to',
      () async {
        expect(
          await fixtures.scan({
            'a.dart':
                '''
abstract class Lists extends AsyncNotifier<Object> {
  Lists();
  factory Lists.real() = _Real;
}

class _Real extends Lists {
  @override
  Future<Object> build() => $read;
}

final listsProvider = AsyncNotifierProvider<Lists, Object>(Lists.real);
''',
          }),
          [unkeyed('listsProvider')],
        );
      },
    );

    test('a class with no concrete build fails', () async {
      expect(
        await fixtures.scan({
          'a.dart': '''
abstract class Lists extends AsyncNotifier<Object> {}

final listsProvider = AsyncNotifierProvider<Lists, Object>(
  () => throw UnimplementedError(),
);
''',
        }),
        [undetermined('listsProvider')],
      );
    });

    test('a build a mixin or a base class supplies', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
mixin Loads on AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

abstract class Base extends AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

class Mixed extends AsyncNotifier<Object> with Loads {}

class Derived extends Base {}

abstract class Restated extends Base {
  @override
  Future<Object> build();
}

class Inherits extends Restated {}

final mixedProvider = AsyncNotifierProvider<Mixed, Object>(Mixed.new);
final derivedProvider = AsyncNotifierProvider<Derived, Object>(Derived.new);
final inheritsProvider = AsyncNotifierProvider<Inherits, Object>(
  Inherits.new,
);
''',
        }),
        [
          unkeyed('mixedProvider'),
          unkeyed('derivedProvider'),
          unkeyed('inheritsProvider'),
        ],
      );
    });

    test('the build a class runs, not one it overrides or one a mixin it '
        'does not apply declares', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
abstract class Base extends AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

mixin Loads on AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

class Quiet extends Base {
  @override
  Future<Object> build() async => 0;
}

class Plain extends AsyncNotifier<Object> {
  @override
  Future<Object> build() async => 0;
}

final quietProvider = AsyncNotifierProvider<Quiet, Object>(Quiet.new);
final plainProvider = AsyncNotifierProvider<Plain, Object>(Plain.new);
''',
        }),
        isEmpty,
      );
    });

    test('a class named through an import prefix, beside a same-named one, '
        'is judged by its own build', () async {
      const loud =
          '''
class Lists extends AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}
''';
      const quiet = '''
class Lists extends AsyncNotifier<Object> {
  @override
  Future<Object> build() async => 0;
}
''';
      expect(
        await fixtures.scan({
          'b.dart': loud,
          'a.dart':
              '''
import 'b.dart' as b;

$quiet
final prefixedProvider = AsyncNotifierProvider<b.Lists, Object>(b.Lists.new);
final localProvider = AsyncNotifierProvider<Lists, Object>(Lists.new);
''',
        }),
        [unkeyed('prefixedProvider')],
      );
      expect(
        await fixtures.scan({
          'b.dart': quiet,
          'a.dart':
              '''
import 'b.dart' as b;

$loud
final prefixedProvider = AsyncNotifierProvider<b.Lists, Object>(
  () => b.Lists(),
);
final localProvider = AsyncNotifierProvider<Lists, Object>(Lists.new);
''',
        }),
        [unkeyed('localProvider')],
      );
    });

    test(
      'a typedef of the notifier class, a generic notifier and a family',
      () async {
        expect(
          await fixtures.scan({
            'a.dart':
                '''
class Lists extends AsyncNotifier<Object> {
  @override
  Future<Object> build() => $read;
}

typedef Aliased = Lists;

class Generic<T extends Object> extends AsyncNotifier<T> {
  @override
  Future<T> build() async => await $read as T;
}

class Item extends AsyncNotifier<Object> {
  Item(this.id);
  final int id;

  @override
  Future<Object> build() => $read;
}

final aliasedProvider = AsyncNotifierProvider<Aliased, Object>(Aliased.new);
final genericProvider = AsyncNotifierProvider<Generic<Object>, Object>(
  Generic<Object>.new,
);
final itemProvider = AsyncNotifierProvider.family<Item, Object, int>(Item.new);
final closureItemProvider = AsyncNotifierProvider.family<Item, Object, int>(
  (id) => Item(id),
);
''',
          }),
          [
            unkeyed('aliasedProvider'),
            unkeyed('genericProvider'),
            unkeyed('itemProvider'),
            unkeyed('closureItemProvider'),
          ],
        );
      },
    );

    test('a sync notifier and a stream notifier', () async {
      expect(
        await fixtures.scan({
          'a.dart':
              '''
class Count extends Notifier<int> {
  @override
  int build() {
    $read;
    return 0;
  }
}

class Rows extends StreamNotifier<Object> {
  @override
  Stream<Object> build() => Stream.fromFuture($read);
}

final countProvider = NotifierProvider<Count, int>(Count.new);
final rowsProvider = StreamNotifierProvider<Rows, Object>(Rows.new);
''',
        }),
        [unkeyed('countProvider'), unkeyed('rowsProvider')],
      );
    });
  });

  group('reads', () {
    // A method that reads, which constructing never calls.
    const service =
        'class Service {\n'
        '  Service(this.ref);\n'
        '  final Ref ref;\n\n'
        '  Future<Object> run() => $read;\n'
        '}\n';
    final through = <String, Map<String, String>>{
      'a closure in the build': {
        'a.dart': lists(build: 'return Future.value(0).then((_) => $read);'),
      },
      'a private and a public method': {
        'a.dart': lists(
          build: '_load();\n    return load();',
          members:
              'Future<Object> _load() => $read;\n\n'
              '  Future<Object> load() => $read;',
        ),
      },
      'a getter': {
        'a.dart': lists(
          build: 'return _rows;',
          members: 'Future<Object> get _rows => $read;',
        ),
      },
      'a setter': {
        'a.dart': lists(
          build: '_rows = 0;\n    return 0;',
          members: 'set _rows(int value) {\n    $read;\n  }',
        ),
      },
      'a tear-off': {
        'a.dart': lists(
          build: 'return [0].map(_load).first;',
          members: 'Future<Object> _load(int _) => $read;',
        ),
      },
      'a field initializer': {
        'a.dart': lists(
          build: 'return _rows;',
          members: 'late final _rows = $read;',
        ),
      },
      'a static method': {
        'a.dart': lists(
          build: 'return _load(ref);',
          members: 'static Future<Object> _load(Ref ref) => $read;',
        ),
      },
      'the constructor of another class': {
        'a.dart': lists(
          before:
              'class Loader {\n'
              '  Loader(Ref ref) : rows = $read;\n'
              '  final Future<Object> rows;\n'
              '}',
          build: 'Loader(ref);\n    return 0;',
        ),
      },
      'a field initializer of a class it constructs': {
        'a.dart': lists(
          before:
              'class Loader {\n'
              '  Loader(this.ref);\n'
              '  final Ref ref;\n'
              '  late final rows = $read;\n'
              '}',
          build: 'Loader(ref);\n    return 0;',
        ),
      },
      'a super call': {
        'a.dart': lists(
          before:
              'abstract class Base extends AsyncNotifier<Object> {\n'
              '  @override\n'
              '  Future<Object> build() => $read;\n'
              '}',
          header: 'Lists extends Base',
          build: 'return super.build();',
        ),
      },
      'a public and a private top-level function': {
        'a.dart': lists(
          before:
              'Future<Object> load(Ref ref) => $read;\n\n'
              'Future<Object> _load(Ref ref) => $read;',
          build: 'load(ref);\n    return _load(ref);',
        ),
      },
      'the initializer of a top-level variable': {
        'a.dart': lists(
          before: 'final _loader = (Ref ref) => $read;',
          build: 'return _loader(ref);',
        ),
      },
      'a public extension member': {
        'a.dart': lists(
          before:
              'extension Loads on Lists {\n  Future<Object> load() => $read;\n}',
          build: 'return load();',
        ),
      },
      'a local function': {
        'a.dart': lists(
          build: 'Future<Object> load() => $read;\n    return load();',
        ),
      },
      'a helper of an applied mixin': {
        'a.dart': lists(
          before:
              'mixin Loads on AsyncNotifier<Object> {\n'
              '  Future<Object> _load() => $read;\n'
              '}',
          header: 'Lists extends AsyncNotifier<Object> with Loads',
          build: 'return _load();',
        ),
      },
      'a helper of a base class': {
        'a.dart': lists(
          before:
              'abstract class Base extends AsyncNotifier<Object> {\n'
              '  Future<Object> _load() => $read;\n'
              '}',
          header: 'Lists extends Base',
          build: 'return _load();',
        ),
      },
      'an operator': {
        'a.dart': lists(
          before:
              'class Rows {\n'
              '  Rows(this.ref);\n'
              '  final Ref ref;\n'
              '  Future<Object> operator +(int _) => $read;\n'
              '}',
          build: 'return Rows(ref) + 1;',
        ),
      },
      'a generic helper': {
        'a.dart': lists(
          build: 'return _load<Object>();',
          members: 'Future<T> _load<T>() async => await $read as T;',
        ),
      },
      'a mixin from another library, through a private function of that '
          'library': {
        'b.dart':
            'mixin Loads on AsyncNotifier<Object> {\n'
            '  Future<Object> load() => _fetch(ref);\n'
            '}\n\n'
            'Future<Object> _fetch(Ref ref) => $read;',
        'a.dart': lists(
          before: "import 'b.dart';",
          header: 'Lists extends AsyncNotifier<Object> with Loads',
          build: 'return load();',
        ),
      },
      'a function a part in a subdirectory declares': {
        'a.dart': lists(
          before: "part 'parts/b.dart';",
          build: 'return _load(ref);',
        ),
        'parts/b.dart':
            "part of '../a.dart';\n\nFuture<Object> _load(Ref ref) => $read;",
      },
      'any member of a class whose constructor is torn off as the callback': {
        'a.dart':
            '$service\nfinal listsProvider = Provider<Service>(Service.new);',
      },
      'any member of a class its closure creates': {
        'a.dart':
            '$service\n'
            'final listsProvider = Provider<Object>((ref) => Service(ref));',
      },
      'any member of a class its closure creates in a cascade': {
        'a.dart':
            '$service\n'
            'final listsProvider = Provider<Object>(\n'
            '  (ref) => Service(ref)..ref,\n'
            ');',
      },
      'any member of a class in a local its closure returns': {
        'a.dart':
            '$service\n'
            'final listsProvider = Provider<Object>((ref) {\n'
            '  final service = Service(ref);\n'
            '  return service;\n'
            '});',
      },
      'any member of a class the function it names creates': {
        'a.dart':
            '$service\n'
            'Service _make(Ref ref) => Service(ref);\n\n'
            'final listsProvider = Provider<Object>(_make);',
      },
      'any member of the class its value type argument names': {
        'a.dart':
            '$service\n'
            'Service _make(Ref ref) => Service(ref);\n\n'
            'final listsProvider = Provider<Service>((ref) => _make(ref));',
      },
      'an override of a member reached on another object': {
        'a.dart': lists(
          before:
              'class Loader {\n'
              '  Loader(this.ref);\n'
              '  final Ref ref;\n\n'
              '  Future<Object> load() async => 0;\n'
              '}\n\n'
              'class Real extends Loader {\n'
              '  Real(super.ref);\n\n'
              '  @override\n'
              '  Future<Object> load() => $read;\n'
              '}\n\n'
              'Loader _loader(Ref ref) => Real(ref);',
          build: 'return _loader(ref).load();',
        ),
      },
      'an implementation of an abstract member reached on another object': {
        'a.dart': lists(
          before:
              'abstract interface class Loader {\n'
              '  Future<Object> load();\n'
              '}\n\n'
              'class Real implements Loader {\n'
              '  Real(this.ref);\n'
              '  final Ref ref;\n\n'
              '  @override\n'
              '  Future<Object> load() => $read;\n'
              '}\n\n'
              'Loader _loader(Ref ref) => Real(ref);',
          build: 'return _loader(ref).load();',
        ),
      },
    };
    for (final MapEntry(key: shape, value: files) in through.entries) {
      test('through $shape', () async {
        expect(await fixtures.scan(files), [unkeyed('listsProvider')]);
      });
    }

    // The base's build calls _load(), which the class overrides.
    String overriding({required String base, required String override}) =>
        '''
abstract class Base extends AsyncNotifier<Object> {
  Future<Object> _load() $base

  @override
  Future<Object> build() => _load();
}

class Lists extends Base {
  @override
  Future<Object> _load() $override
}

final listsProvider = AsyncNotifierProvider<Lists, Object>(Lists.new);
''';
    test('through an override that reads where its base does not', () async {
      expect(
        await fixtures.scan({
          'a.dart': overriding(base: 'async => 0;', override: '=> $read;'),
        }),
        [unkeyed('listsProvider')],
      );
    });

    test(
      'through a base method an abstract restatement does not replace',
      () async {
        expect(
          await fixtures.scan({
            'a.dart':
                '''
abstract class Base extends AsyncNotifier<Object> {
  Future<Object> _load() => $read;

  @override
  Future<Object> build() => _load();
}

abstract class Restated extends Base {
  @override
  Future<Object> _load();
}

class Lists extends Restated {}

final listsProvider = AsyncNotifierProvider<Lists, Object>(Lists.new);
''',
          }),
          [unkeyed('listsProvider')],
        );
      },
    );

    final notThrough = <String, String>{
      'the base method an override replaces': overriding(
        base: '=> $read;',
        override: 'async => 0;',
      ),
      'a comment, a doc comment or a string': lists(
        build: '// repositoryProvider\n    return size;',
        members:
            '/// Reads [repositoryProvider] one day.\n'
            "  String get size => 'repositoryProvider';",
      ),
      'a local named repositoryProvider': lists(
        build: 'final repositoryProvider = 0;\n    return repositoryProvider;',
      ),
      'a same-named provider of its own library': lists(
        before: 'final repositoryProvider = Provider<int>((ref) => 0);',
        build: 'return ref.watch(repositoryProvider);',
      ),
      'a helper nothing calls': lists(
        build: 'return 0;',
        members: 'Future<Object> _load() => $read;',
      ),
      'a member of a class its closure creates but does not return':
          '$service\n'
          'final listsProvider = Provider<int>((ref) {\n'
          '  Service(ref);\n'
          '  return 0;\n'
          '});',
    };
    for (final MapEntry(key: shape, value: source) in notThrough.entries) {
      test('not through $shape', () async {
        expect(await fixtures.scan({'a.dart': source}), isEmpty);
      });
    }

    test(
      'not through another provider it watches, which answers for itself',
      () async {
        expect(
          await fixtures.scan({
            'a.dart': lists(
              before:
                  'final rowsProvider = FutureProvider<Object>((ref) => $read);',
              build: 'return ref.watch(rowsProvider.future);',
            ),
          }),
          [unkeyed('rowsProvider')],
        );
      },
    );
  });

  group('keys', () {
    String reads(String body) => '$body\n    return $read;';

    final masked = <String, Map<String, String>>{
      'only in a listen callback': {
        'a.dart': lists(
          before: clock,
          build: reads('ref.listen(clockProvider, (_, _) => $watch);'),
        ),
      },
      'only in an onDispose callback': {
        'a.dart': lists(build: reads('ref.onDispose(() => $watch);')),
      },
      'only in a then callback': {
        'a.dart': lists(
          build: reads('await Future.value(0).then((_) => $watch);'),
        ),
      },
      'only in a forEach callback': {
        'a.dart': lists(build: reads('[0].forEach((_) => $watch);')),
      },
      'only in a stored closure': {
        'a.dart': lists(build: reads('final key = () => $watch;\n    key();')),
      },
      'only in a helper only a callback calls': {
        'a.dart': lists(
          before: clock,
          build: reads('ref.listen(clockProvider, (_, _) => _key());'),
          members: 'void _key() => $watch;',
        ),
      },
      'only in a mixin helper only a callback calls': {
        'a.dart': lists(
          before:
              '$clock\n\n'
              'mixin Keyed on AsyncNotifier<Object> {\n'
              '  void _key() => $watch;\n'
              '}',
          header: 'Lists extends AsyncNotifier<Object> with Keyed',
          build: reads('ref.listen(clockProvider, (_, _) => _key());'),
        ),
      },
      'only in a late local': {
        'a.dart': lists(build: reads('late final account = $watch;')),
      },
      'only in a late local only a callback reads': {
        'a.dart': lists(
          build: reads(
            'late final account = $watch;\n'
            '    ref.onDispose(() => account);',
          ),
        ),
      },
      'only in a field initializer the build reads': {
        'a.dart': lists(
          build: reads('_account;'),
          members: 'late final _account = $watch;',
        ),
      },
      'only in a method nothing calls': {
        'a.dart': lists(members: 'void _key() => $watch;'),
      },
      'only in a local function nothing calls': {
        'a.dart': lists(build: reads('void key() => $watch;')),
      },
      'only in a method only torn off': {
        'a.dart': lists(
          build: reads('[0].forEach(_key);'),
          members: 'void _key(int _) => $watch;',
        ),
      },
      'only in a different notifier\'s same-named method': {
        'a.dart': lists(
          before:
              'class Other extends AsyncNotifier<Object> {\n'
              '  void _key() => $watch;\n\n'
              '  @override\n'
              '  Future<Object> build() async => _key;\n'
              '}',
          build: reads('_key();'),
          members: 'void _key() {}',
        ),
      },
      'only in a base method the class overrides': {
        'a.dart':
            '''
abstract class Base extends AsyncNotifier<Object> {
  void _key() => $watch;

  @override
  Future<Object> build() {
    _key();
    return $read;
  }
}

class Lists extends Base {
  @override
  void _key() {}
}

final listsProvider = AsyncNotifierProvider<Lists, Object>(Lists.new);
''',
      },
      'only in the mixin a later mixin overrides': {
        'a.dart': lists(
          before:
              'mixin Keyed on AsyncNotifier<Object> {\n'
              '  void _key() => $watch;\n'
              '  void key() => _key();\n'
              '}\n\n'
              'mixin Loose on AsyncNotifier<Object> {\n'
              '  void _key() {}\n'
              '}',
          header: 'Lists extends AsyncNotifier<Object> with Keyed, Loose',
          build: reads('key();'),
        ),
      },
      'only in a setter beside the getter the build reads': {
        'a.dart': lists(
          build: reads('_n;'),
          members: 'int get _n => 0;\n  set _n(int value) => $watch;',
        ),
      },
      'only in a method of another object': {
        'a.dart': lists(
          before:
              'class Keyer extends AsyncNotifier<Object> {\n'
              '  void key() => $watch;\n\n'
              '  @override\n'
              '  Future<Object> build() async => 0;\n'
              '}',
          build: reads('Keyer().key();'),
        ),
      },
      'only in a constructor the build calls': {
        'a.dart': lists(
          before: 'class Keyer {\n  Keyer(Ref ref) {\n    $watch;\n  }\n}',
          build: reads('Keyer(ref);'),
        ),
      },
      'only in a mixin getter a local of its name hides': {
        'a.dart': lists(
          before:
              'mixin Scoped on AsyncNotifier<Object> {\n'
              '  String? get account => $watch;\n'
              '}',
          header: 'Lists extends AsyncNotifier<Object> with Scoped',
          build: reads(
            'final account = ref.read(signedInAccountProvider);\n'
            '    account;',
          ),
        ),
      },
      'only in a method a listener parameter is named like': {
        'a.dart': lists(
          before: clock,
          build: reads('ref.listen(clockProvider, (previous, next) {});'),
          members: 'void next() => $watch;',
        ),
      },
      'only in a method a parameter is named like': {
        'a.dart': lists(
          build: reads('_each(() {});'),
          members:
              'void _each(void Function() next) => next();\n\n'
              '  void next() => $watch;',
        ),
      },
      'a watch on a ref the provider was not given': {
        'a.dart': lists(
          before: 'class Holder {\n  Holder(this.ref);\n  final Ref ref;\n}',
          build: reads('Holder(ref).ref.watch(signedInAccountProvider);'),
        ),
      },
      'only in a helper the call hands a ref the provider was not given': {
        'a.dart': lists(
          before: 'class Holder {\n  Holder(this.ref);\n  final Ref ref;\n}',
          build: reads('_key(Holder(ref).ref);'),
          members: 'static void _key(Ref ref) => $watch;',
        ),
      },
      'a read of the account': {
        'a.dart': lists(build: reads('ref.read(signedInAccountProvider);')),
      },
      'a watch on something other than a Ref': {
        'a.dart': lists(
          before: 'class Fake {\n  void watch(Object? listened) {}\n}',
          build: reads('Fake().watch(signedInAccountProvider);'),
        ),
      },
      'only in a same-named private member of another library': {
        'b.dart':
            'mixin Keyed on AsyncNotifier<Object> {\n'
            '  void _key() => $watch;\n'
            '  void key() => _key();\n'
            '}',
        'a.dart': lists(
          before:
              "import 'b.dart';\n\n"
              'abstract class Base extends AsyncNotifier<Object> {\n'
              '  void _key() {}\n'
              '}',
          header: 'Lists extends Base with Keyed',
          build: reads('_key();'),
        ),
      },
      'a watch of a provider whose name holds the account provider\'s': {
        'a.dart': lists(
          before:
              'final signedInAccountProviderCopy = '
              'Provider<String?>((ref) => null);',
          build: reads('ref.watch(signedInAccountProviderCopy);'),
        ),
      },
      'a watch of a same-named provider of its own library': {
        'a.dart': lists(
          before:
              'final signedInAccountProvider = '
              'Provider<String?>((ref) => null);',
          build: reads('$watch;'),
        ),
      },
    };
    for (final MapEntry(key: shape, value: files) in masked.entries) {
      test('does not key: $shape', () async {
        expect(await fixtures.scan(files), [unkeyed('listsProvider')]);
      });
    }

    final keying = <String, String>{
      'in the build': lists(build: reads('$watch;')),
      'in a helper the build calls': lists(
        build: reads('_key();'),
        members: 'void _key() => $watch;',
      ),
      'in a helper the build calls through this': lists(
        build: reads('this._key();'),
        members: 'void _key() => $watch;',
      ),
      'in a getter the build reads': lists(
        build: reads('account;'),
        members: 'String? get account => $watch;',
      ),
      'in a mixin helper': lists(
        before:
            'mixin Keyed on AsyncNotifier<Object> {\n'
            '  void _key() => $watch;\n'
            '}',
        header: 'Lists extends AsyncNotifier<Object> with Keyed',
        build: reads('_key();'),
      ),
      'in a base helper an override calls through super': lists(
        before:
            'abstract class Base extends AsyncNotifier<Object> {\n'
            '  void _key() => $watch;\n'
            '}',
        header: 'Lists extends Base',
        build: reads('_key();'),
        members: '@override\n  void _key() => super._key();',
      ),
      'in a called local function': lists(
        build: reads('void key() => $watch;\n    key();'),
      ),
      'in a helper a called local function calls': lists(
        build: reads('void key() => _key();\n    key();'),
        members: 'void _key() => $watch;',
      ),
      'after an await': lists(
        build: reads('await Future<void>.value();\n    $watch;'),
      ),
      'in a branch': lists(build: reads('if (identical(0, 1)) $watch;')),
      'after a return': lists(
        build: reads('_key();'),
        members:
            'void _key() {\n'
            '    if (identical(0, 0)) return;\n'
            '    $watch;\n'
            '  }',
      ),
      'a select on the account': lists(
        build: reads('ref.watch(signedInAccountProvider.select((id) => id));'),
      ),
      'a watch in a cascade': lists(
        build: reads('ref..watch(signedInAccountProvider);'),
      ),
      'a watch through an import prefix': lists(
        before:
            "import 'package:waxdeck/src/auth/auth_controller.dart' as auth;",
        build: reads('ref.watch(auth.signedInAccountProvider);'),
      ),
      'in a top-level function given the ref': lists(
        before: 'void _key(Ref ref) => $watch;',
        build: reads('_key(ref);'),
      ),
      'in a static method given the ref': lists(
        build: reads('_key(ref);'),
        members: 'static void _key(Ref ref) => $watch;',
      ),
      'in a method an extension member calls back on the notifier': lists(
        before: 'extension on Lists {\n  void _key() => _inner();\n}',
        build: reads('_key();'),
        members: 'void _inner() => $watch;',
      ),
      'in a function provider\'s closure, named function or constructor':
          '''
Future<Object> _load(Ref ref) {
  $watch;
  return $read;
}

class Service {
  Service(Ref ref) {
    $watch;
    $read;
  }
}

final closureProvider = FutureProvider<Object>((ref) {
  $watch;
  return $read;
});
final namedProvider = FutureProvider<Object>(_load);
final serviceProvider = Provider<Service>(Service.new);
''',
    };
    for (final MapEntry(key: shape, value: source) in keying.entries) {
      test('keys: $shape', () async {
        expect(await fixtures.scan({'a.dart': source}), isEmpty);
      });
    }
  });
}
