// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'star_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StarUpdate extends StarUpdate {
  @override
  final bool starred;

  factory _$StarUpdate([void Function(StarUpdateBuilder)? updates]) =>
      (StarUpdateBuilder()..update(updates))._build();

  _$StarUpdate._({required this.starred}) : super._();
  @override
  StarUpdate rebuild(void Function(StarUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StarUpdateBuilder toBuilder() => StarUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StarUpdate && starred == other.starred;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, starred.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'StarUpdate',
    )..add('starred', starred)).toString();
  }
}

class StarUpdateBuilder implements Builder<StarUpdate, StarUpdateBuilder> {
  _$StarUpdate? _$v;

  bool? _starred;
  bool? get starred => _$this._starred;
  set starred(bool? starred) => _$this._starred = starred;

  StarUpdateBuilder() {
    StarUpdate._defaults(this);
  }

  StarUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _starred = $v.starred;
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
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
