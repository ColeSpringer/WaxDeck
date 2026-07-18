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
  const MirrorPlayState({
    required this.pid,
    required this.positionMs,
    required this.played,
    required this.finished,
    required this.playCount,
    required this.starred,
    this.rating,
    this.updatedAt,
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
  }) => MirrorPlayState(
    pid: pid ?? this.pid,
    positionMs: positionMs ?? this.positionMs,
    played: played ?? this.played,
    finished: finished ?? this.finished,
    playCount: playCount ?? this.playCount,
    starred: starred ?? this.starred,
    rating: rating.present ? rating.value : this.rating,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
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
          ..write('updatedAt: $updatedAt')
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
          other.updatedAt == this.updatedAt);
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
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    pid,
    startedAt,
    msPlayed,
    finished,
    client,
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
  const OutboxListen({
    required this.sessionId,
    required this.pid,
    required this.startedAt,
    required this.msPlayed,
    required this.finished,
    required this.client,
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
    };
  }

  OutboxListen copyWith({
    String? sessionId,
    String? pid,
    DateTime? startedAt,
    int? msPlayed,
    bool? finished,
    String? client,
  }) => OutboxListen(
    sessionId: sessionId ?? this.sessionId,
    pid: pid ?? this.pid,
    startedAt: startedAt ?? this.startedAt,
    msPlayed: msPlayed ?? this.msPlayed,
    finished: finished ?? this.finished,
    client: client ?? this.client,
  );
  OutboxListen copyWithCompanion(OutboxListensCompanion data) {
    return OutboxListen(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      pid: data.pid.present ? data.pid.value : this.pid,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      msPlayed: data.msPlayed.present ? data.msPlayed.value : this.msPlayed,
      finished: data.finished.present ? data.finished.value : this.finished,
      client: data.client.present ? data.client.value : this.client,
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
          ..write('client: $client')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, pid, startedAt, msPlayed, finished, client);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxListen &&
          other.sessionId == this.sessionId &&
          other.pid == this.pid &&
          other.startedAt == this.startedAt &&
          other.msPlayed == this.msPlayed &&
          other.finished == this.finished &&
          other.client == this.client);
}

class OutboxListensCompanion extends UpdateCompanion<OutboxListen> {
  final Value<String> sessionId;
  final Value<String> pid;
  final Value<DateTime> startedAt;
  final Value<int> msPlayed;
  final Value<bool> finished;
  final Value<String> client;
  final Value<int> rowid;
  const OutboxListensCompanion({
    this.sessionId = const Value.absent(),
    this.pid = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.msPlayed = const Value.absent(),
    this.finished = const Value.absent(),
    this.client = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxListensCompanion.insert({
    required String sessionId,
    required String pid,
    required DateTime startedAt,
    required int msPlayed,
    this.finished = const Value.absent(),
    this.client = const Value.absent(),
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
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (pid != null) 'pid': pid,
      if (startedAt != null) 'started_at': startedAt,
      if (msPlayed != null) 'ms_played': msPlayed,
      if (finished != null) 'finished': finished,
      if (client != null) 'client': client,
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
    Value<int>? rowid,
  }) {
    return OutboxListensCompanion(
      sessionId: sessionId ?? this.sessionId,
      pid: pid ?? this.pid,
      startedAt: startedAt ?? this.startedAt,
      msPlayed: msPlayed ?? this.msPlayed,
      finished: finished ?? this.finished,
      client: client ?? this.client,
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
          ..write('spanEndMs: $spanEndMs')
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
          other.spanEndMs == this.spanEndMs);
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
                Value<int> rowid = const Value.absent(),
              }) => OutboxListensCompanion(
                sessionId: sessionId,
                pid: pid,
                startedAt: startedAt,
                msPlayed: msPlayed,
                finished: finished,
                client: client,
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
                Value<int> rowid = const Value.absent(),
              }) => OutboxListensCompanion.insert(
                sessionId: sessionId,
                pid: pid,
                startedAt: startedAt,
                msPlayed: msPlayed,
                finished: finished,
                client: client,
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
}
