// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_password_created.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppPasswordCreated extends AppPasswordCreated {
  @override
  final String secret;
  @override
  final String id;
  @override
  final String label;
  @override
  final DateTime createdAt;
  @override
  final DateTime? lastUsedAt;

  factory _$AppPasswordCreated([
    void Function(AppPasswordCreatedBuilder)? updates,
  ]) => (AppPasswordCreatedBuilder()..update(updates))._build();

  _$AppPasswordCreated._({
    required this.secret,
    required this.id,
    required this.label,
    required this.createdAt,
    this.lastUsedAt,
  }) : super._();
  @override
  AppPasswordCreated rebuild(
    void Function(AppPasswordCreatedBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  AppPasswordCreatedBuilder toBuilder() =>
      AppPasswordCreatedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppPasswordCreated &&
        secret == other.secret &&
        id == other.id &&
        label == other.label &&
        createdAt == other.createdAt &&
        lastUsedAt == other.lastUsedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, secret.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, lastUsedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppPasswordCreated')
          ..add('secret', secret)
          ..add('id', id)
          ..add('label', label)
          ..add('createdAt', createdAt)
          ..add('lastUsedAt', lastUsedAt))
        .toString();
  }
}

class AppPasswordCreatedBuilder
    implements
        Builder<AppPasswordCreated, AppPasswordCreatedBuilder>,
        AppPasswordBuilder {
  _$AppPasswordCreated? _$v;

  String? _secret;
  String? get secret => _$this._secret;
  set secret(covariant String? secret) => _$this._secret = secret;

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

  AppPasswordCreatedBuilder() {
    AppPasswordCreated._defaults(this);
  }

  AppPasswordCreatedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _secret = $v.secret;
      _id = $v.id;
      _label = $v.label;
      _createdAt = $v.createdAt;
      _lastUsedAt = $v.lastUsedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant AppPasswordCreated other) {
    _$v = other as _$AppPasswordCreated;
  }

  @override
  void update(void Function(AppPasswordCreatedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppPasswordCreated build() => _build();

  _$AppPasswordCreated _build() {
    final _$result =
        _$v ??
        _$AppPasswordCreated._(
          secret: BuiltValueNullFieldError.checkNotNull(
            secret,
            r'AppPasswordCreated',
            'secret',
          ),
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'AppPasswordCreated',
            'id',
          ),
          label: BuiltValueNullFieldError.checkNotNull(
            label,
            r'AppPasswordCreated',
            'label',
          ),
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'AppPasswordCreated',
            'createdAt',
          ),
          lastUsedAt: lastUsedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
