import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The conventions a compiler cannot see, as a ratchet.
///
/// The app's screens are supposed to reach for `waxdeck_ui` - its rows,
/// its glyphs, its spacing ladder, its type - rather than for Material's
/// primitives, and to look their copy up rather than type it. Most of
/// that is habit, and habits regress silently: a screen written in a
/// hurry grows a `SwitchListTile` beside nine `WaxSettingRow`s and
/// nothing says so.
///
/// So it is counted, per file, against a committed allowlist that may
/// only ever shrink. A count over its allowance fails with the
/// convention to reach for instead; a count under it fails just as
/// loudly with "lower it", which is what stops a conversion from
/// stalling half-done. A file with no entry has no tolerance at all -
/// that is the half that holds new code to the conventions from its
/// first line - and an entry naming a file that no longer exists fails
/// too, so a rename cannot carry a stale floor along with it.
///
/// Re-seed after adding a rule:
///
///     WAXDECK_UI_CONVENTIONS=write flutter test test/ui_conventions_test.dart
void main() {
  group('ui conventions', () {
    test('the allowlist only ever shrinks', () {
      final counts = <String, Map<String, int>>{};
      final findings = <String, List<_Finding>>{};

      for (final file in _sources()) {
        final path = _pathOf(file);
        if (_isGenerated(path)) continue;
        final (:source, :code) = _scan(path);
        final lines = source.split('\n');
        for (final rule in _rules) {
          if (!rule.appliesTo(path)) continue;
          for (final hit in rule.find(code)) {
            // Offsets survive the blanking - a comment becomes spaces of
            // the same width - so the line is the file's own.
            final line = '\n'.allMatches(code.substring(0, hit.at)).length + 1;
            counts.putIfAbsent(path, () => <String, int>{});
            counts[path]![rule.name] = (counts[path]![rule.name] ?? 0) + 1;
            findings
                .putIfAbsent(path, () => <_Finding>[])
                .add(_Finding(rule, line, lines[line - 1].trim(), hit));
          }
        }
      }

      final allowlistFile = File('test/ui_conventions_allowlist.json');
      if (Platform.environment['WAXDECK_UI_CONVENTIONS'] == 'write') {
        allowlistFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(_sorted(counts))}\n',
        );
        return;
      }

      final allowed = (jsonDecode(allowlistFile.readAsStringSync()) as Map).map(
        (file, rules) => MapEntry(
          file as String,
          (rules as Map).map(
            (rule, count) => MapEntry(rule as String, count as int),
          ),
        ),
      );

      final failures = <String>[];
      for (final file in <String>{
        ...allowed.keys,
        ...counts.keys,
      }.toList()..sort()) {
        if (!counts.containsKey(file) && !File(file).existsSync()) {
          failures.add(
            '$file: allowlisted, but there is no such file - drop the entry '
            '(a rename must not carry its old tolerance along)',
          );
          continue;
        }
        final rules = <String>{
          ...?allowed[file]?.keys,
          ...?counts[file]?.keys,
        }.toList()..sort();
        for (final rule in rules) {
          final budget = allowed[file]?[rule] ?? 0;
          final actual = counts[file]?[rule] ?? 0;
          if (actual > budget) {
            final over = findings[file]!.where((f) => f.rule.name == rule);
            failures.add(
              '$file: $rule x$actual, allowed $budget\n'
              '${over.map((f) => f.describe(file)).join('\n')}',
            );
          } else if (actual < budget) {
            failures.add(
              '$file: $rule x$actual, allowlist still says $budget - '
              'ratchet: lower it to $actual'
              '${actual == 0 ? ' (or drop the entry)' : ''}',
            );
          }
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'The allowlist in test/ui_conventions_allowlist.json only ever '
            'shrinks; re-seed it with WAXDECK_UI_CONVENTIONS=write only when '
            'adding a rule.\n\n${failures.join('\n\n')}',
      );
    });

    test('Material comes from material_ui, through the design system', () {
      // An SDK Material widget compiles beside material_ui's, then finds
      // no Theme, Material or localizations of its type above it.
      final offenders = <String>[
        ..._sourcesMatching(const <String>[_designSystem], _sdkMaterial),
        ..._sourcesMatching(_clientRoots, _anyMaterial),
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'import package:waxdeck_ui/waxdeck_ui.dart (inside waxdeck_ui, '
            'package:material_ui) instead:\n${offenders.join('\n')}',
      );
    });

    test('type comes from the design system, never a named face', () {
      // The web build cannot fetch a face it does not bundle
      // (web/index.html), so a family named here draws nothing there.
      final offenders = _sourcesMatching(const <String>['lib'], _namedFace);
      expect(
        offenders,
        isEmpty,
        reason:
            'set it in a WaxType token (WaxType.monoData, or '
            'WaxType.monoRun inside other text):\n${offenders.join('\n')}',
      );
    });

    test('selectable text is WaxProse', () {
      // On the web SelectableText selects in a hidden field set in another
      // face, so a drag highlights one span and copies another.
      final offenders = _sourcesMatching(const <String>[
        'lib',
        _designSystem,
      ], _selectableText);
      expect(
        offenders,
        isEmpty,
        reason: 'use WaxProse:\n${offenders.join('\n')}',
      );
    });

    test('a dialog says its message in prose a reader can copy', () {
      // Every dialog body was swept onto WaxProse; a bare Text there is
      // the unselectable help this rule exists to keep out.
      final offenders = <String>[
        for (final file in _sources(const <String>['lib', _designSystem]))
          if (_pathOf(file) case final path
              when !_isGenerated(path) && _dialogWithBareText(_scan(path).code))
            path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'wrap the message in WaxProse:\n${offenders.join('\n')}',
      );
    });

    test('the dialog rule reads the dialog, not what is inside it', () {
      expect(_dialogWithBareText('AlertDialog(content: Text(a))'), isTrue);
      expect(
        _dialogWithBareText('AlertDialog(content: const Text(a))'),
        isTrue,
      );
      expect(_dialogWithBareText('AlertDialog(content: WaxProse(a))'), isFalse);
      expect(
        _dialogWithBareText(
          "AlertDialog(content: WaxProse(')'), actions: [SnackBar(content: Text(b))])",
        ),
        isFalse,
      );
    });

    test('bottom sheets open through showWaxSheet', () {
      // Whose body a mouse drags to select, not to move the sheet.
      final offenders = <String>[
        for (final path in _sourcesMatching(const <String>[
          'lib',
          _designSystem,
        ], _rawSheet))
          if (!path.endsWith('/components/sheet.dart')) path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'use showWaxSheet:\n${offenders.join('\n')}',
      );
    });

    test('toasts go through the shell messenger', () {
      // The shell coalesces a run by channel; a screen's own hide eats
      // whatever unread bar another screen raised.
      final offenders = <String>[
        for (final path in _sourcesMatching(const <String>[
          'lib',
          _designSystem,
        ], _rawToast))
          if (!path.endsWith('/shell/shell_messages.dart')) path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'use shellMessengerProvider:\n${offenders.join('\n')}',
      );
    });

    test('no host installs a generated delegate list', () {
      // gen-l10n's lists name the SDK's Material tables, which material_ui
      // never reads: under es there is no Material table of its type at all.
      final offenders = _sourcesMatching(const <String>[
        ..._clientRoots,
        _designSystem,
      ], _generatedDelegates);
      expect(
        offenders,
        isEmpty,
        reason:
            'install appLocalizationsDelegates or waxLocalizationsDelegates:\n'
            '${offenders.join('\n')}',
      );
    });

    test('no app host installs the design system list', () {
      // It compiles wherever the barrel reaches but carries no
      // AppLocalizations, so context.l10n fails a null check far from the
      // cause. The app's list spreads it; this file names it.
      final offenders = <String>[
        for (final path in _sourcesMatching(_appRoots, _designSystemList))
          if (path != 'lib/src/l10n/l10n.dart' &&
              path != 'test/ui_conventions_test.dart')
            path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'install appLocalizationsDelegates:\n${offenders.join('\n')}',
      );
    });
  });

  // What the copy rule reads, pinned directly. Its counts are a sweep's
  // done-signal, and a rule that quietly stops seeing a shape reports
  // zero for a file still full of English.
  group('the copy rule', () {
    List<String> found(String code) =>
        _CopyRule().find(code).map((h) => h.hint).toList();

    test('reads past a ternary, a fallback, an arrow, and a switch', () {
      expect(found("label: on ? 'Shuffle on' : 'Shuffle off',"), hasLength(2));
      expect(found("title: item?.name ?? 'Loading',"), hasLength(1));
      expect(
        found("label: switch (r) { A() => 'Repeat all', B() => 'One' },"),
        hasLength(2),
      );
      expect(found("starLabel: (s) => s ? 'Unstar' : 'Star',"), hasLength(2));
    });

    test('reads a name by what it ends in', () {
      expect(found("ratingLabel: (n) => 'stars',"), hasLength(1));
      expect(found("emptyMessage: 'nothing here',"), hasLength(1));
      expect(found("messenger.show('started'),"), hasLength(1));
      // A field's copy arrives under a name ending in Text, not Label.
      expect(found("labelText: 'Username',"), hasLength(1));
      expect(found("helperText: 'At least 8 characters',"), hasLength(1));
      // The names that end in Text and carry no words hold no literal,
      // so they need no exception of their own.
      expect(found('obscureText: true,'), isEmpty);
    });

    test('reads every argument of a positional notification', () {
      expect(
        found("TaskNotification('{displayName}', 'Downloading {progress}')"),
        hasLength(1),
      );
      expect(
        found("const TaskNotification('Downloaded', 'Download failed'),"),
        hasLength(2),
      );
    });

    test('a placeholder the plugin fills is not copy', () {
      expect(found("title: '{displayName}',"), isEmpty);
      expect(found("title: '{numFinished} of {numTotal}',"), hasLength(1));
    });

    test('a channel name is copy', () {
      expect(
        found("androidNotificationChannelName: 'WaxDeck playback',"),
        hasLength(1),
      );
    });

    test('a debug label is not copy', () {
      expect(found("FocusNode(debugLabel: 'wax-field')"), isEmpty);
      // Only that name. A field labelled for a reader still counts.
      expect(found("label: 'Search'"), hasLength(1));
    });

    test('a literal being matched against is not copy', () {
      expect(found("label: frame['message'] as String,"), isEmpty);
      expect(found("label: switch (k) { 'detected' => other },"), isEmpty);
      expect(found("label: kind == 'backup' ? a : b,"), isEmpty);
    });

    test('formatting is not copy', () {
      expect(found(r"text: '$count',"), isEmpty);
      expect(found(r"message: warnings.join('\n'),"), isEmpty);
    });

    test('prose split across lines is one site', () {
      expect(
        found("message:\n  'one half '\n  'and the other',"),
        hasLength(1),
      );
    });

    test('a name and the widget under it count once', () {
      expect(found("title: Text('Backups'),"), hasLength(1));
    });

    test('selectable prose is text like any other', () {
      expect(found("SelectableText('Invite link'),"), hasLength(1));
      expect(found("WaxProse('Holds every slot'),"), hasLength(1));
      // The block takes a child, whose own Text is what gets counted.
      expect(found("WaxProse.block(child: Text('Empty')),"), hasLength(1));
    });

    test('prose built in code counts wherever it stands', () {
      expect(found(r"String f(int n) { return '$n queued items'; }"), [
        "'queued items'",
      ]);
      expect(found(r"final saved = 'saved ${m}m ${s}s';"), hasLength(1));
      expect(found(r"x.add('${d.count} items');"), hasLength(1));
      // Once, where a named slot reads it too.
      expect(found(r"label: '$n queued items',"), hasLength(1));
    });

    test('built text with no prose in it is formatting', () {
      expect(found(r"final key = 'sort:${choice.name}';"), isEmpty);
      expect(found(r"final at = '${d.at} [${d.source}]';"), isEmpty);
      expect(found(r"final n = ' x${d.count}';"), isEmpty);
      expect(found(r"final v = 'v$apiVersion';"), isEmpty);
      // Plain prose with nothing built into it is the named slots' to see.
      expect(found("final s = 'Nothing here yet';"), isEmpty);
    });

    test('a log line is not copy', () {
      expect(found(r"debugPrint('preload skipped: $error');"), isEmpty);
      expect(found(r"print('mint failed for $pid');"), isEmpty);
    });

    test('an exception or an assertion is not copy', () {
      expect(found(r"throw StateError('no session for $pid');"), isEmpty);
      expect(found(r"throw 'bad state in $where';"), isEmpty);
      expect(
        found(r"throw ArgumentError.value(x, 'x', 'not a pid: $x');"),
        isEmpty,
      );
      expect(found(r"assert(ok, 'never twice for $pid');"), isEmpty);
    });

    test('a name exempts a call\'s arguments only, and only a log\'s, an '
        'assertion\'s or an SDK error\'s', () {
      // Each of these draws copy, and each read as a log or an exception
      // when any bracket after a name ending in Error counted.
      expect(
        found(
          r"try { save(); } on WaxDeckApiException { "
          r"final text = 'Could not save $name'; }",
        ),
        hasLength(1),
      );
      expect(
        found(
          r"class SaveError { String get line => 'Could not save $name'; }",
        ),
        hasLength(1),
      );
      expect(
        found(r"showError(context, 'Could not save $name');"),
        hasLength(1),
      );
      expect(found(r"_LoadError(line: 'Could not load $year');"), hasLength(1));
    });

    test('an exception\'s message is not copy, wherever it is thrown or '
        'failed with', () {
      expect(
        found(r"if (bad) throw FooException('no route to $host');"),
        isEmpty,
      );
      expect(
        found(r"String f() => throw FooException('no route to $host');"),
        isEmpty,
      );
      expect(
        found(r"return Future.error(SocketException('no route to $host'));"),
        isEmpty,
      );
      expect(
        found(r"done.completeError(FooException('no route to $host'));"),
        isEmpty,
      );
    });

    test('a toString is not copy', () {
      expect(found(r"String toString() => 'Foo of $bar';"), isEmpty);
      expect(
        found(r"String toString() { return 'Foo of $bar at $baz'; }"),
        isEmpty,
      );
    });

    test('a header value is not copy', () {
      expect(found(r"headers: {'Authorization': 'Bearer $token'},"), isEmpty);
    });

    test('SQL is not copy', () {
      expect(
        found(r"db.customSelect('SELECT pid FROM items WHERE kind = $k');"),
        isEmpty,
      );
    });
  });

  // The raw-widget rules, pinned directly: each must see its widget and
  // must not see the Wax component that replaces it.
  group('the raw widget rules', () {
    int count(String rule, String code) =>
        _rules.firstWhere((r) => r.name == rule).find(code).length;

    test('buttons', () {
      expect(count('material-button', 'TextButton(onPressed: f)'), 1);
      expect(count('material-button', 'FilledButton.icon(icon: i)'), 1);
      expect(count('material-button', 'OutlinedButton.tonal()'), 1);
      expect(count('material-button', 'WaxButton(label: a)'), 0);
      // Any named constructor, but a static helper is no site of its own.
      expect(count('material-button', 'ElevatedButton.adaptive(child: c)'), 1);
      expect(count('material-button', 'WaxButton.adaptive(label: a)'), 0);
      expect(
        count('material-button', 'FilledButton.styleFrom(elevation: 0)'),
        0,
      );
    });

    test('progress indicators', () {
      expect(count('material-progress', 'CircularProgressIndicator()'), 1);
      expect(
        count('material-progress', 'LinearProgressIndicator(value: 0)'),
        1,
      );
      expect(count('material-progress', 'WaxSpinner()'), 0);
      expect(count('material-progress', 'WaxProgressBar(value: 0)'), 0);
      expect(
        count('material-progress', 'CircularProgressIndicator.adaptive()'),
        1,
      );
      expect(count('material-progress', 'WaxProgressBar.adaptive()'), 0);
    });

    test('text fields', () {
      expect(count('material-text-field', 'TextField(controller: c)'), 1);
      expect(count('material-text-field', 'TextFormField(controller: c)'), 1);
      expect(count('material-text-field', 'WaxTextField(controller: c)'), 0);
    });

    test('ink', () {
      expect(count('raw-ink', 'InkWell(onTap: f)'), 1);
      expect(count('raw-ink', 'InkResponse(onTap: f)'), 1);
      expect(count('raw-ink', 'WaxTappable(onTap: f)'), 0);
      expect(count('raw-ink', 'WaxInkTappable(onPressed: f)'), 0);
    });

    // A fix is what a sweep follows, so one naming a component the design
    // system lacks sends it to delete the primitive with nothing to swap.
    test('every component a fix names is one the design system declares', () {
      final declaration = RegExp(
        r'^(?:(?:abstract|base|final|sealed|interface) )*class (Wax\w+)',
        multiLine: true,
      );
      final declared = <String>{
        for (final file in _sources(const <String>[_designSystem]))
          for (final match in declaration.allMatches(file.readAsStringSync()))
            match.group(1)!,
      };
      expect(declared, contains('WaxTappable'), reason: 'the scan reads');
      for (final rule in _rules) {
        for (final named in RegExp(r'\bWax[A-Z]\w*').allMatches(rule.fix)) {
          expect(declared, contains(named[0]), reason: rule.name);
        }
      }
    });

    test('list tiles include the expansion tile', () {
      expect(count('material-list-tile', 'ExpansionTile(title: t)'), 1);
      expect(count('material-list-tile', 'WaxSettingRow(title: t)'), 0);
      expect(count('material-list-tile', 'WaxDisclosure(title: t)'), 0);
      for (final code in [
        'SwitchListTile.adaptive(value: v)',
        'CheckboxListTile.adaptive(value: v)',
        'RadioListTile<int>.adaptive(value: 1)',
        'ListTile.dense(title: t)',
      ]) {
        expect(count('material-list-tile', code), 1, reason: code);
      }
      expect(count('material-list-tile', 'WaxOptionRow.adaptive(title: t)'), 0);
      expect(count('material-list-tile', 'ListTile.divideTiles(tiles: t)'), 0);
    });

    test('miscellany', () {
      for (final code in [
        'Card(child: c)',
        'Divider()',
        'Slider(value: 0)',
        'Tooltip(message: m)',
        'DropdownButton<int>(items: i)',
        'DropdownButtonFormField<int>(items: i)',
        'DropdownMenu<int>(dropdownMenuEntries: e)',
        'DropdownMenuItem<int>(value: 1)',
        'DropdownMenuEntry<int>(value: 1)',
        'VerticalDivider()',
        'Card.filled(child: c)',
        'Card.outlined(child: c)',
        'Slider.adaptive(value: 0)',
        'DropdownMenuItem<int>.of(value: 1)',
        'TabBar(tabs: t)',
        'TabBar.secondary(tabs: t)',
        'TabBarView(children: c)',
        'DefaultTabController(length: 3, child: c)',
      ]) {
        expect(count('material-misc', code), 1, reason: code);
      }
      expect(count('material-misc', 'ExpansionTile(title: t)'), 0);
      for (final code in [
        'WaxSlider(value: 0)',
        'WaxTooltip(message: m)',
        'WaxMenuButton<int>(items: i)',
        'StatCard(child: c)',
        'WaxHairline()',
        'WaxHairline.vertical()',
        'WaxBanner(message: m)',
        'StatCard.filled(child: c)',
        'WaxSlider.adaptive(value: 0)',
        'Divider.createBorderSide(context)',
        'Tooltip.dismissAllToolTips()',
      ]) {
        expect(count('material-misc', code), 0, reason: code);
      }
    });

    test('the divider fix carries the band into the hairline', () {
      final fix = _rules.firstWhere((r) => r.name == 'material-misc').fix;
      expect(fix, contains('WaxHairline(extent: WaxSpace.s16)'));
      expect(fix, contains('Divider() '));
      expect(fix, contains('WaxHairline()'));
      expect(fix, contains('WaxHairline.vertical'));
      expect(fix, contains("VerticalDivider's width"));
    });

    test('spacing', () {
      expect(count('raw-spacing', 'Wrap(spacing: 8, children: c)'), 1);
      expect(count('raw-spacing', 'Wrap(runSpacing: 6)'), 1);
      expect(count('raw-spacing', 'Wrap(spacing: WaxSpace.s8)'), 0);
      expect(count('raw-spacing', 'Wrap(spacing: 0)'), 0);
      for (final code in [
        'GridView(mainAxisSpacing: 8)',
        'Delegate(crossAxisSpacing: 12)',
        'Wrap(spacing: 0.5)',
        'Wrap(runSpacing: -4)',
        'Delegate(mainAxisSpacing: -0.25)',
      ]) {
        expect(count('raw-spacing', code), 1, reason: code);
      }
      for (final code in [
        'Delegate(mainAxisSpacing: WaxShellMetrics.gridGap)',
        'Delegate(crossAxisSpacing: WaxSpace.s8)',
        'Wrap(spacing: -WaxSpace.s4)',
        'Wrap(spacing: 0.0)',
        'Delegate(mainAxisSpacing: 0)',
      ]) {
        expect(count('raw-spacing', code), 0, reason: code);
      }
    });

    test('error-only faces', () {
      // A face that reads its error off AsyncError alone draws its wait
      // through Riverpod's retry backoff: the state is AsyncLoading then,
      // still carrying the error.
      for (final code in [
        'AsyncError(:final error) => ErrorState(',
        'AsyncError() => Text(l10n.failed),',
        'case AsyncError(:final error):',
        'if (state case AsyncError(error: final e)) {}',
        'AsyncError<Foo>() => x,',
        // `when` answers loading for a read that is retrying.
        'words.when(loading: () => a, error: (e, _) => b, data: (v) => c)',
        'words.maybeWhen(error: (e, _) => b, orElse: () => a)',
        'words.whenOrNull(\n  error: (e, _) => b,\n)',
      ]) {
        expect(count('error-only-face', code), 1, reason: code);
      }
      for (final code in [
        'state = AsyncError(e, stackTrace);',
        'return AsyncError<Foo>(error, StackTrace.current);',
        'AsyncValue(:final error?) => ErrorState(',
        'AsyncValue(hasError: true) => Text(l10n.failed),',
        'words.when(skipLoadingOnReload: true, loading: () => a, '
            'error: (e, _) => b, data: (v) => c)',
        'when(x)',
      ]) {
        expect(count('error-only-face', code), 0, reason: code);
      }
    });

    test('an error state that offers a retry says when it is retrying', () {
      // Between Riverpod's retries the read is still failing and already
      // asking again: a Try again drawn live there reads as dead.
      for (final code in [
        "ErrorState(message: m, onRetry: () => ref.invalidate(p))",
        "ErrorState(\n  title: t,\n  message: m,\n  onRetry: retry,\n)",
      ]) {
        expect(count('error-state-retrying', code), 1, reason: code);
      }
      for (final code in [
        "ErrorState(message: m, retrying: s.isLoading, onRetry: retry)",
        "ErrorState(message: m, onRetry: retry, retrying: false)",
        "ErrorState(title: t, message: m)",
        "ErrorState(message: m, detail: Foo(onRetry: retry))",
      ]) {
        expect(count('error-state-retrying', code), 0, reason: code);
      }
    });

    test('an error state is built only by the house faces', () {
      final rule = _rules.firstWhere((r) => r.name == 'error-state-home');
      expect(count('error-state-home', 'ErrorState(title: t, message: m)'), 1);
      expect(count('error-state-home', 'AsyncFailureCard.from(s)'), 0);
      expect(rule.appliesTo('lib/src/settings/account_sections.dart'), isTrue);
      // The homes are counted too, each held by the allowlist at the one
      // it builds, so a second one there is caught like anywhere else.
      for (final home in [
        'lib/src/shell/async_box_face.dart',
        'lib/src/shell/async_sliver_face.dart',
        'lib/src/player/player_screen.dart',
      ]) {
        expect(rule.appliesTo(home), isTrue, reason: home);
      }
      expect(
        rule.appliesTo('$_designSystem/src/components/states.dart'),
        isFalse,
      );
    });

    test('a failed read is drawn explained', () {
      for (final code in [
        'AsyncValue(hasError: true) => Text(l10n.failed),',
        'AsyncValue(:final error?) => ErrorState(title: t),',
        'AsyncValue(hasError: true) => const SizedBox.shrink(),',
        'AsyncValue(hasError: true) when ready => Padding(\n'
            '  padding: p,\n  child: Text(l10n.failed),\n),',
        'AsyncValue(hasError: true) => <Widget>[Text(l10n.failed)],',
        'AsyncValue(error: final e?) => Text(l10n.failed),',
        'AsyncValue(hasError: true) when a == b => Text(l10n.failed),',
        'AsyncValue(hasError: true) => WaxBanner(message: l10n.down),',
        // A fixed sentence with a Retry is still a fixed sentence.
        'AsyncValue(hasError: true) => <Widget>[...local, WaxBanner(\n'
            '  message: l10n.degraded,\n  onAction: () => ref.invalidate(p),\n)],',
      ]) {
        expect(count('unexplained-failure', code), 1, reason: code);
      }
      for (final code in [
        'AsyncValue(hasError: true) => AsyncFailureCard.from(s, onRetry: r),',
        'AsyncValue(:final error?) => Text(context.explain(error)),',
        'AsyncValue(:final error?) => Text(explainError(l10n, error)),',
        'AsyncValue(hasError: true) => Padding(\n'
            '  padding: p,\n  child: AsyncFailureCard.from(s, onRetry: r),\n),',
        // A status word in a value, not a face drawn for a read.
        'AsyncValue(hasError: true) => l10n.unknown,',
        // A statement takes its own branch, not an arm's.
        'case AsyncValue(hasError: true):',
        'if (s case AsyncValue(hasError: true)) {}',
        // The arm ends at its own comma: the next arm is not its body.
        'AsyncValue(hasError: true) => Text(context.explain(e)), '
            '_ => Text(l10n.waiting),',
        // A value's arm, not the error's.
        'AsyncValue(:final value?) => Column(children: c),',
        // An explained line, asking again.
        'AsyncValue(:final error?) => WaxBanner(\n'
            '  message: context.explain(error),\n  onAction: retry,\n),',
      ]) {
        expect(count('unexplained-failure', code), 0, reason: code);
      }
    });

    test('prose slots', () {
      expect(count('prose-slot-args', "WaxField(help: 'a')"), 1);
      expect(count('prose-slot-args', "InputDecoration(helperText: 'a')"), 1);
      expect(count('prose-slot-args', "Header(overline: 'a')"), 1);
      expect(
        count('prose-slot-args', "EmptyState(title: 't', message: 'a')"),
        1,
      );
      expect(
        count(
          'prose-slot-args',
          "EmptyState(\n  title: 't',\n  message: m,\n)",
        ),
        1,
      );
      expect(count('prose-slot-args', "EmptyState(title: 't')"), 0);
      expect(
        count(
          'prose-slot-args',
          "EmptyState(title: 't', action: Foo(message: m))",
        ),
        0,
      );
      expect(count('prose-slot-args', "WaxField(helpLabel: 'a')"), 0);
      expect(count('prose-slot-args', 'x = on ? help : other;'), 0);
      expect(count('prose-slot-args', 'case help:'), 0);
      expect(count('prose-slot-args', "Text('For help: call us')"), 0);
      expect(count('prose-slot-args', 'W(a: 1,\n  help: help)'), 1);
    });

    test('the design system is not held to them', () {
      const lib = '../packages/waxdeck_ui/lib/src/components/x.dart';
      for (final name in [
        'material-button',
        'material-progress',
        'material-text-field',
        'raw-ink',
        'material-misc',
        'raw-spacing',
        'prose-slot-args',
        'material-list-tile',
      ]) {
        final rule = _rules.firstWhere((r) => r.name == name);
        expect(rule.appliesTo(lib), isFalse, reason: name);
        expect(rule.appliesTo('lib/src/a.dart'), isTrue, reason: name);
        // The catalogue is the design system's taste reference, and held.
        expect(
          rule.appliesTo(
            '../packages/waxdeck_ui/example/lib/pages/components_page.dart',
          ),
          isTrue,
          reason: name,
        );
      }
    });
  });
}

