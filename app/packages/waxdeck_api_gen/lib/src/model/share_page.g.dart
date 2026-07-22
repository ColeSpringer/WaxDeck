// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SharePage extends SharePage {
  @override
  final BuiltList<Share> shares;
  @override
  final String? nextCursor;

  factory _$SharePage([void Function(SharePageBuilder)? updates]) =>
      (SharePageBuilder()..update(updates))._build();

  _$SharePage._({required this.shares, this.nextCursor}) : super._();
  @override
  SharePage rebuild(void Function(SharePageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SharePageBuilder toBuilder() => SharePageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SharePage &&
        shares == other.shares &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, shares.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SharePage')
          ..add('shares', shares)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class SharePageBuilder implements Builder<SharePage, SharePageBuilder> {
  _$SharePage? _$v;

  ListBuilder<Share>? _shares;
  ListBuilder<Share> get shares => _$this._shares ??= ListBuilder<Share>();
  set shares(ListBuilder<Share>? shares) => _$this._shares = shares;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  SharePageBuilder() {
    SharePage._defaults(this);
  }

  SharePageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _shares = $v.shares.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SharePage other) {
    _$v = other as _$SharePage;
  }

  @override
  void update(void Function(SharePageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SharePage build() => _build();

  _$SharePage _build() {
    _$SharePage _$result;
    try {
      _$result =
          _$v ?? _$SharePage._(shares: shares.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'shares';
        shares.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SharePage',
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
