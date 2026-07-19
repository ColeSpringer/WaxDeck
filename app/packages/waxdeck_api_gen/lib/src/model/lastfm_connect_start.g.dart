// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lastfm_connect_start.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LastfmConnectStart extends LastfmConnectStart {
  @override
  final String authUrl;

  factory _$LastfmConnectStart([
    void Function(LastfmConnectStartBuilder)? updates,
  ]) => (LastfmConnectStartBuilder()..update(updates))._build();

  _$LastfmConnectStart._({required this.authUrl}) : super._();
  @override
  LastfmConnectStart rebuild(
    void Function(LastfmConnectStartBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  LastfmConnectStartBuilder toBuilder() =>
      LastfmConnectStartBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LastfmConnectStart && authUrl == other.authUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, authUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'LastfmConnectStart',
    )..add('authUrl', authUrl)).toString();
  }
}

class LastfmConnectStartBuilder
    implements Builder<LastfmConnectStart, LastfmConnectStartBuilder> {
  _$LastfmConnectStart? _$v;

  String? _authUrl;
  String? get authUrl => _$this._authUrl;
  set authUrl(String? authUrl) => _$this._authUrl = authUrl;

  LastfmConnectStartBuilder() {
    LastfmConnectStart._defaults(this);
  }

  LastfmConnectStartBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _authUrl = $v.authUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LastfmConnectStart other) {
    _$v = other as _$LastfmConnectStart;
  }

  @override
  void update(void Function(LastfmConnectStartBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LastfmConnectStart build() => _build();

  _$LastfmConnectStart _build() {
    final _$result =
        _$v ??
        _$LastfmConnectStart._(
          authUrl: BuiltValueNullFieldError.checkNotNull(
            authUrl,
            r'LastfmConnectStart',
            'authUrl',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
