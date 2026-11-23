/// The scans `catalog_refresh_audit.dart` runs over `lib/`, on the
/// analyzer's resolved view of the package ([AnalysisHost]).
///
/// The operations are the methods of the interfaces `WaxDeckApi`
/// implements, one interface per tag of the API spec, as `make generate`
/// writes them: each method's doc comment opens with the `VERB /path` of
/// every operation it serves. A method is a read when every verb is GET
/// and a write otherwise; one with no such opening fails the scan, as does
/// a name two tags share. A reference is to an operation when it names
/// that method, called or torn off, on the tag interface or on a subtype
/// of it (the repository, the client). Which operations are the
/// catalog's is a [CatalogRule]: the catalog's tags whole, so an
/// operation the spec adds to one is held the day it is generated, and
/// every operation of every other tag by name, so one added there is
/// asked of someone before the scans pass.
///
/// The read scan takes each top-level provider (found, and its build
/// determined, as `account_scoping_scan.dart` says) and the catalog reads
/// it refers to, itself or through anything of this package it refers
/// to, however deep: the following that scan documents, so a helper
/// function and a closure are read. A notifier is read whole, every
/// member its class runs as itself and not only what its build names:
/// what a `loadMore` reads is the provider's state as much. The create
/// callback of another provider is not followed: a provider that only
/// watches a swept one reads nothing itself. Nor is what
/// `CatalogWrites.landed` runs: that is the sweep, and no read of the
/// provider whose write landed. A provider is swept when a sweep's list
/// holds it, and the lists are read from their declarations: the list
/// literals, through the lists they spread or name.
///
/// Then every reference to a catalog read is taken. One that sits in a
/// body a swept provider's walk read is in that sweep. Any other is in
/// none and is reported where it sits, as `path: Type.member:
/// operation`: a provider no list holds, what such a provider reaches, a
/// widget's own state, a function that fetches and acts, a provider a
/// class holds. An entry excuses one operation in one declaration, so a
/// read added beside it, there or in whatever the same provider reaches
/// next, is reported. A provider in no sweep that reads through a body a
/// swept provider also runs is reported by its own name and the
/// operation, since the body is in a sweep and it is not.
///
/// What the read scan cannot see: a function a swept provider reaches
/// and a widget also calls for itself counts as swept; a second
/// reference to an operation in a declaration an entry already names
/// passes under that entry; and a function value that arrives from
/// outside what the walk follows is not followed, so the provider that
/// runs it is not asked to join a sweep (the read is still reported
/// where it is written).
///
/// The write scan takes every reference to a catalog write and the
/// declaration it sits in: the method, constructor or top-level function,
/// or the field or top-level variable whose initializer holds it, with
/// every closure and local function inside. The write has landed when
/// that declaration calls `CatalogWrites.landed`: in itself, or in a
/// declaration of this package it refers to, however deep, through those
/// that hold no catalog write of their own. One that does is not gone
/// through: a `landed` beside a write is that write's.
///
/// What the write scan cannot see: control flow (a `landed` on one
/// branch, or ahead of the write, counts), which of two writes in one
/// declaration a `landed` belongs to, and a `landed` that only the
/// caller of the declaration makes, which is reported.
///
/// A library either scan resolves fails when it does not compile.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'account_scoping_scan.dart';
import 'analysis_host.dart';

/// One method of the generated client: the tag interface that declares
/// it and the verbs of the operations it serves.
typedef Operation = ({String tag, String name, Set<String> verbs});

/// Which operations are the catalog's: the catalog's tag interfaces
/// whole, the operations excepted from them by name, and every operation
/// of every other tag by name, each with why.
class CatalogRule {
  const CatalogRule({
    required this.readTags,
    required this.writeTags,
    this.readsByAnotherVerb = const {},
    this.noRowRead = const {},
    this.readsElsewhere = const {},
    this.otherReads = const {},
    this.noRowWritten = const {},
    this.writesElsewhere = const {},
    this.otherWrites = const {},
  });

  /// The tag interfaces whose reads answer with catalog rows.
  final Set<String> readTags;

  /// The tag interfaces whose writes change catalog rows.
  final Set<String> writeTags;

  /// Operations that are not GET and only read.
  final Map<String, String> readsByAnotherVerb;

  /// Reads of a read tag that answer with no catalog row.
  final Map<String, String> noRowRead;

  /// Reads outside the read tags that do answer with catalog rows.
  final Map<String, String> readsElsewhere;

