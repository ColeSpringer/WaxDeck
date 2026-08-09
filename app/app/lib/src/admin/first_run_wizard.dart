import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show ClientSettingKeys;
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../health/health_controller.dart';
import '../settings/client_prefs.dart';
import '../settings/settings_registry.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'admin_providers.dart';
import 'dashboard_screen.dart';

/// The three things a new server needs, in the order it needs them.
enum FirstRunStep {
  /// Nothing to scan yet: point at the libraries screen.
  addLibrary('add-library'),

  /// A root is declared and nothing has read it.
  scan('scan'),

  /// A scan is running or the first health sweep has not landed. The
  /// step with something to do while waiting.
  warming('warming');

  const FirstRunStep(this.id);

  /// The step's own name in an identifier, so a test names the step
  /// rather than a position.
  final String id;
}

/// How far the tour has got, as the one durable fact behind it.
///
/// Ordered, and compared by that order: progress only ever moves
/// forward, so a stale rebuild cannot walk it back a step.
enum FirstRunStage { none, addLibrary, scan, warming, done }

/// The furthest stage this device reached, remembered across launches.
class FirstRunProgress extends EnumSetting<FirstRunStage> {
  @override
  String get settingKey => ClientSettingKeys.firstRunProgress;

  @override
  FirstRunStage get defaultValue => FirstRunStage.none;

  @override
  List<FirstRunStage> get options => FirstRunStage.values;

  /// Records a stage the tour has reached. Never backwards: the wizard
  /// re-derives on every rebuild, and an answer computed before the
  /// stored value landed would otherwise undo real progress.
  void reach(FirstRunStage stage) {
    if (stage.index <= state.index) return;
    set(stage);
  }
}

final firstRunProgressProvider =
    NotifierProvider<FirstRunProgress, FirstRunStage>(FirstRunProgress.new);

/// Whether the guided first run is on, and which step it is showing.
///
/// Entry is strict - an administrator looking at a server with no
/// libraries - and it is the only part anything can derive. Steps two
/// and three are reached by *continuing*, not by re-deriving, because
/// derivation contradicts itself here: both later steps require
/// libraries to exist, so a gate wide enough to reach them would put
/// the wizard back on every healthy idle server and on every manual
/// rescan. Nothing stateless can tell "added a library thirty seconds
/// ago" from "running fine since March".
///
/// Which is why continuing is written down. Held in memory alone, the
/// tour was as long as a page: the console's own surface is the web,
/// where a reload is one keystroke, and after one the wizard could
/// neither continue (the entry condition it would have to re-derive is
/// no longer true, so steps two and three became unreachable for that
/// server) nor stay dismissed (a skip on a still-rootless server came
/// straight back). Both are the same missing fact, and
/// [FirstRunProgress] is it. Per device, because a tour is something a
/// person walked through rather than a property of an account.
///
/// The stored value arrives a beat after the first build - the store is
/// read asynchronously - and the wizard is written to survive that
/// rather than to wait for it: every step is derived from the stage and
/// the live server state together, so the answer corrects itself when
/// the read lands. The cost is at most a frame of dashboard before a
/// resumed tour draws, which is the right way round; a frame of *wizard*
/// on a healthy server would be the console's first lie to somebody who
/// has run it for a year.
class FirstRunWizard extends Notifier<FirstRunStep?> {
  FirstRunStep? _last;

  @override
  FirstRunStep? build() {
    if (!ref.watch(isAdminProvider)) return null;
    final reached = ref.watch(firstRunProgressProvider);
    if (reached == FirstRunStage.done) return null;

    final libraries = ref.watch(librariesProvider);
    // Nothing is decided while the answer is unknown.
    if (!libraries.hasValue) return _last;
    final roots = libraries.value ?? const <LibraryInfo>[];

    // Never entered and nothing to guide: a server that already has a
    // library was not started here.
    if (reached == FirstRunStage.none && roots.isNotEmpty) return _last = null;
    if (roots.isEmpty) {
      return _at(FirstRunStep.addLibrary, FirstRunStage.addLibrary);
    }

    // Step two is answered by the library having been read, which is a
    // scan job existing at all rather than one caught mid-flight. A
    // running scan is the same answer seen at a different moment: a
    // handful of files is indexed between two reads of this list, and a
    // step that could only be satisfied by observing the running state
    // would strand exactly the smallest libraries on it, clicking Scan
    // at a server that keeps finishing before anyone looks.
    //
    // It has to be this rather than `warmingUp`, which is true from a
    // server's first boot - before there is anything warming - and
    // would skip the step that starts the scan.
    final jobs = ref.watch(adminJobsProvider).value ?? const <Job>[];
    final scanning = jobs.any(
      (job) => job.kind == 'scan' && job.state == 'running',
    );
    final scanned =
        reached.index >= FirstRunStage.warming.index ||
        jobs.any((job) => job.kind == 'scan');
    if (!scanned) return _at(FirstRunStep.scan, FirstRunStage.scan);

    final warming = ref.watch(healthProvider).value?.warmingUp ?? false;
    if (scanning || warming) {
      return _at(FirstRunStep.warming, FirstRunStage.warming);
    }
    // Warm-up finished, which is the end of the tour and the end of the
    // wizard: there is nothing left to guide somebody through.
    _remember(FirstRunStage.done);
    return _last = null;
  }

