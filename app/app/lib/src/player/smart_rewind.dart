/// How far a spoken-word resume steps back for context.
///
/// Coming back to a book after a night is coming back mid-sentence, and
/// the sentence before it is what makes the next one make sense. The
/// step is a seek in the resume path, so nothing about listen accounting
/// changes: the time is heard twice and counted twice, exactly as it
/// would be if the listener scrubbed back by hand.
///
/// Music is excluded on purpose. A track resumed a day later starts
/// where it stopped, and rewinding three seconds into a song is noise
/// rather than context.
enum SmartRewind {
  /// Resume where the checkpoint says, and nowhere else.
  off(<_Step>[]),

  /// The default ladder: a beat after a break, a sentence after an
  /// hour, a paragraph after a day.
  short(<_Step>[
    _Step(Duration(minutes: 5), Duration(seconds: 3)),
    _Step(Duration(hours: 1), Duration(seconds: 10)),
    _Step(Duration(days: 1), Duration(seconds: 30)),
  ]),

  /// Twice the ladder, for listeners who lose the thread faster than
  /// three seconds recovers.
  long(<_Step>[
    _Step(Duration(minutes: 5), Duration(seconds: 6)),
    _Step(Duration(hours: 1), Duration(seconds: 20)),
    _Step(Duration(days: 1), Duration(minutes: 1)),
  ]);

  const SmartRewind(this._ladder);

  /// Thresholds in ascending order; the last one crossed wins.
  final List<_Step> _ladder;

  /// How far back a resume goes after a pause of [gap].
  ///
  /// Zero below the first threshold, which is the ordinary case: a
  /// pause to answer a question is not a pause that lost the thread,
  /// and stepping back for it would make the transport feel broken.
  Duration rewindFor(Duration gap) {
    var back = Duration.zero;
    for (final step in _ladder) {
      if (gap >= step.after) back = step.by;
    }
    return back;
  }

  /// What the setting's picker says for this option.
  String get label => switch (this) {
    SmartRewind.off => 'Off',
    SmartRewind.short => 'A little',
    SmartRewind.long => 'More',
  };
}

class _Step {
  const _Step(this.after, this.by);

  /// How long the pause has to be for this step to apply.
  final Duration after;

  /// How far back it goes.
  final Duration by;
}
