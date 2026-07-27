/// Native clients ship their own binary: nothing here can replace it.
const bool canReloadPage = false;

void reloadPage() {
  throw UnsupportedError('reloading the page is a web-only path');
}
