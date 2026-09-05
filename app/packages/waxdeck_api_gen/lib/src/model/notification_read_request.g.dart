// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_read_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationReadRequest extends NotificationReadRequest {
  @override
  final BuiltList<String>? ids;

  factory _$NotificationReadRequest([
    void Function(NotificationReadRequestBuilder)? updates,
  ]) => (NotificationReadRequestBuilder()..update(updates))._build();

  _$NotificationReadRequest._({this.ids}) : super._();
  @override
  NotificationReadRequest rebuild(
    void Function(NotificationReadRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationReadRequestBuilder toBuilder() =>
      NotificationReadRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationReadRequest && ids == other.ids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, ids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'NotificationReadRequest',
    )..add('ids', ids)).toString();
  }
}

class NotificationReadRequestBuilder
    implements
        Builder<NotificationReadRequest, NotificationReadRequestBuilder> {
  _$NotificationReadRequest? _$v;

  ListBuilder<String>? _ids;
  ListBuilder<String> get ids => _$this._ids ??= ListBuilder<String>();
  set ids(ListBuilder<String>? ids) => _$this._ids = ids;

  NotificationReadRequestBuilder() {
    NotificationReadRequest._defaults(this);
  }

  NotificationReadRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _ids = $v.ids?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationReadRequest other) {
    _$v = other as _$NotificationReadRequest;
  }

  @override
  void update(void Function(NotificationReadRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationReadRequest build() => _build();

  _$NotificationReadRequest _build() {
    _$NotificationReadRequest _$result;
    try {
      _$result = _$v ?? _$NotificationReadRequest._(ids: _ids?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'ids';
        _ids?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationReadRequest',
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
