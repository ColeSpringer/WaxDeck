//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mix_basis.g.dart';

class MixBasis extends EnumClass {

  /// Which engine answered a discovery request: `sonic` used stored audio embeddings, `metadata` used genre and artist heuristics (the zero-setup fallback). 
  @BuiltValueEnumConst(wireName: r'sonic')
  static const MixBasis sonic = _$sonic;
  /// Which engine answered a discovery request: `sonic` used stored audio embeddings, `metadata` used genre and artist heuristics (the zero-setup fallback). 
  @BuiltValueEnumConst(wireName: r'metadata')
  static const MixBasis metadata = _$metadata;
  /// Which engine answered a discovery request: `sonic` used stored audio embeddings, `metadata` used genre and artist heuristics (the zero-setup fallback). 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const MixBasis unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<MixBasis> get serializer => _$mixBasisSerializer;

  const MixBasis._(String name): super(name);

  static BuiltSet<MixBasis> get values => _$values;
  static MixBasis valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class MixBasisMixin = Object with _$MixBasisMixin;

