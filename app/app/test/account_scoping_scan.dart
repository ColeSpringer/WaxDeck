/// The scan `account_scoping_audit.dart` runs over `lib/`, on the
/// analyzer's resolved view of the package ([AnalysisHost]).
///
/// The providers are the top-level variables of `lib/` whose static type is
/// a Riverpod `ProviderOrFamily`, the sealed supertype of every provider and
/// family. Generated files are not read: `*.g.dart`, gen-l10n's
/// `lib/src/l10n/gen/`, and the `make generate` outputs
/// `lib/src/shell/semantics_ids.dart` and `lib/src/shell/app_version.dart`,
/// none of which declares a provider. A provider is kept alive unless the
/// Riverpod call that creates it goes through `autoDispose` (as
/// `FutureProvider.autoDispose`, `.autoDispose.family` or
/// `.family.autoDispose`) or passes `isAutoDispose: true` as a literal; even
/// then it is kept alive when its reads reach, below, refers to Riverpod's
/// `keepAlive`, since its build can then call `keepAlive()` on its `Ref`.
///
/// A function provider's build is its create callback: a closure, the
/// function it names, or the constructor it tears off, with the field
/// initializers that constructing runs. A notifier's build is the concrete
/// `build` its class runs: the class the create callback creates, else the
/// notifier type argument. A callback that tears off a constructor creates
/// its class; a closure, or a function the callback names, creates the
/// class its returns do (outside the closures in it), each an instance
/// creation, a cascade on one, or a local variable initialised by either.
/// A notifier whose callback creates more than one class, or goes through
/// a factory that does not redirect, fails, as does any provider whose
/// build the scan cannot determine.
///
/// A provider reads the repository when its build refers to the
/// `repositoryProvider` of `lib/src/providers.dart`, itself or through
/// anything of this package it refers to, however deep: functions,
/// methods, getters, setters, operators and constructors, called, torn off
/// or read, with everything inside their closures and local functions, a
/// constructor's field initializers, and the initializer of a field or
/// top-level variable it reads. The create callback of another provider it
/// names is not followed: that runs in the other provider. A member named
/// on the notifier itself (with or without `this`, or through `super`) is
/// the concrete member its class runs, so a mixin's or base class's
/// implementation of it is followed and one an override replaces is not.
/// An instance member this package declares, reached on any other object,
/// is the member it resolves to and every override of it this package
/// declares, in a subtype or a mixin a subtype applies, so an abstract
/// member is read as its implementations. A function provider that holds an object of a
/// class this package declares is read as that whole class besides: every
/// member of the class and of its supertypes and mixins this package
/// declares, since the object is the provider and outlives accounts. The
/// class is the one its callback creates, else the provider's value type
/// argument. `repositoryProvider` itself reads the repository.
///
/// A provider is keyed on the account only by `watch`, on its own `Ref`, of
/// the `signedInAccountProvider` of `lib/src/auth/auth_controller.dart`, or
/// of a `select` on it, where the build runs it as part of building: in its
/// own body, or in the body of a function, method, getter, setter or local
/// function it calls, however deep, a call on the notifier resolved as
/// above. Its own `Ref` is the create callback's ref parameter, the
/// notifier's `ref` on itself, or a `Ref` parameter of a function the build
/// calls that the call binds to its own `Ref`; a local function shares the
/// notifier and the `Ref` of the body that declares it. Never in a closure
/// (one handed to `listen`, `onDispose`, `then` or `forEach`, or stored), a
/// `late` local's or a field's initializer, a constructor the build calls,
/// or a member of another object, whose watch would be on that object's
/// ref; nor through a function only torn off or named. A read does not
/// rebuild a provider, so it keys nothing.
///
/// A library the scan resolves fails when it does not compile: what does
/// not resolve refers to nothing.
///
/// Where the rule stops is what no static scan decides. Control flow is not
/// followed: a watch after an `await` or a `return`, or in a branch,
/// counts. A function value that arrives from outside what the scan walks
/// (a parameter, a field assigned elsewhere) is not read.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'analysis_host.dart';

