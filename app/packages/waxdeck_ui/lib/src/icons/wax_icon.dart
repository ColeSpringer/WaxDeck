import 'package:flutter/material.dart';

// Family names of the vendored subsets, as top-level constants so the
// glyph constructor stays const-evaluable.
const String _regularFamily = 'PhosphorRegular';
const String _fillFamily = 'PhosphorFill';
const String _fontPackage = 'waxdeck_ui';

/// One icon in both of the weights WaxDeck ships.
///
/// Regular is inactive, fill is active or selected. That weight flip is
/// the icon system's state convention: colour alone never carries state,
/// so a selected tab still reads as selected in greyscale.
///
/// Both glyphs are const [IconData] over vendored subset fonts, so the
/// bundle carries exactly the glyphs named in [WaxIcons] and nothing
/// else. See `tools/fetch-icons.sh` for how the subsets are produced.
@immutable
class WaxGlyph {
  /// Phosphor gives a glyph the same codepoint in every style, so the
  /// pair below differs only by family. Both are written out as const
  /// [IconData] literals because `IconData.codePoint` is `@mustBeConst`:
  /// the icon tree-shaker only strips glyphs it can see statically, and
  /// a forwarded codepoint would fail the release build outright.
  const WaxGlyph(this.regular, this.fill);

  final IconData regular;
  final IconData fill;

  int get codePoint => regular.codePoint;

  IconData resolve({required bool active}) => active ? fill : regular;
}

/// Renders a [WaxGlyph].
///
/// Every icon in the app goes through this widget rather than through an
/// icon package directly, so the set can be swapped without touching call
/// sites.
///
/// Pass [semanticLabel] when the icon is the whole meaning of a control;
/// leave it null when a visible label already says the same thing, so a
/// screen reader does not hear it twice.
class WaxIcon extends StatelessWidget {
  const WaxIcon(
    this.glyph, {
    this.size = 20,
    this.color,
    this.active = false,
    this.semanticLabel,
    super.key,
  });

  final WaxGlyph glyph;
  final double size;
  final Color? color;

  /// Selected, playing, starred: renders the fill weight.
  final bool active;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Icon(
    glyph.resolve(active: active),
    size: size,
    color: color,
    semanticLabel: semanticLabel,
  );
}

/// The named icons WaxDeck uses.
///
/// Phosphor's set (MIT) is vendored as two subset fonts rather than
/// pulled from `phosphor_flutter`, which cannot compile against Flutter
/// 3.44: that package subclasses `IconData`, and `IconData` is now a
/// final class. The wrapper above is what makes that swap invisible to
/// call sites. Codepoints match upstream Phosphor, so an icon can be
/// looked up by name at phosphoricons.com.
///
/// Adding an icon means adding it here and re-running
/// `tools/fetch-icons.sh`, which rebuilds the subsets from the codepoints
/// on this page. `test/icons_test.dart` fails if the two ever disagree.
///
/// Deliberately *not* `@staticIconProvider`. That annotation tells the
/// release build's icon tree-shaker to ignore the constants declared in
/// the annotated class, so a glyph survives only where the shaker finds
/// its constant materialized at a use site - which a reference from
/// another package's widget code is not. With the annotation on, 32 of
/// these 57 names shipped as blank boxes in release builds while
/// rendering correctly in every debug run, golden, and widget test.
/// Without it the shipped subsets are exactly the vendored ones (27 KB
/// for both weights), which is what `fetch-icons.sh` curated them down to
/// in the first place; the annotation's saving is 16 KB and its price is
/// silent, release-only blanks. MaterialIcons still shakes 1.6 MB to
/// 21 KB, which is where that optimization earns its keep.
abstract final class WaxIcons {
  static const String fontPackage = _fontPackage;
  static const String regularFamily = _regularFamily;
  static const String fillFamily = _fillFamily;

