/// Models kept hand-written because their decode does more than copy
/// fields: named constructors, wire decoding, a computed field, or a hand
/// enum standing in for the spec's. Each has a decodeX and an encodeX with
/// the codec's signatures. The generated codec and calls read the schema
/// through the decoders; an encoder is called only where a request or
/// another schema carries the class, and the others pair a decoder.
library;

import 'dart:convert';

import 'gen/codec.g.dart';
import 'models.dart';
import 'wire.dart';

/// One node of a smart rule's condition tree. [type] selects the shape:
/// `all` and `any` carry [nodes], `not` carries [node], `condition`
/// compares [field] with [op] against [value] (or [values] for
/// `inTheRange`). Values are strings on the wire regardless of the
/// field's kind.
class RuleNode {
  const RuleNode({
    required this.type,
    this.nodes = const [],
    this.node,
    this.field,
    this.op,
    this.value,
    this.values = const [],
  });

  const RuleNode.all([this.nodes = const []])
    : type = 'all',
      node = null,
      field = null,
      op = null,
      value = null,
      values = const [];

  const RuleNode.any([this.nodes = const []])
    : type = 'any',
      node = null,
      field = null,
      op = null,
      value = null,
      values = const [];

  const RuleNode.condition({
    required String this.field,
    required String this.op,
    this.value,
    this.values = const [],
  }) : type = 'condition',
       nodes = const [],
       node = null;

  final String type;
  final List<RuleNode> nodes;
  final RuleNode? node;
  final String? field;
  final String? op;
  final String? value;
  final List<String> values;
}

/// A playlist: `static` (manual ordered members) or `smart` (rule
/// evaluated on read). [itemCount] is null when omitted (smart playlists
/// on list pages). [rule] is null for static playlists.
class Playlist {
  const Playlist({
    required this.pid,
    required this.name,
    required this.kind,
    required this.visibility,
    required this.ownerName,
    required this.isOwner,
    required this.createdAt,
    required this.updatedAt,
    this.itemCount,
    this.rule,
    this.artUrl,
  });

  final String pid;
  final String name;

  /// `static` or `smart`; unknown kinds render read-only.
  final String kind;

  /// `private` or `shared`.
  final String visibility;
  final String ownerName;

  /// True when the caller owns the playlist and may edit it.
  final bool isOwner;
  final int? itemCount;
  final SmartRule? rule;

  /// The playlist's cover, when it has one: an owner's upload, or the
  /// mosaic the server builds from the members. Null means neither, so
  /// the client draws its own placeholder rather than fetching a 404.
  final String? artUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSmart => kind == 'smart';
  bool get isShared => visibility == 'shared';
}

/// How one path line of an M3U8 document reads: an entry, the item of
/// the line before it through a different path to it (another of its
/// files, or another spelling of the same file), or nothing the caller
/// can see.
enum M3uLineOutcome { matched, merged, unmatched }

/// One path line of an M3U8 document and what it matched; [item] is
/// null on an unmatched line.
class M3uPreviewLine {
  const M3uPreviewLine({required this.path, required this.outcome, this.item});

  final String path;
  final M3uLineOutcome outcome;
  final ItemSummary? item;
}

/// How an M3U8 document would import, every path line in document
/// order.
class M3uPreview {
  const M3uPreview({
    required this.matched,
    required this.merged,
    required this.unmatched,
    this.lines = const [],
  });

  final int matched;
  final int merged;
  final int unmatched;
  final List<M3uPreviewLine> lines;
}

/// One queue entry of a playback session, hydrated for display.
class PlaybackSessionEntry {
  const PlaybackSessionEntry({
    required this.pid,
    required this.title,
    this.artist,
    this.durationMs,
  });

  final String pid;
  final String title;
  final String? artist;
  final int? durationMs;

  /// A slot the caller may not see: on somebody else's session, an item
  /// outside this account's library grants keeps its place in the queue
  /// with nothing in it, so `index` still lines up.
  bool get withheld => pid.isEmpty;

