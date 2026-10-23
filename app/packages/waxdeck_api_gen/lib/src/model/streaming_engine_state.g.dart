// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'streaming_engine_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StreamingEngineState extends StreamingEngineState {
  @override
  final bool configured;
  @override
  final bool connected;
  @override
  final bool timelines;
  @override
  final bool voiceBoost;
  @override
  final bool fileTools;

  factory _$StreamingEngineState([
    void Function(StreamingEngineStateBuilder)? updates,
  ]) => (StreamingEngineStateBuilder()..update(updates))._build();

  _$StreamingEngineState._({
    required this.configured,
    required this.connected,
    required this.timelines,
    required this.voiceBoost,
    required this.fileTools,
  }) : super._();
  @override
  StreamingEngineState rebuild(
    void Function(StreamingEngineStateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  StreamingEngineStateBuilder toBuilder() =>
      StreamingEngineStateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StreamingEngineState &&
        configured == other.configured &&
        connected == other.connected &&
        timelines == other.timelines &&
        voiceBoost == other.voiceBoost &&
        fileTools == other.fileTools;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, configured.hashCode);
    _$hash = $jc(_$hash, connected.hashCode);
    _$hash = $jc(_$hash, timelines.hashCode);
    _$hash = $jc(_$hash, voiceBoost.hashCode);
    _$hash = $jc(_$hash, fileTools.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StreamingEngineState')
          ..add('configured', configured)
          ..add('connected', connected)
          ..add('timelines', timelines)
          ..add('voiceBoost', voiceBoost)
          ..add('fileTools', fileTools))
        .toString();
  }
}

class StreamingEngineStateBuilder
    implements Builder<StreamingEngineState, StreamingEngineStateBuilder> {
  _$StreamingEngineState? _$v;

  bool? _configured;
  bool? get configured => _$this._configured;
  set configured(bool? configured) => _$this._configured = configured;

  bool? _connected;
  bool? get connected => _$this._connected;
  set connected(bool? connected) => _$this._connected = connected;

  bool? _timelines;
  bool? get timelines => _$this._timelines;
  set timelines(bool? timelines) => _$this._timelines = timelines;

  bool? _voiceBoost;
  bool? get voiceBoost => _$this._voiceBoost;
  set voiceBoost(bool? voiceBoost) => _$this._voiceBoost = voiceBoost;

  bool? _fileTools;
  bool? get fileTools => _$this._fileTools;
  set fileTools(bool? fileTools) => _$this._fileTools = fileTools;

  StreamingEngineStateBuilder() {
    StreamingEngineState._defaults(this);
  }

  StreamingEngineStateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _configured = $v.configured;
      _connected = $v.connected;
      _timelines = $v.timelines;
      _voiceBoost = $v.voiceBoost;
      _fileTools = $v.fileTools;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StreamingEngineState other) {
    _$v = other as _$StreamingEngineState;
  }

  @override
  void update(void Function(StreamingEngineStateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StreamingEngineState build() => _build();

  _$StreamingEngineState _build() {
    final _$result =
        _$v ??
        _$StreamingEngineState._(
          configured: BuiltValueNullFieldError.checkNotNull(
            configured,
            r'StreamingEngineState',
            'configured',
          ),
          connected: BuiltValueNullFieldError.checkNotNull(
            connected,
            r'StreamingEngineState',
            'connected',
          ),
          timelines: BuiltValueNullFieldError.checkNotNull(
            timelines,
            r'StreamingEngineState',
            'timelines',
          ),
          voiceBoost: BuiltValueNullFieldError.checkNotNull(
            voiceBoost,
            r'StreamingEngineState',
            'voiceBoost',
          ),
          fileTools: BuiltValueNullFieldError.checkNotNull(
            fileTools,
            r'StreamingEngineState',
            'fileTools',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
