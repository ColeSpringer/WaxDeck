// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_bulk_decision.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReviewBulkDecisionActionEnum _$reviewBulkDecisionActionEnum_approve =
    const ReviewBulkDecisionActionEnum._('approve');
const ReviewBulkDecisionActionEnum _$reviewBulkDecisionActionEnum_asIs =
    const ReviewBulkDecisionActionEnum._('asIs');
const ReviewBulkDecisionActionEnum _$reviewBulkDecisionActionEnum_unofficial =
    const ReviewBulkDecisionActionEnum._('unofficial');
const ReviewBulkDecisionActionEnum _$reviewBulkDecisionActionEnum_skip =
    const ReviewBulkDecisionActionEnum._('skip');
const ReviewBulkDecisionActionEnum _$reviewBulkDecisionActionEnum_discard =
    const ReviewBulkDecisionActionEnum._('discard');
const ReviewBulkDecisionActionEnum
_$reviewBulkDecisionActionEnum_unknownDefaultOpenApi =
    const ReviewBulkDecisionActionEnum._('unknownDefaultOpenApi');

ReviewBulkDecisionActionEnum _$reviewBulkDecisionActionEnumValueOf(
  String name,
) {
  switch (name) {
    case 'approve':
      return _$reviewBulkDecisionActionEnum_approve;
    case 'asIs':
      return _$reviewBulkDecisionActionEnum_asIs;
    case 'unofficial':
      return _$reviewBulkDecisionActionEnum_unofficial;
    case 'skip':
      return _$reviewBulkDecisionActionEnum_skip;
    case 'discard':
      return _$reviewBulkDecisionActionEnum_discard;
    case 'unknownDefaultOpenApi':
      return _$reviewBulkDecisionActionEnum_unknownDefaultOpenApi;
    default:
      return _$reviewBulkDecisionActionEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ReviewBulkDecisionActionEnum>
_$reviewBulkDecisionActionEnumValues =
    BuiltSet<ReviewBulkDecisionActionEnum>(const <ReviewBulkDecisionActionEnum>[
      _$reviewBulkDecisionActionEnum_approve,
      _$reviewBulkDecisionActionEnum_asIs,
      _$reviewBulkDecisionActionEnum_unofficial,
      _$reviewBulkDecisionActionEnum_skip,
      _$reviewBulkDecisionActionEnum_discard,
      _$reviewBulkDecisionActionEnum_unknownDefaultOpenApi,
    ]);

Serializer<ReviewBulkDecisionActionEnum>
_$reviewBulkDecisionActionEnumSerializer =
    _$ReviewBulkDecisionActionEnumSerializer();

class _$ReviewBulkDecisionActionEnumSerializer
    implements PrimitiveSerializer<ReviewBulkDecisionActionEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'approve': 'approve',
    'asIs': 'as-is',
    'unofficial': 'unofficial',
    'skip': 'skip',
    'discard': 'discard',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'approve': 'approve',
    'as-is': 'asIs',
    'unofficial': 'unofficial',
    'skip': 'skip',
    'discard': 'discard',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ReviewBulkDecisionActionEnum];
  @override
  final String wireName = 'ReviewBulkDecisionActionEnum';

  @override
  Object serialize(
    Serializers serializers,
    ReviewBulkDecisionActionEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ReviewBulkDecisionActionEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ReviewBulkDecisionActionEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ReviewBulkDecision extends ReviewBulkDecision {
  @override
  final BuiltList<String> entryIds;
  @override
  final ReviewBulkDecisionActionEnum action;

  factory _$ReviewBulkDecision([
    void Function(ReviewBulkDecisionBuilder)? updates,
  ]) => (ReviewBulkDecisionBuilder()..update(updates))._build();

  _$ReviewBulkDecision._({required this.entryIds, required this.action})
    : super._();
  @override
  ReviewBulkDecision rebuild(
    void Function(ReviewBulkDecisionBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ReviewBulkDecisionBuilder toBuilder() =>
      ReviewBulkDecisionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewBulkDecision &&
        entryIds == other.entryIds &&
        action == other.action;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entryIds.hashCode);
    _$hash = $jc(_$hash, action.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewBulkDecision')
          ..add('entryIds', entryIds)
          ..add('action', action))
        .toString();
  }
}

class ReviewBulkDecisionBuilder
    implements Builder<ReviewBulkDecision, ReviewBulkDecisionBuilder> {
  _$ReviewBulkDecision? _$v;

  ListBuilder<String>? _entryIds;
  ListBuilder<String> get entryIds =>
      _$this._entryIds ??= ListBuilder<String>();
  set entryIds(ListBuilder<String>? entryIds) => _$this._entryIds = entryIds;

  ReviewBulkDecisionActionEnum? _action;
  ReviewBulkDecisionActionEnum? get action => _$this._action;
  set action(ReviewBulkDecisionActionEnum? action) => _$this._action = action;

  ReviewBulkDecisionBuilder() {
    ReviewBulkDecision._defaults(this);
  }

  ReviewBulkDecisionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entryIds = $v.entryIds.toBuilder();
      _action = $v.action;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewBulkDecision other) {
    _$v = other as _$ReviewBulkDecision;
  }

  @override
  void update(void Function(ReviewBulkDecisionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewBulkDecision build() => _build();

  _$ReviewBulkDecision _build() {
    _$ReviewBulkDecision _$result;
    try {
      _$result =
          _$v ??
          _$ReviewBulkDecision._(
            entryIds: entryIds.build(),
            action: BuiltValueNullFieldError.checkNotNull(
              action,
              r'ReviewBulkDecision',
              'action',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entryIds';
        entryIds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ReviewBulkDecision',
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