  factory PlaybackSessionEntry.fromWire(Map<String, dynamic> json) {
    return PlaybackSessionEntry(
      pid: json['pid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }
}

/// One playback session: a queue playing (or paused) on an endpoint.
/// Position is a snapshot: positionMs was true at positionAt; while
/// playing, render by extrapolating forward with rate against the
/// server clock offset.
class PlaybackSessionInfo {
  const PlaybackSessionInfo({
    required this.id,
    required this.endpointId,
    required this.mine,
    required this.authority,
    required this.playing,
    required this.index,
    required this.positionMs,
    required this.positionAt,
    required this.rate,
    required this.queueVersion,
    required this.entries,
    this.endpointName,
    this.ownerName,
    this.volume,
    this.repeat,
    this.shuffle = false,
    this.ended = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? positionAt;

  final String id;
  final String endpointId;
  final String? endpointName;
  final bool mine;
  final String? ownerName;

  /// `remote` or `mirror`; open vocabulary.
  final String authority;
  final bool playing;
  final int index;
  final int positionMs;
  final DateTime positionAt;
  final double rate;
  final double? volume;
  final String? repeat;
  final bool shuffle;
  final int queueVersion;

  /// Empty when a WebSocket frame omitted the unchanged queue.
  final List<PlaybackSessionEntry> entries;
  final bool ended;

  /// The last change, position ticks included, so never before
  /// [positionAt], which it reads as when not given.
  final DateTime updatedAt;

  /// Decodes a WebSocket `session` frame payload (frames do not pass
  /// through the generated client).
  factory PlaybackSessionInfo.fromWire(Map<String, dynamic> json) {
    final entries = (json['entries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlaybackSessionEntry.fromWire)
        .toList(growable: false);
    return PlaybackSessionInfo(
      id: json['id'] as String? ?? '',
      endpointId: json['endpointId'] as String? ?? '',
      endpointName: json['endpointName'] as String?,
      mine: json['mine'] as bool? ?? false,
      ownerName: json['ownerName'] as String?,
      authority: json['authority'] as String? ?? 'remote',
      playing: json['playing'] as bool? ?? false,
      index: (json['index'] as num?)?.toInt() ?? 0,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      positionAt:
          DateTime.tryParse(json['positionAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble(),
      repeat: json['repeat'] as String?,
      shuffle: json['shuffle'] as bool? ?? false,
      queueVersion: (json['queueVersion'] as num?)?.toInt() ?? 0,
      entries: entries,
      ended: json['ended'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  /// The current entry, when the queue is known and the entry is one the
  /// caller may see.
  PlaybackSessionEntry? get currentEntry =>
      index >= 0 && index < entries.length && !entries[index].withheld
      ? entries[index]
      : null;
}

/// Whether the caller is authenticated, and as whom.
///
/// Equal to another that says the same on the wire, every field of the
/// user included: a session read again that changed nothing is not news to
/// what watches the session.
class SessionState {
  const SessionState({
    required this.authenticated,
    this.user,
    this.serverReadOnly = false,
  });

  final bool authenticated;
  final WaxDeckUser? user;

  /// The server-wide read-only switch as of this read: uploads, edits that
  /// write files and deletions are refused for every account. False when
  /// the read carries no `server` object, as a signed-out probe does not.
  final bool serverReadOnly;

  String get _wire => jsonEncode(encodeSessionState(this));

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SessionState && other._wire == _wire;

  @override
  int get hashCode => _wire.hashCode;
}

RuleNode decodeRuleNode(Map<String, Object?> json, WireContext ctx) {
  const type = 'RuleNode';
  return RuleNode(
    type: readRequired(json, 'type', type, wireString),
    nodes:
        readOptional(
          json,
          'nodes',
          type,
          (v, at) => wireList(
            v,
            at,
            (e, at) => decodeRuleNode(wireObject(e, at), ctx),
          ),
        ) ??
        const [],
    node: readOptional(
      json,
      'node',
      type,
      (v, at) => decodeRuleNode(wireObject(v, at), ctx),
    ),
    field: readOptional(json, 'field', type, wireString),
    op: readOptional(json, 'op', type, wireString),
    value: readOptional(json, 'value', type, wireString),
    values:
        readOptional(
          json,
          'values',
          type,
          (v, at) => wireList(v, at, wireString),
        ) ??
        const [],
  );
}

/// Empty [RuleNode.nodes] and [RuleNode.values] are left out: the server
/// reads them absent.
Map<String, Object?> encodeRuleNode(RuleNode value) => {
  'type': value.type,
  if (value.nodes.isNotEmpty)
    'nodes': [for (final e in value.nodes) encodeRuleNode(e)],
  if (value.node case final v?) 'node': encodeRuleNode(v),
  'field': ?value.field,
  'op': ?value.op,
  'value': ?value.value,
  if (value.values.isNotEmpty) 'values': value.values,
};

/// [Playlist.artUrl] is the shared art endpoint under the playlist's own
/// pid when the wire says it has art.
Playlist decodePlaylist(Map<String, Object?> json, WireContext ctx) {
  const type = 'Playlist';
  final pid = readRequired(json, 'pid', type, wireString);
  final hasArt = readOptional(json, 'hasArt', type, wireBool) ?? false;
  return Playlist(
    pid: pid,
    name: readRequired(json, 'name', type, wireString),
    kind: readRequired(json, 'kind', type, wireString),
    visibility: readRequired(json, 'visibility', type, wireString),
    ownerName: readRequired(json, 'ownerName', type, wireString),
    isOwner: readRequired(json, 'isOwner', type, wireBool),
    itemCount: readOptional(json, 'itemCount', type, wireInt),
    rule: readOptional(
      json,
      'rule',
      type,
      (v, at) => decodeSmartRule(wireObject(v, at), ctx),
    ),
    artUrl: hasArt
        ? resolveMediaUrl(ctx.baseUrl, '/api/v1/items/$pid/art')
        : null,
    createdAt: readRequired(json, 'createdAt', type, wireDateTime),
    updatedAt: readRequired(json, 'updatedAt', type, wireDateTime),
  );
}

Map<String, Object?> encodePlaylist(Playlist value) => {
  'pid': value.pid,
  'name': value.name,
  'kind': value.kind,
  'visibility': value.visibility,
  'ownerName': value.ownerName,
  'isOwner': value.isOwner,
  'hasArt': value.artUrl != null,
  'itemCount': ?value.itemCount,
  if (value.rule case final v?) 'rule': encodeSmartRule(v),
  'createdAt': value.createdAt.toUtc().toIso8601String(),
  'updatedAt': value.updatedAt.toUtc().toIso8601String(),
};

/// An outcome a newer server added reads as unmatched, without its item:
/// this build cannot say what such a line will do.
M3uPreviewLine decodeM3uPreviewLine(
  Map<String, Object?> json,
  WireContext ctx,
) {
  const type = 'M3uPreviewLine';
  final outcome = switch (readRequired(json, 'outcome', type, wireString)) {
    'matched' => M3uLineOutcome.matched,
    'merged' => M3uLineOutcome.merged,
    _ => M3uLineOutcome.unmatched,
  };
  return M3uPreviewLine(
    path: readRequired(json, 'path', type, wireString),
    outcome: outcome,
    item: outcome == M3uLineOutcome.unmatched
        ? null
        : readOptional(
            json,
            'item',
            type,
            (v, at) => decodeItemSummary(wireObject(v, at), ctx),
          ),
  );
}

Map<String, Object?> encodeM3uPreviewLine(M3uPreviewLine value) => {
  'path': value.path,
  'outcome': value.outcome.name,
  if (value.item case final v?) 'item': encodeItemSummary(v),
};

M3uPreview decodeM3uPreview(Map<String, Object?> json, WireContext ctx) {
  const type = 'M3uPreview';
  return M3uPreview(
    matched: readRequired(json, 'matched', type, wireInt),
    merged: readRequired(json, 'merged', type, wireInt),
    unmatched: readRequired(json, 'unmatched', type, wireInt),
    lines: readRequired(
      json,
      'entries',
      type,
      (v, at) => wireList(
        v,
        at,
        (e, at) => decodeM3uPreviewLine(wireObject(e, at), ctx),
      ),
    ),
  );
}

Map<String, Object?> encodeM3uPreview(M3uPreview value) => {
  'matched': value.matched,
  'merged': value.merged,
  'unmatched': value.unmatched,
  'entries': [for (final e in value.lines) encodeM3uPreviewLine(e)],
};

/// The codec's decode: each field fromWire reads is checked first, so a
/// wrong type fails as a malformed answer (a FormatException) rather than
/// as fromWire's cast (a TypeError), and so does a missing field the
/// contract requires. fromWire itself stays lenient, as a WebSocket frame
/// takes it too.
PlaybackSessionEntry decodePlaybackSessionEntry(
  Map<String, Object?> json,
  WireContext ctx,
) {
  const type = 'PlaybackSessionEntry';
  readRequired(json, 'pid', type, wireString);
  readRequired(json, 'title', type, wireString);
  readOptional(json, 'artist', type, wireString);
  readOptional(json, 'durationMs', type, wireInt);
  return PlaybackSessionEntry.fromWire(json);
}

Map<String, Object?> encodePlaybackSessionEntry(PlaybackSessionEntry value) => {
  'pid': value.pid,
  'title': value.title,
  'artist': ?value.artist,
  'durationMs': ?value.durationMs,
};

/// As [decodePlaybackSessionEntry], over [PlaybackSessionInfo.fromWire].
PlaybackSessionInfo decodePlaybackSessionInfo(
  Map<String, Object?> json,
  WireContext ctx,
) {
  const type = 'PlaybackSessionInfo';
  readRequired(json, 'id', type, wireString);
  readRequired(json, 'endpointId', type, wireString);
  readOptional(json, 'endpointName', type, wireString);
  readRequired(json, 'mine', type, wireBool);
  readOptional(json, 'ownerName', type, wireString);
  readRequired(json, 'authority', type, wireString);
  readRequired(json, 'playing', type, wireBool);
  readRequired(json, 'index', type, wireInt);
  readRequired(json, 'positionMs', type, wireInt);
  readRequired(json, 'positionAt', type, wireDateTime);
  readRequired(json, 'rate', type, wireDouble);
  readOptional(json, 'volume', type, wireDouble);
  readOptional(json, 'repeat', type, wireString);
  readOptional(json, 'shuffle', type, wireBool);
  readRequired(json, 'queueVersion', type, wireInt);
  readOptional(
    json,
    'entries',
    type,
    (v, at) => wireList(
      v,
      at,
      (e, at) => decodePlaybackSessionEntry(wireObject(e, at), ctx),
    ),
  );
  readOptional(json, 'ended', type, wireBool);
  readRequired(json, 'updatedAt', type, wireDateTime);
  return PlaybackSessionInfo.fromWire(json);
}

Map<String, Object?> encodePlaybackSessionInfo(PlaybackSessionInfo value) => {
  'id': value.id,
  'endpointId': value.endpointId,
  'endpointName': ?value.endpointName,
  'mine': value.mine,
  'ownerName': ?value.ownerName,
  'authority': value.authority,
  'playing': value.playing,
  'index': value.index,
  'positionMs': value.positionMs,
  'positionAt': value.positionAt.toUtc().toIso8601String(),
  'rate': value.rate,
  'volume': ?value.volume,
  'repeat': ?value.repeat,
  'shuffle': value.shuffle,
  'queueVersion': value.queueVersion,
  'entries': [for (final e in value.entries) encodePlaybackSessionEntry(e)],
  'ended': value.ended,
  'updatedAt': value.updatedAt.toUtc().toIso8601String(),
};

/// [SessionState.serverReadOnly] is the `server` object's switch, false
/// when the read carries none.
SessionState decodeSessionState(Map<String, Object?> json, WireContext ctx) {
  const type = 'SessionState';
  return SessionState(
    authenticated: readRequired(json, 'authenticated', type, wireBool),
    user: readOptional(
      json,
      'user',
      type,
      (v, at) => decodeWaxDeckUser(wireObject(v, at), ctx),
    ),
    serverReadOnly:
        readOptional(
          json,
          'server',
          type,
          (v, at) => decodeSessionServer(wireObject(v, at), ctx),
        )?.readOnly ??
        false,
  );
}

Map<String, Object?> encodeSessionState(SessionState value) => {
  'authenticated': value.authenticated,
  if (value.user case final v?) 'user': encodeWaxDeckUser(v),
  'server': encodeSessionServer(SessionServer(readOnly: value.serverReadOnly)),
};
