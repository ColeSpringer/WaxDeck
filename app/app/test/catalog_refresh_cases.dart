import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analysis_host.dart';
import 'catalog_refresh_scan.dart';

/// What every fixture library imports.
const _imports = '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sync/catalog_writes.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
''';

/// A rule of the cases' own, so they pin the scans and not what the
/// audit's rule happens to file.
const _rule = CatalogRule(
  readTags: {
    'LibraryApi',
    'MetadataApi',
    'BooksApi',
    'PodcastsApi',
    'HealthApi',
  },
  writeTags: {
    'LibraryApi',
    'MetadataApi',
    'HealthApi',
    'ReviewApi',
    'PodcastsApi',
  },
  readsByAnotherVerb: {'resolveEntities': 'why', 'resolveItems': 'why'},
  noRowRead: {'getItemPermissions': 'why', 'getLibraryHealth': 'why'},
  readsElsewhere: {'listTrash': 'why'},
  noRowWritten: {'rematchItem': 'why', 'fetchEpisode': 'why'},
  writesElsewhere: {'putGenreTree': 'why', 'restoreTrashEntry': 'why'},
);

/// The scans' rules, case by case, on fixture libraries laid over the
/// package of the host [host] returns, under [_rule].
void catalogRefreshCases(AnalysisHost Function() host) {
  var count = 0;

  /// Lays [files] over a fresh directory under `lib/` and answers their
  /// paths, each of which must compile.
  Future<List<String>> lay(Map<String, String> files) async {
    final dir = 'lib/catalog_refresh_fixture${count++}';
    final paths = <String>[];
    for (final MapEntry(key: name, value: source) in files.entries) {
      host().write('$dir/$name', '$_imports\n$source');
      paths.add('$dir/$name');
    }
    for (final path in paths) {
      final unit = await host().session.getResolvedUnit(host().absolute(path));
      expect(
        (unit as ResolvedUnitResult).diagnostics.where(
          (diagnostic) => diagnostic.severity == Severity.error,
        ),
        isEmpty,
        reason: '$path does not compile',
      );
    }
    return paths;
  }

  String cut(String line) =>
      line.replaceAll(RegExp(r'lib/catalog_refresh_fixture\d+/'), '');

  /// The read scan's lines for [files]; a file named `registry.dart`
  /// declares the registry, as the list `held`, in place of the app's.
  /// [allowed] names providers as `provider: operation`, [allowedSites]
  /// sites of `a.dart` as `Type.member: operation`.
  Future<List<String>> reads(
    Map<String, String> files, {
    Set<String> allowed = const {},
    Set<String> allowedSites = const {},
  }) async {
    final paths = await lay(files);
    final registry = paths.where((p) => p.endsWith('/registry.dart'));
    final lines = await unregisteredReadsIn(
      host(),
      paths,
      _rule,
      allowed: {for (final entry in allowed) entry: 'a reason'},
      allowedSites: {
        for (final site in allowedSites) '${paths.first}: $site': 'a reason',
      },
      registry: registry.isEmpty
          ? catalogRegistry
          : (path: registry.single, lists: const ['held']),
    );
    return lines.map(cut).toList();
  }

  /// The write scan's lines for [source], with the entries [allowed] as
  /// `Type.member: operation`.
  Future<List<String>> writes(
    String source, {
    Set<String> allowed = const {},
  }) async {
    final paths = await lay({'a.dart': source});
    final lines = await unlandedWritesIn(
      host(),
      paths,
      _rule,
      allowed: {for (final entry in allowed) '${paths.single}: $entry': 'why'},
    );
    return lines.map(cut).toList();
  }

  /// The line of [source], as [lay] writes it, that holds [text].
  int lineOf(String source, String text) =>
      '$_imports\n$source'.split('\n').indexWhere((l) => l.contains(text)) + 1;

  /// The line for the read of [name] at [call] in [holder], which the
  /// providers [by] run in no sweep, or no provider at all.
  String unswept(
    String source,
    String holder,
    String call,
    String name, {
    String? by,
  }) =>
      'a.dart:${lineOf(source, call)}: $holder reads the catalog ($name) '
      '${by == null ? 'where no provider reaches it' : 'for $by, in no sweep'} '
      '(to allow it: \'a.dart: $holder: $name\')';

  String unlanded(String source, String holder, String call, String name) =>
      'a.dart:${lineOf(source, call)}: $holder calls $name and never '
      'CatalogWrites.landed (to allow it: \'a.dart: $holder: $name\')';

  group('the client\'s operations', () {
    test('are read off the tag interfaces: a GET is a read, any other verb '
        'a write', () async {
      final operations = await Operations.of(host());
      final named = operations.named;
      expect(named('listItems')?.tag, 'LibraryApi');
      expect(named('listItems')?.verbs, {'GET'});
      expect(named('editEntity')?.verbs, {'PATCH'});
      expect(named('clearItemLyrics')?.verbs, {'DELETE'});
      expect(named('resolveEntities')?.verbs, {'POST'});
      // A hand-documented method that serves two paths.
      expect(named('setEntityStar')?.tag, 'PlaybackApi');
      expect(named('setEntityStar')?.verbs, {'PUT'});
      expect(named('artUrlFor'), isNull);
    });

    test('are the catalog\'s by tag, with the exceptions by name', () async {
      final operations = await Operations.of(host());
      bool read(String name) => _rule.catalogRead(operations.named(name)!);
      bool write(String name) => _rule.catalogWrite(operations.named(name)!);

      expect((read('getAlbum'), write('getAlbum')), (true, false));
      expect((read('editEntity'), write('editEntity')), (false, true));
      // A read by POST is a read; one that answers no row is neither.
      expect(
        (read('resolveEntities'), write('resolveEntities')),
        (true, false),
      );
      expect(
        (read('getItemPermissions'), write('getItemPermissions')),
        (false, false),
      );
      // A write tag's writes, and not its reads.
      expect((read('listDuplicates'), write('mergeDuplicates')), (true, true));
      expect(
        (read('getLibraryHealth'), read('listReviewQueue')),
        (false, false),
      );
      expect(write('rematchItem'), isFalse);
      // Outside the tags, only what the rule names.
      expect((write('putGenreTree'), write('emptyTrash')), (true, false));
      expect((read('listTrash'), read('listJobs')), (true, false));
      expect((read('getPodcast'), write('subscribePodcast')), (true, true));
      expect((write('fetchEpisode'), write('deleteBookmark')), (false, false));
    });

    test('a rule that names nothing, or excepts nothing, says so', () async {
      final operations = await Operations.of(host());
      const rule = CatalogRule(
        readTags: {'LibraryApi', 'NoSuchApi'},
        writeTags: {'MetadataApi'},
        readsByAnotherVerb: {'listItems': 'why', 'resolveItems': 'why'},
        noRowRead: {'getAlbum': '', 'getRuleFields': 'why', 'gone': 'why'},
        readsElsewhere: {'getItem': 'why', 'listTrash': 'why'},
        noRowWritten: {'editEntity': 'why', 'getItemMetadata': 'why'},
        writesElsewhere: {'renameEntity': 'why', 'emptyTrash': 'why'},
      );
      expect(
        rule.rot(operations).where((line) => !line.contains('filed nowhere')),
        [
          'NoSuchApi is not a tag interface of the client',
          'listItems is not an operation of another verb than GET (any '
              'more): drop the entry',
          'getAlbum is excepted without a reason',
          'getRuleFields is not a read of a catalog tag (any more): drop the '
              'entry',
          'gone is not an operation of the client: drop the entry',
          'getItem is not a read outside the catalog tags (any more): drop '
              'the entry',
          'getItemMetadata is not a write of a catalog tag (any more): drop '
              'the entry',
          'renameEntity is not a write outside the catalog tags (any more): '
              'drop the entry',
        ],
      );
    });

    test('an operation of any other tag is asked of someone: one filed '
        'nowhere, twice, or under another tag says so', () async {
      final operations = await Operations.of(host());
      const rule = CatalogRule(
        readTags: {'LibraryApi'},
        writeTags: {'LibraryApi'},
        readsByAnotherVerb: {'listPlayStates': 'why'},
        readsElsewhere: {'getTopList': 'why', 'getListeningStats': 'why'},
        otherReads: {
          'StatsApi': {
            'getListeningStats': 'why',
            'getListeningHeatmap': 'why',
            'listListenLog': 'why',
            'getYearInReview': 'why',
            // Another tag's, and a write.
            'health': 'why',
            'putPrefs': 'why',
          },
          'PlaybackApi': {'listPlayStates': 'why'},
          'LibraryApi': {'listItems': 'why'},
        },
        otherWrites: {
          'SharesApi': {'createShare': 'why', 'listShares': 'why'},
        },
      );
      // The lines that open with one of these, of the hundreds a rule
      // this small leaves unfiled.
      const asked = {
        'health',
        'putPrefs',
        'listItems',
        'listPlayStates',
        'createShare',
        'listShares',
        'revokeShare',
        'getListeningStats',
        'getListeningHeatmap',
        'getTopList',
        'listListenLog',
        'getYearInReview',
        'getServerYearInReview',
      };
      expect(
        rule
            .rot(operations)
            .where((line) => asked.contains(line.split(' ').first)),
        [
          'health is not a read of StatsApi, outside the catalog tags (any '
              'more): drop the entry',
          'putPrefs is not a read of StatsApi, outside the catalog tags '
              '(any more): drop the entry',
          'listItems is not a read of LibraryApi, outside the catalog tags '
              '(any more): drop the entry',
          'listShares is not a write of SharesApi, outside the catalog tags '
              '(any more): drop the entry',
          'listShares is a read of SharesApi that is filed nowhere: name it '
              'in readsElsewhere when it answers with catalog rows, else '
              'under SharesApi with why not',
          'revokeShare is a write of SharesApi that is filed nowhere: name '
              'it in writesElsewhere when it changes catalog rows, else '
              'under SharesApi with why not',
          'getListeningStats is filed twice: as a catalog read and as not '
              'one',
          'getServerYearInReview is a read of StatsApi that is filed '
              'nowhere: name it in readsElsewhere when it answers with '
              'catalog rows, else under StatsApi with why not',
          'health is a read of SystemApi that is filed nowhere: name it in '
              'readsElsewhere when it answers with catalog rows, else under '
              'SystemApi with why not',
          'putPrefs is a write of UsersApi that is filed nowhere: name it '
              'in writesElsewhere when it changes catalog rows, else under '
              'UsersApi with why not',
        ],
      );
    });
  });

  group('a provider that reads the catalog', () {
    test('is reported when no sweep holds it, whatever kind of provider it '
        'is', () async {
      const source = '''
