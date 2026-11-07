import '../models.dart';

/// Podcast subscriptions, episodes and OPML.
abstract interface class PodcastsApi {
  /// `GET /podcasts`: keyset-paginated list of the caller's podcast
  /// subscriptions, ordered by show title then pid.
  Future<SubscriptionPage> listSubscriptions({String? cursor, int? limit});

  /// `POST /podcasts`: subscribes the caller to a show, cataloging it on
  /// first subscription. [sourceType] is `rss` (default) or `youtube`;
  /// supplying credentials marks the show private.
  Future<Subscription> subscribePodcast({
    required String url,
    String? sourceType,
    String? username,
    String? password,
    String? folder,
  });

  /// `GET /podcasts/directory`: searches the public podcast directory by
  /// show name. Every match carries the feed URL to subscribe with.
  Future<List<PodcastDirectoryEntry>> searchPodcastDirectory(
    String query, {
    int? limit,
  });

  /// `GET /podcasts/{pid}`: show detail with the caller's subscription
  /// state, for any cataloged show.
  Future<PodcastDetail> getPodcast(String pid);

  /// `DELETE /podcasts/{pid}`: removes the caller's subscription. Never
  /// destructive to the catalog; a no-op when not subscribed. With
  /// [removeDownloads], and only when the caller was the show's last
  /// subscriber, the downloaded audio moves to the server trash.
  Future<void> unsubscribePodcast(String pid, {bool removeDownloads});

  /// `PUT /podcasts/{pid}/settings`: full replace of the caller's
  /// per-subscription settings; absent fields reset to defaults, so
  /// senders start from the stored value.
  Future<Subscription> putSubscriptionSettings(
    String pid,
    SubscriptionSettings settings,
  );

  /// `GET /podcasts/{pid}/episodes`: keyset-paginated episodes, newest
  /// first.
  Future<EpisodePage> listEpisodes(String pid, {String? cursor, int? limit});

  /// `GET /episodes/{pid}`: full episode detail with sanitized show
  /// notes and chapter marks.
  Future<EpisodeDetail> getEpisode(String pid);

  /// `GET /episodes/{pid}/transcript`: the episode's transcript as
  /// time-coded cues; the first call may take a moment while the server
  /// fetches and caches it.
  Future<Transcript> getEpisodeTranscript(String pid);

  /// `POST /episodes/{pid}/transcript`: indexes the episode's transcript
  /// text for search without downloading the audio, so a streamed episode
  /// turns up in transcript search. A no-op success when already indexed.
  Future<void> captureEpisodeTranscript(String pid);

  /// `POST /episodes/{pid}/fetch`: queues a server-side download of the
  /// episode's audio. A no-op success when already downloaded or queued.
  Future<void> fetchEpisode(String pid);

  /// `DELETE /episodes/{pid}/fetch`: removes an episode's fetched audio
  /// from the server (archive, not delete: playback state survives and the
  /// episode stays fetchable).
  Future<void> removeEpisodeDownload(String pid);

  /// `POST /podcasts/{pid}/refresh`: fetches the feed now and reports
  /// how many episodes appeared. Subscribers only; a successful refresh
  /// re-enables a feed auto-disabled after repeated failures.
  Future<RefreshResult> refreshPodcast(String pid);

  /// `GET /podcasts/episodes`: episodes across every show the caller
  /// follows. [filter] picks which and, with it, the order: `latest` and
  /// `unplayed` are newest published first, `in-progress` is
  /// most-recently-played first. A cursor is only valid for the filter
  /// it was issued under.
  Future<EpisodePage> listSubscribedEpisodes({
    SubscribedEpisodes filter,
    String? cursor,
    int? limit,
  });

  /// `GET /podcasts/opml`: the caller's subscriptions as an OPML 2.0
  /// document.
  Future<String> exportOpml();

  /// `POST /podcasts/opml`: subscribes the caller to every feed in the
  /// document and answers each feed's outcome; per-feed failures do not
  /// fail the import.
  Future<List<OpmlImportOutcome>> importOpml(String opml);
}