/// The generated sources, in which every rule is meaningless because
/// nobody writes them. A directory stands for everything under it.
const _generated = <String>[
  'lib/src/shell/semantics_ids.dart',
  'lib/src/shell/app_version.dart',
  'lib/src/l10n/gen',
  '../packages/waxdeck_ui/lib/src/l10n/gen',
];

bool _isGenerated(String path) =>
    _generated.any((g) => path == g || path.startsWith('$g/'));

/// Every package held to the conventions, relative to `app/app`, which
/// is where this test runs.
///
/// The catalogue is in because it is the taste reference the
/// screen-level audit judges against and would otherwise be the one
/// Flutter app in the repo where a `SwitchListTile` is invisible. Its
/// copy is the one thing it is not held to; see [_CopyRule.appliesTo].
///
/// `waxdeck_ui` itself is in for one rule and out for the rest: it
/// declares the ladder, the glyphs, and the type scale, so raw
/// measurements and Material primitives are what it is made of - but its
/// copy is copy like anywhere else, and it holds eighty strings no caller
/// can pass in. See [_Rule.appliesTo], which is where that split lives.
const _roots = <String>[
  'lib',
  _designSystem,
  '../packages/waxdeck_ui/example/lib',
  '../packages/waxdeck_data/lib',
  '../packages/waxdeck_player/lib',
];