/// One line per breach of the rule among the providers [files] declare,
/// given the providers [exempt] from it, and one per library the scan
/// resolves that does not compile.
Future<List<String>> breachesIn(
  AnalysisHost host,
  Iterable<String> files,
  Map<String, String> exempt,
) async {
  final scan = await _Scan.open(host, files);
  final breaches = <String>[];
  final unkeyed = <String>{};
  final undetermined = <String>{};
  final declared = <String, List<String>>{};
  for (final verdict in await scan.verdicts()) {
    final (:path, :name, :unknown, :breach) = verdict;
    (declared[name] ??= []).add(path);
    if (unknown != null) {
      undetermined.add(name);
      breaches.add(
        '$path: $name has a build the scan cannot determine ($unknown); it '
        'fails closed on what it cannot read',
      );
    } else if (breach) {
      unkeyed.add(name);
      if (!exempt.containsKey(name)) {
        breaches.add(
          '$path: $name reads the repository without watching '
          'signedInAccountProvider',
        );
      }
    }
  }
  for (final name in exempt.keys) {
    final paths = declared[name] ?? const <String>[];
    if (paths.length > 1) {
      breaches.add(
        '$name is exempt, but more than one library declares a provider of '
        'that name (${paths.join(', ')}): an entry covers one provider',
      );
    } else if (!unkeyed.contains(name) && !undetermined.contains(name)) {
      breaches.add(
        '$name is exempt, but it is not a kept-alive provider that reads the '
        'repository unkeyed (any more): drop the entry',
      );
    }
  }
  return [...await scan.errors(), ...breaches];
}

/// Generated sources under `lib/`.
const _generated = [
  'lib/src/l10n/gen/',
  'lib/src/shell/app_version.dart',
  'lib/src/shell/semantics_ids.dart',
];

bool _scanned(String path) =>
    path.startsWith('lib/') &&
    path.endsWith('.dart') &&
    !path.endsWith('.g.dart') &&
    !_generated.any(path.startsWith);

/// A provider: why its build is unknown, or whether it is kept alive and
/// reads the repository unkeyed.
typedef _Verdict = ({String path, String name, String? unknown, bool breach});

/// A build: where it starts, the lookup order of the notifier class it
/// runs on (empty for a function provider), and what only reading starts
/// from besides (the class a function provider holds, whole).
typedef _Build = ({
  List<_Item> roots,
  List<InterfaceElement> chain,
  List<_Item> whole,
});

/// A body to read: [self] when its `this` is the notifier, with [holder]
/// the index in the chain of the class or mixin that declares it, and
/// [refs] the parameters in it that hold the provider's own `Ref`.
typedef _Item = ({AstNode node, bool self, int? holder, Set<Element> refs});

/// How a member is reached: on the object running the code, through
/// `super`, or on anything else.
enum _Via { self, superclass, other }

typedef _Ref = ({
  Element element,
  _Via via,
  bool invoked,
  ArgumentList? arguments,
});

class _Scan {
  _Scan(this.host, this.files, this._repository, this._account);

  static Future<_Scan> open(AnalysisHost host, Iterable<String> files) async {
    Future<TopLevelVariableElement> variable(String uri, String name) async {
      final library = await host.session.getLibraryByUri(uri);
      if (library is LibraryElementResult) {
        if (library.element.getTopLevelVariable(name) case final found?) {
          return found;
        }
      }
      throw StateError('the scan looks for $name in $uri, which lacks it');
    }

    return _Scan(
      host,
      files.toList(),
      await variable(
        'package:waxdeck/src/providers.dart',
        'repositoryProvider',
      ),
      await variable(
        'package:waxdeck/src/auth/auth_controller.dart',
        'signedInAccountProvider',
      ),
    );
  }

  final AnalysisHost host;
  final List<String> files;
  final TopLevelVariableElement _repository;
  final TopLevelVariableElement _account;
  final _libraries = <LibraryElement, Future<ResolvedLibraryResult>>{};
  final _locals = <Element, FunctionDeclaration>{};
  final _overriding = <ExecutableElement, Future<List<ExecutableElement>>>{};
  Future<Map<Element, Set<InterfaceElement>>>? _below;

  AnalysisSession get session => host.session;

