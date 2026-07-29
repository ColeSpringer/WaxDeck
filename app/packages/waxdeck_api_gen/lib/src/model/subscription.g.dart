// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Subscription extends Subscription {
  @override
  final PodcastShow show_;
  @override
  final SubscriptionSettings settings;
  @override
  final DateTime subscribedAt;
  @override
  final int? unplayedCount;

  factory _$Subscription([void Function(SubscriptionBuilder)? updates]) =>
      (SubscriptionBuilder()..update(updates))._build();

  _$Subscription._({
    required this.show_,
    required this.settings,
    required this.subscribedAt,
    this.unplayedCount,
  }) : super._();
  @override
  Subscription rebuild(void Function(SubscriptionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SubscriptionBuilder toBuilder() => SubscriptionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Subscription &&
        show_ == other.show_ &&
        settings == other.settings &&
        subscribedAt == other.subscribedAt &&
        unplayedCount == other.unplayedCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, show_.hashCode);
    _$hash = $jc(_$hash, settings.hashCode);
    _$hash = $jc(_$hash, subscribedAt.hashCode);
    _$hash = $jc(_$hash, unplayedCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Subscription')
          ..add('show_', show_)
          ..add('settings', settings)
          ..add('subscribedAt', subscribedAt)
          ..add('unplayedCount', unplayedCount))
        .toString();
  }
}

class SubscriptionBuilder
    implements Builder<Subscription, SubscriptionBuilder> {
  _$Subscription? _$v;

  PodcastShowBuilder? _show_;
  PodcastShowBuilder get show_ => _$this._show_ ??= PodcastShowBuilder();
  set show_(PodcastShowBuilder? show_) => _$this._show_ = show_;

  SubscriptionSettingsBuilder? _settings;
  SubscriptionSettingsBuilder get settings =>
      _$this._settings ??= SubscriptionSettingsBuilder();
  set settings(SubscriptionSettingsBuilder? settings) =>
      _$this._settings = settings;

  DateTime? _subscribedAt;
  DateTime? get subscribedAt => _$this._subscribedAt;
  set subscribedAt(DateTime? subscribedAt) =>
      _$this._subscribedAt = subscribedAt;

  int? _unplayedCount;
  int? get unplayedCount => _$this._unplayedCount;
  set unplayedCount(int? unplayedCount) =>
      _$this._unplayedCount = unplayedCount;

  SubscriptionBuilder() {
    Subscription._defaults(this);
  }

  SubscriptionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _show_ = $v.show_.toBuilder();
      _settings = $v.settings.toBuilder();
      _subscribedAt = $v.subscribedAt;
      _unplayedCount = $v.unplayedCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Subscription other) {
    _$v = other as _$Subscription;
  }

  @override
  void update(void Function(SubscriptionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Subscription build() => _build();

  _$Subscription _build() {
    _$Subscription _$result;
    try {
      _$result =
          _$v ??
          _$Subscription._(
            show_: show_.build(),
            settings: settings.build(),
            subscribedAt: BuiltValueNullFieldError.checkNotNull(
              subscribedAt,
              r'Subscription',
              'subscribedAt',
            ),
            unplayedCount: unplayedCount,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'show_';
        show_.build();
        _$failedField = 'settings';
        settings.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Subscription',
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
