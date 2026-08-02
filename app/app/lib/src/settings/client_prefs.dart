import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show ClientSettingKeys;
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxDensity;

import '../auth/auth_controller.dart';
import '../player/smart_rewind.dart';
import 'client_settings_providers.dart';

/// The per-device preferences (ADR-0027), one notifier each.
///
/// Everything here describes the machine in front of the listener - how
/// far its transports jump, how tightly its rows pack, what its
/// connection costs - which is the line that decides what goes here and
/// what goes on the account's synced document (`prefs_controller.dart`).
/// Every one of them is read by something: a preference with no reader
/// is a promise the app does not keep.

/// A boolean preference.
///
/// The base exists because ten hand-written `decode`s are ten chances to
/// write the one that reads a stored value as its opposite, and because
/// the value a bad parse falls back to has to be the declared default
/// rather than `false`.
abstract class BoolSetting extends Notifier<bool> with StoredSetting<bool> {
  @override
  bool? decode(String raw) => switch (raw) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  @override
  String encode(bool value) => '$value';

  @override
  bool build() => hydrate();

  void set(bool value) => put(value);

  void toggle() => put(!state);
}

/// An integer preference, bounded.
abstract class IntSetting extends Notifier<int> with StoredSetting<int> {
  /// The range a stored value has to fall in to be believed. A value
  /// outside it reads as nothing stored, which is what makes shrinking
  /// the range in a later build safe.
  int get minValue;
  int get maxValue;

  @override
  int? decode(String raw) {
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < minValue || parsed > maxValue) return null;
    return parsed;
  }

  @override
  String encode(int value) => '$value';

  @override
  int build() => hydrate();

  void set(int value) => put(value.clamp(minValue, maxValue));
}

/// A preference chosen from a fixed list.
abstract class EnumSetting<T extends Enum> extends Notifier<T>
    with StoredSetting<T> {
  /// The values, in the order the picker offers them.
  List<T> get options;

  /// Stored by name, so a value's meaning survives reordering the enum -
  /// an index would silently become a different setting.
  @override
  T? decode(String raw) {
    for (final option in options) {
      if (option.name == raw) return option;
    }
    return null;
  }

  @override
  String encode(T value) => value.name;

  @override
  T build() => hydrate();

  void set(T value) => put(value);
}

// --- playback ----------------------------------------------------------------

/// How far the back transport jumps on a podcast or a book.
class SkipBackSeconds extends IntSetting {
  /// The intervals the picker offers. A free number field would let
  /// somebody type 3600 and lose their place in a book with one tap.
  static const options = <int>[5, 10, 15, 20, 30, 45, 60];

  @override
  String get settingKey => ClientSettingKeys.skipBackSeconds;

  @override
  int get defaultValue => 15;

  @override
  int get minValue => options.first;

  @override
  int get maxValue => options.last;
}

/// How far the forward transport jumps.
class SkipForwardSeconds extends IntSetting {
  static const options = SkipBackSeconds.options;

  @override
  String get settingKey => ClientSettingKeys.skipForwardSeconds;

  /// Thirty forward against fifteen back, which is what every player
  /// ships: the forward jump skips an ad break and the back one replays
  /// a sentence, and they are not the same distance.
  @override
  int get defaultValue => 30;

  @override
  int get minValue => options.first;

  @override
  int get maxValue => options.last;
}

final skipBackSecondsProvider = NotifierProvider<SkipBackSeconds, int>(
  SkipBackSeconds.new,
);
final skipForwardSecondsProvider = NotifierProvider<SkipForwardSeconds, int>(
  SkipForwardSeconds.new,
);

/// The speeds a picker offers, and the encoding a stored one uses.
///
/// Stored as an integer percentage rather than as a double, because a
/// double's text form is where a preference goes to acquire a rounding
/// error: 1.2 written and read back through `toString` is exact today
/// and is not something to depend on across two Dart versions.
abstract class SpeedSetting extends Notifier<double>
    with StoredSetting<double> {
  static const options = <double>[0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0];

  @override
  double get defaultValue => 1.0;

  @override
  double? decode(String raw) {
    final percent = int.tryParse(raw);
    if (percent == null || percent < 50 || percent > 400) return null;
    return percent / 100;
  }

  @override
  String encode(double value) => '${(value * 100).round()}';

  @override
  double build() => hydrate();

  void set(double value) => put(value);
}