final albumProvider = FutureProvider.autoDispose.family<AlbumDetail, String>(
  (ref, pid) => ref.watch(repositoryProvider).getAlbum(pid),
);

class Listing extends AsyncNotifier<ItemPage> {
  @override
  Future<ItemPage> build() => ref.watch(repositoryProvider).listItems();
}

final listingProvider = AsyncNotifierProvider<Listing, ItemPage>(Listing.new);

final cardsProvider = FutureProvider<EntityResolution>(
  (ref) => ref.watch(repositoryProvider).resolveEntities(const []),
);

final tornOffProvider = Provider<Future<ItemDetail> Function(String)>(
  (ref) => ref.watch(repositoryProvider).getItem,
);
''';
      expect(await reads({'a.dart': source}), [
        unswept(
          source,
          'albumProvider',
          'getAlbum(pid)',
          'getAlbum',
          by: 'albumProvider',
        ),
        unswept(
          source,
          'Listing.build',
          'listItems()',
          'listItems',
          by: 'listingProvider',
        ),
        unswept(
          source,
          'cardsProvider',
          'resolveEntities(',
          'resolveEntities',
          by: 'cardsProvider',
        ),
        unswept(
          source,
          'tornOffProvider',
          '.getItem,',
          'getItem',
          by: 'tornOffProvider',
        ),
      ]);
    });

    test('is reported for a read a helper makes, however deep, and for one '
        'the notifier\'s own method makes', () async {
      const source = '''