/// The design system's own sources, which every rule but the copy one
/// has nothing to say about.
const _designSystem = '../packages/waxdeck_ui/lib';

/// The app package's own sources.
const _appRoots = <String>['lib', 'test', 'integration_test', 'tool'];

/// Every client source but the design system's library, which alone
/// imports material_ui and cupertino_ui. The pure-Dart packages cannot.
const _clientRoots = <String>[
  ..._appRoots,
  '../packages/waxdeck_data/lib',
  '../packages/waxdeck_data/test',
  '../packages/waxdeck_player/lib',
  '../packages/waxdeck_player_testing/lib',
  '../packages/waxdeck_player_testing/test',
  '../packages/waxdeck_ui/test',
  '../packages/waxdeck_ui/example/lib',
  '../packages/waxdeck_ui/example/test',
];

/// The SDK's Material and Cupertino, and the localizations typed to them.
const _sdkMaterialUris =
    r'flutter/(?:material|cupertino)\.dart|flutter_localizations/';

final _sdkMaterial = _importOf(_sdkMaterialUris);
final _anyMaterial = _importOf('$_sdkMaterialUris|material_ui/|cupertino_ui/');

RegExp _importOf(String uris) =>
    RegExp('^(?:import|export) [\'"]package:(?:$uris)', multiLine: true);