/// The speed a podcast episode plays at when its show has none stored.
class PodcastSpeed extends SpeedSetting {
  @override
  String get settingKey => ClientSettingKeys.podcastSpeed;
}

/// The speed a book plays at when it has none stored.
class BookSpeed extends SpeedSetting {
  @override
  String get settingKey => ClientSettingKeys.bookSpeed;
}

final podcastSpeedProvider = NotifierProvider<PodcastSpeed, double>(
  PodcastSpeed.new,
);
final bookSpeedProvider = NotifierProvider<BookSpeed, double>(BookSpeed.new);

/// Whether spoken word trims silence when the show or book has no
/// stored choice of its own. Per device like the speed default beside
/// it: it is about the ears in front of this machine. Off by default,
/// so nothing changes for a listener who never asked.
class TrimSilenceDefault extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.trimSilenceDefault;

  @override
  bool get defaultValue => false;
}

final trimSilenceDefaultProvider = NotifierProvider<TrimSilenceDefault, bool>(
  TrimSilenceDefault.new,
);

/// Whether spoken word opens with loudness normalization when the show
/// or book has no stored choice. The same per-device scope and the same
/// quiet default as the trim beside it.
class VoiceBoostDefault extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.voiceBoostDefault;

  @override
  bool get defaultValue => false;
}

final voiceBoostDefaultProvider = NotifierProvider<VoiceBoostDefault, bool>(
  VoiceBoostDefault.new,
);

/// Whether each spoken-word effect has explained itself once (5.3).
///
/// Not settings, and deliberately absent from the settings registry:
/// nothing offers these as a control, because "show me that hint again"
/// is not a preference anybody has. They are a note that a sentence has
/// been said, kept per device because the hint is about the first time
/// somebody presses the chip on this machine.
class TrimSilenceExplained extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.trimSilenceExplained;

  @override
  bool get defaultValue => false;
}

class VoiceBoostExplained extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.voiceBoostExplained;

  @override
  bool get defaultValue => false;
}

final trimSilenceExplainedProvider =
    NotifierProvider<TrimSilenceExplained, bool>(TrimSilenceExplained.new);
final voiceBoostExplainedProvider = NotifierProvider<VoiceBoostExplained, bool>(
  VoiceBoostExplained.new,
);

/// How far a spoken-word resume steps back for context.
///
/// On by default, at the gentler of the two ladders: three seconds
/// after a break is a correction most listeners never notice and every
/// one of them benefits from, and the listeners who would rather have
/// none are the ones who go looking for the switch.
class SmartRewindSetting extends EnumSetting<SmartRewind> {
  @override
  String get settingKey => ClientSettingKeys.smartRewind;

  @override
  SmartRewind get defaultValue => SmartRewind.short;

  @override
  List<SmartRewind> get options => SmartRewind.values;
}

final smartRewindProvider = NotifierProvider<SmartRewindSetting, SmartRewind>(
  SmartRewindSetting.new,
);

/// Whether gapless preloading waits for an unmetered connection.
///
/// Off by default: preloading buffers one track thirty seconds early,
/// which is a small enough spend that making every listener find this
/// switch to get gapless playback would be the wrong trade.
class PreloadOnWifiOnly extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.preloadOnWifiOnly;

  @override
  bool get defaultValue => false;
}

final preloadOnWifiOnlyProvider = NotifierProvider<PreloadOnWifiOnly, bool>(
  PreloadOnWifiOnly.new,
);

/// Whether downloads wait for an unmetered connection.
///
/// On by default, unlike the preload switch, and for the reason that
/// makes them different: a preload is one track and a download is a
/// nine-hour book. The platform holds the transfer rather than failing
/// it, so the cost of the default being wrong is a download that starts
/// at home.
class DownloadsOnWifiOnly extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.downloadsOnWifiOnly;

  @override
  bool get defaultValue => true;
}

final downloadsOnWifiOnlyProvider = NotifierProvider<DownloadsOnWifiOnly, bool>(
  DownloadsOnWifiOnly.new,
);

/// Whether a desktop left alone with music playing opens the visualizer
/// by itself.
///
/// Off by default, and this one is not a close call: a screen that
/// changes on its own is a surprise, and the listeners who want their
/// machine to become a record player when they walk away are the ones
/// who will go and find the switch.
class VisualizerWhenIdle extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.visualizerWhenIdle;

  @override
  bool get defaultValue => false;
}