  /// Every other read outside the read tags, by tag then by name: why it
  /// answers no catalog row a screen holds.
  final Map<String, Map<String, String>> otherReads;

  /// Writes of a write tag that have changed no catalog row when they
  /// answer.
  final Map<String, String> noRowWritten;

  /// Writes outside the write tags that do change catalog rows.
  final Map<String, String> writesElsewhere;

  /// Every other write outside the write tags, by tag then by name: why
  /// it has changed no catalog row when it answers.
  final Map<String, Map<String, String>> otherWrites;

  bool _reads(Operation operation) =>
      operation.verbs.every((verb) => verb == 'GET') ||
      readsByAnotherVerb.containsKey(operation.name);

  bool catalogRead(Operation operation) =>
      _reads(operation) &&
      (readTags.contains(operation.tag)
          ? !noRowRead.containsKey(operation.name)
          : readsElsewhere.containsKey(operation.name));

  bool catalogWrite(Operation operation) =>
      !_reads(operation) &&
      (writeTags.contains(operation.tag)
          ? !noRowWritten.containsKey(operation.name)
          : writesElsewhere.containsKey(operation.name));

  /// One line per operation of [operations] outside the catalog's tags
  /// that is filed nowhere or twice, and per entry that names nothing
  /// there, excepts nothing, or gives no reason.
  List<String> rot(Operations operations) {
    final byName = {
      for (final operation in operations.all) operation.name: operation,
    };
    final lines = [
      for (final tag in {
        ...readTags,
        ...writeTags,
        ...otherReads.keys,
        ...otherWrites.keys,
      })
        if (!operations.tags.contains(tag))
          '$tag is not a tag interface of the client',
    ];
    void check(
      Map<String, String> entries,
      bool Function(Operation) stands,
      String what,
    ) {
      for (final MapEntry(key: name, value: reason) in entries.entries) {
        final operation = byName[name];
        if (operation == null) {
          lines.add('$name is not an operation of the client: drop the entry');
        } else if (!stands(operation)) {
          lines.add('$name is not $what (any more): drop the entry');
        } else if (reason.trim().isEmpty) {
          lines.add('$name is excepted without a reason');
        }
      }
    }

    check(
      readsByAnotherVerb,
      (operation) => operation.verbs.any((verb) => verb != 'GET'),
      'an operation of another verb than GET',
    );
    check(
      noRowRead,
      (operation) => readTags.contains(operation.tag) && _reads(operation),
      'a read of a catalog tag',
    );
    check(
      readsElsewhere,
      (operation) => !readTags.contains(operation.tag) && _reads(operation),
      'a read outside the catalog tags',
    );
    check(
      noRowWritten,
      (operation) => writeTags.contains(operation.tag) && !_reads(operation),
      'a write of a catalog tag',
    );
    check(
      writesElsewhere,
      (operation) => !writeTags.contains(operation.tag) && !_reads(operation),
      'a write outside the catalog tags',
    );
    for (final MapEntry(key: tag, value: entries) in otherReads.entries) {
      check(
        entries,
        (operation) =>
            operation.tag == tag &&
            !readTags.contains(tag) &&
            _reads(operation),
        'a read of $tag, outside the catalog tags',
      );
    }
    for (final MapEntry(key: tag, value: entries) in otherWrites.entries) {
      check(
        entries,
        (operation) =>
            operation.tag == tag &&
            !writeTags.contains(tag) &&
            !_reads(operation),
        'a write of $tag, outside the catalog tags',
      );
    }

    // An operation outside the catalog's tags is asked of someone.
    for (final operation in operations.all) {
      final name = operation.name;
      final (tags, held, other, kind, lists) = _reads(operation)
          ? (readTags, readsElsewhere, otherReads, 'read', 'readsElsewhere')
          : (
              writeTags,
              writesElsewhere,
              otherWrites,
              'write',
              'writesElsewhere',
            );
      if (tags.contains(operation.tag)) continue;
      final filed = other[operation.tag]?.containsKey(name) ?? false;
      if (held.containsKey(name) && filed) {
        lines.add('$name is filed twice: as a catalog $kind and as not one');
      } else if (!held.containsKey(name) && !filed) {
        lines.add(
          '$name is a $kind of ${operation.tag} that is filed nowhere: name '
          'it in $lists when it ${kind == 'read' ? 'answers with' : 'changes'} '
          'catalog rows, else under ${operation.tag} with why not',
        );
      }
    }
    return lines;
  }
}