final _generatedDelegates = RegExp(
  r'\b(?:App|Wax)Localizations\.localizationsDelegates\b',
);

final _designSystemList = RegExp(r'\bwaxLocalizationsDelegates\b');

final _selectableText = RegExp(r'\bSelectableText(?:\.rich)?\(');

final _rawSheet = RegExp(r'\bshowModalBottomSheet\b');

final _rawToast = RegExp(r'\bScaffoldMessenger(?:State)?\b');

/// Whether an `AlertDialog(` in [code] takes a bare `Text` as its content.
bool _dialogWithBareText(String code) {
  for (final match in RegExp(r'\bAlertDialog\(').allMatches(code)) {
    final args = _topLevel(code, match.end - 1);
    if (RegExp(r'\bcontent\s*:\s*(?:const\s+)?Text\b').hasMatch(args)) {
      return true;
    }
  }
  return false;
}

/// The arguments of the call whose `(` is at [open], with everything
/// nested deeper, strings included, blanked to spaces.
String _topLevel(String code, int open) {
  final out = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = open; i < code.length; i++) {
    final char = code[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      out.write(' ');
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
      out.write(' ');
      continue;
    }
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) depth--;
    if (depth == 0) break;
    out.write(depth == 1 ? char : ' ');
  }
  return out.toString();
}

/// A font family spelled out as a string rather than taken from a token.
final _namedFace = RegExp(r'''\bfontFamily\s*:[^,;)]*['"]''');

List<String> _sourcesMatching(List<String> roots, RegExp pattern) => <String>[
  for (final file in _sources(roots))
    if (_pathOf(file) case final path
        when !_isGenerated(path) && pattern.hasMatch(_scan(path).code))
      path,
];

/// A source's path with forward slashes, as the allowlist spells it.
String _pathOf(File file) => file.path.split(Platform.pathSeparator).join('/');

/// Each source read and blanked once, however many tests walk it.
final _scans = <String, ({String source, String code})>{};

({String source, String code}) _scan(String path) =>
    _scans.putIfAbsent(path, () {
      final source = File(path).readAsStringSync();
      return (source: source, code: _code(source));
    });

List<File> _sources([List<String> roots = _roots]) => <File>[
  for (final root in roots)
    if (Directory(root).existsSync())
      ...Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
]..sort((a, b) => a.path.compareTo(b.path));

