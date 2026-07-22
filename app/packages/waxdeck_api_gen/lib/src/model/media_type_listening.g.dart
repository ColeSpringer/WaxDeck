// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_type_listening.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MediaTypeListening extends MediaTypeListening {
  @override
  final MediaType mediaType;
  @override
  final int ms;
  @override
  final int sessions;

  factory _$MediaTypeListening([
    void Function(MediaTypeListeningBuilder)? updates,
  ]) => (MediaTypeListeningBuilder()..update(updates))._build();

  _$MediaTypeListening._({
    required this.mediaType,
    required this.ms,
    required this.sessions,
  }) : super._();
  @override
  MediaTypeListening rebuild(
    void Function(MediaTypeListeningBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MediaTypeListeningBuilder toBuilder() =>
      MediaTypeListeningBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MediaTypeListening &&
        mediaType == other.mediaType &&
        ms == other.ms &&
        sessions == other.sessions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, ms.hashCode);
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MediaTypeListening')
          ..add('mediaType', mediaType)
          ..add('ms', ms)
          ..add('sessions', sessions))
        .toString();
  }
}

class MediaTypeListeningBuilder
    implements Builder<MediaTypeListening, MediaTypeListeningBuilder> {
  _$MediaTypeListening? _$v;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  int? _ms;
  int? get ms => _$this._ms;
  set ms(int? ms) => _$this._ms = ms;

  int? _sessions;
  int? get sessions => _$this._sessions;
  set sessions(int? sessions) => _$this._sessions = sessions;

  MediaTypeListeningBuilder() {
    MediaTypeListening._defaults(this);
  }

  MediaTypeListeningBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mediaType = $v.mediaType;
      _ms = $v.ms;
      _sessions = $v.sessions;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MediaTypeListening other) {
    _$v = other as _$MediaTypeListening;
  }

  @override
  void update(void Function(MediaTypeListeningBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MediaTypeListening build() => _build();

  _$MediaTypeListening _build() {
    final _$result =
        _$v ??
        _$MediaTypeListening._(
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'MediaTypeListening',
            'mediaType',
          ),
          ms: BuiltValueNullFieldError.checkNotNull(
            ms,
            r'MediaTypeListening',
            'ms',
          ),
          sessions: BuiltValueNullFieldError.checkNotNull(
            sessions,
            r'MediaTypeListening',
            'sessions',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
