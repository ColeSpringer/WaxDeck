// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'soundbite.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Soundbite extends Soundbite {
  @override
  final int startMs;
  @override
  final int durationMs;
  @override
  final String? title;

  factory _$Soundbite([void Function(SoundbiteBuilder)? updates]) =>
      (SoundbiteBuilder()..update(updates))._build();

  _$Soundbite._({required this.startMs, required this.durationMs, this.title})
    : super._();
  @override
  Soundbite rebuild(void Function(SoundbiteBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SoundbiteBuilder toBuilder() => SoundbiteBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Soundbite &&
        startMs == other.startMs &&
        durationMs == other.durationMs &&
        title == other.title;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startMs.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Soundbite')
          ..add('startMs', startMs)
          ..add('durationMs', durationMs)
          ..add('title', title))
        .toString();
  }
}

class SoundbiteBuilder implements Builder<Soundbite, SoundbiteBuilder> {
  _$Soundbite? _$v;

  int? _startMs;
  int? get startMs => _$this._startMs;
  set startMs(int? startMs) => _$this._startMs = startMs;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  SoundbiteBuilder() {
    Soundbite._defaults(this);
  }

  SoundbiteBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startMs = $v.startMs;
      _durationMs = $v.durationMs;
      _title = $v.title;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Soundbite other) {
    _$v = other as _$Soundbite;
  }

  @override
  void update(void Function(SoundbiteBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Soundbite build() => _build();

  _$Soundbite _build() {
    final _$result =
        _$v ??
        _$Soundbite._(
          startMs: BuiltValueNullFieldError.checkNotNull(
            startMs,
            r'Soundbite',
            'startMs',
          ),
          durationMs: BuiltValueNullFieldError.checkNotNull(
            durationMs,
            r'Soundbite',
            'durationMs',
          ),
          title: title,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