final _opening = RegExp('`(GET|HEAD|POST|PUT|PATCH|DELETE) /[^`]*`');

/// The client's operations, by the method that serves them.
class Operations {
  Operations._(this._byName, this._declaring);

  static final _opened = Expando<Future<Operations>>();

  /// The operations of the client [host] resolves, read once per host.
  static Future<Operations> of(AnalysisHost host) =>
      _opened[host] ??= () async {
        const uri = 'package:waxdeck_api/src/gen/api.g.dart';
        final library = await host.session.getLibraryByUri(uri);
        final all = library is LibraryElementResult
            ? library.element.getClass('WaxDeckApi')
            : null;
        if (all == null) throw StateError('$uri declares no WaxDeckApi');
        final byName = <String, Operation>{};
        final declaring = <String, InterfaceElement>{};
        for (final tag in all.interfaces.map((type) => type.element)) {
          for (final method in tag.methods) {
            final name = method.name!;
            // The paragraph a blank doc line ends.
            final opening = (method.documentationComment ?? '')
                .split(RegExp(r'\n\s*///\s*(\n|$)'))
                .first;
            final verbs = {
              for (final match in _opening.allMatches(opening)) match[1]!,
            };
            if (verbs.isEmpty) {
              throw StateError(
                '${tag.name}.$name does not open its doc comment with the '
                '`VERB /path` it serves, so the scan cannot tell a read from '
                'a write',
              );
            }
            if (byName.containsKey(name)) {
              throw StateError('two tag interfaces declare $name');
            }
            byName[name] = (tag: tag.name!, name: name, verbs: verbs);
            declaring[name] = tag;
          }
        }
        return Operations._(byName, declaring);
      }();

  final Map<String, Operation> _byName;
  final Map<String, InterfaceElement> _declaring;

  Iterable<Operation> get all => _byName.values;

  /// The tag interfaces, by name.
  late final Set<String> tags = {
    for (final tag in _declaring.values) tag.name!,
  };

  /// The operation named [name].
  Operation? named(String name) => _byName[name];

  /// The operation [element] is the method of, on the tag interface or
  /// on a subtype of it.
  Operation? operator [](Element? element) {
    if (element is! MethodElement) return null;
    final operation = _byName[element.name];
    final owner = element.enclosingElement;
    if (operation == null || owner is! InterfaceElement) return null;
    final tag = _declaring[operation.name];
    return owner == tag || owner.allSupertypes.any((t) => t.element == tag)
        ? operation
        : null;
  }
}

/// Where the sweeps' lists are declared, and which they are: the
/// registry every pass sweeps, and the reads asked once a run of changes
/// goes quiet.
typedef Registry = ({String path, List<String> lists});

const Registry catalogRegistry = (
  path: 'lib/src/sync/catalog_reads.dart',
  lists: [
    'catalogReadProviders',
    'catalogReadFamilies',
    'catalogQuietReads',
    'catalogQuietFamilies',
  ],
);

