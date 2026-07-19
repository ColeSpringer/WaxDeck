// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'podcast_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PodcastDetail extends PodcastDetail {
  @override
  final PodcastShow show_;
  @override
  final bool subscribed;
  @override
  final SubscriptionSettings? settings;

  factory _$PodcastDetail([void Function(PodcastDetailBuilder)? updates]) =>
      (PodcastDetailBuilder()..update(updates))._build();

  _$PodcastDetail._({
    required this.show_,
    required this.subscribed,
    this.settings,
  }) : super._();
  @override
  PodcastDetail rebuild(void Function(PodcastDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PodcastDetailBuilder toBuilder() => PodcastDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PodcastDetail &&
        show_ == other.show_ &&
        subscribed == other.subscribed &&
        settings == other.settings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, show_.hashCode);
    _$hash = $jc(_$hash, subscribed.hashCode);
    _$hash = $jc(_$hash, settings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PodcastDetail')
          ..add('show_', show_)
          ..add('subscribed', subscribed)
          ..add('settings', settings))
        .toString();
  }
}

class PodcastDetailBuilder
    implements Builder<PodcastDetail, PodcastDetailBuilder> {
  _$PodcastDetail? _$v;

  PodcastShowBuilder? _show_;
  PodcastShowBuilder get show_ => _$this._show_ ??= PodcastShowBuilder();
  set show_(PodcastShowBuilder? show_) => _$this._show_ = show_;

  bool? _subscribed;
  bool? get subscribed => _$this._subscribed;
  set subscribed(bool? subscribed) => _$this._subscribed = subscribed;

  SubscriptionSettingsBuilder? _settings;
  SubscriptionSettingsBuilder get settings =>
      _$this._settings ??= SubscriptionSettingsBuilder();
  set settings(SubscriptionSettingsBuilder? settings) =>
      _$this._settings = settings;

  PodcastDetailBuilder() {
    PodcastDetail._defaults(this);
  }

  PodcastDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _show_ = $v.show_.toBuilder();
      _subscribed = $v.subscribed;
      _settings = $v.settings?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PodcastDetail other) {
    _$v = other as _$PodcastDetail;
  }

  @override
  void update(void Function(PodcastDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PodcastDetail build() => _build();

  _$PodcastDetail _build() {
    _$PodcastDetail _$result;
    try {
      _$result =
          _$v ??
          _$PodcastDetail._(
            show_: show_.build(),
            subscribed: BuiltValueNullFieldError.checkNotNull(
              subscribed,
              r'PodcastDetail',
              'subscribed',
            ),
            settings: _settings?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'show_';
        show_.build();

        _$failedField = 'settings';
        _settings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PodcastDetail',
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
