// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cast_preflight_base.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CastPreflightBase extends CastPreflightBase {
  @override
  final String base_;
  @override
  final String source_;
  @override
  final bool reachable;
  @override
  final BuiltList<String> notes;

  factory _$CastPreflightBase([
    void Function(CastPreflightBaseBuilder)? updates,
  ]) => (CastPreflightBaseBuilder()..update(updates))._build();

  _$CastPreflightBase._({
    required this.base_,
    required this.source_,
    required this.reachable,
    required this.notes,
  }) : super._();
  @override
  CastPreflightBase rebuild(void Function(CastPreflightBaseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CastPreflightBaseBuilder toBuilder() =>
      CastPreflightBaseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CastPreflightBase &&
        base_ == other.base_ &&
        source_ == other.source_ &&
        reachable == other.reachable &&
        notes == other.notes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, base_.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, reachable.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CastPreflightBase')
          ..add('base_', base_)
          ..add('source_', source_)
          ..add('reachable', reachable)
          ..add('notes', notes))
        .toString();
  }
}

class CastPreflightBaseBuilder
    implements Builder<CastPreflightBase, CastPreflightBaseBuilder> {
  _$CastPreflightBase? _$v;

  String? _base_;
  String? get base_ => _$this._base_;
  set base_(String? base_) => _$this._base_ = base_;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  bool? _reachable;
  bool? get reachable => _$this._reachable;
  set reachable(bool? reachable) => _$this._reachable = reachable;

  ListBuilder<String>? _notes;
  ListBuilder<String> get notes => _$this._notes ??= ListBuilder<String>();
  set notes(ListBuilder<String>? notes) => _$this._notes = notes;

  CastPreflightBaseBuilder() {
    CastPreflightBase._defaults(this);
  }

  CastPreflightBaseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _base_ = $v.base_;
      _source_ = $v.source_;
      _reachable = $v.reachable;
      _notes = $v.notes.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CastPreflightBase other) {
    _$v = other as _$CastPreflightBase;
  }

  @override
  void update(void Function(CastPreflightBaseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CastPreflightBase build() => _build();

  _$CastPreflightBase _build() {
    _$CastPreflightBase _$result;
    try {
      _$result =
          _$v ??
          _$CastPreflightBase._(
            base_: BuiltValueNullFieldError.checkNotNull(
              base_,
              r'CastPreflightBase',
              'base_',
            ),
            source_: BuiltValueNullFieldError.checkNotNull(
              source_,
              r'CastPreflightBase',
              'source_',
            ),
            reachable: BuiltValueNullFieldError.checkNotNull(
              reachable,
              r'CastPreflightBase',
              'reachable',
            ),
            notes: notes.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'notes';
        notes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CastPreflightBase',
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
