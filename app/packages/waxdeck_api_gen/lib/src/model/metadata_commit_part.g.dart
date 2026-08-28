// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_commit_part.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MetadataCommitPartPart_Enum _$metadataCommitPartPartEnum_fields =
    const MetadataCommitPartPart_Enum._('fields');
const MetadataCommitPartPart_Enum _$metadataCommitPartPartEnum_credit =
    const MetadataCommitPartPart_Enum._('credit');
const MetadataCommitPartPart_Enum _$metadataCommitPartPartEnum_lyrics =
    const MetadataCommitPartPart_Enum._('lyrics');
const MetadataCommitPartPart_Enum _$metadataCommitPartPartEnum_chapters =
    const MetadataCommitPartPart_Enum._('chapters');
const MetadataCommitPartPart_Enum _$metadataCommitPartPartEnum_tagSet =
    const MetadataCommitPartPart_Enum._('tagSet');
const MetadataCommitPartPart_Enum _$metadataCommitPartPartEnum_tagRemove =
    const MetadataCommitPartPart_Enum._('tagRemove');
const MetadataCommitPartPart_Enum _$metadataCommitPartPartEnum_releaseStatus =
    const MetadataCommitPartPart_Enum._('releaseStatus');
const MetadataCommitPartPart_Enum
_$metadataCommitPartPartEnum_unknownDefaultOpenApi =
    const MetadataCommitPartPart_Enum._('unknownDefaultOpenApi');

