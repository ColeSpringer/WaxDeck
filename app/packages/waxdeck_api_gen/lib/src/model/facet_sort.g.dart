// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'facet_sort.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const FacetSort _$count = const FacetSort._('count');
const FacetSort _$label = const FacetSort._('label');

FacetSort _$valueOf(String name) {
  switch (name) {
    case 'count':
      return _$count;
    case 'label':
      return _$label;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<FacetSort> _$values = BuiltSet<FacetSort>(const <FacetSort>[
  _$count,
  _$label,
]);

class _$FacetSortMeta {
  const _$FacetSortMeta();
  FacetSort get count => _$count;
  FacetSort get label => _$label;
  FacetSort valueOf(String name) => _$valueOf(name);
  BuiltSet<FacetSort> get values => _$values;
}

mixin _$FacetSortMixin {
  // ignore: non_constant_identifier_names
  _$FacetSortMeta get FacetSort => const _$FacetSortMeta();
}

Serializer<FacetSort> _$facetSortSerializer = _$FacetSortSerializer();

class _$FacetSortSerializer implements PrimitiveSerializer<FacetSort> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'count': 'count',
    'label': 'label',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'count': 'count',
    'label': 'label',
  };

  @override
  final Iterable<Type> types = const <Type>[FacetSort];
  @override
  final String wireName = 'FacetSort';

  @override
  Object serialize(
    Serializers serializers,
    FacetSort object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  FacetSort deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => FacetSort.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
