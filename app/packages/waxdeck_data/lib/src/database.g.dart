// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $MirrorItemsTable extends MirrorItems
    with TableInfo<$MirrorItemsTable, MirrorItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MirrorItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<String> pid = GeneratedColumn<String>(
    'pid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ulidMeta = const VerificationMeta('ulid');
  @override
  late final GeneratedColumn<String> ulid = GeneratedColumn<String>(
    'ulid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pid,
    ulid,
    mediaType,
    title,
    artist,
    album,
    durationMs,
    sortKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mirror_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MirrorItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    } else if (isInserting) {
      context.missing(_pidMeta);
    }
    if (data.containsKey('ulid')) {
      context.handle(
        _ulidMeta,
        ulid.isAcceptableOrUnknown(data['ulid']!, _ulidMeta),
      );
    } else if (isInserting) {
      context.missing(_ulidMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pid};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ulid},
  ];
  @override
  MirrorItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MirrorItem(
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pid'],
      )!,
      ulid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ulid'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
    );
  }

  @override
  $MirrorItemsTable createAlias(String alias) {
    return $MirrorItemsTable(attachedDatabase, alias);
  }
}

class MirrorItem extends DataClass implements Insertable<MirrorItem> {
  final String pid;

  /// The bare ULID (the pid without its type prefix). Delete
  /// tombstones match on it, since a tombstone's prefix is not
  /// significant once the item is gone.
  final String ulid;
  final String mediaType;
  final String title;
  final String? artist;
  final String? album;
  final int durationMs;