/// One breach: where it is, and any pointer built from its text.
class _Hit {
  const _Hit(this.at, [this.hint = '']);

  final int at;
  final String hint;
}

/// A rule states what it forbids and what to reach for instead.
class _Rule {
  const _Rule({required this.name, required this.pattern, required this.fix});

  final String name;
  final RegExp pattern;
  final String fix;

  /// Whether this rule has anything to say about [path].
  ///
  /// The design system is the standing exception: it is what the ladder,
  /// the glyphs, and the type scale are made of, so counting raw
  /// measurements and Material primitives there would count the
  /// definitions. [_CopyRule] overrides this, because copy is copy
  /// wherever it is written.
  bool appliesTo(String path) => !path.startsWith('$_designSystem/');

  Iterable<_Hit> find(String code) =>
      pattern.allMatches(code).map((m) => _Hit(m.start));
}

/// The insets rule, which a bare pattern does not fit. An `EdgeInsets`
/// call runs across lines as often as not and nests brackets when an
/// argument is computed, so its arguments are read by walking the
/// brackets rather than by matching.
class _InsetsRule extends _Rule {
  _InsetsRule()
    : super(
        name: 'raw-inset',
        // The unnamed constructor as well as the named ones:
        // `EdgeInsets(left: 16)` is the same offence spelled the long
        // way, and a pattern that demanded a `.name` waved it through.
        pattern: RegExp(r'\bEdgeInsets(?:Directional)?(?:\.\w+)?\('),
        fix: 'use the WaxSpace ladder',
      );

  /// A number standing where an argument's value goes: after the open
  /// bracket, a separator, or a label, and nothing but the next
  /// separator after it.
  ///
  /// Narrow on purpose. `WaxSpace.s12` hides digits inside an
  /// identifier, and `gutter.horizontal / 2` is arithmetic on a token
  /// rather than a measurement somebody typed - neither is the thing
  /// this rule is about, and a looser test reports both. The leading
  /// `-` is here because `only(top: -6)` is as raw as `only(top: 6)`.
  static final _literal = RegExp(
    r'(?:^|[(,:?])\s*(-?\d+(?:\.\d+)?)\s*(?=[,)]|$)',
  );

  static const _ladder = <int>[4, 8, 12, 16, 20, 24, 32, 40, 48, 64];

  @override
  Iterable<_Hit> find(String code) sync* {
    for (final match in pattern.allMatches(code)) {
      final args = arguments(code, match.end);
      if (args == null) continue;
      // Zero is structure rather than measurement - `fromLTRB(0, 0, 0,
      // WaxSpace.s8)` is already written the way the ladder wants - so
      // it is not counted and has no rung to point at.
      final values = _literal
          .allMatches(args)
          .map((m) => double.parse(m.group(1)!))
          .where((v) => v != 0)
          .toSet();
      if (values.isEmpty) continue;
      yield _Hit(match.start, rungs(values));
    }
  }

  /// The inset's own arguments: the text between the opening bracket at
  /// [start] and its partner, with anything nested inside a further call
  /// blanked out.
  ///
  /// Blanked rather than kept, because a number handed to another
  /// function is that function's business and not a measurement in
  /// pixels. `EdgeInsets.all(_s(0.07))` scales a share card by a
  /// fraction of its canvas; reading the 0.07 as a length produced the
  /// advice "0.07 -> nearest s4" and an allowlist entry that could never
  /// go to zero.
  static String? arguments(String code, int start) {
    final own = StringBuffer();
    var depth = 1;
    for (var i = start; i < code.length; i++) {
      final char = code[i];
      if (char == '(') depth++;
      if (char == ')') depth--;
      if (depth == 0) return own.toString();
      own.write(depth == 1 && char != '(' ? char : ' ');
    }
    return null;
  }

  /// The nearest rung to each literal, so the failure says what to type.
  static String rungs(Set<double> values) => (values.toList()..sort())
      .map((value) {
        final rung = _ladder.reduce(
          (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
        );
        final near = value.toString().replaceAll(RegExp(r'\.0$'), '');
        return rung == value
            ? '$near -> WaxSpace.s$rung'
            : '$near -> nearest s$rung';
      })
      .join(', ');
}

/// The gap rule: a childless `SizedBox` measured in raw pixels.
///
/// The commonest raw measurement in the codebase by a wide margin, and
/// the one an inset rule alone leaves untouched - the space between two
/// widgets is spacing whether it is spelled as padding or as an empty
/// box.
///
/// Childless is the whole distinction, and it is why this walks the
/// brackets rather than matching a pattern. `SizedBox(width: 360, child:
/// field)` is a content box being given a width, and 360 is not a rung
/// on a scale that stops at 64; `SizedBox(height: 8)` is a gap.
class _GapRule extends _Rule {
  _GapRule()
    : super(
        name: 'raw-gap',
        pattern: RegExp(r'\bSizedBox\('),
        fix: 'use the WaxSpace ladder',
      );

  static final _measure = RegExp(
    r'(?:^|,)\s*(?:width|height):\s*(-?\d+(?:\.\d+)?)\s*(?=[,)]|$)',
  );

  @override
  Iterable<_Hit> find(String code) sync* {
    for (final match in pattern.allMatches(code)) {
      final args = _InsetsRule.arguments(code, match.end);
      if (args == null || args.contains('child:')) continue;
      final values = _measure
          .allMatches(args)
          .map((m) => double.parse(m.group(1)!))
          .where((v) => v != 0)
          .toSet();
      if (values.isEmpty) continue;
      yield _Hit(match.start, _InsetsRule.rungs(values));
    }
  }
}

/// The copy rule: an English sentence typed into a widget rather than
/// looked up.
///
/// Copy is the one convention that cannot be spotted by its shape - a
/// string literal is a string literal - so it is spotted by its
/// position: the child of a `Text`, or the value of an argument name
/// that carries words to a reader. Everything else a widget is handed
/// (a pid, a wire token, a semantics identifier, a route) reaches it
/// under a different name.
///
/// A literal with no letters left once its interpolations are removed is
/// not copy: `'$count'` and `'  -  '` are formatting, and counting them
/// would put a floor on a file that has nothing to translate.
class _CopyRule extends _Rule {
  _CopyRule()
    : super(
        name: 'hardcoded-copy',
        // Matched by suffix, not by whole names, which somebody would
        // add one beside. `Text` is a suffix like the rest: it catches
        // the field parameters a form's copy arrives through.
        pattern: RegExp(
          r'\b(?:(?:Selectable)?Text|WaxProse)\(\s*|'
          // The shell messenger takes its sentence positionally.
          r'\.show\(\s*|'
          // So does a download notification, both its title and its body.
          r'\bTaskNotification\(\s*|'
          // `debugLabel` names a diagnostic-tree node no reader sees.
          r'\b(?!debugLabel\b)\w*(?:[Ll]abel|[Tt]itle|[Oo]verline|[Cc]aption|[Hh]elp'
          r'|[Hh]int|[Tt]ooltip|[Mm]essage|[Bb]lurb|[Dd]etail'
          r'|[Tt]agline|[Ss]ubject|[Tt]ext|[Cc]hannelName)\s*:\s*|'
          r'\b(?:confirmWord|semanticLabel)\s*:\s*',
        ),
        fix:
            'move it to an ARB key and read it through context.l10n '
            '(context.waxL10n inside the design system)',
      );

  /// Interpolations, so what is left is what a translator would work on.
  static final _interpolation = RegExp(r'\$\{[^{}]*\}|\$\w+');

  /// Escapes go with them: the `n` in `'\n'` is a newline, not a word,
  /// and a separator counted as copy is a floor on a finished file.
  static final _escape = RegExp(r'\\.');

  /// And the `{displayName}` a plugin fills in, which is no word either.
  static final _placeholder = RegExp(r'\{\w+\}');

  /// Calls whose every argument is copy, not only the first.
  static final _positional = RegExp(r'^TaskNotification\(');
  static final _letter = RegExp(r'[A-Za-z]');

  /// The design system is in - its components own eighty strings a
  /// caller cannot reach, and that is exactly the copy that goes
  /// untranslated by default.
  ///
  /// The catalogue is out: its strings are the demo library it draws -
  /// album titles, specimen copy - and none of it is ever translated, so
  /// counting them would put a permanent floor on the one root where a
  /// nonzero count means nothing.
  @override
  bool appliesTo(String path) =>
      !path.startsWith('../packages/waxdeck_ui/example/');