  /// Each provider [files] declare.
  Future<List<_Verdict>> verdicts() async {
    final found = <_Verdict>[];
    for (final path in files.where(_scanned)) {
      final unit = await session.getUnitElement(host.absolute(path));
      if (unit is! UnitElementResult) throw StateError('cannot read $path');
      for (final fragment in unit.fragment.topLevelVariables) {
        final variable = fragment.element;
        if (!_isProvider(variable.type)) continue;
        final name = variable.name!;
        final creation = _creation(
          (await declaration(variable) as VariableDeclaration?)?.initializer,
        );
        final build = creation == null
            ? 'Riverpod does not create it'
            : await buildOf(variable, creation.arguments);
        if (build is! _Build) {
          found.add((path: path, name: name, unknown: '$build', breach: false));
          continue;
        }
        final autoDispose = creation!.autoDispose;
        final reached = await reach(build, keepAlive: autoDispose);
        found.add((
          path: path,
          name: name,
          unknown: null,
          breach:
              (!autoDispose || reached.keepsAlive) &&
              (variable == _repository || reached.reads) &&
              !await keyed(build),
        ));
      }
    }
    return found;
  }

  /// One line per unit of `lib/` the scan resolved that does not compile.
  Future<List<String>> errors() async =>
      [for (final library in _libraries.values) ...host.errors(await library)]
        ..sort();

  /// The declaration of [element] when this package declares it.
  Future<AstNode?> declaration(Element element) async {
    if (element is LocalFunctionElement) return _locals[element];
    final library = element.library;
    if (library == null || !_ours(library)) return null;
    final resolved = await (_libraries[library] ??= host.resolve(
      library.firstFragment.source.fullName,
    ));
    return resolved.getFragmentDeclaration(element.firstFragment)?.node;
  }

  /// The build of [provider], created with [arguments], or why the scan
  /// cannot tell.
  Future<Object> buildOf(
    TopLevelVariableElement provider,
    ArgumentList arguments,
  ) async {
    final callback = arguments.arguments
        .whereType<Expression>()
        .firstOrNull
        ?.unParenthesized;
    if (callback == null) return 'it has no create callback';
    final type = provider.type;
    if (_riverpodSupertype(type, const {
          r'$FunctionalProvider',
          'FunctionalFamily',
        })
        case final functional?) {
      final List<_Item> roots;
      final Set<InterfaceElement> held;
      final named = _elementOf(callback);
      if (callback is FunctionExpression) {
        roots = [_item(callback, refs: _refParameter(callback.parameters))];
        held = _held(callback.body);
      } else if (named is ConstructorElement && _ours(named.library)) {
        roots = await _construction(
          named,
          refs: {
            if (named.formalParameters.where((p) => p.isPositional).firstOrNull
                case final first?)
              first.baseElement,
          },
        );
        held = {named.enclosingElement};
      } else {
        final node = named is ExecutableElement
            ? await declaration(named)
            : null;
        final (body, parameters) = _bodyOf(node);
        if (body == null) {
          return 'its create callback is neither a closure nor a function of '
              'this package';
        }
        roots = [_item(node!, refs: _refParameter(parameters))];
        held = _held(body);
      }
      final value = functional.typeArguments[1].element;
      return (
        roots: roots,
        chain: const <InterfaceElement>[],
        whole: [
          for (final type
              in held.isNotEmpty
                  ? held
                  : {
                      if (value is InterfaceElement && _ours(value.library))
                        value,
                    })
            ...await _whole(type),
        ],
      );
    }
    final notifierType = _riverpodSupertype(type, const {
      r'$ClassProvider',
      'ClassFamily',
    })?.typeArguments.first;
    if (notifierType == null) {
      return 'it is neither a function nor a class provider';
    }
    final constructed = await _constructed(callback);
    if (constructed is String) return constructed;
    final notifier = constructed ?? notifierType.element;
    if (notifier is! ClassElement) return 'its notifier is not a class';
    final chain = _chainOf(notifier);
    for (final (index, holder) in chain.indexed) {
      final build = holder.getMethod('build');
      if (build == null || build.isAbstract || build.isStatic) continue;
      final node = await declaration(build);
      if (node is! MethodDeclaration) {
        return '${notifier.name} runs a build this package does not declare';
      }
      return (
        roots: [(node: node, self: true, holder: index, refs: <Element>{})],
        chain: chain,
        whole: const <_Item>[],
      );
    }
    return '${notifier.name} has no concrete build';
  }

  /// The class [callback], a notifier's create callback, creates: null when
  /// it creates none the scan can see, a reason when it creates more than
  /// one or goes through a factory.
  Future<Object?> _constructed(Expression callback) async {
    if (callback is ConstructorReference) {
      return _madeBy(callback.constructorName.element?.baseElement);
    }
    final FunctionBody? body;
    if (callback is FunctionExpression) {
      body = callback.body;
    } else {
      final named = _elementOf(callback);
      (body, _) = _bodyOf(
        named is ExecutableElement ? await declaration(named) : null,
      );
    }
    if (body == null) return null;
    final classes = {
      for (final constructor in _creators(body))
        constructor == null ? null : _madeBy(constructor),
    };
    if (classes.length > 1) {
      return 'its create callback returns more than one kind of notifier';
    }
    return classes.firstOrNull;
  }