Future<AlbumDetail> _album(WaxDeckRepository repository, String pid) =>
    repository.getAlbum(pid);

Future<String> _title(Ref ref, String pid) async =>
    (await _album(ref.watch(repositoryProvider), pid)).title;

final titleProvider = FutureProvider.family<String, String>(_title);

mixin Paged on AsyncNotifier<ItemPage> {
  Future<ItemPage> page();

  @override
  Future<ItemPage> build() => page();
}

class Tracks extends AsyncNotifier<ItemPage> with Paged {
  @override
  Future<ItemPage> page() => ref.read(repositoryProvider).listItems();
}

class Other extends AsyncNotifier<ItemPage> with Paged {
  @override
  Future<ItemPage> page() => ref.read(repositoryProvider).browse(
    DiscoveryList.newest,
  );
}

final tracksProvider = AsyncNotifierProvider<Tracks, ItemPage>(Tracks.new);

final otherProvider = AsyncNotifierProvider<Other, ItemPage>(Other.new);
''';
      expect(await reads({'a.dart': source}), [
        unswept(
          source,
          '_album',
          'getAlbum(pid)',
          'getAlbum',
          by: 'titleProvider',
        ),
        // Each its own page, not the other notifier's.
        unswept(
          source,
          'Tracks.page',
          'listItems()',
          'listItems',
          by: 'tracksProvider',
        ),
        unswept(source, 'Other.page', 'browse(', 'browse', by: 'otherProvider'),
      ]);
    });

    test('passes when a sweep\'s list holds it, itself or through a list '
        'that list spreads', () async {
      const source = '''
