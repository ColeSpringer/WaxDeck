// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_stats.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewStats extends ReviewStats {
  @override
  final int pending;
  @override
  final int? identifying;
  @override
  final int applied;
  @override
  final int autoApplied;
  @override
  final int? asIs;
  @override
  final int? unofficial;
  @override
  final int? skipped;
  @override
  final int reverted;
  @override
  final int revertedAutoApplied;

  factory _$ReviewStats([void Function(ReviewStatsBuilder)? updates]) =>
      (ReviewStatsBuilder()..update(updates))._build();

  _$ReviewStats._({
    required this.pending,
    this.identifying,
    required this.applied,
    required this.autoApplied,
    this.asIs,
    this.unofficial,
    this.skipped,
    required this.reverted,
    required this.revertedAutoApplied,
  }) : super._();
  @override
  ReviewStats rebuild(void Function(ReviewStatsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewStatsBuilder toBuilder() => ReviewStatsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewStats &&
        pending == other.pending &&
        identifying == other.identifying &&
        applied == other.applied &&
        autoApplied == other.autoApplied &&
        asIs == other.asIs &&
        unofficial == other.unofficial &&
        skipped == other.skipped &&
        reverted == other.reverted &&
        revertedAutoApplied == other.revertedAutoApplied;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pending.hashCode);
    _$hash = $jc(_$hash, identifying.hashCode);
    _$hash = $jc(_$hash, applied.hashCode);
    _$hash = $jc(_$hash, autoApplied.hashCode);
    _$hash = $jc(_$hash, asIs.hashCode);
    _$hash = $jc(_$hash, unofficial.hashCode);
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jc(_$hash, reverted.hashCode);
    _$hash = $jc(_$hash, revertedAutoApplied.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewStats')
          ..add('pending', pending)
          ..add('identifying', identifying)
          ..add('applied', applied)
          ..add('autoApplied', autoApplied)
          ..add('asIs', asIs)
          ..add('unofficial', unofficial)
          ..add('skipped', skipped)
          ..add('reverted', reverted)
          ..add('revertedAutoApplied', revertedAutoApplied))
        .toString();
  }
}

class ReviewStatsBuilder implements Builder<ReviewStats, ReviewStatsBuilder> {
  _$ReviewStats? _$v;

  int? _pending;
  int? get pending => _$this._pending;
  set pending(int? pending) => _$this._pending = pending;

  int? _identifying;
  int? get identifying => _$this._identifying;
  set identifying(int? identifying) => _$this._identifying = identifying;

  int? _applied;
  int? get applied => _$this._applied;
  set applied(int? applied) => _$this._applied = applied;

  int? _autoApplied;
  int? get autoApplied => _$this._autoApplied;
  set autoApplied(int? autoApplied) => _$this._autoApplied = autoApplied;

  int? _asIs;
  int? get asIs => _$this._asIs;
  set asIs(int? asIs) => _$this._asIs = asIs;

  int? _unofficial;
  int? get unofficial => _$this._unofficial;
  set unofficial(int? unofficial) => _$this._unofficial = unofficial;

  int? _skipped;
  int? get skipped => _$this._skipped;
  set skipped(int? skipped) => _$this._skipped = skipped;

  int? _reverted;
  int? get reverted => _$this._reverted;
  set reverted(int? reverted) => _$this._reverted = reverted;

  int? _revertedAutoApplied;
  int? get revertedAutoApplied => _$this._revertedAutoApplied;
  set revertedAutoApplied(int? revertedAutoApplied) =>
      _$this._revertedAutoApplied = revertedAutoApplied;

  ReviewStatsBuilder() {
    ReviewStats._defaults(this);
  }

  ReviewStatsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pending = $v.pending;
      _identifying = $v.identifying;
      _applied = $v.applied;
      _autoApplied = $v.autoApplied;
      _asIs = $v.asIs;
      _unofficial = $v.unofficial;
      _skipped = $v.skipped;
      _reverted = $v.reverted;
      _revertedAutoApplied = $v.revertedAutoApplied;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewStats other) {
    _$v = other as _$ReviewStats;
  }

  @override
  void update(void Function(ReviewStatsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewStats build() => _build();

  _$ReviewStats _build() {
    final _$result =
        _$v ??
        _$ReviewStats._(
          pending: BuiltValueNullFieldError.checkNotNull(
            pending,
            r'ReviewStats',
            'pending',
          ),
          identifying: identifying,
          applied: BuiltValueNullFieldError.checkNotNull(
            applied,
            r'ReviewStats',
            'applied',
          ),
          autoApplied: BuiltValueNullFieldError.checkNotNull(
            autoApplied,
            r'ReviewStats',
            'autoApplied',
          ),
          asIs: asIs,
          unofficial: unofficial,
          skipped: skipped,
          reverted: BuiltValueNullFieldError.checkNotNull(
            reverted,
            r'ReviewStats',
            'reverted',
          ),
          revertedAutoApplied: BuiltValueNullFieldError.checkNotNull(
            revertedAutoApplied,
            r'ReviewStats',
            'revertedAutoApplied',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
