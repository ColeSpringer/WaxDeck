// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scrobbler_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScrobblerList extends ScrobblerList {
  @override
  final BuiltList<Scrobbler> scrobblers;

  factory _$ScrobblerList([void Function(ScrobblerListBuilder)? updates]) =>
      (ScrobblerListBuilder()..update(updates))._build();

  _$ScrobblerList._({required this.scrobblers}) : super._();
  @override
  ScrobblerList rebuild(void Function(ScrobblerListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScrobblerListBuilder toBuilder() => ScrobblerListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScrobblerList && scrobblers == other.scrobblers;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, scrobblers.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ScrobblerList',
    )..add('scrobblers', scrobblers)).toString();
  }
}

class ScrobblerListBuilder
    implements Builder<ScrobblerList, ScrobblerListBuilder> {
  _$ScrobblerList? _$v;

  ListBuilder<Scrobbler>? _scrobblers;
  ListBuilder<Scrobbler> get scrobblers =>
      _$this._scrobblers ??= ListBuilder<Scrobbler>();
  set scrobblers(ListBuilder<Scrobbler>? scrobblers) =>
      _$this._scrobblers = scrobblers;

  ScrobblerListBuilder() {
    ScrobblerList._defaults(this);
  }

  ScrobblerListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scrobblers = $v.scrobblers.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScrobblerList other) {
    _$v = other as _$ScrobblerList;
  }

  @override
  void update(void Function(ScrobblerListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScrobblerList build() => _build();

  _$ScrobblerList _build() {
    _$ScrobblerList _$result;
    try {
      _$result = _$v ?? _$ScrobblerList._(scrobblers: scrobblers.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'scrobblers';
        scrobblers.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ScrobblerList',
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