  /// What [build] refers to, however deep: the repository, and, for
  /// [keepAlive], Riverpod's `keepAlive`.
  Future<({bool reads, bool keepsAlive})> reach(
    _Build build, {
    required bool keepAlive,
  }) async {
    var reads = false;
    var keepsAlive = false;
    final seen = <Object>{};
    final queue = [...build.roots, ...build.whole];
    while (queue.isNotEmpty && !(reads && (keepsAlive || !keepAlive))) {
      final item = queue.removeLast();
      if (!seen.add((item.node, item.self, item.holder))) continue;
      for (final ref in _visit(item, ranOnly: false).refs) {
        final element = ref.element;
        reads = reads || _variableOf(element) == _repository;
        keepsAlive =
            keepsAlive || element.name == 'keepAlive' && _isRiverpod(element);
        queue.addAll(await _follow(ref, item, build.chain, keys: false));
      }
    }
    return (reads: reads, keepsAlive: keepsAlive);
  }

  /// Whether [build] watches the account on its own `Ref` as part of
  /// building.
  Future<bool> keyed(_Build build) async {
    final seen = <(AstNode, bool, int?), List<Set<Element>>>{};
    final queue = [...build.roots];
    while (queue.isNotEmpty) {
      final item = queue.removeLast();
      // A field or variable initializer runs once, when first read.
      if (item.node is VariableDeclaration) continue;
      final visits = seen[(item.node, item.self, item.holder)] ??= [];
      // A visit with every ref this one has found all this one would.
      if (visits.any((refs) => refs.containsAll(item.refs))) continue;
      visits.add(item.refs);
      final ran = _visit(item, ranOnly: true);
      if (ran.calls.any(
        (call) => _watchesAccount(call) && _isOwnRef(call.realTarget, item),
      )) {
        return true;
      }
      for (final ref in ran.refs) {
        if (ref.invoked) {
          queue.addAll(await _follow(ref, item, build.chain, keys: true));
        }
      }
    }
    return false;
  }

  _Refs _visit(_Item item, {required bool ranOnly}) {
    final node = item.node;
    final refs = _Refs(
      ranOnly: ranOnly,
      own: switch (node) {
        FunctionDeclaration(:final functionExpression) => functionExpression,
        FunctionExpression() => node,
        _ => null,
      },
    );
    if (node is VariableDeclaration) {
      node.initializer?.accept(refs);
    } else {
      node.accept(refs);
    }
    _locals.addAll(refs.locals);
    return refs;
  }

  /// The bodies [ref], made from [from], leads to: for [keys], only what a
  /// call runs.
  Future<List<_Item>> _follow(
    _Ref ref,
    _Item from,
    List<InterfaceElement> chain, {
    required bool keys,
  }) async {
    final element = ref.element;
    if (element is! ExecutableElement) return const [];
    final instance =
        !element.isStatic &&
        (element is MethodElement || element is PropertyAccessorElement) &&
        element.enclosingElement is InstanceElement;
    final onNotifier = from.self && ref.via != _Via.other && instance;
    // Another object's member watches through that object's ref, if any.
    if (keys && instance && !onNotifier) return const [];
    final ExecutableElement? target;
    if (onNotifier && element.enclosingElement is InterfaceElement) {
      target = _concrete(
        chain,
        element,
        ref.via == _Via.superclass ? (from.holder ?? chain.length) + 1 : 0,
      );
    } else {
      target = element;
    }
    if (target == null) return const [];
    final bound = keys
        ? _bound(ref.arguments, from, target)
        : const <Element>{};
    final _Item Function(AstNode) at;
    if (element is LocalFunctionElement) {
      final refs = {...from.refs, ...bound};
      at = (node) =>
          (node: node, self: from.self, holder: from.holder, refs: refs);
    } else {
      final owner = target.enclosingElement;
      final self =
          onNotifier && (owner is ExtensionElement || chain.contains(owner));
      final holder = self ? chain.indexWhere((at) => at == owner) : -1;
      at = (node) => (
        node: node,
        self: self,
        holder: holder < 0 ? null : holder,
        refs: bound,
      );
    }

    final items = <_Item>[];
    for (final runs in [
      target,
      // Any other object may be of a subtype that overrides the member.
      if (!keys && instance && !onNotifier) ...await _overrides(target),
    ]) {
      if (runs is PropertyAccessorElement && runs.isOriginVariable) {
        if (runs is! GetterElement) continue;
        final variable = runs.variable;
        if (_isProvider(variable.type)) continue;
        if (await declaration(variable) case final node?) items.add(at(node));
      } else if (runs is ConstructorElement) {
        if (!keys) items.addAll(await _construction(runs));
      } else if (await declaration(runs) case final node?) {
        items.add(at(node));
      }
    }
    return items;
  }

