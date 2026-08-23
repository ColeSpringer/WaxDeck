// Settings: sections that are locations, and a search over the whole
// registry.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough, typeInto, wheelIntoViewport } from '../gestures';

export class Settings extends Surface {
  search(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.settingsSearch));
  }

  section(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.settingsSection(name)));
  }

  /// One setting's control, by the registry name the app draws it under.
  setting(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.setting(name)));
  }

  result(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.settingsResult(name)));
  }

  /// Open a section and wait for one of its settings, which is what
  /// proves the section rather than the list is on screen.
  async openSection(name: string, containing: string): Promise<void> {
    await clickThrough(this.section(name), this.setting(containing));
  }

  /// Open a section by its own location, cold. Sections are links a
  /// stranger can follow, which is what makes "it is under Playback"
  /// something you can send somebody.
  async enterSection(name: string, showing: Locator): Promise<void> {
    await this.ctx.page.goto(`/settings/${name}`);
    await showing.waitFor({ timeout: T.nav });
  }

  /// The same, for a section whose landmark control publishes its own
  /// handle rather than a `setting-<id>` - the scrobbling switches do.
  async openSectionShowing(name: string, id: string): Promise<void> {
    await clickThrough(this.section(name), this.control(id));
  }

  /// Type into the settings search and open what it finds. The registry's
  /// keywords are what make another app's vocabulary land here, so a word
  /// that appears in no setting's name still finds it.
  async findAndOpen(query: string, result: string, lands: string): Promise<void> {
    await typeInto(this.ctx.page, this.search(), query);
    await clickThrough(this.result(result), this.setting(lands));
  }

  /// Choose a value from a setting's menu. The menu-at-rest wait lives in
  /// the gesture: near a screen edge a popup is repositioned as it grows,
  /// and a click at a rect read a frame earlier lands one row off.
  ///
  /// Wheeled into the viewport first: a section is longer than the
  /// window, and a row below the fold still reports visible.
  async choose(name: string, option: Locator, settled?: Locator): Promise<void> {
    const trigger = this.setting(name);
    await wheelIntoViewport(this.ctx.page, trigger);
    await chooseFromMenu(trigger, option, settled);
  }


  /// Open a row that leads somewhere, and wait for what it opens.
  async openSetting(name: string, lands: string): Promise<void> {
    await clickThrough(this.setting(name), this.control(lands));
  }

  /// A row in an open setting menu, by the value it stands for. Not by
  /// the label: that is copy, and it translates. What the row reads is
  /// still the spec's to assert, through `buttonNamed`.
  option(setting: string, value: string | number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.settingOption(setting, value)));
  }

  /// A switch by its accessible name - the "no id exists" case the copy
  /// rule allows a driver. Deliberately not forced: this screen settles,
  /// so a forced click at a rect read a moment earlier lands on whatever
  /// moved into that spot while the rows above finished loading.
  switchNamed(name: string | RegExp): Locator {
    return this.ctx.page.getByRole('switch', { name });
  }

  /// A control by its accessible name, for asserting what a chosen value
  /// reads as.
  buttonNamed(name: string | RegExp): Locator {
    return this.ctx.page.getByRole('button', { name });
  }

  /// Plant a device preference before the app next boots, for a spec
  /// whose subject one of the defaults would otherwise hide.
  ///
  /// These never reach the server - they describe the device, and the
  /// app keeps them in `localStorage` - so there is no API hand for
  /// them and no session to carry them. Walking the settings screen
  /// instead would work and is what `openSection` is for; this is the
  /// cheaper form for a spec that only needs the state, not the walk.
  ///
  /// Applies from the next navigation, which `nav.enter` always is.
  async presetDevice(pref: DevicePref, value: string): Promise<void> {
    await this.ctx.page.addInitScript(
      ([key, stored]) => {
        try {
          window.localStorage.setItem(key, stored);
        } catch {
          // A browser refusing site data leaves the default standing,
          // which is a spec that fails rather than one that lies.
        }
      },
      [pref, value] as const,
    );
  }
}

/// The device preferences a spec may plant, spelled as the app stores
/// them.
///
/// The app's own list is `ClientSettingKeys` in
/// `app/packages/waxdeck_data/lib/src/client_settings_store.dart`.
/// Unlike the semantics identifiers, these are not generated into the
/// suite, so a key named here is a duplicated spelling; keep the list to
/// the ones a spec actually plants.
export const DevicePref = {
  /// Whether a music queue that has run out keeps going with similar
  /// music. On by default.
  keepPlayingSimilar: 'waxdeck.playback.keepPlayingSimilar',
} as const;

export type DevicePref = (typeof DevicePref)[keyof typeof DevicePref];
