// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trash_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TrashList extends TrashList {
  @override
  final BuiltList<TrashEntry> entries;

  factory _$TrashList([void Function(TrashListBuilder)? updates]) =>
      (TrashListBuilder()..update(updates))._build();

  _$TrashList._({required this.entries}) : super._();
  @override
  TrashList rebuild(void Function(TrashListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TrashListBuilder toBuilder() => TrashListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TrashList && entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'TrashList',
    )..add('entries', entries)).toString();
  }
}

class TrashListBuilder implements Builder<TrashList, TrashListBuilder> {
  _$TrashList? _$v;

  ListBuilder<TrashEntry>? _entries;
  ListBuilder<TrashEntry> get entries =>
      _$this._entries ??= ListBuilder<TrashEntry>();
  set entries(ListBuilder<TrashEntry>? entries) => _$this._entries = entries;

  TrashListBuilder() {
    TrashList._defaults(this);
  }

  TrashListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TrashList other) {
    _$v = other as _$TrashList;
  }

  @override
  void update(void Function(TrashListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TrashList build() => _build();

  _$TrashList _build() {
    _$TrashList _$result;
    try {
      _$result = _$v ?? _$TrashList._(entries: entries.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'TrashList',
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
