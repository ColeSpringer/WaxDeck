// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upgrade_member.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpgradeMember extends UpgradeMember {
  @override
  final String itemPid;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final String codec;
  @override
  final int? bitrate;
  @override
  final int? sampleRate;
  @override
  final int? bitDepth;
  @override
  final bool lossless;
  @override
  final bool best;

  factory _$UpgradeMember([void Function(UpgradeMemberBuilder)? updates]) =>
      (UpgradeMemberBuilder()..update(updates))._build();

  _$UpgradeMember._({
    required this.itemPid,
    required this.title,
    this.artist,
    required this.codec,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    required this.lossless,
    required this.best,
  }) : super._();
  @override
  UpgradeMember rebuild(void Function(UpgradeMemberBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpgradeMemberBuilder toBuilder() => UpgradeMemberBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpgradeMember &&
        itemPid == other.itemPid &&
        title == other.title &&
        artist == other.artist &&
        codec == other.codec &&
        bitrate == other.bitrate &&
        sampleRate == other.sampleRate &&
        bitDepth == other.bitDepth &&
        lossless == other.lossless &&
        best == other.best;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, codec.hashCode);
    _$hash = $jc(_$hash, bitrate.hashCode);
    _$hash = $jc(_$hash, sampleRate.hashCode);
    _$hash = $jc(_$hash, bitDepth.hashCode);
    _$hash = $jc(_$hash, lossless.hashCode);
    _$hash = $jc(_$hash, best.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpgradeMember')
          ..add('itemPid', itemPid)
          ..add('title', title)
          ..add('artist', artist)
          ..add('codec', codec)
          ..add('bitrate', bitrate)
          ..add('sampleRate', sampleRate)
          ..add('bitDepth', bitDepth)
          ..add('lossless', lossless)
          ..add('best', best))
        .toString();
  }
}

class UpgradeMemberBuilder
    implements Builder<UpgradeMember, UpgradeMemberBuilder> {
  _$UpgradeMember? _$v;

  String? _itemPid;
  String? get itemPid => _$this._itemPid;
  set itemPid(String? itemPid) => _$this._itemPid = itemPid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  String? _codec;
  String? get codec => _$this._codec;
  set codec(String? codec) => _$this._codec = codec;

  int? _bitrate;
  int? get bitrate => _$this._bitrate;
  set bitrate(int? bitrate) => _$this._bitrate = bitrate;

  int? _sampleRate;
  int? get sampleRate => _$this._sampleRate;
  set sampleRate(int? sampleRate) => _$this._sampleRate = sampleRate;

  int? _bitDepth;
  int? get bitDepth => _$this._bitDepth;
  set bitDepth(int? bitDepth) => _$this._bitDepth = bitDepth;

  bool? _lossless;
  bool? get lossless => _$this._lossless;
  set lossless(bool? lossless) => _$this._lossless = lossless;

  bool? _best;
  bool? get best => _$this._best;
  set best(bool? best) => _$this._best = best;

  UpgradeMemberBuilder() {
    UpgradeMember._defaults(this);
  }

  UpgradeMemberBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPid = $v.itemPid;
      _title = $v.title;
      _artist = $v.artist;
      _codec = $v.codec;
      _bitrate = $v.bitrate;
      _sampleRate = $v.sampleRate;
      _bitDepth = $v.bitDepth;
      _lossless = $v.lossless;
      _best = $v.best;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpgradeMember other) {
    _$v = other as _$UpgradeMember;
  }

  @override
  void update(void Function(UpgradeMemberBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpgradeMember build() => _build();

  _$UpgradeMember _build() {
    final _$result =
        _$v ??
        _$UpgradeMember._(
          itemPid: BuiltValueNullFieldError.checkNotNull(
            itemPid,
            r'UpgradeMember',
            'itemPid',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'UpgradeMember',
            'title',
          ),
          artist: artist,
          codec: BuiltValueNullFieldError.checkNotNull(
            codec,
            r'UpgradeMember',
            'codec',
          ),
          bitrate: bitrate,
          sampleRate: sampleRate,
          bitDepth: bitDepth,
          lossless: BuiltValueNullFieldError.checkNotNull(
            lossless,
            r'UpgradeMember',
            'lossless',
          ),
          best: BuiltValueNullFieldError.checkNotNull(
            best,
            r'UpgradeMember',
            'best',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
