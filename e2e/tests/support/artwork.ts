// The artwork endpoint's "no cover", told apart from trouble.
//
// An item with nothing anywhere in its fallback chain answers its art URL
// with a 404 - the contract says so, and the client draws a monogram for
// it - and the fixture library has almost no covers, so a page that lists
// it makes dozens of these a minute. Chrome echoes each one as a console
// error whose location is the art URL. A spec that watches the page for
// trouble leaves both out rather than reading a designed answer as a
// failure; anything else that 404s is still trouble.

const ART = /\/api\/v1\/items\/[^/?#]+\/art(?:[?#]|$)/;

/// A response that is the artwork endpoint saying there is no cover.
export const isNoCover = (status: number, url: string) => status === 404 && ART.test(url);

/// Chrome's console echo of such a response.
export const isNoCoverEcho = (text: string, location: string) =>
  text.includes('status of 404') && ART.test(location);
