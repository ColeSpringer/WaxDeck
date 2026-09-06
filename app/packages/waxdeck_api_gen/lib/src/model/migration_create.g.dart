// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationCreate extends MigrationCreate {
  @override
  final String source_;
  @override
  final String? serverUrl;
  @override
  final String? accountId;
  @override
  final String? username;
  @override
  final String? password;
  @override
  final String? token;
  @override
  final String? exportId;
  @override
  final MigrationOptions? options;
  @override
  final bool? dryRun;

  factory _$MigrationCreate([void Function(MigrationCreateBuilder)? updates]) =>
      (MigrationCreateBuilder()..update(updates))._build();

  _$MigrationCreate._({
    required this.source_,
    this.serverUrl,
    this.accountId,
    this.username,
    this.password,
    this.token,
    this.exportId,
    this.options,
    this.dryRun,
  }) : super._();
  @override
  MigrationCreate rebuild(void Function(MigrationCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationCreateBuilder toBuilder() => MigrationCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationCreate &&
        source_ == other.source_ &&
        serverUrl == other.serverUrl &&
        accountId == other.accountId &&
        username == other.username &&
        password == other.password &&
        token == other.token &&
        exportId == other.exportId &&
        options == other.options &&
        dryRun == other.dryRun;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, serverUrl.hashCode);
    _$hash = $jc(_$hash, accountId.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jc(_$hash, exportId.hashCode);
    _$hash = $jc(_$hash, options.hashCode);
    _$hash = $jc(_$hash, dryRun.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationCreate')
          ..add('source_', source_)
          ..add('serverUrl', serverUrl)
          ..add('accountId', accountId)
          ..add('username', username)
          ..add('password', password)
          ..add('token', token)
          ..add('exportId', exportId)
          ..add('options', options)
          ..add('dryRun', dryRun))
        .toString();
  }
}

class MigrationCreateBuilder
    implements Builder<MigrationCreate, MigrationCreateBuilder> {
  _$MigrationCreate? _$v;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _serverUrl;
  String? get serverUrl => _$this._serverUrl;
  set serverUrl(String? serverUrl) => _$this._serverUrl = serverUrl;

  String? _accountId;
  String? get accountId => _$this._accountId;
  set accountId(String? accountId) => _$this._accountId = accountId;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _token;
  String? get token => _$this._token;
  set token(String? token) => _$this._token = token;

  String? _exportId;
  String? get exportId => _$this._exportId;
  set exportId(String? exportId) => _$this._exportId = exportId;

  MigrationOptionsBuilder? _options;
  MigrationOptionsBuilder get options =>
      _$this._options ??= MigrationOptionsBuilder();
  set options(MigrationOptionsBuilder? options) => _$this._options = options;

  bool? _dryRun;
  bool? get dryRun => _$this._dryRun;
  set dryRun(bool? dryRun) => _$this._dryRun = dryRun;

  MigrationCreateBuilder() {
    MigrationCreate._defaults(this);
  }

  MigrationCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _source_ = $v.source_;
      _serverUrl = $v.serverUrl;
      _accountId = $v.accountId;
      _username = $v.username;
      _password = $v.password;
      _token = $v.token;
      _exportId = $v.exportId;
      _options = $v.options?.toBuilder();
      _dryRun = $v.dryRun;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationCreate other) {
    _$v = other as _$MigrationCreate;
  }

  @override
  void update(void Function(MigrationCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationCreate build() => _build();

  _$MigrationCreate _build() {
    _$MigrationCreate _$result;
    try {
      _$result =
          _$v ??
          _$MigrationCreate._(
            source_: BuiltValueNullFieldError.checkNotNull(
              source_,
              r'MigrationCreate',
              'source_',
            ),
            serverUrl: serverUrl,
            accountId: accountId,
            username: username,
            password: password,
            token: token,
            exportId: exportId,
            options: _options?.build(),
            dryRun: dryRun,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'options';
        _options?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MigrationCreate',
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
