// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyrics.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Lyrics extends Lyrics {
  @override
  final String pid;
  @override
  final String source_;
  @override
  final String? provider;
  @override
  final BuiltList<SyncedLine>? synced;
  @override
  final String? unsynced;

  factory _$Lyrics([void Function(LyricsBuilder)? updates]) =>
      (LyricsBuilder()..update(updates))._build();

  _$Lyrics._({
    required this.pid,
    required this.source_,
    this.provider,
    this.synced,
    this.unsynced,
  }) : super._();
  @override
  Lyrics rebuild(void Function(LyricsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LyricsBuilder toBuilder() => LyricsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Lyrics &&
        pid == other.pid &&
        source_ == other.source_ &&
        provider == other.provider &&
        synced == other.synced &&
        unsynced == other.unsynced;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, synced.hashCode);
    _$hash = $jc(_$hash, unsynced.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Lyrics')
          ..add('pid', pid)
          ..add('source_', source_)
          ..add('provider', provider)
          ..add('synced', synced)
          ..add('unsynced', unsynced))
        .toString();
  }
}

class LyricsBuilder implements Builder<Lyrics, LyricsBuilder> {
  _$Lyrics? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  ListBuilder<SyncedLine>? _synced;
  ListBuilder<SyncedLine> get synced =>
      _$this._synced ??= ListBuilder<SyncedLine>();
  set synced(ListBuilder<SyncedLine>? synced) => _$this._synced = synced;

  String? _unsynced;
  String? get unsynced => _$this._unsynced;
  set unsynced(String? unsynced) => _$this._unsynced = unsynced;

  LyricsBuilder() {
    Lyrics._defaults(this);
  }

  LyricsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _source_ = $v.source_;
      _provider = $v.provider;
      _synced = $v.synced?.toBuilder();
      _unsynced = $v.unsynced;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Lyrics other) {
    _$v = other as _$Lyrics;
  }

  @override
  void update(void Function(LyricsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Lyrics build() => _build();

  _$Lyrics _build() {
    _$Lyrics _$result;
    try {
      _$result =
          _$v ??
          _$Lyrics._(
            pid: BuiltValueNullFieldError.checkNotNull(pid, r'Lyrics', 'pid'),
            source_: BuiltValueNullFieldError.checkNotNull(
              source_,
              r'Lyrics',
              'source_',
            ),
            provider: provider,
            synced: _synced?.build(),
            unsynced: unsynced,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'synced';
        _synced?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Lyrics',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
