// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_password_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppPasswordList extends AppPasswordList {
  @override
  final BuiltList<AppPassword> appPasswords;

  factory _$AppPasswordList([void Function(AppPasswordListBuilder)? updates]) =>
      (AppPasswordListBuilder()..update(updates))._build();

  _$AppPasswordList._({required this.appPasswords}) : super._();
  @override
  AppPasswordList rebuild(void Function(AppPasswordListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppPasswordListBuilder toBuilder() => AppPasswordListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppPasswordList && appPasswords == other.appPasswords;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appPasswords.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'AppPasswordList',
    )..add('appPasswords', appPasswords)).toString();
  }
}

class AppPasswordListBuilder
    implements Builder<AppPasswordList, AppPasswordListBuilder> {
  _$AppPasswordList? _$v;

  ListBuilder<AppPassword>? _appPasswords;
  ListBuilder<AppPassword> get appPasswords =>
      _$this._appPasswords ??= ListBuilder<AppPassword>();
  set appPasswords(ListBuilder<AppPassword>? appPasswords) =>
      _$this._appPasswords = appPasswords;

  AppPasswordListBuilder() {
    AppPasswordList._defaults(this);
  }

  AppPasswordListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appPasswords = $v.appPasswords.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppPasswordList other) {
    _$v = other as _$AppPasswordList;
  }

  @override
  void update(void Function(AppPasswordListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppPasswordList build() => _build();

  _$AppPasswordList _build() {
    _$AppPasswordList _$result;
    try {
      _$result = _$v ?? _$AppPasswordList._(appPasswords: appPasswords.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'appPasswords';
        appPasswords.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'AppPasswordList',
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