final albumProvider = FutureProvider.family<AlbumDetail, String>(
  (ref, pid) => ref.watch(repositoryProvider).getAlbum(pid),
);

final itemProvider = FutureProvider.family<ItemDetail, String>(
  (ref, pid) => ref.watch(repositoryProvider).getItem(pid),
);

final bookProvider = FutureProvider.family<BookDetail, String>(
  (ref, pid) => ref.watch(repositoryProvider).getBook(pid),
);

final leftOutProvider = FutureProvider<ItemPage>(
  (ref) => ref.watch(repositoryProvider).listItems(),
);
''';
      expect(
        await reads({
          'a.dart': source,
          'registry.dart': '''
import 'a.dart';

final shelves = <Object>[itemProvider];
final hubs = <Object>[bookProvider];
final held = <Object>[albumProvider, ...shelves, hubs];
''',
        }),
        [
          unswept(
            source,
            'leftOutProvider',
            'listItems()',
            'listItems',
            by: 'leftOutProvider',
          ),
        ],
      );
    });

    test(
      'a registry entry the scan cannot read as a provider is reported',
      () async {
        const source = '''
final albumProvider = FutureProvider.family<AlbumDetail, String>(
  (ref, pid) => ref.watch(repositoryProvider).getAlbum(pid),
);

List<Object> more() => [albumProvider];
''';
        final lines = await reads({
          'a.dart': source,
          'registry.dart': '''
import 'a.dart';

final built = more();
final held = <Object>[...built, more().first];
''',
        });
        expect(lines, [
          'registry.dart: built is not a list literal, so the scan cannot read '
              'what the registry holds through it',
          'registry.dart: more().first names no top-level variable, so the '
              'scan cannot read it as a registered provider',
          unswept(
            source,
            'albumProvider',
            'getAlbum(pid)',
            'getAlbum',
            by: 'albumProvider',
          ),
        ]);
      },
    );

    test('is not a provider that watches one, reads another tag, or reads '
        'what answers no catalog row', () async {
      expect(
        await reads({
          'a.dart': '''
