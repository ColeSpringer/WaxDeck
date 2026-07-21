// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Credit extends Credit {
  @override
  final String role;
  @override
  final BuiltList<String> names;

  factory _$Credit([void Function(CreditBuilder)? updates]) =>
      (CreditBuilder()..update(updates))._build();

  _$Credit._({required this.role, required this.names}) : super._();
  @override
  Credit rebuild(void Function(CreditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreditBuilder toBuilder() => CreditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Credit && role == other.role && names == other.names;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, names.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Credit')
          ..add('role', role)
          ..add('names', names))
        .toString();
  }
}

class CreditBuilder implements Builder<Credit, CreditBuilder> {
  _$Credit? _$v;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

  ListBuilder<String>? _names;
  ListBuilder<String> get names => _$this._names ??= ListBuilder<String>();
  set names(ListBuilder<String>? names) => _$this._names = names;

  CreditBuilder() {
    Credit._defaults(this);
  }

  CreditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _role = $v.role;
      _names = $v.names.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Credit other) {
    _$v = other as _$Credit;
  }

  @override
  void update(void Function(CreditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Credit build() => _build();

  _$Credit _build() {
    _$Credit _$result;
    try {
      _$result =
          _$v ??
          _$Credit._(
            role: BuiltValueNullFieldError.checkNotNull(
              role,
              r'Credit',
              'role',
            ),
            names: names.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'names';
        names.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Credit',
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
