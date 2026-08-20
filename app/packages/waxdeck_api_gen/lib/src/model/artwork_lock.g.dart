// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'artwork_lock.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ArtworkLock extends ArtworkLock {
  @override
  final bool locked;

  factory _$ArtworkLock([void Function(ArtworkLockBuilder)? updates]) =>
      (ArtworkLockBuilder()..update(updates))._build();

  _$ArtworkLock._({required this.locked}) : super._();
  @override
  ArtworkLock rebuild(void Function(ArtworkLockBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ArtworkLockBuilder toBuilder() => ArtworkLockBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ArtworkLock && locked == other.locked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, locked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ArtworkLock',
    )..add('locked', locked)).toString();
  }
}

class ArtworkLockBuilder implements Builder<ArtworkLock, ArtworkLockBuilder> {
  _$ArtworkLock? _$v;

  bool? _locked;
  bool? get locked => _$this._locked;
  set locked(bool? locked) => _$this._locked = locked;

  ArtworkLockBuilder() {
    ArtworkLock._defaults(this);
  }

  ArtworkLockBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _locked = $v.locked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ArtworkLock other) {
    _$v = other as _$ArtworkLock;
  }

  @override
  void update(void Function(ArtworkLockBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ArtworkLock build() => _build();

  _$ArtworkLock _build() {
    final _$result =
        _$v ??
        _$ArtworkLock._(
          locked: BuiltValueNullFieldError.checkNotNull(
            locked,
            r'ArtworkLock',
            'locked',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
