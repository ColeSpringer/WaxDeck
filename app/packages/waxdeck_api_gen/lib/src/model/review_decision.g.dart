// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_decision.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReviewDecisionActionEnum _$reviewDecisionActionEnum_approve =
    const ReviewDecisionActionEnum._('approve');
const ReviewDecisionActionEnum _$reviewDecisionActionEnum_asIs =
    const ReviewDecisionActionEnum._('asIs');
const ReviewDecisionActionEnum _$reviewDecisionActionEnum_unofficial =
    const ReviewDecisionActionEnum._('unofficial');
const ReviewDecisionActionEnum _$reviewDecisionActionEnum_skip =
    const ReviewDecisionActionEnum._('skip');
const ReviewDecisionActionEnum _$reviewDecisionActionEnum_discard =
    const ReviewDecisionActionEnum._('discard');

ReviewDecisionActionEnum _$reviewDecisionActionEnumValueOf(String name) {
  switch (name) {
    case 'approve':
      return _$reviewDecisionActionEnum_approve;
    case 'asIs':
      return _$reviewDecisionActionEnum_asIs;
    case 'unofficial':
      return _$reviewDecisionActionEnum_unofficial;
    case 'skip':
      return _$reviewDecisionActionEnum_skip;
    case 'discard':
      return _$reviewDecisionActionEnum_discard;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ReviewDecisionActionEnum> _$reviewDecisionActionEnumValues =
    BuiltSet<ReviewDecisionActionEnum>(const <ReviewDecisionActionEnum>[
      _$reviewDecisionActionEnum_approve,
      _$reviewDecisionActionEnum_asIs,
      _$reviewDecisionActionEnum_unofficial,
      _$reviewDecisionActionEnum_skip,
      _$reviewDecisionActionEnum_discard,
    ]);

Serializer<ReviewDecisionActionEnum> _$reviewDecisionActionEnumSerializer =
    _$ReviewDecisionActionEnumSerializer();

class _$ReviewDecisionActionEnumSerializer
    implements PrimitiveSerializer<ReviewDecisionActionEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'approve': 'approve',
    'asIs': 'as-is',
    'unofficial': 'unofficial',
    'skip': 'skip',
    'discard': 'discard',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'approve': 'approve',
    'as-is': 'asIs',
    'unofficial': 'unofficial',
    'skip': 'skip',
    'discard': 'discard',
  };

  @override
  final Iterable<Type> types = const <Type>[ReviewDecisionActionEnum];
  @override
  final String wireName = 'ReviewDecisionActionEnum';

  @override
  Object serialize(
    Serializers serializers,
    ReviewDecisionActionEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ReviewDecisionActionEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ReviewDecisionActionEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ReviewDecision extends ReviewDecision {
  @override
  final ReviewDecisionActionEnum action;
  @override
  final String? candidateMbid;

  factory _$ReviewDecision([void Function(ReviewDecisionBuilder)? updates]) =>
      (ReviewDecisionBuilder()..update(updates))._build();

  _$ReviewDecision._({required this.action, this.candidateMbid}) : super._();
  @override
  ReviewDecision rebuild(void Function(ReviewDecisionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewDecisionBuilder toBuilder() => ReviewDecisionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewDecision &&
        action == other.action &&
        candidateMbid == other.candidateMbid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, action.hashCode);
    _$hash = $jc(_$hash, candidateMbid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewDecision')
          ..add('action', action)
          ..add('candidateMbid', candidateMbid))
        .toString();
  }
}

class ReviewDecisionBuilder
    implements Builder<ReviewDecision, ReviewDecisionBuilder> {
  _$ReviewDecision? _$v;

  ReviewDecisionActionEnum? _action;
  ReviewDecisionActionEnum? get action => _$this._action;
  set action(ReviewDecisionActionEnum? action) => _$this._action = action;

  String? _candidateMbid;
  String? get candidateMbid => _$this._candidateMbid;
  set candidateMbid(String? candidateMbid) =>
      _$this._candidateMbid = candidateMbid;

  ReviewDecisionBuilder() {
    ReviewDecision._defaults(this);
  }

  ReviewDecisionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _action = $v.action;
      _candidateMbid = $v.candidateMbid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewDecision other) {
    _$v = other as _$ReviewDecision;
  }

  @override
  void update(void Function(ReviewDecisionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewDecision build() => _build();

  _$ReviewDecision _build() {
    final _$result =
        _$v ??
        _$ReviewDecision._(
          action: BuiltValueNullFieldError.checkNotNull(
            action,
            r'ReviewDecision',
            'action',
          ),
          candidateMbid: candidateMbid,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