  /// Every literal in the argument's value, not the one at its head.
  ///
  /// Copy hides one token in - behind a `?:`, a `??`, an arrow, a
  /// switch arm - and a rule that reads only the head declares those
  /// files finished having never seen them. Both branches of a ternary
  /// are two sentences to translate, so both are counted.
  ///
  /// Offsets are what dedupe: `title: Text('x')` matches twice, once on
  /// the name and once on the widget, and it is one string either way.
  @override
  Iterable<_Hit> find(String code) sync* {
    final seen = <int>{};
    for (final match in pattern.allMatches(code)) {
      final end = _valueEnd(
        code,
        match.end,
        acrossArguments: _positional.hasMatch(match[0]!),
      );
      var i = match.end;
      while (i < end) {
        final read = _readLiteral(code, i);
        if (read == null) {
          i++;
          continue;
        }
        final after = _skipContinuations(code, read.end, end);
        final matched = _isMatchedAgainst(code, read.start, read.end);
        i = after;
        if (!seen.add(read.start)) continue;
        if (matched) continue;
        final words = read.body
            .replaceAll(_interpolation, '')
            .replaceAll(_escape, '')
            .replaceAll(_placeholder, '');
        if (!_letter.hasMatch(words)) continue;
        yield _Hit(read.start, _preview(words));
      }
    }
    yield* _builtProse(code, seen);
  }

  /// A word beside a space: what separates a sentence from a key, a path
  /// or a formatted number.
  static final _prose = RegExp(r'[A-Za-z]{2,} | [A-Za-z]{2,}');

  /// Calls whose arguments a reader never sees: logs, assertions, the
  /// SDK's errors and exceptions, whatever a `throw` constructs, a failed
  /// future, diagnostics. Read against what stands before a call's own
  /// parenthesis, never a block's brace: a handler, a class or a helper
  /// the app names for an error still draws copy.
  static final _unread = RegExp(
    r'(?:\b(?:debugPrint|debugPrintStack|print|printOnFailure|log|assert)'
    r'|\b(?:Error|Exception|StateError|ArgumentError|RangeError'
    r'|UnsupportedError|UnimplementedError|FormatException|TimeoutException'
    r'|AssertionError|FlutterError|ErrorDescription|ErrorSummary|ErrorHint)'
    r'(?:\.\w+)?'
    r'|\bthrow\s+[\w$.]+(?:<[^>]*>)?|\bFuture\.error|\bcompleteError'
    r'|\b(?:Diagnostics|String|Flag|Enum|Int|Double|Iterable|ObjectFlag'
    r'|Percent|Message)Property(?:<[^>]*>)?)\s*$',
  );

  static final _sql = RegExp(
    r'^\s*(?:SELECT|INSERT|UPDATE|DELETE|WITH|CREATE|DROP|ALTER|PRAGMA)\b',
  );

  /// A statement that throws, or the literal a `throw` stands before.
  static final _thrown = RegExp(r'^\s*throw\b|\bthrow\s*$');

  /// A `toString` body: the arrow's statement, or the block it opens.
  static final _toStringBody = RegExp(r'\btoString\(\)\s*(?:=>|$)');

  /// Prose put together in code: an interpolated literal holding a word
  /// beside a space, wherever it stands. A helper's return reaches a
  /// screen as surely as a `label:` does, and no name above it says so.
  ///
  /// What is not copy has a shape of its own and is left alone: a log
  /// line, an exception or assertion, a `toString`, a literal matched
  /// against, a header value (`Bearer `) and SQL.
  static Iterable<_Hit> _builtProse(String code, Set<int> seen) sync* {
    // Each open bracket and what stands before it, innermost last.
    final before = <({String bracket, String head})>[];
    var statement = 0;
    var i = 0;
    while (i < code.length) {
      final read = _readLiteral(code, i);
      if (read == null) {
        final c = code[i];
        if (c == '(' || c == '[' || c == '{') {
          before.add((
            bracket: c,
            head: code.substring(i < 80 ? 0 : i - 80, i),
          ));
        } else if ((c == ')' || c == ']' || c == '}') && before.isNotEmpty) {
          before.removeLast();
        }
        if (c == ';' || c == '{' || c == '}') statement = i + 1;
        i++;
        continue;
      }
      final end = _skipContinuations(code, read.end, code.length);
      i = end;
      if (code[read.start] == 'r' || !seen.add(read.start)) continue;
      final body = StringBuffer();
      for (var at = read.start; at < end;) {
        final segment = _readLiteral(code, at);
        if (segment == null) {
          at++;
          continue;
        }
        body.write(segment.body);
        at = segment.end;
      }
      final text = body.toString();
      if (!_interpolation.hasMatch(text)) continue;
      final words = text
          .replaceAll(_interpolation, '')
          .replaceAll(_escape, '')
          .replaceAll(_placeholder, '');
      if (!_prose.hasMatch(words)) continue;
      if (words.startsWith('Bearer ') || _sql.hasMatch(words)) continue;
      if (_isMatchedAgainst(code, read.start, read.end)) continue;
      final head = code.substring(statement, read.start);
      if (_thrown.hasMatch(head) || _toStringBody.hasMatch(head)) continue;
      if (before.any(
        (b) => switch (b.bracket) {
          '(' => _unread.hasMatch(b.head),
          '{' => _toStringBody.hasMatch(b.head),
          _ => false,
        },
      )) {
        continue;
      }
      yield _Hit(read.start, _preview(words));
    }
  }

  /// Where the value ends: the comma or closing bracket at the depth it
  /// started on. Strings are stepped over whole, so a bracket inside one
  /// cannot close it.
  static int _valueEnd(String code, int start, {bool acrossArguments = false}) {
    var depth = 0;
    var i = start;
    while (i < code.length) {
      final read = _readLiteral(code, i);
      if (read != null) {
        i = read.end;
        continue;
      }
      final c = code[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') {
        if (depth == 0) return i;
        depth--;
      }
      if (depth == 0 && !acrossArguments && (c == ',' || c == ';')) return i;
      i++;
    }
    return code.length;
  }

  /// Whether the literal is being compared rather than drawn.
  ///
  /// A switch pattern (`'detected' =>`), a map or index key
  /// (`frame['message']`), and an equality test are all wire tokens
  /// standing in an expression that does draw copy. Counting them
  /// would put a floor on files with nothing left to translate, which
  /// is the same lie as missing the copy, pointed the other way.
  static bool _isMatchedAgainst(String code, int start, int end) {
    var before = start - 1;
    while (before >= 0 && (code[before] == ' ' || code[before] == '\n')) {
      before--;
    }
    if (before >= 0 && code[before] == '[') return true;
    if (before >= 1 && (code.startsWith('==', before - 1))) return true;
    if (before >= 1 && (code.startsWith('!=', before - 1))) return true;
    if (before >= 3 && code.startsWith('case', before - 3)) return true;
    var after = end;
    while (after < code.length && (code[after] == ' ' || code[after] == '\n')) {
      after++;
    }
    return code.startsWith('=>', after) || code.startsWith(']', after);
  }

  /// Past the adjacent segments of one literal. Prose split across lines
  /// is one copy site and becomes one ARB key, so it counts once.
  static int _skipContinuations(String code, int end, int limit) {
    var i = end;
    while (i < limit) {
      if (code[i] == ' ' || code[i] == '\n' || code[i] == '\r') {
        i++;
        continue;
      }
      final next = _readLiteral(code, i);
      if (next == null) return i;
      i = next.end;
    }
    return i;
  }

  static String _preview(String words) {
    final flat = words.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 40 ? "'$flat'" : "'${flat.substring(0, 39)}...'";
  }