  FirstRunStep? _at(FirstRunStep step, FirstRunStage stage) {
    _remember(stage);
    return _last = step;
  }

  /// Writes down the stage this build reached, after the build has
  /// settled: a provider may not change another one mid-build, and this
  /// is a write rather than a read. Cheap to repeat - [reach] ignores
  /// anything that is not further along - so every build may schedule
  /// one without the value ever walking backwards.
  void _remember(FirstRunStage stage) {
    unawaited(
      Future<void>.microtask(() {
        if (!ref.mounted) return;
        ref.read(firstRunProgressProvider.notifier).reach(stage);
      }),
    );
  }

  /// Ends the tour on request. Same door as finishing it, and written
  /// down the same way: a skip a reload undid would not be one.
  void skip() {
    ref.read(firstRunProgressProvider.notifier).reach(FirstRunStage.done);
    state = _last = null;
  }
}

final firstRunWizardProvider = NotifierProvider<FirstRunWizard, FirstRunStep?>(
  FirstRunWizard.new,
);

/// The guided first run: one card at a time over the dashboard.
///
/// Capability zero. Every door here opens a surface that already exists
/// - the console's libraries screen, its own Scan action, the review
/// queue - because what a new administrator is missing is not a feature
/// but an order to do things in.
class FirstRunCard extends ConsumerWidget {
  const FirstRunCard({required this.step, super.key});

  final FirstRunStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final number = step.index + 1;
    return Semantics(
      identifier: SemanticsIds.adminWizard,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(WaxSpace.s24),
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: WaxRadius.card,
            border: Border.all(color: colors.hairline),
          ),
          child: Semantics(
            identifier: SemanticsIds.adminWizardStep(step.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step $number of 3',
                  style: WaxType.overline.copyWith(color: colors.accent),
                ),
                const SizedBox(height: WaxSpace.s8),
                Text(_title(step), style: WaxType.headline),
                const SizedBox(height: WaxSpace.s8),
                Text(
                  _blurb(step),
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: WaxSpace.s20),
                Wrap(
                  spacing: WaxSpace.s12,
                  runSpacing: WaxSpace.s12,
                  children: <Widget>[
                    ..._actions(context, ref),
                    WaxButton(
                      label: 'Skip the tour',
                      kind: WaxButtonKind.text,
                      semanticsId: SemanticsIds.adminWizardSkip,
                      onPressed: () =>
                          ref.read(firstRunWizardProvider.notifier).skip(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _title(FirstRunStep step) => switch (step) {
    FirstRunStep.addLibrary => 'Point WaxDeck at your music',
    FirstRunStep.scan => 'Read what is there',
    FirstRunStep.warming => 'While it warms up',
  };

  static String _blurb(FirstRunStep step) => switch (step) {
    FirstRunStep.addLibrary =>
      'A library is a folder WaxDeck reads. Add one and everything else '
          'on this page starts having something to say.',
    FirstRunStep.scan =>
      'A scan indexes the files, pulls their tags, and identifies the '
          'albums it recognises. It runs in the background: you can leave '
          'this page.',
    FirstRunStep.warming =>
      'Files appear as they are indexed, and artwork, matching, and the '
          'health score fill in behind them. Two things worth doing '
          'meanwhile: invite the people who will listen, and look in on '
          'the albums the matcher was unsure of.',
  };

  List<Widget> _actions(BuildContext context, WidgetRef ref) => switch (step) {
    FirstRunStep.addLibrary => <Widget>[
      WaxButton(
        label: 'Add a library',
        icon: WaxIcons.albums,
        semanticsId: SemanticsIds.adminAction('add-library'),
        onPressed: () => context.go(WaxRoute.libraries),
      ),
    ],
    FirstRunStep.scan => <Widget>[
      WaxButton(
        label: 'Scan library',
        icon: WaxIcons.refresh,
        semanticsId: SemanticsIds.adminAction('scan'),
        onPressed: () => startLibraryScan(ref),
      ),
    ],
    FirstRunStep.warming => <Widget>[
      WaxButton(
        label: 'Invite listeners',
        icon: WaxIcons.artists,
        kind: WaxButtonKind.tonal,
        semanticsId: SemanticsIds.adminAction('users'),
        onPressed: () => context.go(WaxRoute.users),
      ),
      WaxButton(
        label: 'Review queue',
        icon: WaxIcons.check,
        kind: WaxButtonKind.tonal,
        semanticsId: SemanticsIds.adminAction('review'),
        onPressed: () => context.go(WaxRoute.review),
      ),
    ],
  };
}
