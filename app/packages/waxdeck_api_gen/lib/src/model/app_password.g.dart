// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_password.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract mixin class AppPasswordBuilder {
  void replace(AppPassword other);
  void update(void Function(AppPasswordBuilder) updates);
  String? get id;
  set id(String? id);

  String? get label;
  set label(String? label);

  DateTime? get createdAt;
  set createdAt(DateTime? createdAt);

  DateTime? get lastUsedAt;
  set lastUsedAt(DateTime? lastUsedAt);
}

class _$$AppPassword extends $AppPassword {
  @override
  final String id;
  @override
  final String label;
  @override
  final DateTime createdAt;
  @override
  final DateTime? lastUsedAt;

  factory _$$AppPassword([void Function($AppPasswordBuilder)? updates]) =>
      ($AppPasswordBuilder()..update(updates))._build();

  _$$AppPassword._({
    required this.id,
    required this.label,
    required this.createdAt,
    this.lastUsedAt,
  }) : super._();
  @override
  $AppPassword rebuild(void Function($AppPasswordBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $AppPasswordBuilder toBuilder() => $AppPasswordBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $AppPassword &&
        id == other.id &&
        label == other.label &&
        createdAt == other.createdAt &&
        lastUsedAt == other.lastUsedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, lastUsedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'$AppPassword')
          ..add('id', id)
          ..add('label', label)
          ..add('createdAt', createdAt)
          ..add('lastUsedAt', lastUsedAt))
        .toString();
  }
}

class $AppPasswordBuilder
    implements Builder<$AppPassword, $AppPasswordBuilder>, AppPasswordBuilder {
  _$$AppPassword? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(covariant String? id) => _$this._id = id;

  String? _label;
  String? get label => _$this._label;
  set label(covariant String? label) => _$this._label = label;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(covariant DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _lastUsedAt;
  DateTime? get lastUsedAt => _$this._lastUsedAt;
  set lastUsedAt(covariant DateTime? lastUsedAt) =>
      _$this._lastUsedAt = lastUsedAt;

  $AppPasswordBuilder() {
    $AppPassword._defaults(this);
  }

  $AppPasswordBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _label = $v.label;
      _createdAt = $v.createdAt;
      _lastUsedAt = $v.lastUsedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant $AppPassword other) {
    _$v = other as _$$AppPassword;
  }

  @override
  void update(void Function($AppPasswordBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $AppPassword build() => _build();

  _$$AppPassword _build() {
    final _$result =
        _$v ??
        _$$AppPassword._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'$AppPassword', 'id'),
          label: BuiltValueNullFieldError.checkNotNull(
            label,
            r'$AppPassword',
            'label',
          ),
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'$AppPassword',
            'createdAt',
          ),
          lastUsedAt: lastUsedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