final visualizerWhenIdleProvider = NotifierProvider<VisualizerWhenIdle, bool>(
  VisualizerWhenIdle.new,
);

/// Whether car mode gets its own control on the player.
///
/// Off by default: the overflow reaches it, and a driver who uses it
/// every day is exactly the person who will turn this on once. A row of
/// glyphs everybody carries for the few who need one is how a player
/// becomes a toolbar.
class CarModeButton extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.carModeButton;

  @override
  bool get defaultValue => false;
}

final carModeButtonProvider = NotifierProvider<CarModeButton, bool>(
  CarModeButton.new,
);

// --- library and metadata ----------------------------------------------------

/// Whether codec, bitrate, and provenance chips are drawn.
///
/// The default follows the role rather than being one value for
/// everybody: an administrator opening an album wants to see that it is
/// the FLAC and not the transcode, and a household member wants the
/// cover and the track list. It is a default and nothing more - the
/// switch is in Settings for both, and one tap either way is stored from
/// then on.
class TechnicalDetails extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.technicalDetails;

  @override
  bool get defaultValue => _isAdmin;

  bool _isAdmin = false;

  @override
  bool build() {
    // Watched, so the default is right on the frame after a sign-in
    // rather than on the next launch. Once anything is stored this
    // stops mattering: [hydrate] answers the stored value and the role
    // is not consulted again.
    final user = ref.watch(authControllerProvider).value?.user;
    _isAdmin = user?.roles.contains('admin') ?? false;
    return hydrate();
  }
}

final technicalDetailsProvider = NotifierProvider<TechnicalDetails, bool>(
  TechnicalDetails.new,
);

// --- appearance --------------------------------------------------------------

/// How large artwork tiles are drawn, as a multiplier on the size class's
/// own extent rather than as a pixel count: the layout system already
/// knows a phone wants smaller tiles than a desktop, and this says
/// whether this listener wants more of them or bigger ones.
enum WaxGridSize {
  small(0.75),
  medium(1.0),
  large(1.35);

  const WaxGridSize(this.scale);

  final double scale;
}

class Density extends EnumSetting<WaxDensity> {
  @override
  String get settingKey => ClientSettingKeys.density;

  @override
  WaxDensity get defaultValue => WaxDensity.comfortable;

  @override
  List<WaxDensity> get options => WaxDensity.values;
}

class GridSize extends EnumSetting<WaxGridSize> {
  @override
  String get settingKey => ClientSettingKeys.gridSize;

  @override
  WaxGridSize get defaultValue => WaxGridSize.medium;

  @override
  List<WaxGridSize> get options => WaxGridSize.values;
}

final densityProvider = NotifierProvider<Density, WaxDensity>(Density.new);
final gridSizeProvider = NotifierProvider<GridSize, WaxGridSize>(GridSize.new);

/// What every artwork grid multiplies its own base tile extent by.
///
/// A scale rather than a size, because the grids do not agree on a base
/// and should not: a station tile is square and a show tile is a cover,
/// and the layout system already varies both by size class. This says
/// bigger or smaller than whatever that screen decided.
final gridScaleProvider = Provider<double>(
  (ref) => ref.watch(gridSizeProvider).scale,
);

// --- accessibility -----------------------------------------------------------

/// An in-app reduce-motion override.
///
/// One-way on purpose. The platform's own setting is an accessibility
/// need and this can only add to it: turning it on stills motion the OS
/// left running, and turning it off does not put motion back where the
/// OS asked for none. `WaxMotion` reads `MediaQuery.disableAnimationsOf`
/// for both, which is why the override is applied by overriding that
/// query rather than by threading a second flag through every widget
/// that animates.
class ReduceMotion extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.reduceMotion;

  @override
  bool get defaultValue => false;
}

final reduceMotionProvider = NotifierProvider<ReduceMotion, bool>(
  ReduceMotion.new,
);

/// How a duration reads on a control and to a screen reader.
String spellSeconds(int seconds) {
  if (seconds % 60 == 0 && seconds >= 60) {
    final minutes = seconds ~/ 60;
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }
  return '$seconds seconds';
}

/// How a speed reads on a control: `1x`, `1.2x`, never `1.0x`.
String spellSpeed(double speed) {
  final text = speed.toStringAsFixed(2);
  final trimmed = text
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
  return '${trimmed}x';
}
