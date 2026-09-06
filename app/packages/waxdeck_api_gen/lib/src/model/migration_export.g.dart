// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_export.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MigrationExportSource_Enum _$migrationExportSourceEnum_spotify =
    const MigrationExportSource_Enum._('spotify');
const MigrationExportSource_Enum _$migrationExportSourceEnum_unknown =
    const MigrationExportSource_Enum._('unknown');
const MigrationExportSource_Enum
_$migrationExportSourceEnum_unknownDefaultOpenApi =
    const MigrationExportSource_Enum._('unknownDefaultOpenApi');

MigrationExportSource_Enum _$migrationExportSourceEnumValueOf(String name) {
  switch (name) {
    case 'spotify':
      return _$migrationExportSourceEnum_spotify;
    case 'unknown':
      return _$migrationExportSourceEnum_unknown;
    case 'unknownDefaultOpenApi':
      return _$migrationExportSourceEnum_unknownDefaultOpenApi;
    default:
      return _$migrationExportSourceEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<MigrationExportSource_Enum> _$migrationExportSourceEnumValues =
    BuiltSet<MigrationExportSource_Enum>(const <MigrationExportSource_Enum>[
      _$migrationExportSourceEnum_spotify,
      _$migrationExportSourceEnum_unknown,
      _$migrationExportSourceEnum_unknownDefaultOpenApi,
    ]);

Serializer<MigrationExportSource_Enum> _$migrationExportSourceEnumSerializer =
    _$MigrationExportSource_EnumSerializer();

class _$MigrationExportSource_EnumSerializer
    implements PrimitiveSerializer<MigrationExportSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'spotify': 'spotify',
    'unknown': 'unknown',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'spotify': 'spotify',
    'unknown': 'unknown',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[MigrationExportSource_Enum];
  @override
  final String wireName = 'MigrationExportSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    MigrationExportSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MigrationExportSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MigrationExportSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MigrationExport extends MigrationExport {
  @override
  final String pid;
  @override
  final MigrationExportSource_Enum source_;
  @override
  final BuiltList<String> files;
  @override
  final int sizeBytes;
  @override
  final DateTime expiresAt;

  factory _$MigrationExport([void Function(MigrationExportBuilder)? updates]) =>
      (MigrationExportBuilder()..update(updates))._build();

  _$MigrationExport._({
    required this.pid,
    required this.source_,
    required this.files,
    required this.sizeBytes,
    required this.expiresAt,
  }) : super._();
  @override
  MigrationExport rebuild(void Function(MigrationExportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationExportBuilder toBuilder() => MigrationExportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationExport &&
        pid == other.pid &&
        source_ == other.source_ &&
        files == other.files &&
        sizeBytes == other.sizeBytes &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, files.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationExport')
          ..add('pid', pid)
          ..add('source_', source_)
          ..add('files', files)
          ..add('sizeBytes', sizeBytes)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class MigrationExportBuilder
    implements Builder<MigrationExport, MigrationExportBuilder> {
  _$MigrationExport? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  MigrationExportSource_Enum? _source_;
  MigrationExportSource_Enum? get source_ => _$this._source_;
  set source_(MigrationExportSource_Enum? source_) => _$this._source_ = source_;

  ListBuilder<String>? _files;
  ListBuilder<String> get files => _$this._files ??= ListBuilder<String>();
  set files(ListBuilder<String>? files) => _$this._files = files;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  MigrationExportBuilder() {
    MigrationExport._defaults(this);
  }

  MigrationExportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _source_ = $v.source_;
      _files = $v.files.toBuilder();
      _sizeBytes = $v.sizeBytes;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationExport other) {
    _$v = other as _$MigrationExport;
  }

  @override
  void update(void Function(MigrationExportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationExport build() => _build();

  _$MigrationExport _build() {
    _$MigrationExport _$result;
    try {
      _$result =
          _$v ??
          _$MigrationExport._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'MigrationExport',
              'pid',
            ),
            source_: BuiltValueNullFieldError.checkNotNull(
              source_,
              r'MigrationExport',
              'source_',
            ),
            files: files.build(),
            sizeBytes: BuiltValueNullFieldError.checkNotNull(
              sizeBytes,
              r'MigrationExport',
              'sizeBytes',
            ),
            expiresAt: BuiltValueNullFieldError.checkNotNull(
              expiresAt,
              r'MigrationExport',
              'expiresAt',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'files';
        files.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MigrationExport',
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