final albumProvider = FutureProvider.family<AlbumDetail, String>(
  (ref, pid) => ref.watch(repositoryProvider).getAlbum(pid),
);

final titleProvider = FutureProvider.family<String, String>(
  (ref, pid) async => (await ref.watch(albumProvider(pid).future)).title,
);

final rulesProvider = FutureProvider<RuleFields>(
  (ref) => ref.watch(repositoryProvider).getRuleFields(),
);

final mayProvider = FutureProvider.family<ItemPermissions, String>(
  (ref, pid) => ref.watch(repositoryProvider).getItemPermissions(pid),
);

final queueProvider = FutureProvider<ReviewEntryPage>(
  (ref) => ref.watch(repositoryProvider).listReviewQueue(),
);
''',
          'registry.dart': '''
import 'a.dart';

final held = <Object>[albumProvider];
''',
        }),
        isEmpty,
      );
    });

    test('passes when its read is allowed where it sits, and an entry that '
        'allows nothing is reported', () async {
      expect(
        await reads(
          {
            'a.dart': '''
final seedProvider = FutureProvider.autoDispose.family<ItemDetail, String>(
  (ref, pid) => ref.watch(repositoryProvider).getItem(pid),
);

final rulesProvider = FutureProvider<RuleFields>(
  (ref) => ref.watch(repositoryProvider).getRuleFields(),
);
''',
          },
          allowedSites: {
            'seedProvider: getItem',
            'rulesProvider: getRuleFields',
            'goneProvider: getItem',
          },
        ),
        [
          for (final site in [
            'rulesProvider: getRuleFields',
            'goneProvider: getItem',
          ])
            '\'a.dart: $site\' is allowed, but no catalog read there is '
                'outside every sweep (any more): drop the entry',
        ],
      );
    });

    test('is reported for a read any member of its notifier makes, named '
        'by its build or not', () async {
      const source = '''
mixin Paging on Notifier<List<ItemSummary>> {
  Future<void> more() async {
    state = (await ref.read(repositoryProvider).browse(
      DiscoveryList.newest,
    )).items;
  }
}

class Shelf extends Notifier<List<ItemSummary>> with Paging {
  @override
  List<ItemSummary> build() => const [];

  Future<void> load() async {
    state = (await ref.read(repositoryProvider).listItems()).items;
  }
}

final shelfProvider = NotifierProvider<Shelf, List<ItemSummary>>(Shelf.new);
''';
      expect(await reads({'a.dart': source}), [
        unswept(
          source,
          'Paging.more',
          'browse(',
          'browse',
          by: 'shelfProvider',
        ),
        unswept(
          source,
          'Shelf.load',
          'listItems()',
          'listItems',
          by: 'shelfProvider',
        ),
      ]);
    });

    test('allowed for one read is reported for the next: another operation '
        'in its own body, and any read in what it goes on to reach', () async {
      const source = '''
Future<ItemPage> _refill(WaxDeckRepository repository) =>
    repository.listItems();

final playbackProvider = FutureProvider<ItemDetail>((ref) async {
  final repository = ref.watch(repositoryProvider);
  await _refill(repository);
  await repository.getAlbum('al-1');
  return repository.getItem('tr-1');
});

final driverProvider = Provider<Future<ItemPage> Function()>(
  (ref) => () => _refill(ref.read(repositoryProvider)),
);
''';
      expect(
        await reads(
          {'a.dart': source},
          allowedSites: {'playbackProvider: getItem'},
        ),
        [
          unswept(
            source,
            '_refill',
            'listItems()',
            'listItems',
            by: 'driverProvider, playbackProvider',
          ),
          unswept(
            source,
            'playbackProvider',
            "getAlbum('al-1')",
            'getAlbum',
            by: 'playbackProvider',
          ),
        ],
      );
      // One entry where the read sits answers for every provider that
      // reaches it: the one that only drives it needs none of its own.
      expect(
        await reads(
          {'a.dart': source},
          allowedSites: {
            'playbackProvider: getItem',
            'playbackProvider: getAlbum',
            '_refill: listItems',
          },
        ),
        isEmpty,
      );
    });

    test('in no sweep is reported by name for a read it makes through a '
        'body a swept provider also runs', () async {
      const files = {
        'a.dart': '''
