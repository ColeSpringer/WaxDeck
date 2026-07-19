// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscribe_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SubscribeRequest extends SubscribeRequest {
  @override
  final String url;
  @override
  final String? sourceType;
  @override
  final String? username;
  @override
  final String? password;
  @override
  final String? folder;

  factory _$SubscribeRequest([
    void Function(SubscribeRequestBuilder)? updates,
  ]) => (SubscribeRequestBuilder()..update(updates))._build();

  _$SubscribeRequest._({
    required this.url,
    this.sourceType,
    this.username,
    this.password,
    this.folder,
  }) : super._();
  @override
  SubscribeRequest rebuild(void Function(SubscribeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SubscribeRequestBuilder toBuilder() =>
      SubscribeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SubscribeRequest &&
        url == other.url &&
        sourceType == other.sourceType &&
        username == other.username &&
        password == other.password &&
        folder == other.folder;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, sourceType.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, folder.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SubscribeRequest')
          ..add('url', url)
          ..add('sourceType', sourceType)
          ..add('username', username)
          ..add('password', password)
          ..add('folder', folder))
        .toString();
  }
}

class SubscribeRequestBuilder
    implements Builder<SubscribeRequest, SubscribeRequestBuilder> {
  _$SubscribeRequest? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _sourceType;
  String? get sourceType => _$this._sourceType;
  set sourceType(String? sourceType) => _$this._sourceType = sourceType;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _folder;
  String? get folder => _$this._folder;
  set folder(String? folder) => _$this._folder = folder;

  SubscribeRequestBuilder() {
    SubscribeRequest._defaults(this);
  }

  SubscribeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _sourceType = $v.sourceType;
      _username = $v.username;
      _password = $v.password;
      _folder = $v.folder;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SubscribeRequest other) {
    _$v = other as _$SubscribeRequest;
  }

  @override
  void update(void Function(SubscribeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SubscribeRequest build() => _build();

  _$SubscribeRequest _build() {
    final _$result =
        _$v ??
        _$SubscribeRequest._(
          url: BuiltValueNullFieldError.checkNotNull(
            url,
            r'SubscribeRequest',
            'url',
          ),
          sourceType: sourceType,
          username: username,
          password: password,
          folder: folder,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
