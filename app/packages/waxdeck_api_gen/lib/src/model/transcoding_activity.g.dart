// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcoding_activity.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TranscodingActivity extends TranscodingActivity {
  @override
  final int activeSessions;
  @override
  final int? activeTimelines;

  factory _$TranscodingActivity([
    void Function(TranscodingActivityBuilder)? updates,
  ]) => (TranscodingActivityBuilder()..update(updates))._build();

  _$TranscodingActivity._({required this.activeSessions, this.activeTimelines})
    : super._();
  @override
  TranscodingActivity rebuild(
    void Function(TranscodingActivityBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  TranscodingActivityBuilder toBuilder() =>
      TranscodingActivityBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TranscodingActivity &&
        activeSessions == other.activeSessions &&
        activeTimelines == other.activeTimelines;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, activeSessions.hashCode);
    _$hash = $jc(_$hash, activeTimelines.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TranscodingActivity')
          ..add('activeSessions', activeSessions)
          ..add('activeTimelines', activeTimelines))
        .toString();
  }
}

class TranscodingActivityBuilder
    implements Builder<TranscodingActivity, TranscodingActivityBuilder> {
  _$TranscodingActivity? _$v;

  int? _activeSessions;
  int? get activeSessions => _$this._activeSessions;
  set activeSessions(int? activeSessions) =>
      _$this._activeSessions = activeSessions;

  int? _activeTimelines;
  int? get activeTimelines => _$this._activeTimelines;
  set activeTimelines(int? activeTimelines) =>
      _$this._activeTimelines = activeTimelines;

  TranscodingActivityBuilder() {
    TranscodingActivity._defaults(this);
  }

  TranscodingActivityBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _activeSessions = $v.activeSessions;
      _activeTimelines = $v.activeTimelines;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TranscodingActivity other) {
    _$v = other as _$TranscodingActivity;
  }

  @override
  void update(void Function(TranscodingActivityBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TranscodingActivity build() => _build();

  _$TranscodingActivity _build() {
    final _$result =
        _$v ??
        _$TranscodingActivity._(
          activeSessions: BuiltValueNullFieldError.checkNotNull(
            activeSessions,
            r'TranscodingActivity',
            'activeSessions',
          ),
          activeTimelines: activeTimelines,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