Future<AlbumDetail> album(WaxDeckRepository repository, String pid) =>
    repository.getAlbum(pid);

final albumProvider = FutureProvider.family<AlbumDetail, String>(
  (ref, pid) => album(ref.watch(repositoryProvider), pid),
);

final copyProvider = FutureProvider.family<AlbumDetail, String>(
  (ref, pid) => album(ref.watch(repositoryProvider), pid),
);
''',
        'registry.dart': '''
import 'a.dart';

final held = <Object>[albumProvider];
''',
      };
      expect(await reads(files), [
        'a.dart: copyProvider reads the catalog (getAlbum) through what a '
            'swept provider also runs, or outside the files read, and is in '
            'no sweep itself (to allow it: \'copyProvider: getAlbum\')',
      ]);
      expect(
        await reads(
          files,
          allowed: {
            'copyProvider: getAlbum',
            'albumProvider: getAlbum',
            'goneProvider: getAlbum',
          },
        ),
        [
          for (final entry in [
            'albumProvider: getAlbum',
            'goneProvider: getAlbum',
          ])
            '\'$entry\' is allowed, but no provider of that name reads '
                'that through a swept body from outside every sweep (any '
                'more): drop the entry',
        ],
      );
    });
  });

  group('a catalog read no provider reaches', () {
    const source = '''
Future<AlbumDetail> fetchAndAct(WidgetRef ref, String pid) =>
    ref.read(repositoryProvider).getAlbum(pid);

class Sheet {
  Sheet(this.ref);

  final WidgetRef ref;

  late final Future<ItemPage> rows = ref.read(repositoryProvider).listItems();

  static final heldProvider = FutureProvider<ItemDetail>(
    (ref) => ref.watch(repositoryProvider).getItem('tr-1'),
  );
}

class Pager {
  Pager(this.repository);

  final WaxDeckRepository repository;

  Future<ItemPage> next() => repository.browse(DiscoveryList.newest);
}

final pagerProvider = Provider<Pager>(
  (ref) => Pager(ref.watch(repositoryProvider)),
);

Future<RuleFields> notTheCatalog(WidgetRef ref) =>
    ref.read(repositoryProvider).getRuleFields();
''';

    test('is reported wherever it sits: a function, a widget\'s own state, '
        'a provider a class holds, an object a provider hands out', () async {
      expect(await reads({'a.dart': source}), [
        unswept(source, 'fetchAndAct', 'getAlbum(pid)', 'getAlbum'),
        unswept(source, 'Sheet.rows', 'listItems()', 'listItems'),
        unswept(source, 'Sheet.heldProvider', "getItem('tr-1')", 'getItem'),
        unswept(source, 'Pager.next', 'browse(', 'browse'),
      ]);
    });

    test('passes when allowed, and an entry that allows nothing is '
        'reported', () async {
      expect(
        await reads(
          {'a.dart': source},
          allowedSites: {
            'fetchAndAct: getAlbum',
            'Sheet.rows: listItems',
            'Sheet.heldProvider: getItem',
            'Pager.next: browse',
            'notTheCatalog: getRuleFields',
          },
        ),
        [
          '\'a.dart: notTheCatalog: getRuleFields\' is allowed, but no '
              'catalog read there is outside every sweep (any more): drop '
              'the entry',
        ],
      );
    });

    test('is not seen past what the scan follows', () async {
      // The scan's stated limits. A widget that calls for itself a helper
      // a swept provider reaches holds rows no sweep reaches. A second
      // read of an operation passes under the entry that names the first
      // in its declaration. A provider that runs a function value set
      // from elsewhere is not asked to join a sweep: the read is reported
      // where it is written.
      const source = '''
