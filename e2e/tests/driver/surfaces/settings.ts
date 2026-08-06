// Settings: sections that are locations, and a search over the whole
// registry.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough, typeInto } from '../gestures';

export class Settings {
  constructor(private readonly ctx: Ctx) {}

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
  async choose(name: string, option: Locator, settled?: Locator): Promise<void> {
    await chooseFromMenu(this.setting(name), option, settled);
  }

  /// A control this account's settings draw that has its own identifier -
  /// the scrobbling switches, the theme picker, the sign-out row.
  control(id: string): Locator {
    return this.ctx.page.locator(sem(id));
  }

  /// Open a row that leads somewhere, and wait for what it opens.
  async openSetting(name: string, lands: string): Promise<void> {
    await clickThrough(this.setting(name), this.control(lands));
  }

  /// A row in an open menu, by the label a person reads. Menus draw no
  /// identifier per option, so this is the "no id exists" case the copy
  /// rule allows a driver - and what the label says is still the spec's
  /// to assert, since the spec is what names it here.
  menuItem(name: string): Locator {
    return this.ctx.page.getByRole('menuitem', { name });
  }

  /// A switch by its accessible name. Same reasoning as `menuItem`, and
  /// deliberately not forced: this screen settles, so Playwright's own
  /// stability wait is the right one - a forced click at a rect read a
  /// moment earlier lands on whatever moved into that spot while the
  /// rows above finished loading their connection state.
  switchNamed(name: string | RegExp): Locator {
    return this.ctx.page.getByRole('switch', { name });
  }

  /// A control by its accessible name, for asserting what a chosen value
  /// reads as.
  buttonNamed(name: string | RegExp): Locator {
    return this.ctx.page.getByRole('button', { name });
  }

  /// Text on the screen, for the rows that are prose rather than
  /// controls - the version numbers About reports.
  text(what: string | RegExp, exact = false): Locator {
    return this.ctx.page.getByText(what, { exact });
  }

  async ready(): Promise<void> {
    await this.search().waitFor({ timeout: T.nav });
  }
}
