// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'star_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StarUpdate extends StarUpdate {
  @override
  final bool starred;
  @override
  final DateTime? recordedAt;

  factory _$StarUpdate([void Function(StarUpdateBuilder)? updates]) =>
      (StarUpdateBuilder()..update(updates))._build();

  _$StarUpdate._({required this.starred, this.recordedAt}) : super._();
  @override
  StarUpdate rebuild(void Function(StarUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StarUpdateBuilder toBuilder() => StarUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StarUpdate &&
        starred == other.starred &&
        recordedAt == other.recordedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, starred.hashCode);
    _$hash = $jc(_$hash, recordedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StarUpdate')
          ..add('starred', starred)
          ..add('recordedAt', recordedAt))
        .toString();
  }
}

class StarUpdateBuilder implements Builder<StarUpdate, StarUpdateBuilder> {
  _$StarUpdate? _$v;

  bool? _starred;
  bool? get starred => _$this._starred;
  set starred(bool? starred) => _$this._starred = starred;

  DateTime? _recordedAt;
  DateTime? get recordedAt => _$this._recordedAt;
  set recordedAt(DateTime? recordedAt) => _$this._recordedAt = recordedAt;

  StarUpdateBuilder() {
    StarUpdate._defaults(this);
  }

  StarUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _starred = $v.starred;
      _recordedAt = $v.recordedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StarUpdate other) {
    _$v = other as _$StarUpdate;
  }

  @override
  void update(void Function(StarUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StarUpdate build() => _build();

  _$StarUpdate _build() {
    final _$result =
        _$v ??
        _$StarUpdate._(
          starred: BuiltValueNullFieldError.checkNotNull(
            starred,
            r'StarUpdate',
            'starred',
          ),
          recordedAt: recordedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