Future<AlbumDetail> album(WaxDeckRepository repository, String pid) =>
    repository.getAlbum(pid);

final albumProvider = FutureProvider.family<AlbumDetail, String>(
  (ref, pid) => album(ref.watch(repositoryProvider), pid),
);

Future<AlbumDetail> forAWidget(WidgetRef ref, String pid) =>
    album(ref.read(repositoryProvider), pid);

Future<void> twice(WidgetRef ref) async {
  await ref.read(repositoryProvider).getItem('tr-1');
  await ref.read(repositoryProvider).getItem('tr-2');
}

Future<ItemPage> Function(WaxDeckRepository)? hook;

void install() {
  hook = (repository) => repository.listItems();
}

final hookedProvider = FutureProvider<ItemPage?>(
  (ref) async => hook?.call(ref.watch(repositoryProvider)),
);
''';
      expect(
        await reads(
          {
            'a.dart': source,
            'registry.dart': '''
import 'a.dart';

final held = <Object>[albumProvider];
''',
          },
          allowedSites: {'twice: getItem'},
        ),
        [unswept(source, 'install', 'listItems()', 'listItems')],
      );
    });
  });

  group('a catalog write', () {
    test('is reported when its declaration never calls landed, called or '
        'torn off, wherever it sits', () async {
      const source = '''
Future<void> clear(WidgetRef ref, String pid) async {
  await ref.read(repositoryProvider).clearItemLyrics(pid);
}

class Editor extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> detach(String pid) async {
    await ref.read(repositoryProvider).detachItem(pid);
    ref.invalidateSelf();
  }

  Future<void> Function(String) get restore =>
      ref.read(repositoryProvider).restoreTrashEntry;
}

final clearTagProvider = Provider<Future<void> Function(String)>(
  (ref) => (pid) => ref.read(repositoryProvider).clearItemTag(pid, 'mood'),
);
''';
      expect(await writes(source), [
        unlanded(source, 'clear', 'clearItemLyrics(pid)', 'clearItemLyrics'),
        unlanded(source, 'Editor.detach', 'detachItem(pid)', 'detachItem'),
        unlanded(
          source,
          'Editor.restore',
          '.restoreTrashEntry;',
          'restoreTrashEntry',
        ),
        unlanded(
          source,
          'clearTagProvider',
          'clearItemTag(pid',
          'clearItemTag',
        ),
      ]);
    });

    test(
      'has landed when its declaration calls landed: beside it, in a '
      'closure or local function, or around the closure that makes it',
      () async {
        expect(
          await writes('''
Future<void> beside(WidgetRef ref, String pid) async {
  final writes = ref.read(catalogWritesProvider);
  await ref.read(repositoryProvider).clearItemLyrics(pid);
  writes.landed();
}

Future<void> inAClosure(WidgetRef ref, String pid) async {
  final writes = ref.read(catalogWritesProvider);
  await Future<void>(() async {
    await ref.read(repositoryProvider).detachItem(pid);
    writes.landed(artUrls: {pid});
  });
}

Future<void> aroundIt(WidgetRef ref, String pid) async {
  final writes = ref.read(catalogWritesProvider);
  Future<void> delete() => ref.read(repositoryProvider).clearItemLyrics(pid);
  void reread() => writes.landed();
  await delete();
  reread();
}
'''),
          isEmpty,
        );
      },
    );

    test('has landed through a helper that makes no catalog write of its '
        'own, and not through one that does', () async {
      const source = '''
class Editor extends Notifier<int> {
  @override
  int build() => 0;

  void _settle(CatalogWrites writes) => _told(writes);

  void _told(CatalogWrites writes) {
    writes.landed();
    ref.invalidateSelf();
  }

  Future<void> clear(String pid) async {
    final writes = ref.read(catalogWritesProvider);
    await ref.read(repositoryProvider).clearItemLyrics(pid);
    _settle(writes);
  }

