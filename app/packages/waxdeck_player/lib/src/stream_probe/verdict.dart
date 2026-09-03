/// What `probeStream` found at the other end of a stream URL.
///
/// Its own file so both platform halves can import it without importing
/// the library that conditionally exports them.
///
/// Three answers rather than two, because a server can refuse in a way
/// that is about the file rather than about the way to it: a 415 is an
/// endpoint saying it will not serve this as audio, and that is the same
/// verdict Android's renderer gives from inside the player.
enum StreamProbe {
  /// The URL answered with bytes.
  answered,

  /// The server would not make audio out of the file: 415, which our
  /// own sidecar returns for `unsupported-format` - bytes its decoder
  /// will not take, and a shape it cannot build from them. Which of the
  /// two it was does not change the answer here: no number of retries
  /// makes this URL play.
  unplayable,

  /// Nothing usable came back: a status that is neither, a refused
  /// connection, a scheme this cannot ask, the deadline.
  unreachable;

  /// Whether this verdict puts a failed load on the media rather than
  /// on the way to it.
  ///
  /// Written as the two that say yes rather than as "not unreachable",
  /// because the module's rule is that only positive evidence answers
  /// `MediaFault.source` - the answer that moves a queue. A switch over
  /// the enum makes a verdict added later a compile error here rather
  /// than a silent skip.
  ///
  /// The two that do are different evidence for one conclusion. An
  /// answered URL says the bytes were there and the player still could
  /// not finish, which is what garbage on disk looks like from out
  /// here; a refusal says the server reached that verdict first. Both
  /// are the file, and the file is what a queue may step past.
  bool get blamesMedia => switch (this) {
    StreamProbe.answered || StreamProbe.unplayable => true,
    StreamProbe.unreachable => false,
  };
}