/// One line per breach of the read rule in [files]: a reference to a
/// catalog read of [rule] that no provider in a list of [registry]
/// reaches and that [allowedSites] does not name, as
/// `path: Type.member: operation`; a provider in no list that reads
/// through a body a listed one also runs, or through one outside
/// [files], and that [allowed] does not name, as `provider: operation`;
/// an entry of either that excuses nothing; and whatever the scan cannot
/// read.
Future<List<String>> unregisteredReadsIn(
  AnalysisHost host,
  Iterable<String> files,
  CatalogRule rule, {
  Map<String, String> allowed = const {},
  Map<String, String> allowedSites = const {},
  Registry registry = catalogRegistry,
}) async {
  final operations = await Operations.of(host);
  final reads = await LibReads.open(host, files);
  final held = await _registered(reads, host, registry);
  final errors = <String>{};
  final lines = [...held.unread];
  final declared = <String, List<String>>{};
  bool wanted(Element element) => switch (operations[element]) {
    final Operation operation => rule.catalogRead(operation),
    null => false,
  };
  // The bodies a sweep reaches, and each provider no sweep holds with
  // the operations still to be accounted for.
  final swept = <AstNode>{};
  final unswept = <ProviderReads, Set<String>>{};
  final landed = await _landedMethod(host);
  for (final provider in await reads.providers(
    wanted,
    stop: (element) => element == landed,
  )) {
    final name = provider.variable.name!;
    (declared[name] ??= []).add(provider.path);
    final picked = provider.picked;
    if (picked == null) {
      lines.add(
        '${provider.path}: $name has a build the scan cannot determine '
        '(${provider.unknown}); it fails closed on what it cannot read',
      );
    } else if (held.providers.contains(provider.variable)) {
      swept.addAll(provider.read);
    } else if (picked.isNotEmpty) {
      unswept[provider] = {for (final element in picked) element.name!};
    }
  }

  final names = {
    for (final operation in operations.all)
      if (rule.catalogRead(operation)) operation.name,
  };
  final outside = <String>{};
  // By provider and operation: read through a body some sweep reaches.
  final shared = <String, String>{};
  for (final file in files) {
    final resolved = await _libraryNaming(host, file, names);
    if (resolved == null) continue;
    errors.addAll(host.errors(resolved));
    for (final unit in resolved.units) {
      final found = _References(wanted);
      unit.unit.accept(found);
      for (final reference in found.found) {
        final around = _ancestors(reference).toSet();
        final holders = [
          for (final provider in unswept.keys)
            if (provider.read.any(around.contains)) provider,
        ];
        if (around.any(swept.contains)) {
          for (final provider in holders) {
            shared['${provider.variable.name}: ${reference.name}'] =
                provider.path;
          }
          continue;
        }
        for (final provider in holders) {
          unswept[provider]!.remove(reference.name);
        }
        final within = _declarationAround(reference);
        final path = host.relative(unit.path);
        final holder = within == null ? '(no declaration)' : _nameOf(within);
        final key = '$path: $holder: ${reference.name}';
        if (!outside.add(key) || allowedSites.containsKey(key)) continue;
        final by = [for (final provider in holders) provider.variable.name!]
          ..sort();
        lines.add(
          '$path:${unit.lineInfo.getLocation(reference.offset).lineNumber}: '
          '$holder reads the catalog (${reference.name}) '
          '${by.isEmpty ? 'where no provider reaches it' : 'for '
                    '${by.join(', ')}, in no sweep'} '
          '(to allow it: \'$key\')',
        );
      }
    }
  }
  // What a provider in no sweep reads where no line above says so.
  for (final MapEntry(key: provider, value: left) in unswept.entries) {
    for (final name in left) {
      shared.putIfAbsent(
        '${provider.variable.name}: $name',
        () => provider.path,
      );
    }
  }
  for (final MapEntry(:key, value: path) in shared.entries) {
    if (allowed.containsKey(key)) continue;
    final [provider, operation] = key.split(': ');
    lines.add(
      '$path: $provider reads the catalog ($operation) through what a '
      'swept provider also runs, or outside the files read, and is in no '
      'sweep itself (to allow it: \'$key\')',
    );
  }
  for (final key in allowed.keys) {
    final paths = declared[key.split(': ').first] ?? const <String>[];
    if (paths.length > 1) {
      lines.add(
        '\'$key\' is allowed, but more than one library declares a provider '
        'of that name (${paths.join(', ')}): an entry covers one provider',
      );
    } else if (!shared.containsKey(key)) {
      lines.add(
        '\'$key\' is allowed, but no provider of that name reads that '
        'through a swept body from outside every sweep (any more): drop '
        'the entry',
      );
    }
  }
  for (final key in allowedSites.keys) {
    if (!outside.contains(key)) {
      lines.add(
        '\'$key\' is allowed, but no catalog read there is outside every '
        'sweep (any more): drop the entry',
      );
    }
  }
  return [...errors..addAll(await reads.errors()), ...lines];
}

/// [node] and what encloses it.
Iterable<AstNode> _ancestors(AstNode node) sync* {
  for (AstNode? at = node; at != null; at = at.parent) {
    yield at;
  }
}

/// The library at [file], resolved, when any unit of it names one of
/// [names] at all.
Future<ResolvedLibraryResult?> _libraryNaming(
  AnalysisHost host,
  String file,
  Set<String> names,
) async {
  final parsed = host.session.getParsedLibrary(host.absolute(file));
  if (parsed is! ParsedLibraryResult) return null;
  final named = _Names(names);
  for (final unit in parsed.units) {
    unit.unit.accept(named);
  }
  return named.any ? host.resolve(host.absolute(file)) : null;
}

