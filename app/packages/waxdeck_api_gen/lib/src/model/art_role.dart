//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'art_role.g.dart';

class ArtRole extends EnumClass {

  /// One artwork slot on an item or entity. Only `front` walks the album/artist fallback chain and is filled by scans and enrichment; `back`, `disc`, `booklet`, and `background` are set explicitly and resolve at the entity's own level. Defaults to `front`. 
  @BuiltValueEnumConst(wireName: r'front')
  static const ArtRole front = _$front;
  /// One artwork slot on an item or entity. Only `front` walks the album/artist fallback chain and is filled by scans and enrichment; `back`, `disc`, `booklet`, and `background` are set explicitly and resolve at the entity's own level. Defaults to `front`. 
  @BuiltValueEnumConst(wireName: r'back')
  static const ArtRole back = _$back;
  /// One artwork slot on an item or entity. Only `front` walks the album/artist fallback chain and is filled by scans and enrichment; `back`, `disc`, `booklet`, and `background` are set explicitly and resolve at the entity's own level. Defaults to `front`. 
  @BuiltValueEnumConst(wireName: r'disc')
  static const ArtRole disc = _$disc;
  /// One artwork slot on an item or entity. Only `front` walks the album/artist fallback chain and is filled by scans and enrichment; `back`, `disc`, `booklet`, and `background` are set explicitly and resolve at the entity's own level. Defaults to `front`. 
  @BuiltValueEnumConst(wireName: r'booklet')
  static const ArtRole booklet = _$booklet;
  /// One artwork slot on an item or entity. Only `front` walks the album/artist fallback chain and is filled by scans and enrichment; `back`, `disc`, `booklet`, and `background` are set explicitly and resolve at the entity's own level. Defaults to `front`. 
  @BuiltValueEnumConst(wireName: r'background')
  static const ArtRole background = _$background;

  static Serializer<ArtRole> get serializer => _$artRoleSerializer;

  const ArtRole._(String name): super(name);

  static BuiltSet<ArtRole> get values => _$values;
  static ArtRole valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ArtRoleMixin = Object with _$ArtRoleMixin;

