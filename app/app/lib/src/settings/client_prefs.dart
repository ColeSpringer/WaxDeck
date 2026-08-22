import 'dart:async';

import 'package:flutter/widgets.dart'
    show FocusHighlightMode, FocusManager, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart' show ThemePref;
import 'package:waxdeck_data/waxdeck_data.dart' show ClientSettingKeys;
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxCaptionMode, WaxDensity;

import '../auth/auth_controller.dart';
import '../player/smart_rewind.dart';
import 'client_settings_providers.dart';
import 'prefs_controller.dart';

/// The per-device preferences, one notifier each.
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

/// A free-text preference.
///
/// Nothing stored here is a secret: this is for the handful of settings
/// whose value is an identifier somebody pastes in. A credential would
/// belong in the credential store, behind the platform's own keyring.
abstract class StringSetting extends Notifier<String>
    with StoredSetting<String> {
  /// The longest value worth believing. A stored string past it reads as
  /// nothing stored, which is what keeps a corrupted row from becoming a
  /// text field nobody can clear.
  int get maxLength => 128;

  @override
  String? decode(String raw) => raw.length > maxLength ? null : raw;

  @override
  String encode(String value) => value;

  @override
  String build() => hydrate();

  void set(String value) {
    final trimmed = value.trim();
    put(trimmed.length > maxLength ? trimmed.substring(0, maxLength) : trimmed);
  }
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

/// Whether a music queue that has run out keeps going with similar
/// music, rather than ending where it was built to end.
///
/// On by default: a queue that stops dead is the thing the setting
/// exists to prevent, and every other player a listener has used
/// continues. Off is the deliberate choice, and the queue surface
/// carries the same switch so it can be made where it is felt.
class KeepPlayingSimilar extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.keepPlayingSimilar;

  @override
  bool get defaultValue => true;
}

final keepPlayingSimilarProvider = NotifierProvider<KeepPlayingSimilar, bool>(
  KeepPlayingSimilar.new,
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

/// Off by default: deleting somebody's files unasked cannot be undone,
/// and the downloads screen already offers the manual sweep.
class AutoRemoveFinished extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.autoRemoveFinished;

  @override
  bool get defaultValue => false;
}

final autoRemoveFinishedProvider = NotifierProvider<AutoRemoveFinished, bool>(
  AutoRemoveFinished.new,
);

/// How long after finishing a download is reclaimed. `finished` flips
/// the instant playback reaches the end, so no window would delete an
/// episode out from under somebody scrubbing back thirty seconds.
class AutoRemoveFinishedAfterHours extends IntSetting {
  static const options = <int>[1, 6, 24, 72, 168];

  @override
  String get settingKey => ClientSettingKeys.autoRemoveFinishedAfterHours;

  @override
  int get minValue => 1;

  @override
  int get maxValue => 168;

  @override
  int get defaultValue => 24;
}

