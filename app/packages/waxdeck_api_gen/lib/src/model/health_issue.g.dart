// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_issue.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthIssue extends HealthIssue {
  @override
  final String pid;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final MediaType mediaType;
  @override
  final BuiltList<String> rules;

  factory _$HealthIssue([void Function(HealthIssueBuilder)? updates]) =>
      (HealthIssueBuilder()..update(updates))._build();

  _$HealthIssue._({
    required this.pid,
    required this.title,
    this.artist,
    required this.mediaType,
    required this.rules,
  }) : super._();
  @override
  HealthIssue rebuild(void Function(HealthIssueBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthIssueBuilder toBuilder() => HealthIssueBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthIssue &&
        pid == other.pid &&
        title == other.title &&
        artist == other.artist &&
        mediaType == other.mediaType &&
        rules == other.rules;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, rules.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthIssue')
          ..add('pid', pid)
          ..add('title', title)
          ..add('artist', artist)
          ..add('mediaType', mediaType)
          ..add('rules', rules))
        .toString();
  }
}

class HealthIssueBuilder implements Builder<HealthIssue, HealthIssueBuilder> {
  _$HealthIssue? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  ListBuilder<String>? _rules;
  ListBuilder<String> get rules => _$this._rules ??= ListBuilder<String>();
  set rules(ListBuilder<String>? rules) => _$this._rules = rules;

  HealthIssueBuilder() {
    HealthIssue._defaults(this);
  }

  HealthIssueBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _title = $v.title;
      _artist = $v.artist;
      _mediaType = $v.mediaType;
      _rules = $v.rules.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthIssue other) {
    _$v = other as _$HealthIssue;
  }

  @override
  void update(void Function(HealthIssueBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthIssue build() => _build();

  _$HealthIssue _build() {
    _$HealthIssue _$result;
    try {
      _$result =
          _$v ??
          _$HealthIssue._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'HealthIssue',
              'pid',
            ),
            title: BuiltValueNullFieldError.checkNotNull(
              title,
              r'HealthIssue',
              'title',
            ),
            artist: artist,
            mediaType: BuiltValueNullFieldError.checkNotNull(
              mediaType,
              r'HealthIssue',
              'mediaType',
            ),
            rules: rules.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rules';
        rules.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'HealthIssue',
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
