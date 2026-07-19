// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_registration_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PushRegistrationList extends PushRegistrationList {
  @override
  final BuiltList<PushRegistration> registrations;

  factory _$PushRegistrationList([
    void Function(PushRegistrationListBuilder)? updates,
  ]) => (PushRegistrationListBuilder()..update(updates))._build();

  _$PushRegistrationList._({required this.registrations}) : super._();
  @override
  PushRegistrationList rebuild(
    void Function(PushRegistrationListBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PushRegistrationListBuilder toBuilder() =>
      PushRegistrationListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushRegistrationList &&
        registrations == other.registrations;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, registrations.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PushRegistrationList',
    )..add('registrations', registrations)).toString();
  }
}

class PushRegistrationListBuilder
    implements Builder<PushRegistrationList, PushRegistrationListBuilder> {
  _$PushRegistrationList? _$v;

  ListBuilder<PushRegistration>? _registrations;
  ListBuilder<PushRegistration> get registrations =>
      _$this._registrations ??= ListBuilder<PushRegistration>();
  set registrations(ListBuilder<PushRegistration>? registrations) =>
      _$this._registrations = registrations;

  PushRegistrationListBuilder() {
    PushRegistrationList._defaults(this);
  }

  PushRegistrationListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _registrations = $v.registrations.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushRegistrationList other) {
    _$v = other as _$PushRegistrationList;
  }

  @override
  void update(void Function(PushRegistrationListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushRegistrationList build() => _build();

  _$PushRegistrationList _build() {
    _$PushRegistrationList _$result;
    try {
      _$result =
          _$v ?? _$PushRegistrationList._(registrations: registrations.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'registrations';
        registrations.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PushRegistrationList',
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