  /// The string literal beginning at [start], or null if what stands
  /// there is not one. The bounds ride along, because the value scan
  /// has to step over a literal to know a bracket inside it is not a
  /// bracket.
  ///
  /// Interpolations are walked rather than stopped at, because a quote
  /// inside one (`'Added "${item.title}"'`) is not the literal's end.
  static ({int start, int end, String body})? _readLiteral(
    String code,
    int start,
  ) {
    var i = start;
    final raw = i < code.length && code[i] == 'r';
    if (raw) i++;
    final quote = _quoteAt(code, i);
    if (quote == null) return null;
    i += quote.length;
    final body = StringBuffer();
    while (i < code.length) {
      if (!raw && code[i] == r'\' && i + 1 < code.length) {
        body.write(code.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (!raw && code.startsWith(r'${', i)) {
        // Nested quotes and braces live in here; hand the whole
        // interpolation through so the stripper can drop it whole.
        final end = _interpolationEnd(code, i + 2);
        if (end == null) return null;
        body.write(code.substring(i, end));
        i = end;
        continue;
      }
      if (code.startsWith(quote, i)) {
        return (start: start, end: i + quote.length, body: body.toString());
      }
      // A single-quoted literal cannot span a line; an unterminated one
      // is a scan that went wrong, not a finding.
      if (quote.length == 1 && code[i] == '\n') return null;
      body.write(code[i]);
      i++;
    }
    return null;
  }

  static int? _interpolationEnd(String code, int start) {
    var depth = 1;
    for (var i = start; i < code.length; i++) {
      if (code[i] == '{') depth++;
      if (code[i] == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return null;
  }
}

/// A raw widget of [names] (an alternation) being built: with its type
/// arguments, and through any named constructor (`Card.filled(`,
/// `RadioListTile<T>.adaptive(`). The classes' static helpers are left
/// out: a button's `styleFrom` sits inside a site the button already
/// counts, and the others build no widget.
RegExp _built(String names) => RegExp(
  '\\b(?:$names)(?:<[^>]*>)?'
  '(?:\\.(?!(?:styleFrom|createBorderSide|divideTiles|dismissAllToolTips)'
  '\\b)\\w+)?\\(',
);

final _rules = <_Rule>[
  _Rule(
    name: 'material-list-tile',
    // `ExpansionTile` is a list tile by another name.
    pattern: _built('(?:Switch|Checkbox|Radio)?ListTile|ExpansionTile'),
    fix:
        'use WaxSettingRow (a control on the right) or WaxOptionRow '
        '(a tappable row), which carry the house metrics and semantics; '
        'an ExpansionTile is a WaxDisclosure',
  ),
  _Rule(
    name: 'material-icon',
    // `Icons.` and nothing else: `WaxIcons.play` does not match, because
    // the name it ends with is not the name it is.
    pattern: RegExp(r'(?<![\w.])Icons\.\w+'),
    fix:
        'use WaxIcons, whose glyphs are the vendored subset fonts '
        '(a missing one is added with `make icons`, never by hand)',
  ),
  _InsetsRule(),
  _Rule(
    name: 'material-text-theme',
    pattern: RegExp(r'\btextTheme\b'),
    fix:
        "use WaxType, whose styles name the app's own faces; Material's "
        'text theme is a different scale wearing the same words',
  ),
  _GapRule(),
  _Rule(
    name: 'raw-radius',
    pattern: RegExp(r'\bBorderRadius\.circular\(\s*\d'),
    fix: 'use WaxRadius, which owns the corner scale',
  ),
  _Rule(
    name: 'material-button',
    pattern: _built('(?:Filled|Text|Outlined|Elevated)Button'),
    fix: 'use WaxButton, which draws the pill and takes progress: for a wait',
  ),
  _Rule(
    name: 'material-progress',
    pattern: _built('(?:Circular|Linear)ProgressIndicator'),
    fix:
        'use WaxSpinner or ProgressRing (indeterminate or a share), '
        'WaxProgressBar for a bar, or WaxButton(progress:) inside a pill',
  ),
  _Rule(
    name: 'material-text-field',
    pattern: RegExp(r'\bText(?:Form)?Field\('),
    fix: 'use WaxTextField, which carries the house field metrics',
  ),
  _Rule(
    name: 'raw-ink',
    pattern: RegExp(r'\b(?:InkWell|InkResponse)\('),
    fix:
        'use WaxInkTappable, which owns the ink and the press with focus '
        'and semantics on one callback (WaxTappable alone adds no gesture)',
  ),
  _Rule(
    name: 'material-misc',
    pattern: _built(
      'Card|Divider|Slider|Tooltip|DropdownButton|DropdownButtonFormField'
      '|DropdownMenu|DropdownMenuItem|DropdownMenuEntry|VerticalDivider'
      '|TabBar|TabBarView|DefaultTabController',
    ),
    fix:
        'use the Wax counterpart: WaxHairline for a divider, the band the '
        'divider took as its extent (WaxHairline(extent: WaxSpace.s16) for '
        "a 16 px band; a bare Divider() takes the theme's 1 px, which is "
        "WaxHairline()), WaxHairline.vertical with the VerticalDivider's "
        'width as its extent, WaxBanner for a standing message on a card '
        '(a plain surface is surface1, hairline and WaxRadius.card), '
        'WaxSlider, WaxTooltip, and for the dropdown family WaxChoice (a '
        'select that shows its value), WaxSegmented (two or three readings) '
        'or WaxMenuButton (an icon-triggered overflow), and WaxSegmented '
        'switching the view for a tab bar',
  ),
  _Rule(
    name: 'raw-spacing',
    // Any literal but zero, a fraction or a negative included.
    pattern: RegExp(
      r'\b(?:spacing|runSpacing|mainAxisSpacing|crossAxisSpacing)\s*:\s*'
      r'-?(?:0*[1-9]\d*(?:\.\d+)?|0*\.\d*[1-9])',
    ),
    fix: 'use the WaxSpace ladder',
  ),
  _ErrorOnlyFaceRule(),
  _ErrorStateRetryingRule(),
  _ErrorStateHomeRule(),
  _UnexplainedFailureRule(),
  _ProseSlotRule(),
  _CopyRule(),
];

/// The error-only-face rule: an `AsyncError` pattern, and a `when` family
/// call that does not skip loading on reload. Both hide an error that a
/// retrying read still carries: between Riverpod's retries the state is
/// AsyncLoading, which an `AsyncError` arm does not match and which
/// `when` answers with its loading face.
class _ErrorOnlyFaceRule extends _Rule {
  _ErrorOnlyFaceRule()
    : super(
        name: 'error-only-face',
        // A pattern, never a construction: a construction passes the
        // error and the trace positionally, a pattern is empty or names
        // fields.
        pattern: RegExp(r'\bAsyncError(?:<[^>]*>)?\(\s*(?:\)|:|\w+\s*:)'),
        fix:
            'read the error off any state, as AsyncSliverFace and '
            'AsyncBoxFace do (AsyncValue(:final error?) or '
            "AsyncValue(hasError: true)): between Riverpod's retries a "
            'failed read is AsyncLoading still carrying it, which an '
            'AsyncError arm or a plain when() draws as the wait',
      );

  static final _when = RegExp(r'\.(?:when|maybeWhen|whenOrNull)\(');
  static final _skips = RegExp(r'\bskipLoadingOnReload\s*:\s*true\b');

  @override
  Iterable<_Hit> find(String code) sync* {
    final hits = [...super.find(code)];
    for (final match in _when.allMatches(code)) {
      final args = _InsetsRule.arguments(code, match.end);
      if (args != null && !_skips.hasMatch(args)) hits.add(_Hit(match.start));
    }
    yield* hits..sort((a, b) => a.at.compareTo(b.at));
  }
}

/// The retrying rule: an `ErrorState` that offers Try again and does not
/// say whether the read is already asking again. Between Riverpod's
/// retries the press is spent, and a live control there reads as broken.
/// The arguments are walked, so a nested call's `onRetry` is its own.
class _ErrorStateRetryingRule extends _Rule {
  _ErrorStateRetryingRule()
    : super(
        name: 'error-state-retrying',
        pattern: RegExp(r'\bErrorState\('),
        fix:
            'draw a read failure with AsyncFailureCard.from(state, ...) or a '
            'house face, which pass retrying and drop Try again for a gone '
            'entity; otherwise pass retrying: (false where nothing retries)',
      );

  /// App code alone: the catalogue's panes stand for no read, so there
  /// is nothing for them to be retrying.
  @override
  bool appliesTo(String path) => path.startsWith('lib/');

  static final _onRetry = RegExp(r'(?<![\w.])onRetry\s*:');
  static final _retrying = RegExp(r'(?<![\w.])retrying\s*:');

  @override
  Iterable<_Hit> find(String code) sync* {
    for (final match in pattern.allMatches(code)) {
      final args = _InsetsRule.arguments(code, match.end);
      if (args != null &&
          _onRetry.hasMatch(args) &&
          !_retrying.hasMatch(args)) {
        yield _Hit(match.start);
      }
    }
  }
}

/// The home rule: an `ErrorState` built anywhere but the faces that own
/// it. A read's failure goes through `AsyncFailureCard`, which explains
/// the error, drops Try again for a gone entity and draws it busy while
/// the read asks again; a hand-built one did none of that. The homes,
/// the two house faces and the player's start failure (no read, retried
/// by its own press), are counted like any file and held by the
/// allowlist at the one each builds.
class _ErrorStateHomeRule extends _Rule {
  _ErrorStateHomeRule()
    : super(
        name: 'error-state-home',
        pattern: RegExp(r'\bErrorState\('),
        fix:
            'draw a read failure with AsyncFailureCard.from(state, title: '
            '..., onRetry: () => ref.invalidate(provider))',
      );

  @override
  bool appliesTo(String path) => path.startsWith('lib/');
}

/// The unexplained-failure rule: a switch arm for a failed read that
/// draws something, and neither `AsyncFailureCard` nor a sentence from
/// the error table, so every cause reads alike and nothing asks again.
///
/// The arm's body runs to its own comma at its own depth, so the arm
/// after it is not read as its body. An arm that answers a value rather
/// than drawing (a status word for a line built elsewhere) is not a face.
class _UnexplainedFailureRule extends _Rule {
  _UnexplainedFailureRule()
    : super(
        name: 'unexplained-failure',
        pattern: RegExp(
          r'\bAsyncValue\(\s*(?:hasError\s*:\s*true|:final\s+error\?'
          r'|error\s*:\s*final\s+\w+\?)\s*\)(?:\s+when\b(?:(?!=>)[\s\S])*)?\s*=>',
        ),
        fix:
            'draw it with AsyncFailureCard.from(state, title: ..., onRetry: '
            '...), or where no card fits a line that explains the error '
            '(context.explain) with a way to ask again',
      );

  static final _explained = RegExp(
    r'\bAsyncFailureCard\b|\bexplain(?:Error|Refusal|StationDirectory)?\(',
  );
  static final _draws = RegExp(r'\b[A-Z]\w*(?:<[^>]*>)?(?:\.\w+)?\(|\[');

  @override
  bool appliesTo(String path) => path.startsWith('lib/');

  @override
  Iterable<_Hit> find(String code) sync* {
    for (final match in pattern.allMatches(code)) {
      final body = _armBody(code, match.end);
      if (_draws.hasMatch(body) && !_explained.hasMatch(body)) {
        yield _Hit(match.start);
      }
    }
  }

  /// The arm's expression from [start]: up to the first comma at its own
  /// depth, or the bracket that closes the switch around it.
  static String _armBody(String code, int start) {
    var depth = 0;
    String? quote;
    for (var i = start; i < code.length; i++) {
      final char = code[i];
      if (quote != null) {
        if (char == r'\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
      } else if ('([{'.contains(char)) {
        depth++;
      } else if (')]}'.contains(char)) {
        if (depth == 0) return code.substring(start, i);
        depth--;
      } else if (char == ',' && depth == 0) {
        return code.substring(start, i);
      }
    }
    return code.substring(start);
  }
}

/// The prose-slot rule: the arguments that hang a sentence under a
/// label, and an empty state's body line.
///
/// A `(` or `,` before the name is what makes it an argument, so a
/// ternary's `help`, a `case help:` and a string's "help:" stay out.
///
/// `EmptyState(` takes its arguments by walking the brackets, because a
/// call runs across lines and a nested widget may carry its own
/// `message:`.
class _ProseSlotRule extends _Rule {
  _ProseSlotRule()
    : super(
        name: 'prose-slot-args',
        pattern: RegExp(r'(?<=[(,]\s*)(?:help|helperText|overline)\s*:(?!:)'),
        fix:
            'explanatory text only for a consequence the label or title '
            'hides, otherwise none',
      );

  static final _emptyState = RegExp(r'\bEmptyState\(');
  static final _message = RegExp(r'(?<![\w.])message\s*:');

  @override
  Iterable<_Hit> find(String code) sync* {
    final hits = [...super.find(code)];
    for (final match in _emptyState.allMatches(code)) {
      final args = _InsetsRule.arguments(code, match.end);
      if (args != null && _message.hasMatch(args)) hits.add(_Hit(match.start));
    }
    yield* hits..sort((a, b) => a.at.compareTo(b.at));
  }
}

class _Finding {
  const _Finding(this.rule, this.line, this.snippet, this.hit);

  final _Rule rule;
  final int line;
  final String snippet;
  final _Hit hit;

  String describe(String file) =>
      '  $file:$line  $snippet\n'
      '    -> ${rule.fix}${hit.hint.isEmpty ? '' : ' (${hit.hint})'}';
}

/// One nesting level: a string literal being read, or the code inside
/// one of its interpolations.
class _Frame {
  _Frame.string(this.quote, this.raw) : braces = 0;
  _Frame.interpolation() : quote = null, raw = false, braces = 1;

  final String? quote;
  final bool raw;
  int braces;

  bool get inString => quote != null;
}

/// The source with its comments blanked out, so that a doc comment
/// explaining a convention is not counted as a breach of it.
///
/// Offsets are preserved - a comment becomes spaces of the same width,
/// not nothing - so a match's position is still the file's own. String
/// literals are tracked only so that a `//` inside one does not start a
/// comment.
///
/// Strings and interpolations nest, which is why this is a stack rather
/// than a flag. `'${map['k']}'` is one string, holding code, holding
/// another string: a scanner that closed at the quote before `k` would
/// read `]}'` as the start of a fresh literal and put every boundary
/// after it on the wrong side. That direction of error under-counts,
/// and an under-count reports green.
String _code(String source) {
  final out = StringBuffer();
  final stack = <_Frame>[];
  var i = 0;

  while (i < source.length) {
    final frame = stack.isEmpty ? null : stack.last;

    if (frame != null && frame.inString) {
      final quote = frame.quote!;
      if (!frame.raw && source[i] == r'\' && i + 1 < source.length) {
        out.write(source.substring(i, i + 2));
        i += 2;
        continue;
      }
      // A raw string interpolates nothing; `$` is just a dollar there.
      if (!frame.raw && source.startsWith(r'${', i)) {
        out.write(r'${');
        i += 2;
        stack.add(_Frame.interpolation());
        continue;
      }
      if (source.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
        stack.removeLast();
        continue;
      }
      // A single-quoted string cannot span a line, so stopping at the
      // newline keeps an unterminated one from swallowing the file.
      if (quote.length == 1 && source[i] == '\n') {
        stack.removeLast();
        continue;
      }
      out.write(source[i]);
      i++;
      continue;
    }

    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      // Dart nests block comments, so the depth is counted rather than
      // stopping at the first close.
      var depth = 0;
      while (i < source.length) {
        if (source.startsWith('/*', i)) {
          depth++;
          out.write('  ');
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          out.write('  ');
          i += 2;
          if (depth == 0) break;
        } else {
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
      continue;
    }

    final quote = _quoteAt(source, i);
    if (quote != null) {
      // `r` marks a raw string only where it starts a token - `[r'x']`,
      // never the tail of an identifier. Compiling Dart cannot put an
      // identifier against a quote at all, so the second half of this
      // is unreachable; the scanner should not have to prove that about
      // whatever it is pointed at.
      final raw =
          i > 0 &&
          source[i - 1] == 'r' &&
          (i == 1 || !_identifier.hasMatch(source[i - 2]));
      out.write(quote);
      i += quote.length;
      stack.add(_Frame.string(quote, raw));
      continue;
    }

    if (frame != null) {
      if (source[i] == '{') frame.braces++;
      if (source[i] == '}') {
        frame.braces--;
        if (frame.braces == 0) {
          out.write('}');
          i++;
          stack.removeLast();
          continue;
        }
      }
    }

    out.write(source[i]);
    i++;
  }
  return out.toString();
}

final _identifier = RegExp(r'[\w$]');

String? _quoteAt(String source, int i) {
  for (final quote in <String>["'''", '"""', "'", '"']) {
    if (source.startsWith(quote, i)) return quote;
  }
  return null;
}

Map<String, Map<String, int>> _sorted(Map<String, Map<String, int>> counts) {
  final files = counts.keys.toList()..sort();
  return <String, Map<String, int>>{
    for (final file in files)
      file: <String, int>{
        for (final rule in counts[file]!.keys.toList()..sort())
          rule: counts[file]![rule]!,
      },
  };
}