  /// Case-folded title for ordered offline browsing.
  final String sortKey;
  const MirrorItem({
    required this.pid,
    required this.ulid,
    required this.mediaType,
    required this.title,
    this.artist,
    this.album,
    required this.durationMs,
    required this.sortKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pid'] = Variable<String>(pid);
    map['ulid'] = Variable<String>(ulid);
    map['media_type'] = Variable<String>(mediaType);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    map['sort_key'] = Variable<String>(sortKey);
    return map;
  }

  MirrorItemsCompanion toCompanion(bool nullToAbsent) {
    return MirrorItemsCompanion(
      pid: Value(pid),
      ulid: Value(ulid),
      mediaType: Value(mediaType),
      title: Value(title),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      durationMs: Value(durationMs),
      sortKey: Value(sortKey),
    );
  }

  factory MirrorItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MirrorItem(
      pid: serializer.fromJson<String>(json['pid']),
      ulid: serializer.fromJson<String>(json['ulid']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pid': serializer.toJson<String>(pid),
      'ulid': serializer.toJson<String>(ulid),
      'mediaType': serializer.toJson<String>(mediaType),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'durationMs': serializer.toJson<int>(durationMs),
      'sortKey': serializer.toJson<String>(sortKey),
    };
  }

  MirrorItem copyWith({
    String? pid,
    String? ulid,
    String? mediaType,
    String? title,
    Value<String?> artist = const Value.absent(),
    Value<String?> album = const Value.absent(),
    int? durationMs,
    String? sortKey,
  }) => MirrorItem(
    pid: pid ?? this.pid,
    ulid: ulid ?? this.ulid,
    mediaType: mediaType ?? this.mediaType,
    title: title ?? this.title,
    artist: artist.present ? artist.value : this.artist,
    album: album.present ? album.value : this.album,
    durationMs: durationMs ?? this.durationMs,
    sortKey: sortKey ?? this.sortKey,
  );
  MirrorItem copyWithCompanion(MirrorItemsCompanion data) {
    return MirrorItem(
      pid: data.pid.present ? data.pid.value : this.pid,
      ulid: data.ulid.present ? data.ulid.value : this.ulid,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MirrorItem(')
          ..write('pid: $pid, ')
          ..write('ulid: $ulid, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('sortKey: $sortKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pid,
    ulid,
    mediaType,
    title,
    artist,
    album,
    durationMs,
    sortKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MirrorItem &&
          other.pid == this.pid &&
          other.ulid == this.ulid &&
          other.mediaType == this.mediaType &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.durationMs == this.durationMs &&
          other.sortKey == this.sortKey);
}

class MirrorItemsCompanion extends UpdateCompanion<MirrorItem> {
  final Value<String> pid;
  final Value<String> ulid;
  final Value<String> mediaType;
  final Value<String> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<int> durationMs;
  final Value<String> sortKey;
  final Value<int> rowid;
  const MirrorItemsCompanion({
    this.pid = const Value.absent(),
    this.ulid = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MirrorItemsCompanion.insert({
    required String pid,
    required String ulid,
    required String mediaType,
    required String title,
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    required int durationMs,
    required String sortKey,
    this.rowid = const Value.absent(),
  }) : pid = Value(pid),
       ulid = Value(ulid),
       mediaType = Value(mediaType),
       title = Value(title),
       durationMs = Value(durationMs),
       sortKey = Value(sortKey);
  static Insertable<MirrorItem> custom({
    Expression<String>? pid,
    Expression<String>? ulid,
    Expression<String>? mediaType,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<int>? durationMs,
    Expression<String>? sortKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pid != null) 'pid': pid,
      if (ulid != null) 'ulid': ulid,
      if (mediaType != null) 'media_type': mediaType,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sortKey != null) 'sort_key': sortKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MirrorItemsCompanion copyWith({
    Value<String>? pid,
    Value<String>? ulid,
    Value<String>? mediaType,
    Value<String>? title,
    Value<String?>? artist,
    Value<String?>? album,
    Value<int>? durationMs,
    Value<String>? sortKey,
    Value<int>? rowid,
  }) {
    return MirrorItemsCompanion(
      pid: pid ?? this.pid,
      ulid: ulid ?? this.ulid,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      sortKey: sortKey ?? this.sortKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pid.present) {
      map['pid'] = Variable<String>(pid.value);
    }
    if (ulid.present) {
      map['ulid'] = Variable<String>(ulid.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MirrorItemsCompanion(')
          ..write('pid: $pid, ')
          ..write('ulid: $ulid, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('sortKey: $sortKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MirrorPlayStatesTable extends MirrorPlayStates
    with TableInfo<$MirrorPlayStatesTable, MirrorPlayState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MirrorPlayStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<String> pid = GeneratedColumn<String>(
    'pid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _playedMeta = const VerificationMeta('played');
  @override
  late final GeneratedColumn<bool> played = GeneratedColumn<bool>(
    'played',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("played" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _finishedMeta = const VerificationMeta(
    'finished',
  );
  @override
  late final GeneratedColumn<bool> finished = GeneratedColumn<bool>(
    'finished',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("finished" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _starredMeta = const VerificationMeta(
    'starred',
  );
  @override
  late final GeneratedColumn<bool> starred = GeneratedColumn<bool>(
    'starred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("starred" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pid,
    positionMs,
    played,
    finished,
    playCount,
    starred,
    rating,
    updatedAt,
    lastPlayedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mirror_play_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<MirrorPlayState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    } else if (isInserting) {
      context.missing(_pidMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('played')) {
      context.handle(
        _playedMeta,
        played.isAcceptableOrUnknown(data['played']!, _playedMeta),
      );
    }
    if (data.containsKey('finished')) {
      context.handle(
        _finishedMeta,
        finished.isAcceptableOrUnknown(data['finished']!, _finishedMeta),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('starred')) {
      context.handle(
        _starredMeta,
        starred.isAcceptableOrUnknown(data['starred']!, _starredMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pid};
  @override
  MirrorPlayState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MirrorPlayState(
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pid'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      played: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}played'],
      )!,
      finished: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}finished'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      starred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}starred'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played_at'],
      ),
    );
  }

  @override
  $MirrorPlayStatesTable createAlias(String alias) {
    return $MirrorPlayStatesTable(attachedDatabase, alias);
  }
}

class MirrorPlayState extends DataClass implements Insertable<MirrorPlayState> {
  final String pid;
  final int positionMs;
  final bool played;
  final bool finished;
  final int playCount;
  final bool starred;
  final int? rating;
  final DateTime? updatedAt;

  /// When the last counted play was, for the facts sheet read offline.
  /// Null on a state nobody has finished, and on one marked played by
  /// hand, which raises the count and stamps no time.
  ///
  /// Last on purpose, for the reason [DownloadRecords.durationMs] gives.
  final DateTime? lastPlayedAt;
  const MirrorPlayState({
    required this.pid,
    required this.positionMs,
    required this.played,
    required this.finished,
    required this.playCount,
    required this.starred,
    this.rating,
    this.updatedAt,
    this.lastPlayedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pid'] = Variable<String>(pid);
    map['position_ms'] = Variable<int>(positionMs);
    map['played'] = Variable<bool>(played);
    map['finished'] = Variable<bool>(finished);
    map['play_count'] = Variable<int>(playCount);
    map['starred'] = Variable<bool>(starred);
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    }
    return map;
  }

  MirrorPlayStatesCompanion toCompanion(bool nullToAbsent) {
    return MirrorPlayStatesCompanion(
      pid: Value(pid),
      positionMs: Value(positionMs),
      played: Value(played),
      finished: Value(finished),
      playCount: Value(playCount),
      starred: Value(starred),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
    );
  }

  factory MirrorPlayState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MirrorPlayState(
      pid: serializer.fromJson<String>(json['pid']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      played: serializer.fromJson<bool>(json['played']),
      finished: serializer.fromJson<bool>(json['finished']),
      playCount: serializer.fromJson<int>(json['playCount']),
      starred: serializer.fromJson<bool>(json['starred']),
      rating: serializer.fromJson<int?>(json['rating']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      lastPlayedAt: serializer.fromJson<DateTime?>(json['lastPlayedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pid': serializer.toJson<String>(pid),
      'positionMs': serializer.toJson<int>(positionMs),
      'played': serializer.toJson<bool>(played),
      'finished': serializer.toJson<bool>(finished),
      'playCount': serializer.toJson<int>(playCount),
      'starred': serializer.toJson<bool>(starred),
      'rating': serializer.toJson<int?>(rating),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'lastPlayedAt': serializer.toJson<DateTime?>(lastPlayedAt),
    };
  }

  MirrorPlayState copyWith({
    String? pid,
    int? positionMs,
    bool? played,
    bool? finished,
    int? playCount,
    bool? starred,
    Value<int?> rating = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<DateTime?> lastPlayedAt = const Value.absent(),
  }) => MirrorPlayState(
    pid: pid ?? this.pid,
    positionMs: positionMs ?? this.positionMs,
    played: played ?? this.played,
    finished: finished ?? this.finished,
    playCount: playCount ?? this.playCount,
    starred: starred ?? this.starred,
    rating: rating.present ? rating.value : this.rating,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
  );
  MirrorPlayState copyWithCompanion(MirrorPlayStatesCompanion data) {
    return MirrorPlayState(
      pid: data.pid.present ? data.pid.value : this.pid,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      played: data.played.present ? data.played.value : this.played,
      finished: data.finished.present ? data.finished.value : this.finished,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      starred: data.starred.present ? data.starred.value : this.starred,
      rating: data.rating.present ? data.rating.value : this.rating,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MirrorPlayState(')
          ..write('pid: $pid, ')
          ..write('positionMs: $positionMs, ')
          ..write('played: $played, ')
          ..write('finished: $finished, ')
          ..write('playCount: $playCount, ')
          ..write('starred: $starred, ')
          ..write('rating: $rating, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastPlayedAt: $lastPlayedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pid,
    positionMs,
    played,
    finished,
    playCount,
    starred,
    rating,
    updatedAt,
    lastPlayedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MirrorPlayState &&
          other.pid == this.pid &&
          other.positionMs == this.positionMs &&
          other.played == this.played &&
          other.finished == this.finished &&
          other.playCount == this.playCount &&
          other.starred == this.starred &&
          other.rating == this.rating &&
          other.updatedAt == this.updatedAt &&
          other.lastPlayedAt == this.lastPlayedAt);
}

class MirrorPlayStatesCompanion extends UpdateCompanion<MirrorPlayState> {
  final Value<String> pid;
  final Value<int> positionMs;
  final Value<bool> played;
  final Value<bool> finished;
  final Value<int> playCount;
  final Value<bool> starred;
  final Value<int?> rating;
  final Value<DateTime?> updatedAt;
  final Value<DateTime?> lastPlayedAt;
  final Value<int> rowid;
  const MirrorPlayStatesCompanion({
    this.pid = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.played = const Value.absent(),
    this.finished = const Value.absent(),
    this.playCount = const Value.absent(),
    this.starred = const Value.absent(),
    this.rating = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MirrorPlayStatesCompanion.insert({
    required String pid,
    this.positionMs = const Value.absent(),
    this.played = const Value.absent(),
    this.finished = const Value.absent(),
    this.playCount = const Value.absent(),
    this.starred = const Value.absent(),
    this.rating = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pid = Value(pid);
  static Insertable<MirrorPlayState> custom({
    Expression<String>? pid,
    Expression<int>? positionMs,
    Expression<bool>? played,
    Expression<bool>? finished,
    Expression<int>? playCount,
    Expression<bool>? starred,
    Expression<int>? rating,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastPlayedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pid != null) 'pid': pid,
      if (positionMs != null) 'position_ms': positionMs,
      if (played != null) 'played': played,
      if (finished != null) 'finished': finished,
      if (playCount != null) 'play_count': playCount,
      if (starred != null) 'starred': starred,
      if (rating != null) 'rating': rating,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MirrorPlayStatesCompanion copyWith({
    Value<String>? pid,
    Value<int>? positionMs,
    Value<bool>? played,
    Value<bool>? finished,
    Value<int>? playCount,
    Value<bool>? starred,
    Value<int?>? rating,
    Value<DateTime?>? updatedAt,
    Value<DateTime?>? lastPlayedAt,
    Value<int>? rowid,
  }) {
    return MirrorPlayStatesCompanion(
      pid: pid ?? this.pid,
      positionMs: positionMs ?? this.positionMs,
      played: played ?? this.played,
      finished: finished ?? this.finished,
      playCount: playCount ?? this.playCount,
      starred: starred ?? this.starred,
      rating: rating ?? this.rating,
      updatedAt: updatedAt ?? this.updatedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pid.present) {
      map['pid'] = Variable<String>(pid.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (played.present) {
      map['played'] = Variable<bool>(played.value);
    }
    if (finished.present) {
      map['finished'] = Variable<bool>(finished.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (starred.present) {
      map['starred'] = Variable<bool>(starred.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MirrorPlayStatesCompanion(')
          ..write('pid: $pid, ')
          ..write('positionMs: $positionMs, ')
          ..write('played: $played, ')
          ..write('finished: $finished, ')
          ..write('playCount: $playCount, ')
          ..write('starred: $starred, ')
          ..write('rating: $rating, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _catalogSinceMeta = const VerificationMeta(
    'catalogSince',
  );
  @override
  late final GeneratedColumn<String> catalogSince = GeneratedColumn<String>(
    'catalog_since',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverSinceMeta = const VerificationMeta(
    'serverSince',
  );
  @override
  late final GeneratedColumn<String> serverSince = GeneratedColumn<String>(
    'server_since',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, catalogSince, serverSince];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('catalog_since')) {
      context.handle(
        _catalogSinceMeta,
        catalogSince.isAcceptableOrUnknown(
          data['catalog_since']!,
          _catalogSinceMeta,
        ),
      );
    }
    if (data.containsKey('server_since')) {
      context.handle(
        _serverSinceMeta,
        serverSince.isAcceptableOrUnknown(
          data['server_since']!,
          _serverSinceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      catalogSince: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catalog_since'],
      ),
      serverSince: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_since'],
      ),
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  final int id;
  final String? catalogSince;
  final String? serverSince;
  const SyncCursor({required this.id, this.catalogSince, this.serverSince});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || catalogSince != null) {
      map['catalog_since'] = Variable<String>(catalogSince);
    }
    if (!nullToAbsent || serverSince != null) {
      map['server_since'] = Variable<String>(serverSince);
    }
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      id: Value(id),
      catalogSince: catalogSince == null && nullToAbsent
          ? const Value.absent()
          : Value(catalogSince),
      serverSince: serverSince == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSince),
    );
  }

  factory SyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      id: serializer.fromJson<int>(json['id']),
      catalogSince: serializer.fromJson<String?>(json['catalogSince']),
      serverSince: serializer.fromJson<String?>(json['serverSince']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'catalogSince': serializer.toJson<String?>(catalogSince),
      'serverSince': serializer.toJson<String?>(serverSince),
    };
  }

  SyncCursor copyWith({
    int? id,
    Value<String?> catalogSince = const Value.absent(),
    Value<String?> serverSince = const Value.absent(),
  }) => SyncCursor(
    id: id ?? this.id,
    catalogSince: catalogSince.present ? catalogSince.value : this.catalogSince,
    serverSince: serverSince.present ? serverSince.value : this.serverSince,
  );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      id: data.id.present ? data.id.value : this.id,
      catalogSince: data.catalogSince.present
          ? data.catalogSince.value
          : this.catalogSince,
      serverSince: data.serverSince.present
          ? data.serverSince.value
          : this.serverSince,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('id: $id, ')
          ..write('catalogSince: $catalogSince, ')
          ..write('serverSince: $serverSince')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, catalogSince, serverSince);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.id == this.id &&
          other.catalogSince == this.catalogSince &&
          other.serverSince == this.serverSince);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<int> id;
  final Value<String?> catalogSince;
  final Value<String?> serverSince;
  const SyncCursorsCompanion({
    this.id = const Value.absent(),
    this.catalogSince = const Value.absent(),
    this.serverSince = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    this.id = const Value.absent(),
    this.catalogSince = const Value.absent(),
    this.serverSince = const Value.absent(),
  });
  static Insertable<SyncCursor> custom({
    Expression<int>? id,
    Expression<String>? catalogSince,
    Expression<String>? serverSince,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (catalogSince != null) 'catalog_since': catalogSince,
      if (serverSince != null) 'server_since': serverSince,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<int>? id,
    Value<String?>? catalogSince,
    Value<String?>? serverSince,
  }) {
    return SyncCursorsCompanion(
      id: id ?? this.id,
      catalogSince: catalogSince ?? this.catalogSince,
      serverSince: serverSince ?? this.serverSince,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (catalogSince.present) {
      map['catalog_since'] = Variable<String>(catalogSince.value);
    }
    if (serverSince.present) {
      map['server_since'] = Variable<String>(serverSince.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('id: $id, ')
          ..write('catalogSince: $catalogSince, ')
          ..write('serverSince: $serverSince')
          ..write(')'))
        .toString();
  }
}

class $OutboxMutationsTable extends OutboxMutations
    with TableInfo<$OutboxMutationsTable, OutboxMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxMutationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<String> pid = GeneratedColumn<String>(
    'pid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _starredMeta = const VerificationMeta(
    'starred',
  );
  @override
  late final GeneratedColumn<bool> starred = GeneratedColumn<bool>(
    'starred',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("starred" IN (0, 1))',
    ),
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    pid,
    positionMs,
    starred,
    rating,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    } else if (isInserting) {
      context.missing(_pidMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('starred')) {
      context.handle(
        _starredMeta,
        starred.isAcceptableOrUnknown(data['starred']!, _starredMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxMutation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pid'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      ),
      starred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}starred'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $OutboxMutationsTable createAlias(String alias) {
    return $OutboxMutationsTable(attachedDatabase, alias);
  }
}

class OutboxMutation extends DataClass implements Insertable<OutboxMutation> {
  final int id;

  /// `position`, `star`, or `rating`.
  final String kind;
  final String pid;
  final int? positionMs;
  final bool? starred;

  /// The rating value for `rating` entries; null clears the rating.
  final int? rating;
  final DateTime recordedAt;
  const OutboxMutation({
    required this.id,
    required this.kind,
    required this.pid,
    this.positionMs,
    this.starred,
    this.rating,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['pid'] = Variable<String>(pid);
    if (!nullToAbsent || positionMs != null) {
      map['position_ms'] = Variable<int>(positionMs);
    }
    if (!nullToAbsent || starred != null) {
      map['starred'] = Variable<bool>(starred);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    return map;
  }

  OutboxMutationsCompanion toCompanion(bool nullToAbsent) {
    return OutboxMutationsCompanion(
      id: Value(id),
      kind: Value(kind),
      pid: Value(pid),
      positionMs: positionMs == null && nullToAbsent
          ? const Value.absent()
          : Value(positionMs),
      starred: starred == null && nullToAbsent
          ? const Value.absent()
          : Value(starred),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      recordedAt: Value(recordedAt),
    );
  }

  factory OutboxMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxMutation(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      pid: serializer.fromJson<String>(json['pid']),
      positionMs: serializer.fromJson<int?>(json['positionMs']),
      starred: serializer.fromJson<bool?>(json['starred']),
      rating: serializer.fromJson<int?>(json['rating']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'pid': serializer.toJson<String>(pid),
      'positionMs': serializer.toJson<int?>(positionMs),
      'starred': serializer.toJson<bool?>(starred),
      'rating': serializer.toJson<int?>(rating),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
    };
  }

  OutboxMutation copyWith({
    int? id,
    String? kind,
    String? pid,
    Value<int?> positionMs = const Value.absent(),
    Value<bool?> starred = const Value.absent(),
    Value<int?> rating = const Value.absent(),
    DateTime? recordedAt,
  }) => OutboxMutation(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    pid: pid ?? this.pid,
    positionMs: positionMs.present ? positionMs.value : this.positionMs,
    starred: starred.present ? starred.value : this.starred,
    rating: rating.present ? rating.value : this.rating,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  OutboxMutation copyWithCompanion(OutboxMutationsCompanion data) {
    return OutboxMutation(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      pid: data.pid.present ? data.pid.value : this.pid,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      starred: data.starred.present ? data.starred.value : this.starred,
      rating: data.rating.present ? data.rating.value : this.rating,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxMutation(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('pid: $pid, ')
          ..write('positionMs: $positionMs, ')
          ..write('starred: $starred, ')
          ..write('rating: $rating, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, pid, positionMs, starred, rating, recordedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxMutation &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.pid == this.pid &&
          other.positionMs == this.positionMs &&
          other.starred == this.starred &&
          other.rating == this.rating &&
          other.recordedAt == this.recordedAt);
}

class OutboxMutationsCompanion extends UpdateCompanion<OutboxMutation> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> pid;
  final Value<int?> positionMs;
  final Value<bool?> starred;
  final Value<int?> rating;
  final Value<DateTime> recordedAt;
  const OutboxMutationsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.pid = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.starred = const Value.absent(),
    this.rating = const Value.absent(),
    this.recordedAt = const Value.absent(),
  });
  OutboxMutationsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String pid,
    this.positionMs = const Value.absent(),
    this.starred = const Value.absent(),
    this.rating = const Value.absent(),
    required DateTime recordedAt,
  }) : kind = Value(kind),
       pid = Value(pid),
       recordedAt = Value(recordedAt);
  static Insertable<OutboxMutation> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? pid,
    Expression<int>? positionMs,
    Expression<bool>? starred,
    Expression<int>? rating,
    Expression<DateTime>? recordedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (pid != null) 'pid': pid,
      if (positionMs != null) 'position_ms': positionMs,
      if (starred != null) 'starred': starred,
      if (rating != null) 'rating': rating,
      if (recordedAt != null) 'recorded_at': recordedAt,
    });
  }

  OutboxMutationsCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? pid,
    Value<int?>? positionMs,
    Value<bool?>? starred,
    Value<int?>? rating,
    Value<DateTime>? recordedAt,
  }) {
    return OutboxMutationsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      pid: pid ?? this.pid,
      positionMs: positionMs ?? this.positionMs,
      starred: starred ?? this.starred,
      rating: rating ?? this.rating,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (pid.present) {
      map['pid'] = Variable<String>(pid.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (starred.present) {
      map['starred'] = Variable<bool>(starred.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxMutationsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('pid: $pid, ')
          ..write('positionMs: $positionMs, ')
          ..write('starred: $starred, ')
          ..write('rating: $rating, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }
}

class $OutboxListensTable extends OutboxListens
    with TableInfo<$OutboxListensTable, OutboxListen> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxListensTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<String> pid = GeneratedColumn<String>(
    'pid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _msPlayedMeta = const VerificationMeta(
    'msPlayed',
  );
  @override
  late final GeneratedColumn<int> msPlayed = GeneratedColumn<int>(
    'ms_played',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedMeta = const VerificationMeta(
    'finished',
  );
  @override
  late final GeneratedColumn<bool> finished = GeneratedColumn<bool>(
    'finished',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("finished" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientMeta = const VerificationMeta('client');
  @override
  late final GeneratedColumn<String> client = GeneratedColumn<String>(
    'client',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _skippedMsMeta = const VerificationMeta(
    'skippedMs',
  );
  @override
  late final GeneratedColumn<int> skippedMs = GeneratedColumn<int>(
    'skipped_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    pid,
    startedAt,
    msPlayed,
    finished,
    client,
    skippedMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_listens';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxListen> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    } else if (isInserting) {
      context.missing(_pidMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ms_played')) {
      context.handle(
        _msPlayedMeta,
        msPlayed.isAcceptableOrUnknown(data['ms_played']!, _msPlayedMeta),
      );
    } else if (isInserting) {
      context.missing(_msPlayedMeta);
    }
    if (data.containsKey('finished')) {
      context.handle(
        _finishedMeta,
        finished.isAcceptableOrUnknown(data['finished']!, _finishedMeta),
      );
    }
    if (data.containsKey('client')) {
      context.handle(
        _clientMeta,
        client.isAcceptableOrUnknown(data['client']!, _clientMeta),
      );
    }
    if (data.containsKey('skipped_ms')) {
      context.handle(
        _skippedMsMeta,
        skippedMs.isAcceptableOrUnknown(data['skipped_ms']!, _skippedMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  OutboxListen map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxListen(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pid'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      msPlayed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ms_played'],
      )!,
      finished: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}finished'],
      )!,
      client: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client'],
      )!,
      skippedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}skipped_ms'],
      ),
    );
  }

  @override
  $OutboxListensTable createAlias(String alias) {
    return $OutboxListensTable(attachedDatabase, alias);
  }
}

class OutboxListen extends DataClass implements Insertable<OutboxListen> {
  final String sessionId;
  final String pid;
  final DateTime startedAt;
  final int msPlayed;
  final bool finished;
  final String client;

  /// Time the listener did not sit through (silence trimming, speed
  /// above 1x). Null when neither applied, matching the wire field.
  final int? skippedMs;
  const OutboxListen({
    required this.sessionId,
    required this.pid,
    required this.startedAt,
    required this.msPlayed,
    required this.finished,
    required this.client,
    this.skippedMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['pid'] = Variable<String>(pid);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['ms_played'] = Variable<int>(msPlayed);
    map['finished'] = Variable<bool>(finished);
    map['client'] = Variable<String>(client);
    if (!nullToAbsent || skippedMs != null) {
      map['skipped_ms'] = Variable<int>(skippedMs);
    }
    return map;
  }

  OutboxListensCompanion toCompanion(bool nullToAbsent) {
    return OutboxListensCompanion(
      sessionId: Value(sessionId),
      pid: Value(pid),
      startedAt: Value(startedAt),
      msPlayed: Value(msPlayed),
      finished: Value(finished),
      client: Value(client),
      skippedMs: skippedMs == null && nullToAbsent
          ? const Value.absent()
          : Value(skippedMs),
    );
  }

  factory OutboxListen.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxListen(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      pid: serializer.fromJson<String>(json['pid']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      msPlayed: serializer.fromJson<int>(json['msPlayed']),
      finished: serializer.fromJson<bool>(json['finished']),
      client: serializer.fromJson<String>(json['client']),
      skippedMs: serializer.fromJson<int?>(json['skippedMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'pid': serializer.toJson<String>(pid),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'msPlayed': serializer.toJson<int>(msPlayed),
      'finished': serializer.toJson<bool>(finished),
      'client': serializer.toJson<String>(client),
      'skippedMs': serializer.toJson<int?>(skippedMs),
    };
  }

  OutboxListen copyWith({
    String? sessionId,
    String? pid,
    DateTime? startedAt,
    int? msPlayed,
    bool? finished,
    String? client,
    Value<int?> skippedMs = const Value.absent(),
  }) => OutboxListen(
    sessionId: sessionId ?? this.sessionId,
    pid: pid ?? this.pid,
    startedAt: startedAt ?? this.startedAt,
    msPlayed: msPlayed ?? this.msPlayed,
    finished: finished ?? this.finished,
    client: client ?? this.client,
    skippedMs: skippedMs.present ? skippedMs.value : this.skippedMs,
  );
  OutboxListen copyWithCompanion(OutboxListensCompanion data) {
    return OutboxListen(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      pid: data.pid.present ? data.pid.value : this.pid,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      msPlayed: data.msPlayed.present ? data.msPlayed.value : this.msPlayed,
      finished: data.finished.present ? data.finished.value : this.finished,
      client: data.client.present ? data.client.value : this.client,
      skippedMs: data.skippedMs.present ? data.skippedMs.value : this.skippedMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxListen(')
          ..write('sessionId: $sessionId, ')
          ..write('pid: $pid, ')
          ..write('startedAt: $startedAt, ')
          ..write('msPlayed: $msPlayed, ')
          ..write('finished: $finished, ')
          ..write('client: $client, ')
          ..write('skippedMs: $skippedMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    pid,
    startedAt,
    msPlayed,
    finished,
    client,
    skippedMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxListen &&
          other.sessionId == this.sessionId &&
          other.pid == this.pid &&
          other.startedAt == this.startedAt &&
          other.msPlayed == this.msPlayed &&
          other.finished == this.finished &&
          other.client == this.client &&
          other.skippedMs == this.skippedMs);
}

class OutboxListensCompanion extends UpdateCompanion<OutboxListen> {
  final Value<String> sessionId;
  final Value<String> pid;
  final Value<DateTime> startedAt;
  final Value<int> msPlayed;
  final Value<bool> finished;
  final Value<String> client;
  final Value<int?> skippedMs;
  final Value<int> rowid;
  const OutboxListensCompanion({
    this.sessionId = const Value.absent(),
    this.pid = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.msPlayed = const Value.absent(),
    this.finished = const Value.absent(),
    this.client = const Value.absent(),
    this.skippedMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxListensCompanion.insert({
    required String sessionId,
    required String pid,
    required DateTime startedAt,
    required int msPlayed,
    this.finished = const Value.absent(),
    this.client = const Value.absent(),
    this.skippedMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       pid = Value(pid),
       startedAt = Value(startedAt),
       msPlayed = Value(msPlayed);
  static Insertable<OutboxListen> custom({
    Expression<String>? sessionId,
    Expression<String>? pid,
    Expression<DateTime>? startedAt,
    Expression<int>? msPlayed,
    Expression<bool>? finished,
    Expression<String>? client,
    Expression<int>? skippedMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (pid != null) 'pid': pid,
      if (startedAt != null) 'started_at': startedAt,
      if (msPlayed != null) 'ms_played': msPlayed,
      if (finished != null) 'finished': finished,
      if (client != null) 'client': client,
      if (skippedMs != null) 'skipped_ms': skippedMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxListensCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? pid,
    Value<DateTime>? startedAt,
    Value<int>? msPlayed,
    Value<bool>? finished,
    Value<String>? client,
    Value<int?>? skippedMs,
    Value<int>? rowid,
  }) {
    return OutboxListensCompanion(
      sessionId: sessionId ?? this.sessionId,
      pid: pid ?? this.pid,
      startedAt: startedAt ?? this.startedAt,
      msPlayed: msPlayed ?? this.msPlayed,
      finished: finished ?? this.finished,
      client: client ?? this.client,
      skippedMs: skippedMs ?? this.skippedMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (pid.present) {
      map['pid'] = Variable<String>(pid.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (msPlayed.present) {
      map['ms_played'] = Variable<int>(msPlayed.value);
    }
    if (finished.present) {
      map['finished'] = Variable<bool>(finished.value);
    }
    if (client.present) {
      map['client'] = Variable<String>(client.value);
    }
    if (skippedMs.present) {
      map['skipped_ms'] = Variable<int>(skippedMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxListensCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('pid: $pid, ')
          ..write('startedAt: $startedAt, ')
          ..write('msPlayed: $msPlayed, ')
          ..write('finished: $finished, ')
          ..write('client: $client, ')
          ..write('skippedMs: $skippedMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadRecordsTable extends DownloadRecords
    with TableInfo<$DownloadRecordsTable, DownloadRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<String> pid = GeneratedColumn<String>(
    'pid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileIndexMeta = const VerificationMeta(
    'fileIndex',
  );
  @override
  late final GeneratedColumn<int> fileIndex = GeneratedColumn<int>(
    'file_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _essenceHashMeta = const VerificationMeta(
    'essenceHash',
  );
  @override
  late final GeneratedColumn<String> essenceHash = GeneratedColumn<String>(
    'essence_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spanStartMsMeta = const VerificationMeta(
    'spanStartMs',
  );
  @override
  late final GeneratedColumn<int> spanStartMs = GeneratedColumn<int>(
    'span_start_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _spanEndMsMeta = const VerificationMeta(
    'spanEndMs',
  );
  @override
  late final GeneratedColumn<int> spanEndMs = GeneratedColumn<int>(
    'span_end_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pid,
    fileIndex,
    essenceHash,
    etag,
    fileName,
    localPath,
    sizeBytes,
    state,
    spanStartMs,
    spanEndMs,
    durationMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    } else if (isInserting) {
      context.missing(_pidMeta);
    }
    if (data.containsKey('file_index')) {
      context.handle(
        _fileIndexMeta,
        fileIndex.isAcceptableOrUnknown(data['file_index']!, _fileIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIndexMeta);
    }
    if (data.containsKey('essence_hash')) {
      context.handle(
        _essenceHashMeta,
        essenceHash.isAcceptableOrUnknown(
          data['essence_hash']!,
          _essenceHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_essenceHashMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    } else if (isInserting) {
      context.missing(_etagMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('span_start_ms')) {
      context.handle(
        _spanStartMsMeta,
        spanStartMs.isAcceptableOrUnknown(
          data['span_start_ms']!,
          _spanStartMsMeta,
        ),
      );
    }
    if (data.containsKey('span_end_ms')) {
      context.handle(
        _spanEndMsMeta,
        spanEndMs.isAcceptableOrUnknown(data['span_end_ms']!, _spanEndMsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pid, fileIndex};
  @override
  DownloadRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadRecord(
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pid'],
      )!,
      fileIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_index'],
      )!,
      essenceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}essence_hash'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      spanStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}span_start_ms'],
      ),
      spanEndMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}span_end_ms'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
    );
  }

  @override
  $DownloadRecordsTable createAlias(String alias) {
    return $DownloadRecordsTable(attachedDatabase, alias);
  }
}

class DownloadRecord extends DataClass implements Insertable<DownloadRecord> {
  final String pid;
  final int fileIndex;
  final String essenceHash;
  final String etag;
  final String fileName;
  final String localPath;
  final int sizeBytes;

  /// `pending` while the transfer runs, `complete` when the bytes are
  /// on disk.
  final String state;
  final int? spanStartMs;
  final int? spanEndMs;

  /// This file's own duration, as download-info reported it. Null when
  /// the catalog did not know it, and on records written before the
  /// field existed. It is what places a book-timeline position in one
  /// part of a multi-file book with the server unreachable: a part's
  /// offset is the sum of the durations before it, so one missing value
  /// makes the whole item unsequenceable rather than slightly wrong.
  ///
  /// Last on purpose, like every other column a migration added:
  /// `ALTER TABLE ADD COLUMN` appends, so a column declared in the
  /// middle here would sit in a different position on an upgraded
  /// database than on a fresh one. The equivalence test in
  /// `schema_migration_test.dart` catches exactly that, and did.
  final int? durationMs;
  const DownloadRecord({
    required this.pid,
    required this.fileIndex,
    required this.essenceHash,
    required this.etag,
    required this.fileName,
    required this.localPath,
    required this.sizeBytes,
    required this.state,
    this.spanStartMs,
    this.spanEndMs,
    this.durationMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pid'] = Variable<String>(pid);
    map['file_index'] = Variable<int>(fileIndex);
    map['essence_hash'] = Variable<String>(essenceHash);
    map['etag'] = Variable<String>(etag);
    map['file_name'] = Variable<String>(fileName);
    map['local_path'] = Variable<String>(localPath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || spanStartMs != null) {
      map['span_start_ms'] = Variable<int>(spanStartMs);
    }
    if (!nullToAbsent || spanEndMs != null) {
      map['span_end_ms'] = Variable<int>(spanEndMs);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    return map;
  }

  DownloadRecordsCompanion toCompanion(bool nullToAbsent) {
    return DownloadRecordsCompanion(
      pid: Value(pid),
      fileIndex: Value(fileIndex),
      essenceHash: Value(essenceHash),
      etag: Value(etag),
      fileName: Value(fileName),
      localPath: Value(localPath),
      sizeBytes: Value(sizeBytes),
      state: Value(state),
      spanStartMs: spanStartMs == null && nullToAbsent
          ? const Value.absent()
          : Value(spanStartMs),
      spanEndMs: spanEndMs == null && nullToAbsent
          ? const Value.absent()
          : Value(spanEndMs),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
    );
  }

  factory DownloadRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadRecord(
      pid: serializer.fromJson<String>(json['pid']),
      fileIndex: serializer.fromJson<int>(json['fileIndex']),
      essenceHash: serializer.fromJson<String>(json['essenceHash']),
      etag: serializer.fromJson<String>(json['etag']),
      fileName: serializer.fromJson<String>(json['fileName']),
      localPath: serializer.fromJson<String>(json['localPath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      state: serializer.fromJson<String>(json['state']),
      spanStartMs: serializer.fromJson<int?>(json['spanStartMs']),
      spanEndMs: serializer.fromJson<int?>(json['spanEndMs']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pid': serializer.toJson<String>(pid),
      'fileIndex': serializer.toJson<int>(fileIndex),
      'essenceHash': serializer.toJson<String>(essenceHash),
      'etag': serializer.toJson<String>(etag),
      'fileName': serializer.toJson<String>(fileName),
      'localPath': serializer.toJson<String>(localPath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'state': serializer.toJson<String>(state),
      'spanStartMs': serializer.toJson<int?>(spanStartMs),
      'spanEndMs': serializer.toJson<int?>(spanEndMs),
      'durationMs': serializer.toJson<int?>(durationMs),
    };
  }

  DownloadRecord copyWith({
    String? pid,
    int? fileIndex,
    String? essenceHash,
    String? etag,
    String? fileName,
    String? localPath,
    int? sizeBytes,
    String? state,
    Value<int?> spanStartMs = const Value.absent(),
    Value<int?> spanEndMs = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
  }) => DownloadRecord(
    pid: pid ?? this.pid,
    fileIndex: fileIndex ?? this.fileIndex,
    essenceHash: essenceHash ?? this.essenceHash,
    etag: etag ?? this.etag,
    fileName: fileName ?? this.fileName,
    localPath: localPath ?? this.localPath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    state: state ?? this.state,
    spanStartMs: spanStartMs.present ? spanStartMs.value : this.spanStartMs,
    spanEndMs: spanEndMs.present ? spanEndMs.value : this.spanEndMs,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
  );
  DownloadRecord copyWithCompanion(DownloadRecordsCompanion data) {
    return DownloadRecord(
      pid: data.pid.present ? data.pid.value : this.pid,
      fileIndex: data.fileIndex.present ? data.fileIndex.value : this.fileIndex,
      essenceHash: data.essenceHash.present
          ? data.essenceHash.value
          : this.essenceHash,
      etag: data.etag.present ? data.etag.value : this.etag,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      state: data.state.present ? data.state.value : this.state,
      spanStartMs: data.spanStartMs.present
          ? data.spanStartMs.value
          : this.spanStartMs,
      spanEndMs: data.spanEndMs.present ? data.spanEndMs.value : this.spanEndMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRecord(')
          ..write('pid: $pid, ')
          ..write('fileIndex: $fileIndex, ')
          ..write('essenceHash: $essenceHash, ')
          ..write('etag: $etag, ')
          ..write('fileName: $fileName, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('state: $state, ')
          ..write('spanStartMs: $spanStartMs, ')
          ..write('spanEndMs: $spanEndMs, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pid,
    fileIndex,
    essenceHash,
    etag,
    fileName,
    localPath,
    sizeBytes,
    state,
    spanStartMs,
    spanEndMs,
    durationMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRecord &&
          other.pid == this.pid &&
          other.fileIndex == this.fileIndex &&
          other.essenceHash == this.essenceHash &&
          other.etag == this.etag &&
          other.fileName == this.fileName &&
          other.localPath == this.localPath &&
          other.sizeBytes == this.sizeBytes &&
          other.state == this.state &&
          other.spanStartMs == this.spanStartMs &&
          other.spanEndMs == this.spanEndMs &&
          other.durationMs == this.durationMs);
}

class DownloadRecordsCompanion extends UpdateCompanion<DownloadRecord> {
  final Value<String> pid;
  final Value<int> fileIndex;
  final Value<String> essenceHash;
  final Value<String> etag;
  final Value<String> fileName;
  final Value<String> localPath;
  final Value<int> sizeBytes;
  final Value<String> state;
  final Value<int?> spanStartMs;
  final Value<int?> spanEndMs;
  final Value<int?> durationMs;
  final Value<int> rowid;
  const DownloadRecordsCompanion({
    this.pid = const Value.absent(),
    this.fileIndex = const Value.absent(),
    this.essenceHash = const Value.absent(),
    this.etag = const Value.absent(),
    this.fileName = const Value.absent(),
    this.localPath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.state = const Value.absent(),
    this.spanStartMs = const Value.absent(),
    this.spanEndMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadRecordsCompanion.insert({
    required String pid,
    required int fileIndex,
    required String essenceHash,
    required String etag,
    required String fileName,
    required String localPath,
    required int sizeBytes,
    required String state,
    this.spanStartMs = const Value.absent(),
    this.spanEndMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pid = Value(pid),
       fileIndex = Value(fileIndex),
       essenceHash = Value(essenceHash),
       etag = Value(etag),
       fileName = Value(fileName),
       localPath = Value(localPath),
       sizeBytes = Value(sizeBytes),
       state = Value(state);
  static Insertable<DownloadRecord> custom({
    Expression<String>? pid,
    Expression<int>? fileIndex,
    Expression<String>? essenceHash,
    Expression<String>? etag,
    Expression<String>? fileName,
    Expression<String>? localPath,
    Expression<int>? sizeBytes,
    Expression<String>? state,
    Expression<int>? spanStartMs,
    Expression<int>? spanEndMs,
    Expression<int>? durationMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pid != null) 'pid': pid,
      if (fileIndex != null) 'file_index': fileIndex,
      if (essenceHash != null) 'essence_hash': essenceHash,
      if (etag != null) 'etag': etag,
      if (fileName != null) 'file_name': fileName,
      if (localPath != null) 'local_path': localPath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (state != null) 'state': state,
      if (spanStartMs != null) 'span_start_ms': spanStartMs,
      if (spanEndMs != null) 'span_end_ms': spanEndMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadRecordsCompanion copyWith({
    Value<String>? pid,
    Value<int>? fileIndex,
    Value<String>? essenceHash,
    Value<String>? etag,
    Value<String>? fileName,
    Value<String>? localPath,
    Value<int>? sizeBytes,
    Value<String>? state,
    Value<int?>? spanStartMs,
    Value<int?>? spanEndMs,
    Value<int?>? durationMs,
    Value<int>? rowid,
  }) {
    return DownloadRecordsCompanion(
      pid: pid ?? this.pid,
      fileIndex: fileIndex ?? this.fileIndex,
      essenceHash: essenceHash ?? this.essenceHash,
      etag: etag ?? this.etag,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      state: state ?? this.state,
      spanStartMs: spanStartMs ?? this.spanStartMs,
      spanEndMs: spanEndMs ?? this.spanEndMs,
      durationMs: durationMs ?? this.durationMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pid.present) {
      map['pid'] = Variable<String>(pid.value);
    }
    if (fileIndex.present) {
      map['file_index'] = Variable<int>(fileIndex.value);
    }
    if (essenceHash.present) {
      map['essence_hash'] = Variable<String>(essenceHash.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (spanStartMs.present) {
      map['span_start_ms'] = Variable<int>(spanStartMs.value);
    }
    if (spanEndMs.present) {
      map['span_end_ms'] = Variable<int>(spanEndMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRecordsCompanion(')
          ..write('pid: $pid, ')
          ..write('fileIndex: $fileIndex, ')
          ..write('essenceHash: $essenceHash, ')
          ..write('etag: $etag, ')
          ..write('fileName: $fileName, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('state: $state, ')
          ..write('spanStartMs: $spanStartMs, ')
          ..write('spanEndMs: $spanEndMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueEntriesTable extends QueueEntries
    with TableInfo<$QueueEntriesTable, QueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _queueIdMeta = const VerificationMeta(
    'queueId',
  );
  @override
  late final GeneratedColumn<String> queueId = GeneratedColumn<String>(
    'queue_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<String> pid = GeneratedColumn<String>(
    'pid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceRankMeta = const VerificationMeta(
    'sourceRank',
  );
  @override
  late final GeneratedColumn<int> sourceRank = GeneratedColumn<int>(
    'source_rank',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [queueId, pid, position, sourceRank];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('queue_id')) {
      context.handle(
        _queueIdMeta,
        queueId.isAcceptableOrUnknown(data['queue_id']!, _queueIdMeta),
      );
    } else if (isInserting) {
      context.missing(_queueIdMeta);
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    } else if (isInserting) {
      context.missing(_pidMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('source_rank')) {
      context.handle(
        _sourceRankMeta,
        sourceRank.isAcceptableOrUnknown(data['source_rank']!, _sourceRankMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceRankMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {queueId};
  @override
  QueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueEntry(
      queueId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_id'],
      )!,
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pid'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      sourceRank: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_rank'],
      )!,
    );
  }

  @override
  $QueueEntriesTable createAlias(String alias) {
    return $QueueEntriesTable(attachedDatabase, alias);
  }
}

class QueueEntry extends DataClass implements Insertable<QueueEntry> {
  final String queueId;
  final String pid;
  final int position;
  final int sourceRank;
  const QueueEntry({
    required this.queueId,
    required this.pid,
    required this.position,
    required this.sourceRank,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['queue_id'] = Variable<String>(queueId);
    map['pid'] = Variable<String>(pid);
    map['position'] = Variable<int>(position);
    map['source_rank'] = Variable<int>(sourceRank);
    return map;
  }

  QueueEntriesCompanion toCompanion(bool nullToAbsent) {
    return QueueEntriesCompanion(
      queueId: Value(queueId),
      pid: Value(pid),
      position: Value(position),
      sourceRank: Value(sourceRank),
    );
  }

  factory QueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueEntry(
      queueId: serializer.fromJson<String>(json['queueId']),
      pid: serializer.fromJson<String>(json['pid']),
      position: serializer.fromJson<int>(json['position']),
      sourceRank: serializer.fromJson<int>(json['sourceRank']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'queueId': serializer.toJson<String>(queueId),
      'pid': serializer.toJson<String>(pid),
      'position': serializer.toJson<int>(position),
      'sourceRank': serializer.toJson<int>(sourceRank),
    };
  }

  QueueEntry copyWith({
    String? queueId,
    String? pid,
    int? position,
    int? sourceRank,
  }) => QueueEntry(
    queueId: queueId ?? this.queueId,
    pid: pid ?? this.pid,
    position: position ?? this.position,
    sourceRank: sourceRank ?? this.sourceRank,
  );
  QueueEntry copyWithCompanion(QueueEntriesCompanion data) {
    return QueueEntry(
      queueId: data.queueId.present ? data.queueId.value : this.queueId,
      pid: data.pid.present ? data.pid.value : this.pid,
      position: data.position.present ? data.position.value : this.position,
      sourceRank: data.sourceRank.present
          ? data.sourceRank.value
          : this.sourceRank,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueEntry(')
          ..write('queueId: $queueId, ')
          ..write('pid: $pid, ')
          ..write('position: $position, ')
          ..write('sourceRank: $sourceRank')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(queueId, pid, position, sourceRank);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueEntry &&
          other.queueId == this.queueId &&
          other.pid == this.pid &&
          other.position == this.position &&
          other.sourceRank == this.sourceRank);
}

class QueueEntriesCompanion extends UpdateCompanion<QueueEntry> {
  final Value<String> queueId;
  final Value<String> pid;
  final Value<int> position;
  final Value<int> sourceRank;
  final Value<int> rowid;
  const QueueEntriesCompanion({
    this.queueId = const Value.absent(),
    this.pid = const Value.absent(),
    this.position = const Value.absent(),
    this.sourceRank = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueueEntriesCompanion.insert({
    required String queueId,
    required String pid,
    required int position,
    required int sourceRank,
    this.rowid = const Value.absent(),
  }) : queueId = Value(queueId),
       pid = Value(pid),
       position = Value(position),
       sourceRank = Value(sourceRank);
  static Insertable<QueueEntry> custom({
    Expression<String>? queueId,
    Expression<String>? pid,
    Expression<int>? position,
    Expression<int>? sourceRank,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (queueId != null) 'queue_id': queueId,
      if (pid != null) 'pid': pid,
      if (position != null) 'position': position,
      if (sourceRank != null) 'source_rank': sourceRank,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueueEntriesCompanion copyWith({
    Value<String>? queueId,
    Value<String>? pid,
    Value<int>? position,
    Value<int>? sourceRank,
    Value<int>? rowid,
  }) {
    return QueueEntriesCompanion(
      queueId: queueId ?? this.queueId,
      pid: pid ?? this.pid,
      position: position ?? this.position,
      sourceRank: sourceRank ?? this.sourceRank,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (queueId.present) {
      map['queue_id'] = Variable<String>(queueId.value);
    }
    if (pid.present) {
      map['pid'] = Variable<String>(pid.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (sourceRank.present) {
      map['source_rank'] = Variable<int>(sourceRank.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueEntriesCompanion(')
          ..write('queueId: $queueId, ')
          ..write('pid: $pid, ')
          ..write('position: $position, ')
          ..write('sourceRank: $sourceRank, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueMetaTable extends QueueMeta
    with TableInfo<$QueueMetaTable, QueueMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _currentIndexMeta = const VerificationMeta(
    'currentIndex',
  );
  @override
  late final GeneratedColumn<int> currentIndex = GeneratedColumn<int>(
    'current_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _shuffledMeta = const VerificationMeta(
    'shuffled',
  );
  @override
  late final GeneratedColumn<bool> shuffled = GeneratedColumn<bool>(
    'shuffled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("shuffled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _repeatMeta = const VerificationMeta('repeat');
  @override
  late final GeneratedColumn<String> repeat = GeneratedColumn<String>(
    'repeat',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('off'),
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _sourceLabelMeta = const VerificationMeta(
    'sourceLabel',
  );
  @override
  late final GeneratedColumn<String> sourceLabel = GeneratedColumn<String>(
    'source_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourcePidMeta = const VerificationMeta(
    'sourcePid',
  );
  @override
  late final GeneratedColumn<String> sourcePid = GeneratedColumn<String>(
    'source_pid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceRollingMeta = const VerificationMeta(
    'sourceRolling',
  );
  @override
  late final GeneratedColumn<bool> sourceRolling = GeneratedColumn<bool>(
    'source_rolling',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("source_rolling" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _nextQueueIdMeta = const VerificationMeta(
    'nextQueueId',
  );
  @override
  late final GeneratedColumn<int> nextQueueId = GeneratedColumn<int>(
    'next_queue_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceCursorMeta = const VerificationMeta(
    'sourceCursor',
  );
  @override
  late final GeneratedColumn<String> sourceCursor = GeneratedColumn<String>(
    'source_cursor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    currentIndex,
    shuffled,
    repeat,
    sourceKind,
    sourceLabel,
    sourcePid,
    sourceRolling,
    nextQueueId,
    updatedAt,
    sourceCursor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('current_index')) {
      context.handle(
        _currentIndexMeta,
        currentIndex.isAcceptableOrUnknown(
          data['current_index']!,
          _currentIndexMeta,
        ),
      );
    }
    if (data.containsKey('shuffled')) {
      context.handle(
        _shuffledMeta,
        shuffled.isAcceptableOrUnknown(data['shuffled']!, _shuffledMeta),
      );
    }
    if (data.containsKey('repeat')) {
      context.handle(
        _repeatMeta,
        repeat.isAcceptableOrUnknown(data['repeat']!, _repeatMeta),
      );
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    }
    if (data.containsKey('source_label')) {
      context.handle(
        _sourceLabelMeta,
        sourceLabel.isAcceptableOrUnknown(
          data['source_label']!,
          _sourceLabelMeta,
        ),
      );
    }
    if (data.containsKey('source_pid')) {
      context.handle(
        _sourcePidMeta,
        sourcePid.isAcceptableOrUnknown(data['source_pid']!, _sourcePidMeta),
      );
    }
    if (data.containsKey('source_rolling')) {
      context.handle(
        _sourceRollingMeta,
        sourceRolling.isAcceptableOrUnknown(
          data['source_rolling']!,
          _sourceRollingMeta,
        ),
      );
    }
    if (data.containsKey('next_queue_id')) {
      context.handle(
        _nextQueueIdMeta,
        nextQueueId.isAcceptableOrUnknown(
          data['next_queue_id']!,
          _nextQueueIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('source_cursor')) {
      context.handle(
        _sourceCursorMeta,
        sourceCursor.isAcceptableOrUnknown(
          data['source_cursor']!,
          _sourceCursorMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueMetaData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      currentIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_index'],
      )!,
      shuffled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}shuffled'],
      )!,
      repeat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repeat'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      sourceLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_label'],
      )!,
      sourcePid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_pid'],
      ),
      sourceRolling: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}source_rolling'],
      )!,
      nextQueueId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_queue_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      sourceCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_cursor'],
      )!,
    );
  }

  @override
  $QueueMetaTable createAlias(String alias) {
    return $QueueMetaTable(attachedDatabase, alias);
  }
}

class QueueMetaData extends DataClass implements Insertable<QueueMetaData> {
  final int id;
  final int currentIndex;
  final bool shuffled;

  /// `off`, `all`, or `one`, matching the Connect command vocabulary.
  final String repeat;

  /// Provenance: what the queue was built from, for the "Playing from
  /// [source]" line and the restore offer.
  final String sourceKind;
  final String sourceLabel;
  final String? sourcePid;

  /// True for a window over a scope larger than the queue cap (shuffle
  /// all), which is refilled as it drains rather than being the whole
  /// truth.
  final bool sourceRolling;

  /// The next value the queue-id counter will mint, so a restored queue
  /// cannot hand an old id to a new entry.
  final int nextQueueId;
  final DateTime updatedAt;

  /// Where the source's own listing stood when the window was cut, so a
  /// restored rolling queue can draw the next page instead of ending at
  /// the cap. Opaque: keyset cursors are the server's to shape, and the
  /// empty string means "no more was ever asked for".
  ///
  /// Read and written by [StoredQueue] already; what does not fill it
  /// yet is `QueueState.toStored`, since nothing on the queue side pages
  /// a source. That is the one remaining step, and it is a queue-UI one.
  ///
  /// Out of reading order, and deliberately: `ALTER TABLE ADD COLUMN`
  /// appends, so a column added after a table shipped goes last here too
  /// or an upgraded database and a fresh one differ in column order.
  /// (`skippedMs` on the listen outbox is the same, for the same
  /// reason.)
  final String sourceCursor;
  const QueueMetaData({
    required this.id,
    required this.currentIndex,
    required this.shuffled,
    required this.repeat,
    required this.sourceKind,
    required this.sourceLabel,
    this.sourcePid,
    required this.sourceRolling,
    required this.nextQueueId,
    required this.updatedAt,
    required this.sourceCursor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['current_index'] = Variable<int>(currentIndex);
    map['shuffled'] = Variable<bool>(shuffled);
    map['repeat'] = Variable<String>(repeat);
    map['source_kind'] = Variable<String>(sourceKind);
    map['source_label'] = Variable<String>(sourceLabel);
    if (!nullToAbsent || sourcePid != null) {
      map['source_pid'] = Variable<String>(sourcePid);
    }
    map['source_rolling'] = Variable<bool>(sourceRolling);
    map['next_queue_id'] = Variable<int>(nextQueueId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['source_cursor'] = Variable<String>(sourceCursor);
    return map;
  }

  QueueMetaCompanion toCompanion(bool nullToAbsent) {
    return QueueMetaCompanion(
      id: Value(id),
      currentIndex: Value(currentIndex),
      shuffled: Value(shuffled),
      repeat: Value(repeat),
      sourceKind: Value(sourceKind),
      sourceLabel: Value(sourceLabel),
      sourcePid: sourcePid == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcePid),
      sourceRolling: Value(sourceRolling),
      nextQueueId: Value(nextQueueId),
      updatedAt: Value(updatedAt),
      sourceCursor: Value(sourceCursor),
    );
  }

  factory QueueMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueMetaData(
      id: serializer.fromJson<int>(json['id']),
      currentIndex: serializer.fromJson<int>(json['currentIndex']),
      shuffled: serializer.fromJson<bool>(json['shuffled']),
      repeat: serializer.fromJson<String>(json['repeat']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      sourceLabel: serializer.fromJson<String>(json['sourceLabel']),
      sourcePid: serializer.fromJson<String?>(json['sourcePid']),
      sourceRolling: serializer.fromJson<bool>(json['sourceRolling']),
      nextQueueId: serializer.fromJson<int>(json['nextQueueId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      sourceCursor: serializer.fromJson<String>(json['sourceCursor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'currentIndex': serializer.toJson<int>(currentIndex),
      'shuffled': serializer.toJson<bool>(shuffled),
      'repeat': serializer.toJson<String>(repeat),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'sourceLabel': serializer.toJson<String>(sourceLabel),
      'sourcePid': serializer.toJson<String?>(sourcePid),
      'sourceRolling': serializer.toJson<bool>(sourceRolling),
      'nextQueueId': serializer.toJson<int>(nextQueueId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'sourceCursor': serializer.toJson<String>(sourceCursor),
    };
  }

  QueueMetaData copyWith({
    int? id,
    int? currentIndex,
    bool? shuffled,
    String? repeat,
    String? sourceKind,
    String? sourceLabel,
    Value<String?> sourcePid = const Value.absent(),
    bool? sourceRolling,
    int? nextQueueId,
    DateTime? updatedAt,
    String? sourceCursor,
  }) => QueueMetaData(
    id: id ?? this.id,
    currentIndex: currentIndex ?? this.currentIndex,
    shuffled: shuffled ?? this.shuffled,
    repeat: repeat ?? this.repeat,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    sourcePid: sourcePid.present ? sourcePid.value : this.sourcePid,
    sourceRolling: sourceRolling ?? this.sourceRolling,
    nextQueueId: nextQueueId ?? this.nextQueueId,
    updatedAt: updatedAt ?? this.updatedAt,
    sourceCursor: sourceCursor ?? this.sourceCursor,
  );
  QueueMetaData copyWithCompanion(QueueMetaCompanion data) {
    return QueueMetaData(
      id: data.id.present ? data.id.value : this.id,
      currentIndex: data.currentIndex.present
          ? data.currentIndex.value
          : this.currentIndex,
      shuffled: data.shuffled.present ? data.shuffled.value : this.shuffled,
      repeat: data.repeat.present ? data.repeat.value : this.repeat,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      sourceLabel: data.sourceLabel.present
          ? data.sourceLabel.value
          : this.sourceLabel,
      sourcePid: data.sourcePid.present ? data.sourcePid.value : this.sourcePid,
      sourceRolling: data.sourceRolling.present
          ? data.sourceRolling.value
          : this.sourceRolling,
      nextQueueId: data.nextQueueId.present
          ? data.nextQueueId.value
          : this.nextQueueId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sourceCursor: data.sourceCursor.present
          ? data.sourceCursor.value
          : this.sourceCursor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueMetaData(')
          ..write('id: $id, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('shuffled: $shuffled, ')
          ..write('repeat: $repeat, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceLabel: $sourceLabel, ')
          ..write('sourcePid: $sourcePid, ')
          ..write('sourceRolling: $sourceRolling, ')
          ..write('nextQueueId: $nextQueueId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourceCursor: $sourceCursor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    currentIndex,
    shuffled,
    repeat,
    sourceKind,
    sourceLabel,
    sourcePid,
    sourceRolling,
    nextQueueId,
    updatedAt,
    sourceCursor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueMetaData &&
          other.id == this.id &&
          other.currentIndex == this.currentIndex &&
          other.shuffled == this.shuffled &&
          other.repeat == this.repeat &&
          other.sourceKind == this.sourceKind &&
          other.sourceLabel == this.sourceLabel &&
          other.sourcePid == this.sourcePid &&
          other.sourceRolling == this.sourceRolling &&
          other.nextQueueId == this.nextQueueId &&
          other.updatedAt == this.updatedAt &&
          other.sourceCursor == this.sourceCursor);
}

class QueueMetaCompanion extends UpdateCompanion<QueueMetaData> {
  final Value<int> id;
  final Value<int> currentIndex;
  final Value<bool> shuffled;
  final Value<String> repeat;
  final Value<String> sourceKind;
  final Value<String> sourceLabel;
  final Value<String?> sourcePid;
  final Value<bool> sourceRolling;
  final Value<int> nextQueueId;
  final Value<DateTime> updatedAt;
  final Value<String> sourceCursor;
  const QueueMetaCompanion({
    this.id = const Value.absent(),
    this.currentIndex = const Value.absent(),
    this.shuffled = const Value.absent(),
    this.repeat = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceLabel = const Value.absent(),
    this.sourcePid = const Value.absent(),
    this.sourceRolling = const Value.absent(),
    this.nextQueueId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sourceCursor = const Value.absent(),
  });
  QueueMetaCompanion.insert({
    this.id = const Value.absent(),
    this.currentIndex = const Value.absent(),
    this.shuffled = const Value.absent(),
    this.repeat = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceLabel = const Value.absent(),
    this.sourcePid = const Value.absent(),
    this.sourceRolling = const Value.absent(),
    this.nextQueueId = const Value.absent(),
    required DateTime updatedAt,
    this.sourceCursor = const Value.absent(),
  }) : updatedAt = Value(updatedAt);
  static Insertable<QueueMetaData> custom({
    Expression<int>? id,
    Expression<int>? currentIndex,
    Expression<bool>? shuffled,
    Expression<String>? repeat,
    Expression<String>? sourceKind,
    Expression<String>? sourceLabel,
    Expression<String>? sourcePid,
    Expression<bool>? sourceRolling,
    Expression<int>? nextQueueId,
    Expression<DateTime>? updatedAt,
    Expression<String>? sourceCursor,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (currentIndex != null) 'current_index': currentIndex,
      if (shuffled != null) 'shuffled': shuffled,
      if (repeat != null) 'repeat': repeat,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceLabel != null) 'source_label': sourceLabel,
      if (sourcePid != null) 'source_pid': sourcePid,
      if (sourceRolling != null) 'source_rolling': sourceRolling,
      if (nextQueueId != null) 'next_queue_id': nextQueueId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sourceCursor != null) 'source_cursor': sourceCursor,
    });
  }

  QueueMetaCompanion copyWith({
    Value<int>? id,
    Value<int>? currentIndex,
    Value<bool>? shuffled,
    Value<String>? repeat,
    Value<String>? sourceKind,
    Value<String>? sourceLabel,
    Value<String?>? sourcePid,
    Value<bool>? sourceRolling,
    Value<int>? nextQueueId,
    Value<DateTime>? updatedAt,
    Value<String>? sourceCursor,
  }) {
    return QueueMetaCompanion(
      id: id ?? this.id,
      currentIndex: currentIndex ?? this.currentIndex,
      shuffled: shuffled ?? this.shuffled,
      repeat: repeat ?? this.repeat,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      sourcePid: sourcePid ?? this.sourcePid,
      sourceRolling: sourceRolling ?? this.sourceRolling,
      nextQueueId: nextQueueId ?? this.nextQueueId,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceCursor: sourceCursor ?? this.sourceCursor,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (currentIndex.present) {
      map['current_index'] = Variable<int>(currentIndex.value);
    }
    if (shuffled.present) {
      map['shuffled'] = Variable<bool>(shuffled.value);
    }
    if (repeat.present) {
      map['repeat'] = Variable<String>(repeat.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceLabel.present) {
      map['source_label'] = Variable<String>(sourceLabel.value);
    }
    if (sourcePid.present) {
      map['source_pid'] = Variable<String>(sourcePid.value);
    }
    if (sourceRolling.present) {
      map['source_rolling'] = Variable<bool>(sourceRolling.value);
    }
    if (nextQueueId.present) {
      map['next_queue_id'] = Variable<int>(nextQueueId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sourceCursor.present) {
      map['source_cursor'] = Variable<String>(sourceCursor.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueMetaCompanion(')
          ..write('id: $id, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('shuffled: $shuffled, ')
          ..write('repeat: $repeat, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceLabel: $sourceLabel, ')
          ..write('sourcePid: $sourcePid, ')
          ..write('sourceRolling: $sourceRolling, ')
          ..write('nextQueueId: $nextQueueId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourceCursor: $sourceCursor')
          ..write(')'))
        .toString();
  }
}

class $ArtworkPinsTable extends ArtworkPins
    with TableInfo<$ArtworkPinsTable, ArtworkPin> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtworkPinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<String> pid = GeneratedColumn<String>(
    'pid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizePxMeta = const VerificationMeta('sizePx');
  @override
  late final GeneratedColumn<int> sizePx = GeneratedColumn<int>(
    'size_px',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artUrlMeta = const VerificationMeta('artUrl');
  @override
  late final GeneratedColumn<String> artUrl = GeneratedColumn<String>(
    'art_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta(
    'pinnedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pinnedAt = GeneratedColumn<DateTime>(
    'pinned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pid,
    sizePx,
    artUrl,
    etag,
    localPath,
    sizeBytes,
    pinnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artwork_pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArtworkPin> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    } else if (isInserting) {
      context.missing(_pidMeta);
    }
    if (data.containsKey('size_px')) {
      context.handle(
        _sizePxMeta,
        sizePx.isAcceptableOrUnknown(data['size_px']!, _sizePxMeta),
      );
    } else if (isInserting) {
      context.missing(_sizePxMeta);
    }
    if (data.containsKey('art_url')) {
      context.handle(
        _artUrlMeta,
        artUrl.isAcceptableOrUnknown(data['art_url']!, _artUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_artUrlMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    } else if (isInserting) {
      context.missing(_etagMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pid, sizePx};
  @override
  ArtworkPin map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArtworkPin(
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pid'],
      )!,
      sizePx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_px'],
      )!,
      artUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}art_url'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pinned_at'],
      )!,
    );
  }

  @override
  $ArtworkPinsTable createAlias(String alias) {
    return $ArtworkPinsTable(attachedDatabase, alias);
  }
}

class ArtworkPin extends DataClass implements Insertable<ArtworkPin> {
  final String pid;
  final int sizePx;

  /// The art URL the bytes came from, so a revalidation asks for the
  /// same variant rather than whatever the item's front slot became.
  final String artUrl;
  final String etag;
  final String localPath;
  final int sizeBytes;
  final DateTime pinnedAt;
  const ArtworkPin({
    required this.pid,
    required this.sizePx,
    required this.artUrl,
    required this.etag,
    required this.localPath,
    required this.sizeBytes,
    required this.pinnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pid'] = Variable<String>(pid);
    map['size_px'] = Variable<int>(sizePx);
    map['art_url'] = Variable<String>(artUrl);
    map['etag'] = Variable<String>(etag);
    map['local_path'] = Variable<String>(localPath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['pinned_at'] = Variable<DateTime>(pinnedAt);
    return map;
  }

  ArtworkPinsCompanion toCompanion(bool nullToAbsent) {
    return ArtworkPinsCompanion(
      pid: Value(pid),
      sizePx: Value(sizePx),
      artUrl: Value(artUrl),
      etag: Value(etag),
      localPath: Value(localPath),
      sizeBytes: Value(sizeBytes),
      pinnedAt: Value(pinnedAt),
    );
  }

  factory ArtworkPin.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArtworkPin(
      pid: serializer.fromJson<String>(json['pid']),
      sizePx: serializer.fromJson<int>(json['sizePx']),
      artUrl: serializer.fromJson<String>(json['artUrl']),
      etag: serializer.fromJson<String>(json['etag']),
      localPath: serializer.fromJson<String>(json['localPath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      pinnedAt: serializer.fromJson<DateTime>(json['pinnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pid': serializer.toJson<String>(pid),
      'sizePx': serializer.toJson<int>(sizePx),
      'artUrl': serializer.toJson<String>(artUrl),
      'etag': serializer.toJson<String>(etag),
      'localPath': serializer.toJson<String>(localPath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'pinnedAt': serializer.toJson<DateTime>(pinnedAt),
    };
  }

  ArtworkPin copyWith({
    String? pid,
    int? sizePx,
    String? artUrl,
    String? etag,
    String? localPath,
    int? sizeBytes,
    DateTime? pinnedAt,
  }) => ArtworkPin(
    pid: pid ?? this.pid,
    sizePx: sizePx ?? this.sizePx,
    artUrl: artUrl ?? this.artUrl,
    etag: etag ?? this.etag,
    localPath: localPath ?? this.localPath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    pinnedAt: pinnedAt ?? this.pinnedAt,
  );
  ArtworkPin copyWithCompanion(ArtworkPinsCompanion data) {
    return ArtworkPin(
      pid: data.pid.present ? data.pid.value : this.pid,
      sizePx: data.sizePx.present ? data.sizePx.value : this.sizePx,
      artUrl: data.artUrl.present ? data.artUrl.value : this.artUrl,
      etag: data.etag.present ? data.etag.value : this.etag,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArtworkPin(')
          ..write('pid: $pid, ')
          ..write('sizePx: $sizePx, ')
          ..write('artUrl: $artUrl, ')
          ..write('etag: $etag, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(pid, sizePx, artUrl, etag, localPath, sizeBytes, pinnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArtworkPin &&
          other.pid == this.pid &&
          other.sizePx == this.sizePx &&
          other.artUrl == this.artUrl &&
          other.etag == this.etag &&
          other.localPath == this.localPath &&
          other.sizeBytes == this.sizeBytes &&
          other.pinnedAt == this.pinnedAt);
}

class ArtworkPinsCompanion extends UpdateCompanion<ArtworkPin> {
  final Value<String> pid;
  final Value<int> sizePx;
  final Value<String> artUrl;
  final Value<String> etag;
  final Value<String> localPath;
  final Value<int> sizeBytes;
  final Value<DateTime> pinnedAt;
  final Value<int> rowid;
  const ArtworkPinsCompanion({
    this.pid = const Value.absent(),
    this.sizePx = const Value.absent(),
    this.artUrl = const Value.absent(),
    this.etag = const Value.absent(),
    this.localPath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArtworkPinsCompanion.insert({
    required String pid,
    required int sizePx,
    required String artUrl,
    required String etag,
    required String localPath,
    required int sizeBytes,
    required DateTime pinnedAt,
    this.rowid = const Value.absent(),
  }) : pid = Value(pid),
       sizePx = Value(sizePx),
       artUrl = Value(artUrl),
       etag = Value(etag),
       localPath = Value(localPath),
       sizeBytes = Value(sizeBytes),
       pinnedAt = Value(pinnedAt);
  static Insertable<ArtworkPin> custom({
    Expression<String>? pid,
    Expression<int>? sizePx,
    Expression<String>? artUrl,
    Expression<String>? etag,
    Expression<String>? localPath,
    Expression<int>? sizeBytes,
    Expression<DateTime>? pinnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pid != null) 'pid': pid,
      if (sizePx != null) 'size_px': sizePx,
      if (artUrl != null) 'art_url': artUrl,
      if (etag != null) 'etag': etag,
      if (localPath != null) 'local_path': localPath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArtworkPinsCompanion copyWith({
    Value<String>? pid,
    Value<int>? sizePx,
    Value<String>? artUrl,
    Value<String>? etag,
    Value<String>? localPath,
    Value<int>? sizeBytes,
    Value<DateTime>? pinnedAt,
    Value<int>? rowid,
  }) {
    return ArtworkPinsCompanion(
      pid: pid ?? this.pid,
      sizePx: sizePx ?? this.sizePx,
      artUrl: artUrl ?? this.artUrl,
      etag: etag ?? this.etag,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pid.present) {
      map['pid'] = Variable<String>(pid.value);
    }
    if (sizePx.present) {
      map['size_px'] = Variable<int>(sizePx.value);
    }
    if (artUrl.present) {
      map['art_url'] = Variable<String>(artUrl.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtworkPinsCompanion(')
          ..write('pid: $pid, ')
          ..write('sizePx: $sizePx, ')
          ..write('artUrl: $artUrl, ')
          ..write('etag: $etag, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientSettingsTable extends ClientSettings
    with TableInfo<$ClientSettingsTable, ClientSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ClientSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $ClientSettingsTable createAlias(String alias) {
    return $ClientSettingsTable(attachedDatabase, alias);
  }
}

class ClientSetting extends DataClass implements Insertable<ClientSetting> {
  final String key;
  final String value;
  const ClientSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  ClientSettingsCompanion toCompanion(bool nullToAbsent) {
    return ClientSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory ClientSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  ClientSetting copyWith({String? key, String? value}) =>
      ClientSetting(key: key ?? this.key, value: value ?? this.value);
  ClientSetting copyWithCompanion(ClientSettingsCompanion data) {
    return ClientSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class ClientSettingsCompanion extends UpdateCompanion<ClientSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const ClientSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<ClientSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return ClientSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MirrorDatabase extends GeneratedDatabase {
  _$MirrorDatabase(QueryExecutor e) : super(e);
  $MirrorDatabaseManager get managers => $MirrorDatabaseManager(this);
  late final $MirrorItemsTable mirrorItems = $MirrorItemsTable(this);
  late final $MirrorPlayStatesTable mirrorPlayStates = $MirrorPlayStatesTable(
    this,
  );
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $OutboxMutationsTable outboxMutations = $OutboxMutationsTable(
    this,
  );
  late final $OutboxListensTable outboxListens = $OutboxListensTable(this);
  late final $DownloadRecordsTable downloadRecords = $DownloadRecordsTable(
    this,
  );
  late final $QueueEntriesTable queueEntries = $QueueEntriesTable(this);
  late final $QueueMetaTable queueMeta = $QueueMetaTable(this);
  late final $ArtworkPinsTable artworkPins = $ArtworkPinsTable(this);
  late final $ClientSettingsTable clientSettings = $ClientSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    mirrorItems,
    mirrorPlayStates,
    syncCursors,
    outboxMutations,
    outboxListens,
    downloadRecords,
    queueEntries,
    queueMeta,
    artworkPins,
    clientSettings,
  ];
}

typedef $$MirrorItemsTableCreateCompanionBuilder =
    MirrorItemsCompanion Function({
      required String pid,
      required String ulid,
      required String mediaType,
      required String title,
      Value<String?> artist,
      Value<String?> album,
      required int durationMs,
      required String sortKey,
      Value<int> rowid,
    });
typedef $$MirrorItemsTableUpdateCompanionBuilder =
    MirrorItemsCompanion Function({
      Value<String> pid,
      Value<String> ulid,
      Value<String> mediaType,
      Value<String> title,
      Value<String?> artist,
      Value<String?> album,
      Value<int> durationMs,
      Value<String> sortKey,
      Value<int> rowid,
    });

class $$MirrorItemsTableFilterComposer
    extends Composer<_$MirrorDatabase, $MirrorItemsTable> {
  $$MirrorItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ulid => $composableBuilder(
    column: $table.ulid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MirrorItemsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $MirrorItemsTable> {
  $$MirrorItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ulid => $composableBuilder(
    column: $table.ulid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MirrorItemsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $MirrorItemsTable> {
  $$MirrorItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<String> get ulid =>
      $composableBuilder(column: $table.ulid, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);
}

class $$MirrorItemsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $MirrorItemsTable,
          MirrorItem,
          $$MirrorItemsTableFilterComposer,
          $$MirrorItemsTableOrderingComposer,
          $$MirrorItemsTableAnnotationComposer,
          $$MirrorItemsTableCreateCompanionBuilder,
          $$MirrorItemsTableUpdateCompanionBuilder,
          (
            MirrorItem,
            BaseReferences<_$MirrorDatabase, $MirrorItemsTable, MirrorItem>,
          ),
          MirrorItem,
          PrefetchHooks Function()
        > {
  $$MirrorItemsTableTableManager(_$MirrorDatabase db, $MirrorItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MirrorItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MirrorItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MirrorItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pid = const Value.absent(),
                Value<String> ulid = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MirrorItemsCompanion(
                pid: pid,
                ulid: ulid,
                mediaType: mediaType,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                sortKey: sortKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pid,
                required String ulid,
                required String mediaType,
                required String title,
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                required int durationMs,
                required String sortKey,
                Value<int> rowid = const Value.absent(),
              }) => MirrorItemsCompanion.insert(
                pid: pid,
                ulid: ulid,
                mediaType: mediaType,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                sortKey: sortKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MirrorItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $MirrorItemsTable,
      MirrorItem,
      $$MirrorItemsTableFilterComposer,
      $$MirrorItemsTableOrderingComposer,
      $$MirrorItemsTableAnnotationComposer,
      $$MirrorItemsTableCreateCompanionBuilder,
      $$MirrorItemsTableUpdateCompanionBuilder,
      (
        MirrorItem,
        BaseReferences<_$MirrorDatabase, $MirrorItemsTable, MirrorItem>,
      ),
      MirrorItem,
      PrefetchHooks Function()
    >;
typedef $$MirrorPlayStatesTableCreateCompanionBuilder =
    MirrorPlayStatesCompanion Function({
      required String pid,
      Value<int> positionMs,
      Value<bool> played,
      Value<bool> finished,
      Value<int> playCount,
      Value<bool> starred,
      Value<int?> rating,
      Value<DateTime?> updatedAt,
      Value<DateTime?> lastPlayedAt,
      Value<int> rowid,
    });
typedef $$MirrorPlayStatesTableUpdateCompanionBuilder =
    MirrorPlayStatesCompanion Function({
      Value<String> pid,
      Value<int> positionMs,
      Value<bool> played,
      Value<bool> finished,
      Value<int> playCount,
      Value<bool> starred,
      Value<int?> rating,
      Value<DateTime?> updatedAt,
      Value<DateTime?> lastPlayedAt,
      Value<int> rowid,
    });

class $$MirrorPlayStatesTableFilterComposer
    extends Composer<_$MirrorDatabase, $MirrorPlayStatesTable> {
  $$MirrorPlayStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get played => $composableBuilder(
    column: $table.played,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MirrorPlayStatesTableOrderingComposer
    extends Composer<_$MirrorDatabase, $MirrorPlayStatesTable> {
  $$MirrorPlayStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get played => $composableBuilder(
    column: $table.played,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MirrorPlayStatesTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $MirrorPlayStatesTable> {
  $$MirrorPlayStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get played =>
      $composableBuilder(column: $table.played, builder: (column) => column);

  GeneratedColumn<bool> get finished =>
      $composableBuilder(column: $table.finished, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<bool> get starred =>
      $composableBuilder(column: $table.starred, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );
}

class $$MirrorPlayStatesTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $MirrorPlayStatesTable,
          MirrorPlayState,
          $$MirrorPlayStatesTableFilterComposer,
          $$MirrorPlayStatesTableOrderingComposer,
          $$MirrorPlayStatesTableAnnotationComposer,
          $$MirrorPlayStatesTableCreateCompanionBuilder,
          $$MirrorPlayStatesTableUpdateCompanionBuilder,
          (
            MirrorPlayState,
            BaseReferences<
              _$MirrorDatabase,
              $MirrorPlayStatesTable,
              MirrorPlayState
            >,
          ),
          MirrorPlayState,
          PrefetchHooks Function()
        > {
  $$MirrorPlayStatesTableTableManager(
    _$MirrorDatabase db,
    $MirrorPlayStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MirrorPlayStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MirrorPlayStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MirrorPlayStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pid = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<bool> played = const Value.absent(),
                Value<bool> finished = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MirrorPlayStatesCompanion(
                pid: pid,
                positionMs: positionMs,
                played: played,
                finished: finished,
                playCount: playCount,
                starred: starred,
                rating: rating,
                updatedAt: updatedAt,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pid,
                Value<int> positionMs = const Value.absent(),
                Value<bool> played = const Value.absent(),
                Value<bool> finished = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MirrorPlayStatesCompanion.insert(
                pid: pid,
                positionMs: positionMs,
                played: played,
                finished: finished,
                playCount: playCount,
                starred: starred,
                rating: rating,
                updatedAt: updatedAt,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MirrorPlayStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $MirrorPlayStatesTable,
      MirrorPlayState,
      $$MirrorPlayStatesTableFilterComposer,
      $$MirrorPlayStatesTableOrderingComposer,
      $$MirrorPlayStatesTableAnnotationComposer,
      $$MirrorPlayStatesTableCreateCompanionBuilder,
      $$MirrorPlayStatesTableUpdateCompanionBuilder,
      (
        MirrorPlayState,
        BaseReferences<
          _$MirrorDatabase,
          $MirrorPlayStatesTable,
          MirrorPlayState
        >,
      ),
      MirrorPlayState,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<int> id,
      Value<String?> catalogSince,
      Value<String?> serverSince,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<int> id,
      Value<String?> catalogSince,
      Value<String?> serverSince,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$MirrorDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get catalogSince => $composableBuilder(
    column: $table.catalogSince,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverSince => $composableBuilder(
    column: $table.serverSince,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get catalogSince => $composableBuilder(
    column: $table.catalogSince,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverSince => $composableBuilder(
    column: $table.serverSince,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get catalogSince => $composableBuilder(
    column: $table.catalogSince,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverSince => $composableBuilder(
    column: $table.serverSince,
    builder: (column) => column,
  );
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $SyncCursorsTable,
          SyncCursor,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            SyncCursor,
            BaseReferences<_$MirrorDatabase, $SyncCursorsTable, SyncCursor>,
          ),
          SyncCursor,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$MirrorDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> catalogSince = const Value.absent(),
                Value<String?> serverSince = const Value.absent(),
              }) => SyncCursorsCompanion(
                id: id,
                catalogSince: catalogSince,
                serverSince: serverSince,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> catalogSince = const Value.absent(),
                Value<String?> serverSince = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                id: id,
                catalogSince: catalogSince,
                serverSince: serverSince,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $SyncCursorsTable,
      SyncCursor,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        SyncCursor,
        BaseReferences<_$MirrorDatabase, $SyncCursorsTable, SyncCursor>,
      ),
      SyncCursor,
      PrefetchHooks Function()
    >;
typedef $$OutboxMutationsTableCreateCompanionBuilder =
    OutboxMutationsCompanion Function({
      Value<int> id,
      required String kind,
      required String pid,
      Value<int?> positionMs,
      Value<bool?> starred,
      Value<int?> rating,
      required DateTime recordedAt,
    });
typedef $$OutboxMutationsTableUpdateCompanionBuilder =
    OutboxMutationsCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> pid,
      Value<int?> positionMs,
      Value<bool?> starred,
      Value<int?> rating,
      Value<DateTime> recordedAt,
    });

class $$OutboxMutationsTableFilterComposer
    extends Composer<_$MirrorDatabase, $OutboxMutationsTable> {
  $$OutboxMutationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxMutationsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $OutboxMutationsTable> {
  $$OutboxMutationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxMutationsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $OutboxMutationsTable> {
  $$OutboxMutationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get starred =>
      $composableBuilder(column: $table.starred, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$OutboxMutationsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $OutboxMutationsTable,
          OutboxMutation,
          $$OutboxMutationsTableFilterComposer,
          $$OutboxMutationsTableOrderingComposer,
          $$OutboxMutationsTableAnnotationComposer,
          $$OutboxMutationsTableCreateCompanionBuilder,
          $$OutboxMutationsTableUpdateCompanionBuilder,
          (
            OutboxMutation,
            BaseReferences<
              _$MirrorDatabase,
              $OutboxMutationsTable,
              OutboxMutation
            >,
          ),
          OutboxMutation,
          PrefetchHooks Function()
        > {
  $$OutboxMutationsTableTableManager(
    _$MirrorDatabase db,
    $OutboxMutationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxMutationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxMutationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxMutationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> pid = const Value.absent(),
                Value<int?> positionMs = const Value.absent(),
                Value<bool?> starred = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
              }) => OutboxMutationsCompanion(
                id: id,
                kind: kind,
                pid: pid,
                positionMs: positionMs,
                starred: starred,
                rating: rating,
                recordedAt: recordedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String pid,
                Value<int?> positionMs = const Value.absent(),
                Value<bool?> starred = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                required DateTime recordedAt,
              }) => OutboxMutationsCompanion.insert(
                id: id,
                kind: kind,
                pid: pid,
                positionMs: positionMs,
                starred: starred,
                rating: rating,
                recordedAt: recordedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxMutationsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $OutboxMutationsTable,
      OutboxMutation,
      $$OutboxMutationsTableFilterComposer,
      $$OutboxMutationsTableOrderingComposer,
      $$OutboxMutationsTableAnnotationComposer,
      $$OutboxMutationsTableCreateCompanionBuilder,
      $$OutboxMutationsTableUpdateCompanionBuilder,
      (
        OutboxMutation,
        BaseReferences<_$MirrorDatabase, $OutboxMutationsTable, OutboxMutation>,
      ),
      OutboxMutation,
      PrefetchHooks Function()
    >;
typedef $$OutboxListensTableCreateCompanionBuilder =
    OutboxListensCompanion Function({
      required String sessionId,
      required String pid,
      required DateTime startedAt,
      required int msPlayed,
      Value<bool> finished,
      Value<String> client,
      Value<int?> skippedMs,
      Value<int> rowid,
    });
typedef $$OutboxListensTableUpdateCompanionBuilder =
    OutboxListensCompanion Function({
      Value<String> sessionId,
      Value<String> pid,
      Value<DateTime> startedAt,
      Value<int> msPlayed,
      Value<bool> finished,
      Value<String> client,
      Value<int?> skippedMs,
      Value<int> rowid,
    });

class $$OutboxListensTableFilterComposer
    extends Composer<_$MirrorDatabase, $OutboxListensTable> {
  $$OutboxListensTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get msPlayed => $composableBuilder(
    column: $table.msPlayed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get client => $composableBuilder(
    column: $table.client,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skippedMs => $composableBuilder(
    column: $table.skippedMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxListensTableOrderingComposer
    extends Composer<_$MirrorDatabase, $OutboxListensTable> {
  $$OutboxListensTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get msPlayed => $composableBuilder(
    column: $table.msPlayed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get client => $composableBuilder(
    column: $table.client,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skippedMs => $composableBuilder(
    column: $table.skippedMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxListensTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $OutboxListensTable> {
  $$OutboxListensTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get msPlayed =>
      $composableBuilder(column: $table.msPlayed, builder: (column) => column);

  GeneratedColumn<bool> get finished =>
      $composableBuilder(column: $table.finished, builder: (column) => column);

  GeneratedColumn<String> get client =>
      $composableBuilder(column: $table.client, builder: (column) => column);

  GeneratedColumn<int> get skippedMs =>
      $composableBuilder(column: $table.skippedMs, builder: (column) => column);
}

class $$OutboxListensTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $OutboxListensTable,
          OutboxListen,
          $$OutboxListensTableFilterComposer,
          $$OutboxListensTableOrderingComposer,
          $$OutboxListensTableAnnotationComposer,
          $$OutboxListensTableCreateCompanionBuilder,
          $$OutboxListensTableUpdateCompanionBuilder,
          (
            OutboxListen,
            BaseReferences<_$MirrorDatabase, $OutboxListensTable, OutboxListen>,
          ),
          OutboxListen,
          PrefetchHooks Function()
        > {
  $$OutboxListensTableTableManager(
    _$MirrorDatabase db,
    $OutboxListensTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxListensTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxListensTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxListensTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> pid = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<int> msPlayed = const Value.absent(),
                Value<bool> finished = const Value.absent(),
                Value<String> client = const Value.absent(),
                Value<int?> skippedMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxListensCompanion(
                sessionId: sessionId,
                pid: pid,
                startedAt: startedAt,
                msPlayed: msPlayed,
                finished: finished,
                client: client,
                skippedMs: skippedMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String pid,
                required DateTime startedAt,
                required int msPlayed,
                Value<bool> finished = const Value.absent(),
                Value<String> client = const Value.absent(),
                Value<int?> skippedMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxListensCompanion.insert(
                sessionId: sessionId,
                pid: pid,
                startedAt: startedAt,
                msPlayed: msPlayed,
                finished: finished,
                client: client,
                skippedMs: skippedMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxListensTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $OutboxListensTable,
      OutboxListen,
      $$OutboxListensTableFilterComposer,
      $$OutboxListensTableOrderingComposer,
      $$OutboxListensTableAnnotationComposer,
      $$OutboxListensTableCreateCompanionBuilder,
      $$OutboxListensTableUpdateCompanionBuilder,
      (
        OutboxListen,
        BaseReferences<_$MirrorDatabase, $OutboxListensTable, OutboxListen>,
      ),
      OutboxListen,
      PrefetchHooks Function()
    >;
typedef $$DownloadRecordsTableCreateCompanionBuilder =
    DownloadRecordsCompanion Function({
      required String pid,
      required int fileIndex,
      required String essenceHash,
      required String etag,
      required String fileName,
      required String localPath,
      required int sizeBytes,
      required String state,
      Value<int?> spanStartMs,
      Value<int?> spanEndMs,
      Value<int?> durationMs,
      Value<int> rowid,
    });
typedef $$DownloadRecordsTableUpdateCompanionBuilder =
    DownloadRecordsCompanion Function({
      Value<String> pid,
      Value<int> fileIndex,
      Value<String> essenceHash,
      Value<String> etag,
      Value<String> fileName,
      Value<String> localPath,
      Value<int> sizeBytes,
      Value<String> state,
      Value<int?> spanStartMs,
      Value<int?> spanEndMs,
      Value<int?> durationMs,
      Value<int> rowid,
    });

class $$DownloadRecordsTableFilterComposer
    extends Composer<_$MirrorDatabase, $DownloadRecordsTable> {
  $$DownloadRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileIndex => $composableBuilder(
    column: $table.fileIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get essenceHash => $composableBuilder(
    column: $table.essenceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get spanStartMs => $composableBuilder(
    column: $table.spanStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get spanEndMs => $composableBuilder(
    column: $table.spanEndMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadRecordsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $DownloadRecordsTable> {
  $$DownloadRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileIndex => $composableBuilder(
    column: $table.fileIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get essenceHash => $composableBuilder(
    column: $table.essenceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get spanStartMs => $composableBuilder(
    column: $table.spanStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get spanEndMs => $composableBuilder(
    column: $table.spanEndMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadRecordsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $DownloadRecordsTable> {
  $$DownloadRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get fileIndex =>
      $composableBuilder(column: $table.fileIndex, builder: (column) => column);

  GeneratedColumn<String> get essenceHash => $composableBuilder(
    column: $table.essenceHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get spanStartMs => $composableBuilder(
    column: $table.spanStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get spanEndMs =>
      $composableBuilder(column: $table.spanEndMs, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );
}

class $$DownloadRecordsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $DownloadRecordsTable,
          DownloadRecord,
          $$DownloadRecordsTableFilterComposer,
          $$DownloadRecordsTableOrderingComposer,
          $$DownloadRecordsTableAnnotationComposer,
          $$DownloadRecordsTableCreateCompanionBuilder,
          $$DownloadRecordsTableUpdateCompanionBuilder,
          (
            DownloadRecord,
            BaseReferences<
              _$MirrorDatabase,
              $DownloadRecordsTable,
              DownloadRecord
            >,
          ),
          DownloadRecord,
          PrefetchHooks Function()
        > {
  $$DownloadRecordsTableTableManager(
    _$MirrorDatabase db,
    $DownloadRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pid = const Value.absent(),
                Value<int> fileIndex = const Value.absent(),
                Value<String> essenceHash = const Value.absent(),
                Value<String> etag = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int?> spanStartMs = const Value.absent(),
                Value<int?> spanEndMs = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadRecordsCompanion(
                pid: pid,
                fileIndex: fileIndex,
                essenceHash: essenceHash,
                etag: etag,
                fileName: fileName,
                localPath: localPath,
                sizeBytes: sizeBytes,
                state: state,
                spanStartMs: spanStartMs,
                spanEndMs: spanEndMs,
                durationMs: durationMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pid,
                required int fileIndex,
                required String essenceHash,
                required String etag,
                required String fileName,
                required String localPath,
                required int sizeBytes,
                required String state,
                Value<int?> spanStartMs = const Value.absent(),
                Value<int?> spanEndMs = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadRecordsCompanion.insert(
                pid: pid,
                fileIndex: fileIndex,
                essenceHash: essenceHash,
                etag: etag,
                fileName: fileName,
                localPath: localPath,
                sizeBytes: sizeBytes,
                state: state,
                spanStartMs: spanStartMs,
                spanEndMs: spanEndMs,
                durationMs: durationMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $DownloadRecordsTable,
      DownloadRecord,
      $$DownloadRecordsTableFilterComposer,
      $$DownloadRecordsTableOrderingComposer,
      $$DownloadRecordsTableAnnotationComposer,
      $$DownloadRecordsTableCreateCompanionBuilder,
      $$DownloadRecordsTableUpdateCompanionBuilder,
      (
        DownloadRecord,
        BaseReferences<_$MirrorDatabase, $DownloadRecordsTable, DownloadRecord>,
      ),
      DownloadRecord,
      PrefetchHooks Function()
    >;
typedef $$QueueEntriesTableCreateCompanionBuilder =
    QueueEntriesCompanion Function({
      required String queueId,
      required String pid,
      required int position,
      required int sourceRank,
      Value<int> rowid,
    });
typedef $$QueueEntriesTableUpdateCompanionBuilder =
    QueueEntriesCompanion Function({
      Value<String> queueId,
      Value<String> pid,
      Value<int> position,
      Value<int> sourceRank,
      Value<int> rowid,
    });

class $$QueueEntriesTableFilterComposer
    extends Composer<_$MirrorDatabase, $QueueEntriesTable> {
  $$QueueEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceRank => $composableBuilder(
    column: $table.sourceRank,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueEntriesTableOrderingComposer
    extends Composer<_$MirrorDatabase, $QueueEntriesTable> {
  $$QueueEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceRank => $composableBuilder(
    column: $table.sourceRank,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueEntriesTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $QueueEntriesTable> {
  $$QueueEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get queueId =>
      $composableBuilder(column: $table.queueId, builder: (column) => column);

  GeneratedColumn<String> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get sourceRank => $composableBuilder(
    column: $table.sourceRank,
    builder: (column) => column,
  );
}

class $$QueueEntriesTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $QueueEntriesTable,
          QueueEntry,
          $$QueueEntriesTableFilterComposer,
          $$QueueEntriesTableOrderingComposer,
          $$QueueEntriesTableAnnotationComposer,
          $$QueueEntriesTableCreateCompanionBuilder,
          $$QueueEntriesTableUpdateCompanionBuilder,
          (
            QueueEntry,
            BaseReferences<_$MirrorDatabase, $QueueEntriesTable, QueueEntry>,
          ),
          QueueEntry,
          PrefetchHooks Function()
        > {
  $$QueueEntriesTableTableManager(_$MirrorDatabase db, $QueueEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> queueId = const Value.absent(),
                Value<String> pid = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> sourceRank = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueueEntriesCompanion(
                queueId: queueId,
                pid: pid,
                position: position,
                sourceRank: sourceRank,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String queueId,
                required String pid,
                required int position,
                required int sourceRank,
                Value<int> rowid = const Value.absent(),
              }) => QueueEntriesCompanion.insert(
                queueId: queueId,
                pid: pid,
                position: position,
                sourceRank: sourceRank,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $QueueEntriesTable,
      QueueEntry,
      $$QueueEntriesTableFilterComposer,
      $$QueueEntriesTableOrderingComposer,
      $$QueueEntriesTableAnnotationComposer,
      $$QueueEntriesTableCreateCompanionBuilder,
      $$QueueEntriesTableUpdateCompanionBuilder,
      (
        QueueEntry,
        BaseReferences<_$MirrorDatabase, $QueueEntriesTable, QueueEntry>,
      ),
      QueueEntry,
      PrefetchHooks Function()
    >;
typedef $$QueueMetaTableCreateCompanionBuilder =
    QueueMetaCompanion Function({
      Value<int> id,
      Value<int> currentIndex,
      Value<bool> shuffled,
      Value<String> repeat,
      Value<String> sourceKind,
      Value<String> sourceLabel,
      Value<String?> sourcePid,
      Value<bool> sourceRolling,
      Value<int> nextQueueId,
      required DateTime updatedAt,
      Value<String> sourceCursor,
    });
typedef $$QueueMetaTableUpdateCompanionBuilder =
    QueueMetaCompanion Function({
      Value<int> id,
      Value<int> currentIndex,
      Value<bool> shuffled,
      Value<String> repeat,
      Value<String> sourceKind,
      Value<String> sourceLabel,
      Value<String?> sourcePid,
      Value<bool> sourceRolling,
      Value<int> nextQueueId,
      Value<DateTime> updatedAt,
      Value<String> sourceCursor,
    });

class $$QueueMetaTableFilterComposer
    extends Composer<_$MirrorDatabase, $QueueMetaTable> {
  $$QueueMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get shuffled => $composableBuilder(
    column: $table.shuffled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repeat => $composableBuilder(
    column: $table.repeat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePid => $composableBuilder(
    column: $table.sourcePid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sourceRolling => $composableBuilder(
    column: $table.sourceRolling,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextQueueId => $composableBuilder(
    column: $table.nextQueueId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceCursor => $composableBuilder(
    column: $table.sourceCursor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueMetaTableOrderingComposer
    extends Composer<_$MirrorDatabase, $QueueMetaTable> {
  $$QueueMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shuffled => $composableBuilder(
    column: $table.shuffled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeat => $composableBuilder(
    column: $table.repeat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePid => $composableBuilder(
    column: $table.sourcePid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sourceRolling => $composableBuilder(
    column: $table.sourceRolling,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextQueueId => $composableBuilder(
    column: $table.nextQueueId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceCursor => $composableBuilder(
    column: $table.sourceCursor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueMetaTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $QueueMetaTable> {
  $$QueueMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get shuffled =>
      $composableBuilder(column: $table.shuffled, builder: (column) => column);

  GeneratedColumn<String> get repeat =>
      $composableBuilder(column: $table.repeat, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourcePid =>
      $composableBuilder(column: $table.sourcePid, builder: (column) => column);

  GeneratedColumn<bool> get sourceRolling => $composableBuilder(
    column: $table.sourceRolling,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextQueueId => $composableBuilder(
    column: $table.nextQueueId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sourceCursor => $composableBuilder(
    column: $table.sourceCursor,
    builder: (column) => column,
  );
}

class $$QueueMetaTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $QueueMetaTable,
          QueueMetaData,
          $$QueueMetaTableFilterComposer,
          $$QueueMetaTableOrderingComposer,
          $$QueueMetaTableAnnotationComposer,
          $$QueueMetaTableCreateCompanionBuilder,
          $$QueueMetaTableUpdateCompanionBuilder,
          (
            QueueMetaData,
            BaseReferences<_$MirrorDatabase, $QueueMetaTable, QueueMetaData>,
          ),
          QueueMetaData,
          PrefetchHooks Function()
        > {
  $$QueueMetaTableTableManager(_$MirrorDatabase db, $QueueMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> currentIndex = const Value.absent(),
                Value<bool> shuffled = const Value.absent(),
                Value<String> repeat = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String> sourceLabel = const Value.absent(),
                Value<String?> sourcePid = const Value.absent(),
                Value<bool> sourceRolling = const Value.absent(),
                Value<int> nextQueueId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> sourceCursor = const Value.absent(),
              }) => QueueMetaCompanion(
                id: id,
                currentIndex: currentIndex,
                shuffled: shuffled,
                repeat: repeat,
                sourceKind: sourceKind,
                sourceLabel: sourceLabel,
                sourcePid: sourcePid,
                sourceRolling: sourceRolling,
                nextQueueId: nextQueueId,
                updatedAt: updatedAt,
                sourceCursor: sourceCursor,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> currentIndex = const Value.absent(),
                Value<bool> shuffled = const Value.absent(),
                Value<String> repeat = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String> sourceLabel = const Value.absent(),
                Value<String?> sourcePid = const Value.absent(),
                Value<bool> sourceRolling = const Value.absent(),
                Value<int> nextQueueId = const Value.absent(),
                required DateTime updatedAt,
                Value<String> sourceCursor = const Value.absent(),
              }) => QueueMetaCompanion.insert(
                id: id,
                currentIndex: currentIndex,
                shuffled: shuffled,
                repeat: repeat,
                sourceKind: sourceKind,
                sourceLabel: sourceLabel,
                sourcePid: sourcePid,
                sourceRolling: sourceRolling,
                nextQueueId: nextQueueId,
                updatedAt: updatedAt,
                sourceCursor: sourceCursor,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $QueueMetaTable,
      QueueMetaData,
      $$QueueMetaTableFilterComposer,
      $$QueueMetaTableOrderingComposer,
      $$QueueMetaTableAnnotationComposer,
      $$QueueMetaTableCreateCompanionBuilder,
      $$QueueMetaTableUpdateCompanionBuilder,
      (
        QueueMetaData,
        BaseReferences<_$MirrorDatabase, $QueueMetaTable, QueueMetaData>,
      ),
      QueueMetaData,
      PrefetchHooks Function()
    >;
typedef $$ArtworkPinsTableCreateCompanionBuilder =
    ArtworkPinsCompanion Function({
      required String pid,
      required int sizePx,
      required String artUrl,
      required String etag,
      required String localPath,
      required int sizeBytes,
      required DateTime pinnedAt,
      Value<int> rowid,
    });
typedef $$ArtworkPinsTableUpdateCompanionBuilder =
    ArtworkPinsCompanion Function({
      Value<String> pid,
      Value<int> sizePx,
      Value<String> artUrl,
      Value<String> etag,
      Value<String> localPath,
      Value<int> sizeBytes,
      Value<DateTime> pinnedAt,
      Value<int> rowid,
    });

class $$ArtworkPinsTableFilterComposer
    extends Composer<_$MirrorDatabase, $ArtworkPinsTable> {
  $$ArtworkPinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizePx => $composableBuilder(
    column: $table.sizePx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artUrl => $composableBuilder(
    column: $table.artUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArtworkPinsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $ArtworkPinsTable> {
  $$ArtworkPinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizePx => $composableBuilder(
    column: $table.sizePx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artUrl => $composableBuilder(
    column: $table.artUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArtworkPinsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $ArtworkPinsTable> {
  $$ArtworkPinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get sizePx =>
      $composableBuilder(column: $table.sizePx, builder: (column) => column);

  GeneratedColumn<String> get artUrl =>
      $composableBuilder(column: $table.artUrl, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);
}

class $$ArtworkPinsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $ArtworkPinsTable,
          ArtworkPin,
          $$ArtworkPinsTableFilterComposer,
          $$ArtworkPinsTableOrderingComposer,
          $$ArtworkPinsTableAnnotationComposer,
          $$ArtworkPinsTableCreateCompanionBuilder,
          $$ArtworkPinsTableUpdateCompanionBuilder,
          (
            ArtworkPin,
            BaseReferences<_$MirrorDatabase, $ArtworkPinsTable, ArtworkPin>,
          ),
          ArtworkPin,
          PrefetchHooks Function()
        > {
  $$ArtworkPinsTableTableManager(_$MirrorDatabase db, $ArtworkPinsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtworkPinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtworkPinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtworkPinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pid = const Value.absent(),
                Value<int> sizePx = const Value.absent(),
                Value<String> artUrl = const Value.absent(),
                Value<String> etag = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArtworkPinsCompanion(
                pid: pid,
                sizePx: sizePx,
                artUrl: artUrl,
                etag: etag,
                localPath: localPath,
                sizeBytes: sizeBytes,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pid,
                required int sizePx,
                required String artUrl,
                required String etag,
                required String localPath,
                required int sizeBytes,
                required DateTime pinnedAt,
                Value<int> rowid = const Value.absent(),
              }) => ArtworkPinsCompanion.insert(
                pid: pid,
                sizePx: sizePx,
                artUrl: artUrl,
                etag: etag,
                localPath: localPath,
                sizeBytes: sizeBytes,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArtworkPinsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $ArtworkPinsTable,
      ArtworkPin,
      $$ArtworkPinsTableFilterComposer,
      $$ArtworkPinsTableOrderingComposer,
      $$ArtworkPinsTableAnnotationComposer,
      $$ArtworkPinsTableCreateCompanionBuilder,
      $$ArtworkPinsTableUpdateCompanionBuilder,
      (
        ArtworkPin,
        BaseReferences<_$MirrorDatabase, $ArtworkPinsTable, ArtworkPin>,
      ),
      ArtworkPin,
      PrefetchHooks Function()
    >;
typedef $$ClientSettingsTableCreateCompanionBuilder =
    ClientSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$ClientSettingsTableUpdateCompanionBuilder =
    ClientSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$ClientSettingsTableFilterComposer
    extends Composer<_$MirrorDatabase, $ClientSettingsTable> {
  $$ClientSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientSettingsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $ClientSettingsTable> {
  $$ClientSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientSettingsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $ClientSettingsTable> {
  $$ClientSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$ClientSettingsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $ClientSettingsTable,
          ClientSetting,
          $$ClientSettingsTableFilterComposer,
          $$ClientSettingsTableOrderingComposer,
          $$ClientSettingsTableAnnotationComposer,
          $$ClientSettingsTableCreateCompanionBuilder,
          $$ClientSettingsTableUpdateCompanionBuilder,
          (
            ClientSetting,
            BaseReferences<
              _$MirrorDatabase,
              $ClientSettingsTable,
              ClientSetting
            >,
          ),
          ClientSetting,
          PrefetchHooks Function()
        > {
  $$ClientSettingsTableTableManager(
    _$MirrorDatabase db,
    $ClientSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  ClientSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => ClientSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $ClientSettingsTable,
      ClientSetting,
      $$ClientSettingsTableFilterComposer,
      $$ClientSettingsTableOrderingComposer,
      $$ClientSettingsTableAnnotationComposer,
      $$ClientSettingsTableCreateCompanionBuilder,
      $$ClientSettingsTableUpdateCompanionBuilder,
      (
        ClientSetting,
        BaseReferences<_$MirrorDatabase, $ClientSettingsTable, ClientSetting>,
      ),
      ClientSetting,
      PrefetchHooks Function()
    >;

class $MirrorDatabaseManager {
  final _$MirrorDatabase _db;
  $MirrorDatabaseManager(this._db);
  $$MirrorItemsTableTableManager get mirrorItems =>
      $$MirrorItemsTableTableManager(_db, _db.mirrorItems);
  $$MirrorPlayStatesTableTableManager get mirrorPlayStates =>
      $$MirrorPlayStatesTableTableManager(_db, _db.mirrorPlayStates);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$OutboxMutationsTableTableManager get outboxMutations =>
      $$OutboxMutationsTableTableManager(_db, _db.outboxMutations);
  $$OutboxListensTableTableManager get outboxListens =>
      $$OutboxListensTableTableManager(_db, _db.outboxListens);
  $$DownloadRecordsTableTableManager get downloadRecords =>
      $$DownloadRecordsTableTableManager(_db, _db.downloadRecords);
  $$QueueEntriesTableTableManager get queueEntries =>
      $$QueueEntriesTableTableManager(_db, _db.queueEntries);
  $$QueueMetaTableTableManager get queueMeta =>
      $$QueueMetaTableTableManager(_db, _db.queueMeta);
  $$ArtworkPinsTableTableManager get artworkPins =>
      $$ArtworkPinsTableTableManager(_db, _db.artworkPins);
  $$ClientSettingsTableTableManager get clientSettings =>
      $$ClientSettingsTableTableManager(_db, _db.clientSettings);
}