  // Transport.
  /// Phosphor `play`.
  static const play = WaxGlyph(
    IconData(0xE3D0, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE3D0, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `pause`.
  static const pause = WaxGlyph(
    IconData(0xE39E, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE39E, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `stop`.
  static const stop = WaxGlyph(
    IconData(0xE46C, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE46C, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `skip-back`.
  static const previous = WaxGlyph(
    IconData(0xE5A4, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE5A4, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `skip-forward`.
  static const next = WaxGlyph(
    IconData(0xE5A6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE5A6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `rewind`.
  static const rewind = WaxGlyph(
    IconData(0xE6A8, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE6A8, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `fast-forward`.
  static const fastForward = WaxGlyph(
    IconData(0xE6A6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE6A6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `shuffle`.
  static const shuffle = WaxGlyph(
    IconData(0xE422, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE422, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `repeat`.
  static const repeatAll = WaxGlyph(
    IconData(0xE3F6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE3F6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `repeat-once`.
  static const repeatOne = WaxGlyph(
    IconData(0xE3F8, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE3F8, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `infinity`.
  static const keepPlaying = WaxGlyph(
    IconData(0xE634, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE634, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `gauge`.
  static const speed = WaxGlyph(
    IconData(0xE628, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE628, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `moon`.
  static const sleepTimer = WaxGlyph(
    IconData(0xE330, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE330, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `speaker-high`.
  static const volume = WaxGlyph(
    IconData(0xE44A, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE44A, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `speaker-none`.
  static const volumeMuted = WaxGlyph(
    IconData(0xE44E, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE44E, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  // Domains and navigation.
  /// Phosphor `house`.
  static const home = WaxGlyph(
    IconData(0xE2C2, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2C2, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `music-notes`.
  static const music = WaxGlyph(
    IconData(0xE340, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE340, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `microphone-stage`.
  static const podcasts = WaxGlyph(
    IconData(0xE75C, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE75C, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `book-open`.
  static const audiobooks = WaxGlyph(
    IconData(0xE0E6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE0E6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `broadcast`.
  static const radio = WaxGlyph(
    IconData(0xE0F2, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE0F2, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `magnifying-glass`.
  static const search = WaxGlyph(
    IconData(0xE30C, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE30C, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `download-simple`.
  static const downloads = WaxGlyph(
    IconData(0xE20C, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE20C, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `gear`.
  static const settings = WaxGlyph(
    IconData(0xE270, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE270, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `sliders-horizontal`.
  static const admin = WaxGlyph(
    IconData(0xE434, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE434, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `playlist`.
  static const playlists = WaxGlyph(
    IconData(0xE6AA, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE6AA, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `users`.
  static const artists = WaxGlyph(
    IconData(0xE4D6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE4D6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `vinyl-record`.
  static const albums = WaxGlyph(
    IconData(0xECAC, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xECAC, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `chart-bar`.
  static const stats = WaxGlyph(
    IconData(0xE150, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE150, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  // Actions.
  /// Phosphor `star`.
  static const star = WaxGlyph(
    IconData(0xE46A, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE46A, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `heart`.
  static const heart = WaxGlyph(
    IconData(0xE2A8, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2A8, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `list-bullets`.
  static const queue = WaxGlyph(
    IconData(0xE2F2, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2F2, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `list-plus`.
  static const addToQueue = WaxGlyph(
    IconData(0xE2F8, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2F8, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `quotes`.
  static const lyrics = WaxGlyph(
    IconData(0xE660, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE660, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `screencast`.
  static const cast = WaxGlyph(
    IconData(0xE404, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE404, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `devices`.
  static const devices = WaxGlyph(
    IconData(0xEBA4, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xEBA4, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `dots-three`.
  static const more = WaxGlyph(
    IconData(0xE1FE, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE1FE, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `dots-three-vertical`.
  static const moreVertical = WaxGlyph(
    IconData(0xE208, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE208, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `plus`.
  static const add = WaxGlyph(
    IconData(0xE3D4, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE3D4, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `check`.
  static const check = WaxGlyph(
    IconData(0xE182, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE182, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `x`.
  static const close = WaxGlyph(
    IconData(0xE4F6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE4F6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `arrow-left`.
  static const back = WaxGlyph(
    IconData(0xE058, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE058, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `caret-down`.
  static const collapse = WaxGlyph(
    IconData(0xE136, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE136, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `caret-up`.
  static const expand = WaxGlyph(
    IconData(0xE13C, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE13C, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `caret-right`.
  static const forward = WaxGlyph(
    IconData(0xE13A, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE13A, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `caret-left`.
  static const backward = WaxGlyph(
    IconData(0xE138, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE138, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `funnel`.
  static const filter = WaxGlyph(
    IconData(0xE266, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE266, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `sort-ascending`.
  static const sort = WaxGlyph(
    IconData(0xE444, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE444, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `pencil-simple`.
  static const edit = WaxGlyph(
    IconData(0xE3B4, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE3B4, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `trash`.
  static const delete = WaxGlyph(
    IconData(0xE4A6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE4A6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `link-break`. Something pulled off what it was tied to.
  static const detach = WaxGlyph(
    IconData(0xE2E4, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2E4, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `share-network`.
  static const share = WaxGlyph(
    IconData(0xE408, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE408, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `bookmark-simple`.
  static const bookmark = WaxGlyph(
    IconData(0xE0EA, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE0EA, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `lock-simple`. Something held against edits.
  static const lock = WaxGlyph(
    IconData(0xE308, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE308, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `lock-simple-open`. The same hold, released.
  static const lockOpen = WaxGlyph(
    IconData(0xE30A, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE30A, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `arrow-clockwise`.
  static const refresh = WaxGlyph(
    IconData(0xE036, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE036, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `upload-simple`.
  static const upload = WaxGlyph(
    IconData(0xE4C0, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE4C0, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `arrow-square-out`. A link that leaves WaxDeck.
  static const openExternal = WaxGlyph(
    IconData(0xE5DE, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE5DE, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `sign-in`.
  static const signIn = WaxGlyph(
    IconData(0xE428, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE428, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `user-plus`.
  static const addPerson = WaxGlyph(
    IconData(0xE4D0, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE4D0, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  // Server and administration.
  /// Phosphor `archive`. A backup, taken or listed.
  static const archive = WaxGlyph(
    IconData(0xE00C, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE00C, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `key`. An app password or a credential.
  static const key = WaxGlyph(
    IconData(0xE2D6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2D6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `ticket`. An invitation to the server.
  static const ticket = WaxGlyph(
    IconData(0xE490, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE490, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `webhooks-logo`.
  static const webhook = WaxGlyph(
    IconData(0xECAE, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xECAE, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `chat-circle`. A notification target that speaks into a
  /// conversation.
  static const chat = WaxGlyph(
    IconData(0xE168, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE168, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  // States and signals.
  /// Phosphor `clock`. What time it is somewhere, as against [recent],
  /// which is time that has passed.
  static const clock = WaxGlyph(
    IconData(0xE19A, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE19A, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `hourglass`. Something waiting on somebody else.
  static const hourglass = WaxGlyph(
    IconData(0xE2B2, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2B2, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `power`. A subsystem that is not switched on.
  static const power = WaxGlyph(
    IconData(0xE3DA, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE3DA, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `cloud-slash`.
  static const offline = WaxGlyph(
    IconData(0xE1B6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE1B6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `warning`.
  static const warning = WaxGlyph(
    IconData(0xE4E0, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE4E0, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `warning-circle`.
  static const errorCircle = WaxGlyph(
    IconData(0xE4E2, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE4E2, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `check-circle`.
  static const success = WaxGlyph(
    IconData(0xE184, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE184, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `info`.
  static const info = WaxGlyph(
    IconData(0xE2CE, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2CE, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `bell`.
  static const bell = WaxGlyph(
    IconData(0xE0CE, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE0CE, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `clock-counter-clockwise`.
  static const recent = WaxGlyph(
    IconData(0xE1A0, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE1A0, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `waveform`.
  static const waveform = WaxGlyph(
    IconData(0xE802, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE802, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `headphones`.
  static const headphones = WaxGlyph(
    IconData(0xE2A6, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE2A6, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Phosphor `car`.
  static const car = WaxGlyph(
    IconData(0xE112, fontFamily: _regularFamily, fontPackage: _fontPackage),
    IconData(0xE112, fontFamily: _fillFamily, fontPackage: _fontPackage),
  );

  /// Every glyph the app can render, for the catalog and for the
  /// subset drift test.
  static const Map<String, WaxGlyph> all = <String, WaxGlyph>{
    'play': play,
    'pause': pause,
    'stop': stop,
    'previous': previous,
    'next': next,
    'rewind': rewind,
    'fastForward': fastForward,
    'shuffle': shuffle,
    'repeatAll': repeatAll,
    'repeatOne': repeatOne,
    'keepPlaying': keepPlaying,
    'speed': speed,
    'sleepTimer': sleepTimer,
    'volume': volume,
    'volumeMuted': volumeMuted,
    'home': home,
    'music': music,
    'podcasts': podcasts,
    'audiobooks': audiobooks,
    'radio': radio,
    'search': search,
    'downloads': downloads,
    'settings': settings,
    'admin': admin,
    'playlists': playlists,
    'artists': artists,
    'albums': albums,
    'stats': stats,
    'star': star,
    'heart': heart,
    'queue': queue,
    'addToQueue': addToQueue,
    'lyrics': lyrics,
    'cast': cast,
    'devices': devices,
    'more': more,
    'moreVertical': moreVertical,
    'add': add,
    'check': check,
    'close': close,
    'back': back,
    'collapse': collapse,
    'expand': expand,
    'forward': forward,
    'backward': backward,
    'filter': filter,
    'sort': sort,
    'edit': edit,
    'delete': delete,
    'detach': detach,
    'share': share,
    'bookmark': bookmark,
    'lock': lock,
    'lockOpen': lockOpen,
    'refresh': refresh,
    'upload': upload,
    'openExternal': openExternal,
    'signIn': signIn,
    'addPerson': addPerson,
    'archive': archive,
    'key': key,
    'ticket': ticket,
    'webhook': webhook,
    'chat': chat,
    'clock': clock,
    'hourglass': hourglass,
    'power': power,
    'offline': offline,
    'warning': warning,
    'errorCircle': errorCircle,
    'success': success,
    'info': info,
    'bell': bell,
    'recent': recent,
    'waveform': waveform,
    'headphones': headphones,
    'car': car,
  };
}
