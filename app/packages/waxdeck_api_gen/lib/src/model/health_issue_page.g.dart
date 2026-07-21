// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_issue_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthIssuePage extends HealthIssuePage {
  @override
  final BuiltList<HealthIssue> items;
  @override
  final String? nextCursor;

  factory _$HealthIssuePage([void Function(HealthIssuePageBuilder)? updates]) =>
      (HealthIssuePageBuilder()..update(updates))._build();

  _$HealthIssuePage._({required this.items, this.nextCursor}) : super._();
  @override
  HealthIssuePage rebuild(void Function(HealthIssuePageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthIssuePageBuilder toBuilder() => HealthIssuePageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthIssuePage &&
        items == other.items &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthIssuePage')
          ..add('items', items)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class HealthIssuePageBuilder
    implements Builder<HealthIssuePage, HealthIssuePageBuilder> {
  _$HealthIssuePage? _$v;

  ListBuilder<HealthIssue>? _items;
  ListBuilder<HealthIssue> get items =>
      _$this._items ??= ListBuilder<HealthIssue>();
  set items(ListBuilder<HealthIssue>? items) => _$this._items = items;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  HealthIssuePageBuilder() {
    HealthIssuePage._defaults(this);
  }

  HealthIssuePageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthIssuePage other) {
    _$v = other as _$HealthIssuePage;
  }

  @override
  void update(void Function(HealthIssuePageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthIssuePage build() => _build();

  _$HealthIssuePage _build() {
    _$HealthIssuePage _$result;
    try {
      _$result =
          _$v ??
          _$HealthIssuePage._(items: items.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'HealthIssuePage',
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
