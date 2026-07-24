//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/file_diagnostic.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'file_diagnostic_page.g.dart';

/// One page of per-file diagnostics.
///
/// Properties:
/// * [diagnostics] 
/// * [nextCursor] - Cursor for the next page; omitted on the last.
@BuiltValue()
abstract class FileDiagnosticPage implements Built<FileDiagnosticPage, FileDiagnosticPageBuilder> {
  @BuiltValueField(wireName: r'diagnostics')
  BuiltList<FileDiagnostic> get diagnostics;

  /// Cursor for the next page; omitted on the last.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  FileDiagnosticPage._();

  factory FileDiagnosticPage([void updates(FileDiagnosticPageBuilder b)]) = _$FileDiagnosticPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FileDiagnosticPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FileDiagnosticPage> get serializer => _$FileDiagnosticPageSerializer();
}

class _$FileDiagnosticPageSerializer implements PrimitiveSerializer<FileDiagnosticPage> {
  @override
  final Iterable<Type> types = const [FileDiagnosticPage, _$FileDiagnosticPage];

  @override
  final String wireName = r'FileDiagnosticPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FileDiagnosticPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'diagnostics';
    yield serializers.serialize(
      object.diagnostics,
      specifiedType: const FullType(BuiltList, [FullType(FileDiagnostic)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FileDiagnosticPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FileDiagnosticPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'diagnostics':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(FileDiagnostic)]),
          ) as BuiltList<FileDiagnostic>;
          result.diagnostics.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FileDiagnosticPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FileDiagnosticPageBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

