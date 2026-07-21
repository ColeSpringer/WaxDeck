// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_session_transfer.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaybackSessionTransfer extends PlaybackSessionTransfer {
  @override
  final String endpointId;

  factory _$PlaybackSessionTransfer([
    void Function(PlaybackSessionTransferBuilder)? updates,
  ]) => (PlaybackSessionTransferBuilder()..update(updates))._build();

  _$PlaybackSessionTransfer._({required this.endpointId}) : super._();
  @override
  PlaybackSessionTransfer rebuild(
    void Function(PlaybackSessionTransferBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaybackSessionTransferBuilder toBuilder() =>
      PlaybackSessionTransferBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaybackSessionTransfer && endpointId == other.endpointId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endpointId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PlaybackSessionTransfer',
    )..add('endpointId', endpointId)).toString();
  }
}

class PlaybackSessionTransferBuilder
    implements
        Builder<PlaybackSessionTransfer, PlaybackSessionTransferBuilder> {
  _$PlaybackSessionTransfer? _$v;

  String? _endpointId;
  String? get endpointId => _$this._endpointId;
  set endpointId(String? endpointId) => _$this._endpointId = endpointId;

  PlaybackSessionTransferBuilder() {
    PlaybackSessionTransfer._defaults(this);
  }

  PlaybackSessionTransferBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endpointId = $v.endpointId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaybackSessionTransfer other) {
    _$v = other as _$PlaybackSessionTransfer;
  }

  @override
  void update(void Function(PlaybackSessionTransferBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaybackSessionTransfer build() => _build();

  _$PlaybackSessionTransfer _build() {
    final _$result =
        _$v ??
        _$PlaybackSessionTransfer._(
          endpointId: BuiltValueNullFieldError.checkNotNull(
            endpointId,
            r'PlaybackSessionTransfer',
            'endpointId',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
