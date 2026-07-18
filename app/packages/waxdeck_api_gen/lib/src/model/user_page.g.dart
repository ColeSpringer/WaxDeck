// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UserPage extends UserPage {
  @override
  final BuiltList<UserAccount> users;
  @override
  final String? nextCursor;

  factory _$UserPage([void Function(UserPageBuilder)? updates]) =>
      (UserPageBuilder()..update(updates))._build();

  _$UserPage._({required this.users, this.nextCursor}) : super._();
  @override
  UserPage rebuild(void Function(UserPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserPageBuilder toBuilder() => UserPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserPage &&
        users == other.users &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, users.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UserPage')
          ..add('users', users)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class UserPageBuilder implements Builder<UserPage, UserPageBuilder> {
  _$UserPage? _$v;

  ListBuilder<UserAccount>? _users;
  ListBuilder<UserAccount> get users =>
      _$this._users ??= ListBuilder<UserAccount>();
  set users(ListBuilder<UserAccount>? users) => _$this._users = users;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  UserPageBuilder() {
    UserPage._defaults(this);
  }

  UserPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _users = $v.users.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserPage other) {
    _$v = other as _$UserPage;
  }

  @override
  void update(void Function(UserPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UserPage build() => _build();

  _$UserPage _build() {
    _$UserPage _$result;
    try {
      _$result =
          _$v ?? _$UserPage._(users: users.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'users';
        users.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UserPage',
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
