import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [OrganizeApi] for `FakeRepository`.
mixin FakeOrganize on FakeRepositoryState implements OrganizeApi {
  /// Organize profiles and canned results.
  List<OrganizeProfile> organizeProfiles = const [
    OrganizeProfile(name: 'default'),
  ];
  int organizeManagedLibraries = 1;
  OrganizePlan? organizePlanResult;
  OrganizeReport organizeReportResult = const OrganizeReport(
    moved: 0,
    skipped: 0,
    failed: 0,
  );

  final List<({String? profile, List<String>? itemPids})> previewOrganizeCalls =
      [];
  final List<({String? profile, List<String>? itemPids})> applyOrganizeCalls =
      [];

  @override
  Future<OrganizeProfiles> listOrganizeProfiles() async => OrganizeProfiles(
    profiles: List.of(organizeProfiles),
    managedLibraries: organizeManagedLibraries,
  );

  /// Each saved profile, and each deleted name.
  final List<OrganizeProfile> putOrganizeProfileCalls = [];
  final List<String> deleteOrganizeProfileCalls = [];

  /// Thrown by [deleteOrganizeProfile] when set, as a library in use.
  WaxDeckApiException? deleteOrganizeProfileError;

  /// What [putOrganizeProfile] refuses with, when set.
  WaxDeckApiException? putOrganizeProfileError;

  /// What [previewOrganizeProfile] answers, from the music template.
  OrganizeSample Function(String musicTemplate) organizeSampleFor = (music) =>
      OrganizeSample(
        music: music.isEmpty ? 'Artist/Album/01 - Title.flac' : music,
        audiobook: 'Author/Title/Title.m4b',
        podcast: 'Show/Episode.mp3',
      );

  /// Where the sample compilation lands under a profile's folder, as the
  /// server lays it out: Various Artists unless set, its tagged album
  /// artist when empty.
  static String compilationSampleUnder(String? folder) =>
      '${switch (folder) {
        null => 'Various Artists',
        '' => 'Harbor Selectors',
        final named => named,
      }}/Coastal Nights/04 - Night Drive.flac';

  /// Holds profile saves and deletes in flight while a test dismisses
  /// what started them.
  Completer<void>? organizeProfileGate;

  @override
  Future<OrganizeProfile> putOrganizeProfile(
    String name, {
    String musicTemplate = '',
    String audiobookTemplate = '',
    String podcastTemplate = '',
    bool tagWrite = false,
    String? compilationFolder,
  }) async {
    await organizeProfileGate?.future;
    if (putOrganizeProfileError case final error?) throw error;
    final saved = OrganizeProfile(
      name: name,
      musicTemplate: musicTemplate,
      audiobookTemplate: audiobookTemplate,
      podcastTemplate: podcastTemplate,
      tagWrite: tagWrite,
      compilationFolder: compilationFolder,
      sample: organizeSampleFor(musicTemplate),
      saved: OrganizeTemplates(
        music: musicTemplate,
        audiobook: audiobookTemplate,
        podcast: podcastTemplate,
      ),
    );
    putOrganizeProfileCalls.add(saved);
    organizeProfiles = [
      for (final p in organizeProfiles)
        if (p.name != name) p,
      saved,
    ];
    return saved;
  }

  @override
  Future<void> deleteOrganizeProfile(String name) async {
    await organizeProfileGate?.future;
    if (deleteOrganizeProfileError case final error?) throw error;
    deleteOrganizeProfileCalls.add(name);
    organizeProfiles = [
      for (final p in organizeProfiles)
        if (p.name != name) p,
    ];
  }

  @override
  Future<OrganizeSample> previewOrganizeProfile({
    String? name,
    String musicTemplate = '',
    String audiobookTemplate = '',
    String podcastTemplate = '',
    String? compilationFolder,
  }) async {
    previewOrganizeProfileCalls.add(musicTemplate);
    previewOrganizeProfileFolders.add(compilationFolder);
    if (organizeSampleAnswer case final answer?) return answer(musicTemplate);
    final sample = organizeSampleFor(musicTemplate);
    return OrganizeSample(
      music: sample.music,
      audiobook: sample.audiobook,
      podcast: sample.podcast,
      compilation: compilationSampleUnder(compilationFolder),
    );
  }

  /// Every previewed music template, in call order.
  final List<String> previewOrganizeProfileCalls = [];

  /// Every previewed compilation folder, in call order.
  final List<String?> previewOrganizeProfileFolders = [];

  /// Answers a preview in the test's own time, when set.
  Future<OrganizeSample> Function(String musicTemplate)? organizeSampleAnswer;

  @override
  Future<OrganizePlan> previewOrganize({
    String? profile,
    List<String>? itemPids,
  }) async {
    previewOrganizeCalls.add((profile: profile, itemPids: itemPids));
    await previewOrganizeGate?.future;
    if (previewOrganizeError case final error?) throw error;
    return organizePlanResult ??
        OrganizePlan(profile: profile ?? '', totalActions: 0);
  }

  /// Holds a dry run's answer until completed, for the in-flight state.
  Completer<void>? previewOrganizeGate;

  /// What a dry run fails with, when set.
  WaxDeckApiException? previewOrganizeError;

  @override
  Future<OrganizeReport> applyOrganize({
    String? profile,
    List<String>? itemPids,
  }) async {
    applyOrganizeCalls.add((profile: profile, itemPids: itemPids));
    await applyOrganizeGate?.future;
    final report = organizeReportResult;
    // A run that ran as a job is in the history from then on, as the
    // server's journal lists it.
    if (report.jobPid.isNotEmpty) {
      organizeHistory = [
        OrganizeBatch(
          jobPid: report.jobPid,
          kind: 'organize',
          state: 'done',
          startedAt: DateTime.utc(2026, 7, 1, 9),
          profile: profile,
          committed: report.moved,
          undoable: report.moved > 0,
        ),
        ...organizeHistory,
      ];
    }
    return report;
  }

  /// Holds an apply's answer until completed, for the in-flight state.
  Completer<void>? applyOrganizeGate;

  /// The organize runs the history lists, newest first, and the limit
  /// and cursor each read asked for. A page holds at most
  /// [organizeHistoryPageCap] runs when set, as a server answers.
  List<OrganizeBatch> organizeHistory = [];
  int listOrganizeHistoryCalls = 0;
  final List<int?> organizeHistoryLimits = [];
  final List<String?> organizeHistoryCursors = [];
  int? organizeHistoryPageCap;

  /// Thrown by a read of an older page (one with a cursor) while set.
  WaxDeckApiException? organizeHistoryOlderError;

  @override
  Future<OrganizeHistoryPage> listOrganizeHistory({
    String? cursor,
    int? limit,
  }) async {
    listOrganizeHistoryCalls++;
    organizeHistoryLimits.add(limit);
    organizeHistoryCursors.add(cursor);
    if (cursor != null) {
      if (organizeHistoryOlderError case final error?) throw error;
    }
    final start = cursor == null ? 0 : int.parse(cursor);
    var size = limit ?? 20;
    if (organizeHistoryPageCap case final cap? when cap < size) size = cap;
    final end = (start + size).clamp(start, organizeHistory.length);
    return OrganizeHistoryPage(
      runs: organizeHistory.sublist(start, end),
      nextCursor: end < organizeHistory.length ? '$end' : null,
    );
  }

  /// What an undo answers, and the runs it was asked to undo.
  OrganizeReport undoOrganizeResult = const OrganizeReport(
    moved: 0,
    skipped: 0,
    failed: 0,
  );
  final List<String> undoOrganizeCalls = [];

  @override
  Future<OrganizeReport> undoOrganize(String jobPid) async {
    undoOrganizeCalls.add(jobPid);
    return undoOrganizeResult;
  }
}