  /// The `Ref` parameters of [target] that [arguments], made in [from],
  /// bind to the provider's own `Ref`.
  Set<Element> _bound(
    ArgumentList? arguments,
    _Item from,
    ExecutableElement target,
  ) {
    final bound = <Element>{};
    final parameters = target.formalParameters;
    final positional = [
      for (final parameter in parameters)
        if (parameter.isPositional) parameter,
    ];
    var position = 0;
    for (final argument in arguments?.arguments ?? const <Argument>[]) {
      final FormalParameterElement? parameter;
      if (argument is NamedArgument) {
        parameter = parameters
            .where((p) => p.isNamed && p.name == argument.name.lexeme)
            .firstOrNull;
      } else {
        parameter = position < positional.length ? positional[position] : null;
        position++;
      }
      if (parameter != null &&
          _riverpodSupertype(parameter.type, const {'Ref'}) != null &&
          _isOwnRef(argument.argumentExpression, from)) {
        bound.add(parameter.baseElement);
      }
    }
    return bound;
  }

  /// What constructing with [constructor] runs: its declaration, with
  /// [refs] its own `Ref`, the field initializers of its class, and the
  /// superclass constructor it calls.
  Future<List<_Item>> _construction(
    ConstructorElement constructor, {
    Set<Element> refs = const {},
  }) async => [
    if (await declaration(constructor) case final node?)
      _item(node, refs: refs),
    for (final field in constructor.enclosingElement.fields)
      if (!field.isStatic && field.hasInitializer)
        if (await declaration(field) case final node?) _item(node),
    if (constructor.superConstructor case final next?)
      ...await _construction(next.baseElement),
  ];

  /// The declarations of [type] and of its supertypes and mixins this
  /// package declares.
  Future<List<_Item>> _whole(InterfaceElement type) async => [
    for (final at in [type, ...type.allSupertypes.map((t) => t.element)])
      if (await declaration(at) case final node?) _item(node),
  ];

  /// The members of this package that an object of a subtype of the class
  /// declaring [member] runs in its place: declared in the subtype, or in a
  /// mixin it applies.
  Future<List<ExecutableElement>> _overrides(ExecutableElement member) =>
      _overriding[member] ??= () async {
        final owner = member.enclosingElement;
        final name = member.name;
        if (owner is! InterfaceElement ||
            owner is ExtensionTypeElement ||
            name == null ||
            !_ours(member.library)) {
          return const <ExecutableElement>[];
        }
        return <ExecutableElement>{
          for (final type in (await _subtypes())[owner] ?? const {})
            for (final holder in [type, ...type.mixins.map((m) => m.element)])
              if (switch (member) {
                    MethodElement() => holder.getMethod(name),
                    GetterElement() => holder.getGetter(name),
                    SetterElement() => holder.getSetter(name),
                    _ => null,
                  }
                  case final found?
                  when found != member &&
                      !found.isAbstract &&
                      !found.isStatic &&
                      !(member.isPrivate && found.library != member.library))
                found,
        }.toList();
      }();

  /// The types of this package below each type.
  Future<Map<Element, Set<InterfaceElement>>> _subtypes() =>
      _below ??= () async {
        final below = <Element, Set<InterfaceElement>>{};
        for (final type in {
          ...await (_onDisk[host] ??= _typesIn(host, libFiles(host))),
          ...await _typesIn(host, files),
        }) {
          for (final supertype in type.allSupertypes) {
            (below[supertype.element] ??= {}).add(type);
          }
        }
        return below;
      }();