final autoRemoveFinishedAfterHoursProvider =
    NotifierProvider<AutoRemoveFinishedAfterHours, int>(
      AutoRemoveFinishedAfterHours.new,
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

/// Which theme this device draws.
///
/// Per device, and this is the line `client_prefs.dart` opens with: a
/// display theme describes the machine in front of the listener. It was
/// the account's, so a `light` chosen once on the web followed the phone
/// carried outdoors, and the settings row said "Follows you to your other
/// devices" about it.
///
/// [ThemePref.system] by default, so a device nobody has told follows the
/// OS - including a fresh install, which is what the original report was
/// about.
class ThemeSetting extends EnumSetting<ThemePref> {
  @override
  String get settingKey => ClientSettingKeys.theme;

  @override
  ThemePref get defaultValue => ThemePref.system;

  @override
  List<ThemePref> get options => ThemePref.values;

  /// Whether this notifier has already asked. The store holds the
  /// answer that outlives the launch; this only keeps one build from
  /// racing the next.
  var _consideredAccount = false;

  @override
  ThemePref build() {
    // Listened, not watched. What follows is a one-shot migration, and a
    // watch would re-run this notifier - and through it every theme
    // provider the app is built on - on every unrelated write to the
    // account document: a radio pin, a browse sort, a crossfade. Each
    // of those re-runs would also re-fire `hydrate`'s store read, which
    // does not latch until it finds something.
    ref.listen(prefsControllerProvider, (_, next) {
      // Only once a real document is here, which is narrower than
      // `hasValue`: signed out the controller answers the empty
      // default, and a reload keeps that previous value while it runs -
      // so the moment after signing in reads as a document with no
      // theme in it. Spending the one question there marks the device
      // adopted and takes nothing, losing the theme of everybody who
      // signs in.
      if (!next.hasValue || next.isLoading) return;
      final signedIn =
          ref.read(authControllerProvider).value?.authenticated ?? false;
      if (signedIn) unawaited(_adopt(next.requireValue.theme));
    }, fireImmediately: true);
    return hydrate();
  }

  /// Takes the account's theme once, for a device that has none of its
  /// own.
  ///
  /// Without this, everybody who deliberately chose dark or OLED would be
  /// silently flipped to follow-the-system by the build that moved the
  /// setting. Asked exactly once per device, marked as asked either way:
  /// after that the account's field is the deprecated copy the spec says
  /// it is, and a `light` set from another client stays there.
  Future<void> _adopt(ThemePref? account) async {
    if (_consideredAccount) return;
    _consideredAccount = true;
    final store = ref.read(clientSettingsStoreProvider);
    try {
      if (await store.read(ClientSettingKeys.themeAdopted) != null) return;
      // The store rather than [state]: the default and a stored
      // `system` read alike, and only one of them is a choice somebody
      // made.
      final stored = await store.read(settingKey);
      // The value before the mark, both awaited. The mark is what makes
      // this unrepeatable, so it must never outlive a failed write of
      // the thing it records: a store that takes the mark and drops the
      // theme - a locked mirror at launch, a full quota - loses a
      // deliberate OLED for good. This way round the worst case is a
      // second launch that adopts the same value again.
      if (stored == null && account != null) {
        await store.write(settingKey, encode(account));
      }
      await store.write(ClientSettingKeys.themeAdopted, 'y');
      if (stored != null || account == null || !ref.mounted) return;
    } catch (_) {
      // A store that will not answer is not one to write to either.
      return;
    }
    set(account);
  }
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

/// Whether the artwork glow is drawn behind players and entity headers.
///
/// On by default: it is the house look, and light mode has always drawn
/// it at zero, so the off state is a rendering the design system already
/// ships rather than a second one to maintain. What it turns off is the
/// radial wash in the dark themes - the scrim, the wash, and the grain
/// are unaffected, and text contrast is computed against whatever is
/// behind it either way.
class ArtworkGlow extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.artworkGlow;

  @override
  bool get defaultValue => true;
}

/// When cards draw the caption lines under their titles.
///
/// [WaxCaptionMode.always] by default, which is what every grid has
/// always drawn. The other choice is offered because a wall of covers
/// reads better as covers, and it is honoured only where a pointer can
/// ask the caption back - see [cardCaptionsEffectiveProvider].
class CardCaptions extends EnumSetting<WaxCaptionMode> {
  @override
  String get settingKey => ClientSettingKeys.cardCaptions;

  @override
  WaxCaptionMode get defaultValue => WaxCaptionMode.always;

  @override
  List<WaxCaptionMode> get options => WaxCaptionMode.values;
}

final themeSettingProvider = NotifierProvider<ThemeSetting, ThemePref>(
  ThemeSetting.new,
);
final densityProvider = NotifierProvider<Density, WaxDensity>(Density.new);
final gridSizeProvider = NotifierProvider<GridSize, WaxGridSize>(GridSize.new);
final artworkGlowProvider = NotifierProvider<ArtworkGlow, bool>(
  ArtworkGlow.new,
);
final cardCaptionsProvider = NotifierProvider<CardCaptions, WaxCaptionMode>(
  CardCaptions.new,
);

/// Whether this machine has a pointer at all.
///
/// The device question, as against [pointerHighlightProvider]'s "is
/// hovering live this second". They are not the same, and answering one
/// with the other is what made the caption row tell a touchscreen laptop
/// it had no pointer the moment somebody tapped the screen.
final mouseConnectedProvider = Provider<bool>((ref) {
  final tracker = WidgetsBinding.instance.mouseTracker;
  void changed() => ref.invalidateSelf();
  tracker.addListener(changed);
  ref.onDispose(() => tracker.removeListener(changed));
  return tracker.mouseIsConnected;
});

/// Whether this session is in the input mode where hover and focus
/// highlights are reported at all.
///
/// Not "is a mouse plugged in", which is the tempting and wrong
/// question. `FocusableActionDetector` - the thing that reveals a
/// hidden caption - reports no hover while the highlight mode is touch,
/// and a Windows touchscreen laptop, a Chromebook, or a tablet with a
/// mouse paired sits in touch mode for as long as the last input was a
/// finger. Watching the mode rather than the hardware makes the guard
/// exact: it is true precisely when hovering or focusing can bring a
/// caption back, and it flips the moment the pointer moves.
///
/// It flips to touch on any touch-down, which is right for the question
/// it answers and wrong for the question of whether the setting is worth
/// offering: a hybrid machine is in touch mode for as long as the last
/// input was a finger, and it still has the mouse it had a second ago.
/// [mouseConnectedProvider] is the one to ask about the hardware.
final pointerHighlightProvider = Provider<bool>((ref) {
  void changed(FocusHighlightMode _) => ref.invalidateSelf();
  FocusManager.instance.addHighlightModeListener(changed);
  ref.onDispose(
    () => FocusManager.instance.removeHighlightModeListener(changed),
  );
  return FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
});

/// The caption mode the themes are actually built with.
///
/// Hover is the only way back to a hidden caption, so where hovering
/// reports nothing the setting is not honoured. Deliberately
/// one-directional: the failure mode of guessing wrong here is a caption
/// that shows when somebody asked for it to hide, never a name nobody
/// can reach.
final cardCaptionsEffectiveProvider = Provider<WaxCaptionMode>((ref) {
  if (!ref.watch(pointerHighlightProvider)) return WaxCaptionMode.always;
  return ref.watch(cardCaptionsProvider);
});

/// What every artwork grid multiplies its own base tile extent by.
///
/// A scale rather than a size, because the grids do not agree on a base
/// and should not: a station tile is square and a show tile is a cover,
/// and the layout system already varies both by size class. This says
/// bigger or smaller than whatever that screen decided.
final gridScaleProvider = Provider<double>(
  (ref) => ref.watch(gridSizeProvider).scale,
);

// --- integrations ------------------------------------------------------------

/// Whether this desktop publishes "Listening to WaxDeck" to a Discord
/// client running beside it.
///
/// Off by default, and per device rather than per account, because that
/// is what it is: presence is set through the Discord client's own local
/// socket, so the two programs have to be on the same machine. A phone
/// signed in to the same account is not publishing anything.
class DiscordPresenceEnabled extends BoolSetting {
  @override
  String get settingKey => ClientSettingKeys.discordPresence;

  @override
  bool get defaultValue => false;
}

final discordPresenceEnabledProvider =
    NotifierProvider<DiscordPresenceEnabled, bool>(DiscordPresenceEnabled.new);

/// Which registered Discord application the presence is published as.
///
/// An override, and empty is the ordinary case: WaxDeck has one of its
/// own (`kWaxDeckDiscordApplicationId`), and this is here for somebody
/// who would rather publish under an application they registered - a
/// different name after "Listening to", or their own cover art. A public
/// snowflake from the developer portal, not a credential.
class DiscordApplicationId extends StringSetting {
  @override
  String get settingKey => ClientSettingKeys.discordApplicationId;

  @override
  String get defaultValue => '';

  /// A snowflake is at most twenty digits; the slack is for a paste with
  /// something on the end of it, which [set] trims.
  @override
  int get maxLength => 32;
}

final discordApplicationIdProvider =
    NotifierProvider<DiscordApplicationId, String>(DiscordApplicationId.new);

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