/// The providers the lists of [registry] hold, through the lists they
/// spread or name, and one line per entry that cannot be read as one.
Future<({Set<Element> providers, List<String> unread})> _registered(
  LibReads reads,
  AnalysisHost host,
  Registry registry,
) async {
  final library = (await host.resolve(host.absolute(registry.path))).element;
  final providers = <Element>{};
  final unread = <String>[];
  final seen = <Element>{};

  Future<ListLiteral?> literal(Element variable) async {
    final node = await reads.declaration(variable);
    final value = node is VariableDeclaration
        ? node.initializer?.unParenthesized
        : null;
    return value is ListLiteral ? value : null;
  }

  Future<void> list(Element variable) async {
    if (!seen.add(variable)) return;
    final entries = await literal(variable);
    if (entries == null) {
      unread.add(
        '${registry.path}: ${variable.name} is not a list literal, so the '
        'scan cannot read what the registry holds through it',
      );
      return;
    }
    for (final element in entries.elements) {
      final named = switch (element) {
        SpreadElement(:final expression) => expression.unParenthesized,
        final Expression expression => expression.unParenthesized,
        _ => null,
      };
      final entry = switch (named) {
        SimpleIdentifier(:final element) => element,
        PrefixedIdentifier(:final identifier) => identifier.element,
        _ => null,
      };
      final variable = entry is PropertyAccessorElement
          ? entry.variable.baseElement
          : null;
      if (variable is! TopLevelVariableElement) {
        unread.add(
          '${registry.path}: ${element.toSource()} names no top-level '
          'variable, so the scan cannot read it as a registered provider',
        );
      } else if (element is SpreadElement || await literal(variable) != null) {
        await list(variable);
      } else {
        providers.add(variable);
      }
    }
  }

  for (final name in registry.lists) {
    final variable = library.getTopLevelVariable(name);
    if (variable == null) {
      throw StateError('${registry.path} declares no $name');
    }
    await list(variable);
  }
  return (providers: providers, unread: unread);
}

/// One line per breach of the write rule among the references [files]
/// make to a catalog write of [rule]: one whose declaration does not
/// land it and that [allowed] does not name, as
/// `path: Type.member: operation`; an entry of [allowed] that excuses
/// nothing; and each library the scan resolves that does not compile.
Future<List<String>> unlandedWritesIn(
  AnalysisHost host,
  Iterable<String> files,
  CatalogRule rule, {
  Map<String, String> allowed = const {},
}) async {
  final scan = await _Writes.open(host, files, rule);
  final errors = <String>{};
  final lines = <String>[];
  final excused = <String>{};
  for (final file in files) {
    final resolved = await scan.libraryNamingAWrite(file);
    if (resolved == null) continue;
    errors.addAll(host.errors(resolved));
    for (final unit in resolved.units) {
      for (final reference in scan.writesIn(unit.unit)) {
        final within = _declarationAround(reference);
        if (within != null && await scan.lands(within)) continue;
        final path = host.relative(unit.path);
        final holder = within == null ? '(no declaration)' : _nameOf(within);
        final key = '$path: $holder: ${reference.name}';
        excused.add(key);
        if (allowed.containsKey(key)) continue;
        lines.add(
          '$path:${unit.lineInfo.getLocation(reference.offset).lineNumber}: '
          '$holder calls ${reference.name} and never CatalogWrites.landed '
          '(to allow it: \'$key\')',
        );
      }
    }
  }
  for (final key in allowed.keys) {
    if (!excused.contains(key)) {
      lines.add(
        '\'$key\' is allowed, but no catalog write there goes unlanded (any '
        'more): drop the entry',
      );
    }
  }
  return [...errors..addAll(await scan.reads.errors()), ...lines];
}

/// One line per declaration of [named], each `path: Type.member`, that
/// is not there or does not call `landed` by the write scan's rule.
Future<List<String>> notLandingIn(
  AnalysisHost host,
  Iterable<String> named,
  CatalogRule rule,
) async {
  final scan = await _Writes.open(host, const [], rule);
  final lines = <String>[];
  for (final entry in named) {
    final [path, name] = entry.split(': ');
    final resolved = await host.resolve(host.absolute(path));
    final declared = _Declarations(name);
    for (final unit in resolved.units) {
      unit.unit.accept(declared);
    }
    if (declared.found.isEmpty) {
      lines.add('$entry is not declared (any more): drop the entry');
    } else if (!await scan.lands(declared.found.first)) {
      lines.add('$entry does not call CatalogWrites.landed');
    }
  }
  return lines;
}

class _Writes {
  _Writes(this.host, this.reads, this.operations, this.rule, this._landed);

