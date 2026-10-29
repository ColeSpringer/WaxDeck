// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'm3u_preview_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const M3uPreviewEntryOutcomeEnum _$m3uPreviewEntryOutcomeEnum_matched =
    const M3uPreviewEntryOutcomeEnum._('matched');
const M3uPreviewEntryOutcomeEnum _$m3uPreviewEntryOutcomeEnum_merged =
    const M3uPreviewEntryOutcomeEnum._('merged');
const M3uPreviewEntryOutcomeEnum _$m3uPreviewEntryOutcomeEnum_unmatched =
    const M3uPreviewEntryOutcomeEnum._('unmatched');
const M3uPreviewEntryOutcomeEnum
_$m3uPreviewEntryOutcomeEnum_unknownDefaultOpenApi =
    const M3uPreviewEntryOutcomeEnum._('unknownDefaultOpenApi');

M3uPreviewEntryOutcomeEnum _$m3uPreviewEntryOutcomeEnumValueOf(String name) {
  switch (name) {
    case 'matched':
      return _$m3uPreviewEntryOutcomeEnum_matched;
    case 'merged':
      return _$m3uPreviewEntryOutcomeEnum_merged;
    case 'unmatched':
      return _$m3uPreviewEntryOutcomeEnum_unmatched;
    case 'unknownDefaultOpenApi':
      return _$m3uPreviewEntryOutcomeEnum_unknownDefaultOpenApi;
    default:
      return _$m3uPreviewEntryOutcomeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<M3uPreviewEntryOutcomeEnum> _$m3uPreviewEntryOutcomeEnumValues =
    BuiltSet<M3uPreviewEntryOutcomeEnum>(const <M3uPreviewEntryOutcomeEnum>[
      _$m3uPreviewEntryOutcomeEnum_matched,
      _$m3uPreviewEntryOutcomeEnum_merged,
      _$m3uPreviewEntryOutcomeEnum_unmatched,
      _$m3uPreviewEntryOutcomeEnum_unknownDefaultOpenApi,
    ]);

Serializer<M3uPreviewEntryOutcomeEnum> _$m3uPreviewEntryOutcomeEnumSerializer =
    _$M3uPreviewEntryOutcomeEnumSerializer();

class _$M3uPreviewEntryOutcomeEnumSerializer
    implements PrimitiveSerializer<M3uPreviewEntryOutcomeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'matched': 'matched',
    'merged': 'merged',
    'unmatched': 'unmatched',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'matched': 'matched',
    'merged': 'merged',
    'unmatched': 'unmatched',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[M3uPreviewEntryOutcomeEnum];
  @override
  final String wireName = 'M3uPreviewEntryOutcomeEnum';

  @override
  Object serialize(
    Serializers serializers,
    M3uPreviewEntryOutcomeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  M3uPreviewEntryOutcomeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => M3uPreviewEntryOutcomeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$M3uPreviewEntry extends M3uPreviewEntry {
  @override
  final String path;
  @override
  final M3uPreviewEntryOutcomeEnum outcome;
  @override
  final ItemSummary? item;

  factory _$M3uPreviewEntry([void Function(M3uPreviewEntryBuilder)? updates]) =>
      (M3uPreviewEntryBuilder()..update(updates))._build();

  _$M3uPreviewEntry._({required this.path, required this.outcome, this.item})
    : super._();
  @override
  M3uPreviewEntry rebuild(void Function(M3uPreviewEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  M3uPreviewEntryBuilder toBuilder() => M3uPreviewEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is M3uPreviewEntry &&
        path == other.path &&
        outcome == other.outcome &&
        item == other.item;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, outcome.hashCode);
    _$hash = $jc(_$hash, item.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'M3uPreviewEntry')
          ..add('path', path)
          ..add('outcome', outcome)
          ..add('item', item))
        .toString();
  }
}

class M3uPreviewEntryBuilder
    implements Builder<M3uPreviewEntry, M3uPreviewEntryBuilder> {
  _$M3uPreviewEntry? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  M3uPreviewEntryOutcomeEnum? _outcome;
  M3uPreviewEntryOutcomeEnum? get outcome => _$this._outcome;
  set outcome(M3uPreviewEntryOutcomeEnum? outcome) => _$this._outcome = outcome;

  ItemSummary? _item;
  ItemSummary? get item => _$this._item;
  set item(ItemSummary? item) => _$this._item = item;

  M3uPreviewEntryBuilder() {
    M3uPreviewEntry._defaults(this);
  }

  M3uPreviewEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _outcome = $v.outcome;
      _item = $v.item;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(M3uPreviewEntry other) {
    _$v = other as _$M3uPreviewEntry;
  }

  @override
  void update(void Function(M3uPreviewEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  M3uPreviewEntry build() => _build();

  _$M3uPreviewEntry _build() {
    final _$result =
        _$v ??
        _$M3uPreviewEntry._(
          path: BuiltValueNullFieldError.checkNotNull(
            path,
            r'M3uPreviewEntry',
            'path',
          ),
          outcome: BuiltValueNullFieldError.checkNotNull(
            outcome,
            r'M3uPreviewEntry',
            'outcome',
          ),
          item: item,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
