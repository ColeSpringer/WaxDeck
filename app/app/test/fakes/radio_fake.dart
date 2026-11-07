import 'dart:async';
import 'dart:math' as math;

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [RadioApi] for `FakeRepository`.
mixin FakeRadio on FakeRepositoryState implements RadioApi {
  /// Thrown by [updateRadioStation] when set, for the refusal half of
  /// the edit dialog.
  WaxDeckApiException? radioEditError;

  /// Radio stations by pid.
  final Map<String, RadioStation> radioStationsByPid = {};

  /// Directory entries served by [searchRadioDirectory].
  List<RadioDirectoryEntry> directoryEntries = const [];

  int _stationSeq = 0;

  @override
  Future<List<RadioStation>> listRadioStations() async {
    final rows = radioStationsByPid.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  /// Thrown by [createRadioStation] when set: a duplicate stream URL is
  /// the refusal the add dialog most has to render.
  WaxDeckApiException? createStationError;

  /// Every station create asked for, by stream URL.
  final List<String> createStationCalls = [];

  /// Holds [createRadioStation] until completed, with the call recorded.
  Completer<void>? createStationGate;

  @override
  Future<RadioStation> createRadioStation({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    createStationCalls.add(streamUrl);
    await createStationGate?.future;
    final error = createStationError;
    if (error != null) throw error;
    final st = RadioStation(
      pid: 'rs-FAKE${_stationSeq++}',
      name: name,
      streamUrl: streamUrl,
      homepageUrl: homepageUrl,
      logoUrl: logoUrl,
      createdAt: DateTime.utc(2026),
    );
    radioStationsByPid[st.pid] = st;
    return st;
  }

  @override
  Future<RadioStation> updateRadioStation(
    String pid, {
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    final error = radioEditError;
    if (error != null) throw error;
    final st = RadioStation(
      pid: pid,
      name: name,
      streamUrl: streamUrl,
      homepageUrl: homepageUrl,
      logoUrl: logoUrl,
      createdAt: DateTime.utc(2026),
    );
    radioStationsByPid[pid] = st;
    return st;
  }

  @override
  Future<void> deleteRadioStation(String pid) async {
    radioStationsByPid.remove(pid);
  }

  /// Holds a station's play-info call open until the test releases it, so
  /// a tune can be caught mid-flight and another one started over it.
  final Map<String, Completer<void>> radioPlayInfoGates = {};

  @override
  Future<RadioPlayInfo> getRadioPlayInfo(String pid) async {
    radioPlayInfoReads++;
    await radioPlayInfoGates[pid]?.future;
    final line = radioNowPlaying[pid];
    final saved = line == null ? null : _savedByLine[line];
    return RadioPlayInfo(
      url: '/media/radio/$pid?mt=fake',
      nowPlaying: line,
      nowPlayingItemPid: radioNowPlayingItemPid[pid],
      nowPlayingArtKey: radioNowPlayingArtKey[pid],
      nowPlayingSaved: saved != null,
      nowPlayingSavedPid: saved?.pid,
    );
  }

  /// The external-artwork key the server is holding, if any. Absent
  /// until a detached lookup lands, which is what makes the wakeup
  /// worth having.
  final Map<String, String> radioNowPlayingArtKey = {};

  /// How many times play-info has been asked for, which is the only way
  /// a test can see a request that was never made.
  int radioPlayInfoReads = 0;

  /// What each station's stream announces it is playing, when it
  /// announces anything.
  final Map<String, String> radioNowPlaying = {};

  /// The library item a station's announced line resolved to, where the
  /// server matched one. What gives a station a cover of its own rather
  /// than its logo, and so what the face's artwork shape follows.
  final Map<String, String> radioNowPlayingItemPid = {};

  /// The saved songs, newest first, keyed by the announced line so the
  /// server's identity idempotence is modelled rather than mimicked.
  final Map<String, RadioSavedSong> _savedByLine = {};
  var _savedSeq = 0;

  /// Every save request, in call order, so a test can see what line a
  /// heart actually sent.
  final List<({String stationPid, String nowPlaying})> savedSongRequests = [];

  /// Thrown by [saveRadioSong] when set: a full list is the refusal the
  /// heart has to render.
  WaxDeckApiException? saveSongError;

  /// Holds a save open until the test releases it, so a second tap can
  /// be made while the first one is still in flight.
  Future<void>? saveSongGate;

  /// Seeds the list without going through the heart.
  void seedSavedSong(RadioSavedSong song) {
    _savedByLine[song.nowPlaying] = song;
  }

  /// The cursor each saved-songs page read carried, in call order.
  final List<String?> radioSavedCursors = [];

  @override
  Future<RadioSavedSongPage> listRadioSavedSongs({
    String? cursor,
    int? limit,
  }) async {
    radioSavedCursors.add(cursor);
    if (cursor != null) await savedPageGate?.future;
    final rows = _savedByLine.values.toList(growable: false).reversed.toList();
    final from = cursor == null ? 0 : int.parse(cursor);
    final to = limit == null
        ? rows.length
        : math.min(rows.length, from + limit);
    return RadioSavedSongPage(
      songs: rows.sublist(from, to),
      nextCursor: to < rows.length ? '$to' : null,
    );
  }

  /// Holds every page after the first open, so a test can act while the
  /// list is still growing.
  Completer<void>? savedPageGate;

  @override
  Future<RadioSavedSong> saveRadioSong({
    required String stationPid,
    required String nowPlaying,
  }) async {
    savedSongRequests.add((stationPid: stationPid, nowPlaying: nowPlaying));
    await saveSongGate;
    final error = saveSongError;
    if (error != null) throw error;
    final held = _savedByLine[nowPlaying];
    if (held != null) return held;
    final parts = nowPlaying.split(' - ');
    final song = RadioSavedSong(
      pid: 'rw-FAKE${_savedSeq++}',
      nowPlaying: nowPlaying,
      artist: parts.length > 1 ? parts.first : null,
      title: parts.length > 1 ? parts.sublist(1).join(' - ') : null,
      stationPid: stationPid,
      stationName: radioStationsByPid[stationPid]?.name ?? 'Station',
      heardAt: DateTime.utc(2026),
      hasArt: false,
    );
    _savedByLine[nowPlaying] = song;
    return song;
  }

  @override
  Future<void> deleteRadioSavedSong(String pid) async {
    await deleteSavedSongGate;
    final error = deleteSavedSongError;
    if (error != null) throw error;
    _savedByLine.removeWhere((_, song) => song.pid == pid);
  }

  /// Thrown by [deleteRadioSavedSong] when set.
  WaxDeckApiException? deleteSavedSongError;

  /// Held open by a test that has to act while a saved song's delete is
  /// in flight - leaving the list screen, say.
  Future<void>? deleteSavedSongGate;

  /// Every directory query, in call order, so a test can see which surface
  /// a keystroke actually reached.
  final List<String> directoryQueries = [];

  /// Thrown by [searchRadioDirectory] when set: the directory is a public
  /// service over the internet and is unreachable while everything else
  /// works.
  WaxDeckApiException? directoryError;

  /// Holds [searchRadioDirectory] until completed, with the call already
  /// recorded.
  Completer<void>? directoryGate;

  @override
  Future<List<RadioDirectoryEntry>> searchRadioDirectory(
    String query, {
    int? limit,
  }) async {
    directoryQueries.add(query);
    if (directoryGate case final gate?) await gate.future;
    final error = directoryError;
    if (error != null) throw error;
    return directoryEntries;
  }
}