  static Future<_Writes> open(
    AnalysisHost host,
    Iterable<String> files,
    CatalogRule rule,
  ) async {
    return _Writes(
      host,
      await LibReads.open(host, files),
      await Operations.of(host),
      rule,
      await _landedMethod(host),
    );
  }

  final AnalysisHost host;
  final LibReads reads;
  final Operations operations;
  final CatalogRule rule;
  final Element _landed;

  /// The names a catalog write goes by.
  late final Set<String> _names = {
    for (final operation in operations.all)
      if (rule.catalogWrite(operation)) operation.name,
  };

  /// The references to a catalog write under [node].
  List<SimpleIdentifier> writesIn(AstNode node) {
    final found = _References(
      (element) => switch (operations[element]) {
        final Operation operation => rule.catalogWrite(operation),
        null => false,
      },
    );
    node.accept(found);
    return found.found;
  }

  /// The library at [file], resolved, when any unit of it names a
  /// catalog write at all.
  Future<ResolvedLibraryResult?> libraryNamingAWrite(String file) =>
      _libraryNaming(host, file, _names);

  /// Whether [declaration] calls `landed`: in itself, or in a
  /// declaration it refers to, however deep, through those that hold no
  /// catalog write.
  Future<bool> lands(AstNode declaration) async {
    final seen = <AstNode>{declaration};
    final queue = [declaration];
    while (queue.isNotEmpty) {
      final step = await reads.step(queue.removeLast());
      if (step.elements.contains(_landed)) return true;
      for (final next in step.declarations) {
        // A `landed` beside a write is that write's.
        if (seen.add(next) && writesIn(next).isEmpty) queue.add(next);
      }
    }
    return false;
  }
}

/// `CatalogWrites.landed`.
Future<Element> _landedMethod(AnalysisHost host) async {
  const uri = 'package:waxdeck/src/sync/catalog_writes.dart';
  final library = await host.session.getLibraryByUri(uri);
  final landed = library is LibraryElementResult
      ? library.element.getClass('CatalogWrites')?.getMethod('landed')
      : null;
  if (landed == null) throw StateError('$uri has no CatalogWrites.landed');
  return landed;
}

/// The member or top-level declaration [node] sits in.
AstNode? _declarationAround(AstNode node) {
  for (AstNode? at = node; at != null; at = at.parent) {
    switch (at) {
      case MethodDeclaration() || ConstructorDeclaration():
        return at;
      case FunctionDeclaration(parent: CompilationUnit()):
        return at;
      case VariableDeclaration(
        parent: VariableDeclarationList(
          parent: TopLevelVariableDeclaration() || FieldDeclaration(),
        ),
      ):
        return at;
    }
  }
  return null;
}

/// [declaration] as `Type.member`, or its own name at the top level.
String _nameOf(AstNode declaration) {
  final element = switch (declaration) {
    MethodDeclaration(:final declaredFragment?) => declaredFragment.element,
    ConstructorDeclaration(:final declaredFragment?) =>
      declaredFragment.element,
    FunctionDeclaration(:final declaredFragment?) => declaredFragment.element,
    VariableDeclaration(:final declaredFragment?) => declaredFragment.element,
    _ => null,
  };
  final name = element?.name;
  if (element == null || name == null) return '(unnamed)';
  final owner = element.enclosingElement;
  return owner is InstanceElement && owner.name != null
      ? '${owner.name}.$name'
      : name;
}

/// Whether a unit names one of a set at all, outside its comments.
class _Names extends RecursiveAstVisitor<void> {
  _Names(this.names);

  final Set<String> names;
  var any = false;

  @override
  void visitComment(Comment node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    any = any || names.contains(node.name);
  }
}

/// The names under a node whose element [wanted] picks, outside its
/// comments.
class _References extends RecursiveAstVisitor<void> {
  _References(this.wanted);

  final bool Function(Element) wanted;
  final found = <SimpleIdentifier>[];

  @override
  void visitComment(Comment node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element?.baseElement;
    if (element != null && wanted(element)) found.add(node);
  }
}

/// The member and top-level declarations of a unit that go by one name,
/// as [_nameOf] gives it.
class _Declarations extends RecursiveAstVisitor<void> {
  _Declarations(this.name);

  final String name;
  final found = <AstNode>[];

  @override
  void visitMethodDeclaration(MethodDeclaration node) => _take(node);

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) => _take(node);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) _take(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_declarationAround(node) == node) _take(node);
  }

  void _take(AstNode node) {
    if (_nameOf(node) == name) found.add(node);
  }
}
