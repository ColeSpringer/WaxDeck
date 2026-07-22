// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'portable_playlist.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PortablePlaylist extends PortablePlaylist {
  @override
  final String name;
  @override
  final BuiltList<PortableRef> refs;

  factory _$PortablePlaylist([
    void Function(PortablePlaylistBuilder)? updates,
  ]) => (PortablePlaylistBuilder()..update(updates))._build();

  _$PortablePlaylist._({required this.name, required this.refs}) : super._();
  @override
  PortablePlaylist rebuild(void Function(PortablePlaylistBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PortablePlaylistBuilder toBuilder() =>
      PortablePlaylistBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PortablePlaylist &&
        name == other.name &&
        refs == other.refs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, refs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PortablePlaylist')
          ..add('name', name)
          ..add('refs', refs))
        .toString();
  }
}

class PortablePlaylistBuilder
    implements Builder<PortablePlaylist, PortablePlaylistBuilder> {
  _$PortablePlaylist? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  ListBuilder<PortableRef>? _refs;
  ListBuilder<PortableRef> get refs =>
      _$this._refs ??= ListBuilder<PortableRef>();
  set refs(ListBuilder<PortableRef>? refs) => _$this._refs = refs;

  PortablePlaylistBuilder() {
    PortablePlaylist._defaults(this);
  }

  PortablePlaylistBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _refs = $v.refs.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PortablePlaylist other) {
    _$v = other as _$PortablePlaylist;
  }

  @override
  void update(void Function(PortablePlaylistBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PortablePlaylist build() => _build();

  _$PortablePlaylist _build() {
    _$PortablePlaylist _$result;
    try {
      _$result =
          _$v ??
          _$PortablePlaylist._(
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'PortablePlaylist',
              'name',
            ),
            refs: refs.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'refs';
        refs.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PortablePlaylist',
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
