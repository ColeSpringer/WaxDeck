// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_batch.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const OrganizeBatchKindEnum _$organizeBatchKindEnum_organize =
    const OrganizeBatchKindEnum._('organize');
const OrganizeBatchKindEnum _$organizeBatchKindEnum_organizeUndo =
    const OrganizeBatchKindEnum._('organizeUndo');
const OrganizeBatchKindEnum _$organizeBatchKindEnum_unknownDefaultOpenApi =
    const OrganizeBatchKindEnum._('unknownDefaultOpenApi');

OrganizeBatchKindEnum _$organizeBatchKindEnumValueOf(String name) {
  switch (name) {
    case 'organize':
      return _$organizeBatchKindEnum_organize;
    case 'organizeUndo':
      return _$organizeBatchKindEnum_organizeUndo;
    case 'unknownDefaultOpenApi':
      return _$organizeBatchKindEnum_unknownDefaultOpenApi;
    default:
      return _$organizeBatchKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<OrganizeBatchKindEnum> _$organizeBatchKindEnumValues =
    BuiltSet<OrganizeBatchKindEnum>(const <OrganizeBatchKindEnum>[
      _$organizeBatchKindEnum_organize,
      _$organizeBatchKindEnum_organizeUndo,
      _$organizeBatchKindEnum_unknownDefaultOpenApi,
    ]);

Serializer<OrganizeBatchKindEnum> _$organizeBatchKindEnumSerializer =
    _$OrganizeBatchKindEnumSerializer();

class _$OrganizeBatchKindEnumSerializer
    implements PrimitiveSerializer<OrganizeBatchKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'organize': 'organize',
    'organizeUndo': 'organize-undo',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'organize': 'organize',
    'organize-undo': 'organizeUndo',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[OrganizeBatchKindEnum];
  @override
  final String wireName = 'OrganizeBatchKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    OrganizeBatchKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  OrganizeBatchKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => OrganizeBatchKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$OrganizeBatch extends OrganizeBatch {
  @override
  final String jobPid;
  @override
  final OrganizeBatchKindEnum kind;
  @override
  final String state;
  @override
  final DateTime startedAt;
  @override
  final String? profile;
  @override
  final int committed;
  @override
  final int rolledBack;
  @override
  final int planned;
  @override
  final bool undoable;

  factory _$OrganizeBatch([void Function(OrganizeBatchBuilder)? updates]) =>
      (OrganizeBatchBuilder()..update(updates))._build();

  _$OrganizeBatch._({
    required this.jobPid,
    required this.kind,
    required this.state,
    required this.startedAt,
    this.profile,
    required this.committed,
    required this.rolledBack,
    required this.planned,
    required this.undoable,
  }) : super._();
  @override
  OrganizeBatch rebuild(void Function(OrganizeBatchBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeBatchBuilder toBuilder() => OrganizeBatchBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeBatch &&
        jobPid == other.jobPid &&
        kind == other.kind &&
        state == other.state &&
        startedAt == other.startedAt &&
        profile == other.profile &&
        committed == other.committed &&
        rolledBack == other.rolledBack &&
        planned == other.planned &&
        undoable == other.undoable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, jobPid.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jc(_$hash, committed.hashCode);
    _$hash = $jc(_$hash, rolledBack.hashCode);
    _$hash = $jc(_$hash, planned.hashCode);
    _$hash = $jc(_$hash, undoable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeBatch')
          ..add('jobPid', jobPid)
          ..add('kind', kind)
          ..add('state', state)
          ..add('startedAt', startedAt)
          ..add('profile', profile)
          ..add('committed', committed)
          ..add('rolledBack', rolledBack)
          ..add('planned', planned)
          ..add('undoable', undoable))
        .toString();
  }
}

class OrganizeBatchBuilder
    implements Builder<OrganizeBatch, OrganizeBatchBuilder> {
  _$OrganizeBatch? _$v;

  String? _jobPid;
  String? get jobPid => _$this._jobPid;
  set jobPid(String? jobPid) => _$this._jobPid = jobPid;

  OrganizeBatchKindEnum? _kind;
  OrganizeBatchKindEnum? get kind => _$this._kind;
  set kind(OrganizeBatchKindEnum? kind) => _$this._kind = kind;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  DateTime? _startedAt;
  DateTime? get startedAt => _$this._startedAt;
  set startedAt(DateTime? startedAt) => _$this._startedAt = startedAt;

  String? _profile;
  String? get profile => _$this._profile;
  set profile(String? profile) => _$this._profile = profile;

  int? _committed;
  int? get committed => _$this._committed;
  set committed(int? committed) => _$this._committed = committed;

  int? _rolledBack;
  int? get rolledBack => _$this._rolledBack;
  set rolledBack(int? rolledBack) => _$this._rolledBack = rolledBack;

  int? _planned;
  int? get planned => _$this._planned;
  set planned(int? planned) => _$this._planned = planned;

  bool? _undoable;
  bool? get undoable => _$this._undoable;
  set undoable(bool? undoable) => _$this._undoable = undoable;

  OrganizeBatchBuilder() {
    OrganizeBatch._defaults(this);
  }

  OrganizeBatchBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _jobPid = $v.jobPid;
      _kind = $v.kind;
      _state = $v.state;
      _startedAt = $v.startedAt;
      _profile = $v.profile;
      _committed = $v.committed;
      _rolledBack = $v.rolledBack;
      _planned = $v.planned;
      _undoable = $v.undoable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeBatch other) {
    _$v = other as _$OrganizeBatch;
  }

  @override
  void update(void Function(OrganizeBatchBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeBatch build() => _build();

  _$OrganizeBatch _build() {
    final _$result =
        _$v ??
        _$OrganizeBatch._(
          jobPid: BuiltValueNullFieldError.checkNotNull(
            jobPid,
            r'OrganizeBatch',
            'jobPid',
          ),
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'OrganizeBatch',
            'kind',
          ),
          state: BuiltValueNullFieldError.checkNotNull(
            state,
            r'OrganizeBatch',
            'state',
          ),
          startedAt: BuiltValueNullFieldError.checkNotNull(
            startedAt,
            r'OrganizeBatch',
            'startedAt',
          ),
          profile: profile,
          committed: BuiltValueNullFieldError.checkNotNull(
            committed,
            r'OrganizeBatch',
            'committed',
          ),
          rolledBack: BuiltValueNullFieldError.checkNotNull(
            rolledBack,
            r'OrganizeBatch',
            'rolledBack',
          ),
          planned: BuiltValueNullFieldError.checkNotNull(
            planned,
            r'OrganizeBatch',
            'planned',
          ),
          undoable: BuiltValueNullFieldError.checkNotNull(
            undoable,
            r'OrganizeBatch',
            'undoable',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
