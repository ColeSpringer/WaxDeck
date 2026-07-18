// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'play_state_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayStateList extends PlayStateList {
  @override
  final BuiltList<PlayState> states;

  factory _$PlayStateList([void Function(PlayStateListBuilder)? updates]) =>
      (PlayStateListBuilder()..update(updates))._build();

  _$PlayStateList._({required this.states}) : super._();
  @override
  PlayStateList rebuild(void Function(PlayStateListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayStateListBuilder toBuilder() => PlayStateListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayStateList && states == other.states;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, states.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PlayStateList',
    )..add('states', states)).toString();
  }
}

class PlayStateListBuilder
    implements Builder<PlayStateList, PlayStateListBuilder> {
  _$PlayStateList? _$v;

  ListBuilder<PlayState>? _states;
  ListBuilder<PlayState> get states =>
      _$this._states ??= ListBuilder<PlayState>();
  set states(ListBuilder<PlayState>? states) => _$this._states = states;

  PlayStateListBuilder() {
    PlayStateList._defaults(this);
  }

  PlayStateListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _states = $v.states.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayStateList other) {
    _$v = other as _$PlayStateList;
  }

  @override
  void update(void Function(PlayStateListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayStateList build() => _build();

  _$PlayStateList _build() {
    _$PlayStateList _$result;
    try {
      _$result = _$v ?? _$PlayStateList._(states: states.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'states';
        states.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlayStateList',
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
