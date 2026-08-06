// What every surface needs to do its job.

import { Page } from '@playwright/test';
import { Account } from '../accounts';
import { Api } from './api';

/// What every surface needs: a page to drive, an API hand for the
/// server side, and whose account this is.
export interface Ctx {
  readonly page: Page;
  readonly api: Api;
  readonly account: Account;
}