  /// Whether [expression], in [item], is the provider's own `Ref`.
  bool _isOwnRef(Expression? expression, _Item item) =>
      switch (expression?.unParenthesized) {
        SimpleIdentifier(:final element?) =>
          item.refs.contains(element.baseElement) ||
              item.self && _isNotifierRef(element),
        PropertyAccess(target: ThisExpression(), :final propertyName) =>
          item.self && _isNotifierRef(propertyName.element),
        _ => false,
      };

  /// Whether [call] is `watch` on a `Ref` of the account, or of a `select`
  /// on it.
  bool _watchesAccount(MethodInvocation call) {
    final method = call.methodName.element;
    if (call.methodName.name != 'watch' || method is! MethodElement) {
      return false;
    }
    final owner = method.enclosingElement;
    if (owner is! InterfaceElement ||
        ![
          owner.thisType,
          ...owner.allSupertypes,
        ].any((type) => _isRiverpodNamed(type.element, const {'Ref'}))) {
      return false;
    }
    var listened = call.argumentList.arguments
        .whereType<Expression>()
        .firstOrNull
        ?.unParenthesized;
    if (listened case MethodInvocation(
      methodName: SimpleIdentifier(name: 'select', element: final select?),
      :final target?,
    ) when _isRiverpod(select)) {
      listened = target.unParenthesized;
    }
    return listened != null && _variableOf(_elementOf(listened)) == _account;
  }
}

/// The classes and mixins of each file of `lib/` on disk, per host.
final _onDisk = Expando<Future<List<InterfaceElement>>>();

Future<List<InterfaceElement>> _typesIn(
  AnalysisHost host,
  Iterable<String> paths,
) async => [
  for (final path in paths)
    if (await host.session.getUnitElement(host.absolute(path))
        case final UnitElementResult unit)
      for (final fragment in <InterfaceFragment>[
        ...unit.fragment.classes,
        ...unit.fragment.mixins,
        ...unit.fragment.enums,
      ])
        fragment.element,
];

_Item _item(AstNode node, {Set<Element> refs = const {}}) =>
    (node: node, self: false, holder: null, refs: refs);

/// Where Riverpod hands a create callback declaring [parameters] its `Ref`:
/// the first positional parameter.
Set<Element> _refParameter(FormalParameterList? parameters) => {
  if (parameters?.parameters.firstOrNull case final first?
      when first.isPositional)
    if (first.declaredFragment?.element case final element?)
      element.baseElement,
};

/// The body and parameters of [node], a function or method.
(FunctionBody?, FormalParameterList?) _bodyOf(AstNode? node) => switch (node) {
  FunctionDeclaration(:final functionExpression) => (
    functionExpression.body,
    functionExpression.parameters,
  ),
  MethodDeclaration(:final body, :final parameters) => (body, parameters),
  _ => (null, null),
};

/// The classes [body]'s returns create, through any redirecting factory.
Set<InterfaceElement> _held(FunctionBody body) => {
  for (final constructor in _creators(body))
    if (constructor != null)
      switch (_madeBy(constructor)) {
        final InterfaceElement made => made,
        _ => constructor.enclosingElement,
      },
};

/// The constructors [body]'s returns, outside the closures in it, create
/// with: of an instance creation, or of a local variable initialised by
/// one; null for any other return.
List<ConstructorElement?> _creators(FunctionBody body) {
  final returns = _Returns();
  body.accept(returns);
  InstanceCreationExpression? created(Expression? expression) =>
      switch (expression?.unParenthesized) {
        final InstanceCreationExpression creation => creation,
        CascadeExpression(:final target) => created(target),
        _ => null,
      };
  return [
    for (final returned
        in body is ExpressionFunctionBody ? [body.expression] : returns.found)
      (created(returned) ??
              switch (returned.unParenthesized) {
                SimpleIdentifier(:final element?) => created(
                  returns.locals[element],
                ),
                _ => null,
              })
          ?.constructorName
          .element
          ?.baseElement,
  ];
}

/// The class [constructor] creates, through redirecting factories; a
/// reason when a factory decides.
Object _madeBy(ConstructorElement? constructor) {
  final seen = <ConstructorElement>{};
  while (constructor != null && seen.add(constructor)) {
    if (!constructor.isFactory) return constructor.enclosingElement;
    constructor = constructor.redirectedConstructor?.baseElement;
  }
  return 'its create callback builds the notifier through a factory';
}