MetadataCommitPartPart_Enum _$metadataCommitPartPartEnumValueOf(String name) {
  switch (name) {
    case 'fields':
      return _$metadataCommitPartPartEnum_fields;
    case 'credit':
      return _$metadataCommitPartPartEnum_credit;
    case 'lyrics':
      return _$metadataCommitPartPartEnum_lyrics;
    case 'chapters':
      return _$metadataCommitPartPartEnum_chapters;
    case 'tagSet':
      return _$metadataCommitPartPartEnum_tagSet;
    case 'tagRemove':
      return _$metadataCommitPartPartEnum_tagRemove;
    case 'releaseStatus':
      return _$metadataCommitPartPartEnum_releaseStatus;
    case 'unknownDefaultOpenApi':
      return _$metadataCommitPartPartEnum_unknownDefaultOpenApi;
    default:
      return _$metadataCommitPartPartEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<MetadataCommitPartPart_Enum> _$metadataCommitPartPartEnumValues =
    BuiltSet<MetadataCommitPartPart_Enum>(const <MetadataCommitPartPart_Enum>[
      _$metadataCommitPartPartEnum_fields,
      _$metadataCommitPartPartEnum_credit,
      _$metadataCommitPartPartEnum_lyrics,
      _$metadataCommitPartPartEnum_chapters,
      _$metadataCommitPartPartEnum_tagSet,
      _$metadataCommitPartPartEnum_tagRemove,
      _$metadataCommitPartPartEnum_releaseStatus,
      _$metadataCommitPartPartEnum_unknownDefaultOpenApi,
    ]);

const MetadataCommitPartStatusEnum _$metadataCommitPartStatusEnum_committed =
    const MetadataCommitPartStatusEnum._('committed');
const MetadataCommitPartStatusEnum _$metadataCommitPartStatusEnum_refused =
    const MetadataCommitPartStatusEnum._('refused');
const MetadataCommitPartStatusEnum _$metadataCommitPartStatusEnum_skipped =
    const MetadataCommitPartStatusEnum._('skipped');
const MetadataCommitPartStatusEnum
_$metadataCommitPartStatusEnum_unknownDefaultOpenApi =
    const MetadataCommitPartStatusEnum._('unknownDefaultOpenApi');

MetadataCommitPartStatusEnum _$metadataCommitPartStatusEnumValueOf(
  String name,
) {
  switch (name) {
    case 'committed':
      return _$metadataCommitPartStatusEnum_committed;
    case 'refused':
      return _$metadataCommitPartStatusEnum_refused;
    case 'skipped':
      return _$metadataCommitPartStatusEnum_skipped;
    case 'unknownDefaultOpenApi':
      return _$metadataCommitPartStatusEnum_unknownDefaultOpenApi;
    default:
      return _$metadataCommitPartStatusEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<MetadataCommitPartStatusEnum>
_$metadataCommitPartStatusEnumValues =
    BuiltSet<MetadataCommitPartStatusEnum>(const <MetadataCommitPartStatusEnum>[
      _$metadataCommitPartStatusEnum_committed,
      _$metadataCommitPartStatusEnum_refused,
      _$metadataCommitPartStatusEnum_skipped,
      _$metadataCommitPartStatusEnum_unknownDefaultOpenApi,
    ]);

Serializer<MetadataCommitPartPart_Enum> _$metadataCommitPartPartEnumSerializer =
    _$MetadataCommitPartPart_EnumSerializer();
Serializer<MetadataCommitPartStatusEnum>
_$metadataCommitPartStatusEnumSerializer =
    _$MetadataCommitPartStatusEnumSerializer();

class _$MetadataCommitPartPart_EnumSerializer
    implements PrimitiveSerializer<MetadataCommitPartPart_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'fields': 'fields',
    'credit': 'credit',
    'lyrics': 'lyrics',
    'chapters': 'chapters',
    'tagSet': 'tagSet',
    'tagRemove': 'tagRemove',
    'releaseStatus': 'releaseStatus',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'fields': 'fields',
    'credit': 'credit',
    'lyrics': 'lyrics',
    'chapters': 'chapters',
    'tagSet': 'tagSet',
    'tagRemove': 'tagRemove',
    'releaseStatus': 'releaseStatus',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[MetadataCommitPartPart_Enum];
  @override
  final String wireName = 'MetadataCommitPartPart_Enum';

  @override
  Object serialize(
    Serializers serializers,
    MetadataCommitPartPart_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MetadataCommitPartPart_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MetadataCommitPartPart_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MetadataCommitPartStatusEnumSerializer
    implements PrimitiveSerializer<MetadataCommitPartStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'committed': 'committed',
    'refused': 'refused',
    'skipped': 'skipped',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'committed': 'committed',
    'refused': 'refused',
    'skipped': 'skipped',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[MetadataCommitPartStatusEnum];
  @override
  final String wireName = 'MetadataCommitPartStatusEnum';

  @override
  Object serialize(
    Serializers serializers,
    MetadataCommitPartStatusEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MetadataCommitPartStatusEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MetadataCommitPartStatusEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MetadataCommitPart extends MetadataCommitPart {
  @override
  final MetadataCommitPartPart_Enum part_;
  @override
  final String? detail;
  @override
  final MetadataCommitPartStatusEnum status;
  @override
  final Error? refusal;

  factory _$MetadataCommitPart([
    void Function(MetadataCommitPartBuilder)? updates,
  ]) => (MetadataCommitPartBuilder()..update(updates))._build();

  _$MetadataCommitPart._({
    required this.part_,
    this.detail,
    required this.status,
    this.refusal,
  }) : super._();
  @override
  MetadataCommitPart rebuild(
    void Function(MetadataCommitPartBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MetadataCommitPartBuilder toBuilder() =>
      MetadataCommitPartBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetadataCommitPart &&
        part_ == other.part_ &&
        detail == other.detail &&
        status == other.status &&
        refusal == other.refusal;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, part_.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, refusal.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetadataCommitPart')
          ..add('part_', part_)
          ..add('detail', detail)
          ..add('status', status)
          ..add('refusal', refusal))
        .toString();
  }
}

class MetadataCommitPartBuilder
    implements Builder<MetadataCommitPart, MetadataCommitPartBuilder> {
  _$MetadataCommitPart? _$v;

  MetadataCommitPartPart_Enum? _part_;
  MetadataCommitPartPart_Enum? get part_ => _$this._part_;
  set part_(MetadataCommitPartPart_Enum? part_) => _$this._part_ = part_;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  MetadataCommitPartStatusEnum? _status;
  MetadataCommitPartStatusEnum? get status => _$this._status;
  set status(MetadataCommitPartStatusEnum? status) => _$this._status = status;

  ErrorBuilder? _refusal;
  ErrorBuilder get refusal => _$this._refusal ??= ErrorBuilder();
  set refusal(ErrorBuilder? refusal) => _$this._refusal = refusal;

  MetadataCommitPartBuilder() {
    MetadataCommitPart._defaults(this);
  }

  MetadataCommitPartBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _part_ = $v.part_;
      _detail = $v.detail;
      _status = $v.status;
      _refusal = $v.refusal?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetadataCommitPart other) {
    _$v = other as _$MetadataCommitPart;
  }

  @override
  void update(void Function(MetadataCommitPartBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetadataCommitPart build() => _build();

  _$MetadataCommitPart _build() {
    _$MetadataCommitPart _$result;
    try {
      _$result =
          _$v ??
          _$MetadataCommitPart._(
            part_: BuiltValueNullFieldError.checkNotNull(
              part_,
              r'MetadataCommitPart',
              'part_',
            ),
            detail: detail,
            status: BuiltValueNullFieldError.checkNotNull(
              status,
              r'MetadataCommitPart',
              'status',
            ),
            refusal: _refusal?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'refusal';
        _refusal?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MetadataCommitPart',
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
