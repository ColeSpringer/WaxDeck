// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_edit_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TagEditResult extends TagEditResult {
  @override
  final String key;
  @override
  final int stored;

  factory _$TagEditResult([void Function(TagEditResultBuilder)? updates]) =>
      (TagEditResultBuilder()..update(updates))._build();

  _$TagEditResult._({required this.key, required this.stored}) : super._();
  @override
  TagEditResult rebuild(void Function(TagEditResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TagEditResultBuilder toBuilder() => TagEditResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TagEditResult && key == other.key && stored == other.stored;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, stored.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TagEditResult')
          ..add('key', key)
          ..add('stored', stored))
        .toString();
  }
}

class TagEditResultBuilder
    implements Builder<TagEditResult, TagEditResultBuilder> {
  _$TagEditResult? _$v;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  int? _stored;
  int? get stored => _$this._stored;
  set stored(int? stored) => _$this._stored = stored;

  TagEditResultBuilder() {
    TagEditResult._defaults(this);
  }

  TagEditResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _key = $v.key;
      _stored = $v.stored;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TagEditResult other) {
    _$v = other as _$TagEditResult;
  }

  @override
  void update(void Function(TagEditResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TagEditResult build() => _build();

  _$TagEditResult _build() {
    final _$result =
        _$v ??
        _$TagEditResult._(
          key: BuiltValueNullFieldError.checkNotNull(
            key,
            r'TagEditResult',
            'key',
          ),
          stored: BuiltValueNullFieldError.checkNotNull(
            stored,
            r'TagEditResult',
            'stored',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