/// The classes and mixins a member of [notifier] is looked up in, in order:
/// the class, the mixins it applies from the last, then the same up its
/// superclasses.
List<InterfaceElement> _chainOf(InterfaceElement notifier) {
  final chain = <InterfaceElement>[];
  for (
    InterfaceElement? at = notifier;
    at != null && !chain.contains(at);
    at = at.supertype?.element
  ) {
    chain
      ..add(at)
      ..addAll([for (final mixin in at.mixins.reversed) mixin.element]);
  }
  return chain;
}

/// The concrete member like [like] that [chain] runs, looked up from
/// [start].
ExecutableElement? _concrete(
  List<InterfaceElement> chain,
  ExecutableElement like,
  int start,
) {
  final name = like.name;
  if (name == null) return null;
  for (final holder in chain.skip(start)) {
    final ExecutableElement? member = switch (like) {
      MethodElement() => holder.getMethod(name),
      GetterElement() => holder.getGetter(name),
      SetterElement() => holder.getSetter(name),
      _ => null,
    };
    if (member == null || member.isAbstract || member.isStatic) continue;
    if (like.isPrivate && member.library != like.library) continue;
    return member;
  }
  return null;
}

/// The returns in a body and the initializers of its locals, outside the
/// closures in it.
class _Returns extends RecursiveAstVisitor<void> {
  final found = <Expression>[];
  final locals = <Element, Expression?>{};

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (node.expression case final expression?) found.add(expression);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element case final element?) {
      locals[element] = node.initializer;
    }
    super.visitVariableDeclaration(node);
  }
}

/// The arguments of the Riverpod call [initializer] makes, and whether it
/// goes through `autoDispose`; null when it is not a Riverpod call.
({ArgumentList arguments, bool autoDispose})? _creation(
  Expression? initializer,
) {
  final call = initializer?.unParenthesized;
  final (invoked, arguments) = switch (call) {
    InstanceCreationExpression(:final constructorName, :final argumentList) => (
      constructorName.element,
      argumentList,
    ),
    MethodInvocation(:final methodName, :final argumentList) => (
      methodName.element,
      argumentList,
    ),
    FunctionExpressionInvocation(:final element, :final argumentList) => (
      element,
      argumentList,
    ),
    _ => (null, null),
  };
  if (invoked == null || arguments == null || !_isRiverpod(invoked)) {
    return null;
  }
  return (
    arguments: arguments,
    autoDispose:
        _callee(call).any(
          (name) =>
              name.name == 'autoDispose' &&
              name.element != null &&
              _isRiverpod(name.element!),
        ) ||
        arguments.arguments.any(
          (argument) => switch (argument) {
            NamedArgument(
              name: Token(lexeme: 'isAutoDispose'),
              :final argumentExpression,
            ) =>
              argumentExpression.unParenthesized is BooleanLiteral &&
                  (argumentExpression.unParenthesized as BooleanLiteral).value,
            _ => false,
          },
        ),
  );
}

/// The names a call goes through to what it calls, its arguments aside.
Iterable<SimpleIdentifier> _callee(AstNode? node) sync* {
  switch (node) {
    case InstanceCreationExpression(:final constructorName):
      if (constructorName.name case final name?) yield name;
    case MethodInvocation(:final methodName, :final target):
      yield methodName;
      yield* _callee(target);
    case FunctionExpressionInvocation(:final function):
      yield* _callee(function);
    case PropertyAccess(:final propertyName, :final target):
      yield propertyName;
      yield* _callee(target);
    case PrefixedIdentifier(:final prefix, :final identifier):
      yield identifier;
      yield prefix;
    case SimpleIdentifier():
      yield node;
    case ParenthesizedExpression(:final expression):
      yield* _callee(expression);
  }
}

/// The references in a body, with the calls made in it. With [ranOnly],
/// only what runs when the body does: not inside a closure but [own], a
/// local function's body, or a `late` local's initializer.
class _Refs extends RecursiveAstVisitor<void> {
  _Refs({required this.ranOnly, required this.own});

  final bool ranOnly;
  final FunctionExpression? own;
  final refs = <_Ref>[];
  final calls = <MethodInvocation>[];
  final locals = <Element, FunctionDeclaration>{};

  void _add(
    Element? element,
    _Via via, {
    required bool invoked,
    ArgumentList? arguments,
  }) {
    if (element != null) {
      refs.add((
        element: element.baseElement,
        via: via,
        invoked: invoked,
        arguments: arguments,
      ));
    }
  }

  static _Via _on(Expression? target) => switch (target) {
    null || ThisExpression() => _Via.self,
    SuperExpression() => _Via.superclass,
    _ => _Via.other,
  };

