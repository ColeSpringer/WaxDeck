/// When a URL minted under a media token that the server says expires at
/// [expiresAt] stops working on this device's clock, read at [now]: a
/// minute early, since the two clocks need not agree. A clock already
/// past that runs ahead of the server's by more than the token's whole
/// life, and holds the URL ten minutes; a refusal says the rest.
DateTime mediaUrlStaleAt(DateTime expiresAt, {required DateTime now}) {
  final staleAt = expiresAt.subtract(const Duration(minutes: 1));
  return now.isBefore(staleAt) ? staleAt : now.add(const Duration(minutes: 10));
}
