// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feed_person.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FeedPerson extends FeedPerson {
  @override
  final String name;
  @override
  final String? role;
  @override
  final String? group;
  @override
  final String? img;
  @override
  final String? href;

  factory _$FeedPerson([void Function(FeedPersonBuilder)? updates]) =>
      (FeedPersonBuilder()..update(updates))._build();

  _$FeedPerson._({
    required this.name,
    this.role,
    this.group,
    this.img,
    this.href,
  }) : super._();
  @override
  FeedPerson rebuild(void Function(FeedPersonBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FeedPersonBuilder toBuilder() => FeedPersonBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FeedPerson &&
        name == other.name &&
        role == other.role &&
        group == other.group &&
        img == other.img &&
        href == other.href;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, group.hashCode);
    _$hash = $jc(_$hash, img.hashCode);
    _$hash = $jc(_$hash, href.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FeedPerson')
          ..add('name', name)
          ..add('role', role)
          ..add('group', group)
          ..add('img', img)
          ..add('href', href))
        .toString();
  }
}

class FeedPersonBuilder implements Builder<FeedPerson, FeedPersonBuilder> {
  _$FeedPerson? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

  String? _group;
  String? get group => _$this._group;
  set group(String? group) => _$this._group = group;

  String? _img;
  String? get img => _$this._img;
  set img(String? img) => _$this._img = img;

  String? _href;
  String? get href => _$this._href;
  set href(String? href) => _$this._href = href;

  FeedPersonBuilder() {
    FeedPerson._defaults(this);
  }

  FeedPersonBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _role = $v.role;
      _group = $v.group;
      _img = $v.img;
      _href = $v.href;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FeedPerson other) {
    _$v = other as _$FeedPerson;
  }

  @override
  void update(void Function(FeedPersonBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FeedPerson build() => _build();

  _$FeedPerson _build() {
    final _$result =
        _$v ??
        _$FeedPerson._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'FeedPerson',
            'name',
          ),
          role: role,
          group: group,
          img: img,
          href: href,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
