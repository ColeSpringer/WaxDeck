//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_export.g.dart';

/// One uploaded account data export, staged for an import to read. 
///
/// Properties:
/// * [pid] - Goes on `createMigration` as `exportId`.
/// * [source_] - Which service's export this was recognised as. `unknown` is reserved for a server that stages an archive without naming it; this one refuses what it cannot read, so nothing it stages carries that value. 
/// * [files] - The files inside the archive this import will read.
/// * [sizeBytes] - The uploaded archive's size on disk.
/// * [expiresAt] - When the staged file is swept. An import that has not started by then has to upload the export again. 
@BuiltValue()
abstract class MigrationExport implements Built<MigrationExport, MigrationExportBuilder> {
  /// Goes on `createMigration` as `exportId`.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Which service's export this was recognised as. `unknown` is reserved for a server that stages an archive without naming it; this one refuses what it cannot read, so nothing it stages carries that value. 
  @BuiltValueField(wireName: r'source')
  MigrationExportSource_Enum get source_;
  // enum source_Enum {  spotify,  unknown,  };

  /// The files inside the archive this import will read.
  @BuiltValueField(wireName: r'files')
  BuiltList<String> get files;

  /// The uploaded archive's size on disk.
  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  /// When the staged file is swept. An import that has not started by then has to upload the export again. 
  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  MigrationExport._();

  factory MigrationExport([void updates(MigrationExportBuilder b)]) = _$MigrationExport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationExportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationExport> get serializer => _$MigrationExportSerializer();
}

class _$MigrationExportSerializer implements PrimitiveSerializer<MigrationExport> {
  @override
  final Iterable<Type> types = const [MigrationExport, _$MigrationExport];

  @override
  final String wireName = r'MigrationExport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationExport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(MigrationExportSource_Enum),
    );
    yield r'files';
    yield serializers.serialize(
      object.files,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'sizeBytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    yield r'expiresAt';
    yield serializers.serialize(
      object.expiresAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationExport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationExportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationExportSource_Enum),
          ) as MigrationExportSource_Enum;
          result.source_ = valueDes;
          break;
        case r'files':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.files.replace(valueDes);
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationExport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationExportBuilder();
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

class MigrationExportSource_Enum extends EnumClass {

  /// Which service's export this was recognised as. `unknown` is reserved for a server that stages an archive without naming it; this one refuses what it cannot read, so nothing it stages carries that value. 
  @BuiltValueEnumConst(wireName: r'spotify')
  static const MigrationExportSource_Enum spotify = _$migrationExportSourceEnum_spotify;
  /// Which service's export this was recognised as. `unknown` is reserved for a server that stages an archive without naming it; this one refuses what it cannot read, so nothing it stages carries that value. 
  @BuiltValueEnumConst(wireName: r'unknown')
  static const MigrationExportSource_Enum unknown = _$migrationExportSourceEnum_unknown;
  /// Which service's export this was recognised as. `unknown` is reserved for a server that stages an archive without naming it; this one refuses what it cannot read, so nothing it stages carries that value. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const MigrationExportSource_Enum unknownDefaultOpenApi = _$migrationExportSourceEnum_unknownDefaultOpenApi;

  static Serializer<MigrationExportSource_Enum> get serializer => _$migrationExportSourceEnumSerializer;

  const MigrationExportSource_Enum._(String name): super(name);

  static BuiltSet<MigrationExportSource_Enum> get values => _$migrationExportSourceEnumValues;
  static MigrationExportSource_Enum valueOf(String name) => _$migrationExportSourceEnumValueOf(name);
}