  @override
  void visitComment(Comment node) {}

  @override
  void visitAnnotation(Annotation node) {}

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (!ranOnly || node == own) super.visitFunctionExpression(node);
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    final declaration = node.functionDeclaration;
    if (declaration.declaredFragment?.element case final element?) {
      locals[element] = declaration;
    }
    super.visitFunctionDeclarationStatement(node);
  }

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    if (!ranOnly || !node.isLate) super.visitVariableDeclarationList(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    calls.add(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element == null) return;
    final getter = element is GetterElement;
    switch (node.parent) {
      case MethodInvocation(
            :final methodName,
            :final realTarget,
            :final argumentList,
          )
          when methodName == node:
        _add(element, _on(realTarget), invoked: true, arguments: argumentList);
      case PropertyAccess(:final propertyName, :final realTarget)
          when propertyName == node:
        _add(element, _on(realTarget), invoked: getter);
      case PrefixedIdentifier(:final identifier) when identifier == node:
        _add(element, _Via.other, invoked: getter);
      case ConstructorName():
        break;
      case DotShorthandInvocation() || DotShorthandConstructorInvocation():
        _add(element, _Via.other, invoked: true);
      default:
        _add(element, _Via.self, invoked: getter);
    }
  }

  @override
  void visitConstructorName(ConstructorName node) {
    _add(
      node.element,
      _Via.other,
      invoked: node.parent is InstanceCreationExpression,
    );
    super.visitConstructorName(node);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    _add(node.element, _Via.other, invoked: true);
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    _add(node.element, _Via.other, invoked: true);
    super.visitRedirectingConstructorInvocation(node);
  }

  void _assigned(CompoundAssignmentExpression node, Expression target) {
    final via = switch (target) {
      PropertyAccess(:final realTarget) => _on(realTarget),
      SimpleIdentifier() => _Via.self,
      _ => _Via.other,
    };
    _add(node.readElement, via, invoked: true);
    _add(node.writeElement, via, invoked: true);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _assigned(node, node.leftHandSide);
    _add(node.element, _Via.other, invoked: true);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _assigned(node, node.operand);
    _add(node.element, _Via.other, invoked: true);
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _assigned(node, node.operand);
    _add(node.element, _Via.other, invoked: true);
    super.visitPostfixExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    _add(node.element, _Via.other, invoked: true);
    super.visitBinaryExpression(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    _add(node.element, _Via.other, invoked: true);
    super.visitIndexExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _add(node.element, _Via.other, invoked: true);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitImplicitCallReference(ImplicitCallReference node) {
    _add(node.element, _Via.other, invoked: false);
    super.visitImplicitCallReference(node);
  }
}

/// The element [expression] names, when it is a name.
Element? _elementOf(Expression expression) => switch (expression) {
  Identifier(:final element) => element,
  ConstructorReference(:final constructorName) => constructorName.element,
  PropertyAccess(:final propertyName) => propertyName.element,
  FunctionReference(:final function) => _elementOf(function),
  _ => null,
}?.baseElement;

/// The variable behind [element] when it is a variable's getter.
Element? _variableOf(Element? element) =>
    element is PropertyAccessorElement ? element.variable.baseElement : element;

/// Whether [element] is the `ref` a Riverpod notifier holds.
bool _isNotifierRef(Element? element) =>
    element is GetterElement && _isRiverpodNamed(element, const {'ref'});

bool _ours(LibraryElement library) =>
    library.uri.scheme == 'package' &&
    library.uri.pathSegments.firstOrNull == 'waxdeck';

bool _isRiverpod(Element element) {
  final uri = element.library?.uri;
  return uri != null &&
      uri.scheme == 'package' &&
      const {'riverpod', 'flutter_riverpod'}.contains(uri.pathSegments.first);
}

bool _isRiverpodNamed(Element element, Set<String> names) =>
    names.contains(element.name) && _isRiverpod(element);

/// The supertype of [type] Riverpod declares under one of [names].
InterfaceType? _riverpodSupertype(DartType type, Set<String> names) {
  if (type is! InterfaceType) return null;
  for (final candidate in [type, ...type.allSupertypes]) {
    if (_isRiverpodNamed(candidate.element, names)) return candidate;
  }
  return null;
}

bool _isProvider(DartType type) =>
    _riverpodSupertype(type, const {'ProviderOrFamily'}) != null;