  Future<void> detach(String pid) async {
    final writes = ref.read(catalogWritesProvider);
    await ref.read(repositoryProvider).detachItem(pid);
    writes.landed();
  }

  // The landing it reaches is the detach's own.
  Future<void> clearTagThenDetach(String pid) async {
    await ref.read(repositoryProvider).clearItemTag(pid, 'mood');
    await detach(pid);
  }
}
''';
      expect(await writes(source), [
        unlanded(
          source,
          'Editor.clearTagThenDetach',
          'clearItemTag(pid',
          'clearItemTag',
        ),
      ]);
    });

    test('is reported when only the caller of its declaration lands it, '
        'unless that is allowed', () async {
      const source = '''
Future<void> _write(WidgetRef ref, String pid) =>
    ref.read(repositoryProvider).clearItemLyrics(pid);

Future<void> save(WidgetRef ref, String pid) async {
  final writes = ref.read(catalogWritesProvider);
  await _write(ref, pid);
  writes.landed();
}
''';
      expect(await writes(source), [
        unlanded(source, '_write', 'clearItemLyrics(pid)', 'clearItemLyrics'),
      ]);
      expect(
        await writes(source, allowed: {'_write: clearItemLyrics'}),
        isEmpty,
      );
    });

    test('an entry that allows nothing is reported', () async {
      const source = '''
Future<void> save(WidgetRef ref, String pid) async {
  final writes = ref.read(catalogWritesProvider);
  await ref.read(repositoryProvider).clearItemLyrics(pid);
  writes.landed();
}
''';
      expect(await writes(source, allowed: {'save: clearItemLyrics'}), [
        '\'a.dart: save: clearItemLyrics\' is allowed, but no catalog write '
            'there goes unlanded (any more): drop the entry',
      ]);
    });

    test('is not a read, a write of another tag, or a write that has '
        'changed no row when it answers', () async {
      expect(
        await writes('''
Future<void> others(WidgetRef ref, String pid) async {
  final repository = ref.read(repositoryProvider);
  await repository.getAlbum(pid);
  await repository.resolveEntities([pid]);
  await repository.deleteBookmark(pid, 'one');
  await repository.emptyTrash();
  await repository.rematchItem(pid);
}
'''),
        isEmpty,
      );
    });

    test('a declaration named as landing another\'s write is held to '
        'calling landed', () async {
      final paths = await lay({
        'a.dart': '''
void lands(WidgetRef ref) {
  void reread() => ref.read(catalogWritesProvider).landed();
  reread();
}

class Sheet {
  void forgets(WidgetRef ref) => ref.read(catalogWritesProvider);
}
''',
      });
      final at = paths.single;
      expect(
        await notLandingIn(host(), [
          '$at: lands',
          '$at: Sheet.forgets',
          '$at: gone',
        ], _rule),
        [
          '$at: Sheet.forgets does not call CatalogWrites.landed',
          '$at: gone is not declared (any more): drop the entry',
        ],
      );
    });

    test('is not seen past what the scan follows', () async {
      // The scan's stated limits: none of these lands its write, or
      // every one of them, on every path once the server has answered.
      expect(
        await writes('''
Future<void> oneBranch(WidgetRef ref, String pid, bool tell) async {
  final writes = ref.read(catalogWritesProvider);
  await ref.read(repositoryProvider).clearItemLyrics(pid);
  if (tell) writes.landed();
}

Future<void> oneOfTwo(WidgetRef ref, String pid) async {
  final writes = ref.read(catalogWritesProvider);
  await ref.read(repositoryProvider).clearItemLyrics(pid);
  writes.landed();
  await ref.read(repositoryProvider).detachItem(pid);
}

Future<void> ahead(WidgetRef ref, String pid) async {
  ref.read(catalogWritesProvider).landed();
  await ref.read(repositoryProvider).clearItemLyrics(pid);
}
'''),
        isEmpty,
      );
    });
  });
}
