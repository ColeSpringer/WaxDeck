/// Non-web platforms never navigate the current page.
void navigateSameTab(String url) {
  throw UnsupportedError('same-tab navigation is a web-only path');
}
