// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers =
    (Serializers().toBuilder()
          ..add($AppPassword.serializer)
          ..add($EpisodeSummary.serializer)
          ..add($ItemSummary.serializer)
          ..add($User.serializer)
          ..add(AppPasswordCreate.serializer)
          ..add(AppPasswordCreated.serializer)
          ..add(AppPasswordList.serializer)
          ..add(BookDetail.serializer)
          ..add(BookPart.serializer)
          ..add(BookResume.serializer)
          ..add(BookSettings.serializer)
          ..add(BootstrapRequest.serializer)
          ..add(BootstrapStatus.serializer)
          ..add(CastPreflight.serializer)
          ..add(CastPreflightBase.serializer)
          ..add(CatalogSyncEntry.serializer)
          ..add(CatalogSyncPage.serializer)
          ..add(ChapterMark.serializer)
          ..add(DeviceSession.serializer)
          ..add(DeviceSessionKindEnum.serializer)
          ..add(DiscoveryList.serializer)
          ..add(DownloadFile.serializer)
          ..add(DownloadInfo.serializer)
          ..add(Episode.serializer)
          ..add(EpisodePage.serializer)
          ..add(Error.serializer)
          ..add(Health.serializer)
          ..add(Item.serializer)
          ..add(ItemPage.serializer)
          ..add(Job.serializer)
          ..add(LastfmConnectStart.serializer)
          ..add(Libraries.serializer)
          ..add(LibraryAccess.serializer)
          ..add(LibraryAccessModeEnum.serializer)
          ..add(LinkedIdentity.serializer)
          ..add(ListenBrainzConnect.serializer)
          ..add(ListenIngestResult.serializer)
          ..add(ListenReport.serializer)
          ..add(ListenSession.serializer)
          ..add(ListenSessionSource_Enum.serializer)
          ..add(LoginRequest.serializer)
          ..add(LoginResponse.serializer)
          ..add(Lyrics.serializer)
          ..add(M3uImport.serializer)
          ..add(M3uImportResult.serializer)
          ..add(MediaType.serializer)
          ..add(ModelLibrary.serializer)
          ..add(NotificationConfig.serializer)
          ..add(NotificationConfigUpdate.serializer)
          ..add(OidcExchangeRequest.serializer)
          ..add(OidcProvider.serializer)
          ..add(OidcProviders.serializer)
          ..add(OpmlImport.serializer)
          ..add(OpmlImportEntry.serializer)
          ..add(OpmlImportResult.serializer)
          ..add(PasswordChange.serializer)
          ..add(PlayInfo.serializer)
          ..add(PlayState.serializer)
          ..add(PlayStateList.serializer)
          ..add(PlayStateQuery.serializer)
          ..add(PlayStateUpdate.serializer)
          ..add(PlaybackSession.serializer)
          ..add(PlaybackSessionCreate.serializer)
          ..add(PlaybackSessionEntry.serializer)
          ..add(PlaybackSessionList.serializer)
          ..add(PlaybackSessionTransfer.serializer)
          ..add(PlayerEndpoint.serializer)
          ..add(PlayerEndpointList.serializer)
          ..add(Playlist.serializer)
          ..add(PlaylistCreate.serializer)
          ..add(PlaylistEntry.serializer)
          ..add(PlaylistItemsPage.serializer)
          ..add(PlaylistItemsUpdate.serializer)
          ..add(PlaylistPage.serializer)
          ..add(PlaylistPreview.serializer)
          ..add(PlaylistUpdate.serializer)
          ..add(PodcastDetail.serializer)
          ..add(PodcastShow.serializer)
          ..add(Prefs.serializer)
          ..add(PrefsThemeEnum.serializer)
          ..add(PushRegistration.serializer)
          ..add(PushRegistrationCreate.serializer)
          ..add(PushRegistrationList.serializer)
          ..add(RadioDirectoryEntry.serializer)
          ..add(RadioDirectoryResults.serializer)
          ..add(RadioPlayInfo.serializer)
          ..add(RadioStation.serializer)
          ..add(RadioStationEdit.serializer)
          ..add(RadioStationList.serializer)
          ..add(RatingUpdate.serializer)
          ..add(RefreshResult.serializer)
          ..add(RejectedListen.serializer)
          ..add(Role.serializer)
          ..add(RuleField.serializer)
          ..add(RuleFields.serializer)
          ..add(RuleNode.serializer)
          ..add(RuleSort.serializer)
          ..add(RuleTagKey.serializer)
          ..add(Scrobbler.serializer)
          ..add(ScrobblerList.serializer)
          ..add(SearchHit.serializer)
          ..add(SearchResults.serializer)
          ..add(ServerSyncEvent.serializer)
          ..add(ServerSyncPage.serializer)
          ..add(SessionInfo.serializer)
          ..add(SessionList.serializer)
          ..add(SkipMap.serializer)
          ..add(SkipSpan.serializer)
          ..add(SmartRule.serializer)
          ..add(StarUpdate.serializer)
          ..add(SubscribeRequest.serializer)
          ..add(Subscription.serializer)
          ..add(SubscriptionPage.serializer)
          ..add(SubscriptionSettings.serializer)
          ..add(SyncedLine.serializer)
          ..add(TimelineBoundary.serializer)
          ..add(TimelineCreate.serializer)
          ..add(TimelineInfo.serializer)
          ..add(Transcript.serializer)
          ..add(TranscriptCue.serializer)
          ..add(UserAccount.serializer)
          ..add(UserCreate.serializer)
          ..add(UserPage.serializer)
          ..add(UserUpdate.serializer)
          ..add(WsAckFrame.serializer)
          ..add(WsCommandFrame.serializer)
          ..add(WsCommandResultFrame.serializer)
          ..add(WsEndpointCommandFrame.serializer)
          ..add(WsErrorFrame.serializer)
          ..add(WsEventFrame.serializer)
          ..add(WsPingFrame.serializer)
          ..add(WsPongFrame.serializer)
          ..add(WsRegisterEndpointFrame.serializer)
          ..add(WsSessionFrame.serializer)
          ..add(WsSessionReportFrame.serializer)
          ..add(WsSubscribeFrame.serializer)
          ..add(WsWatchFrame.serializer)
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(AppPassword)]),
            () => ListBuilder<AppPassword>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(CastPreflightBase),
            ]),
            () => ListBuilder<CastPreflightBase>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(CatalogSyncEntry)]),
            () => ListBuilder<CatalogSyncEntry>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ChapterMark)]),
            () => ListBuilder<ChapterMark>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(DeviceSession)]),
            () => ListBuilder<DeviceSession>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(DownloadFile)]),
            () => ListBuilder<DownloadFile>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(EpisodeSummary)]),
            () => ListBuilder<EpisodeSummary>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ItemSummary)]),
            () => ListBuilder<ItemSummary>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ItemSummary)]),
            () => ListBuilder<ItemSummary>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(LinkedIdentity)]),
            () => ListBuilder<LinkedIdentity>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ListenSession)]),
            () => ListBuilder<ListenSession>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ModelLibrary)]),
            () => ListBuilder<ModelLibrary>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(OidcProvider)]),
            () => ListBuilder<OidcProvider>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(OpmlImportEntry)]),
            () => ListBuilder<OpmlImportEntry>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(PlayState)]),
            () => ListBuilder<PlayState>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(PlaybackSession)]),
            () => ListBuilder<PlaybackSession>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(PlaybackSessionEntry),
            ]),
            () => ListBuilder<PlaybackSessionEntry>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(PlayerEndpoint)]),
            () => ListBuilder<PlayerEndpoint>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Playlist)]),
            () => ListBuilder<Playlist>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(PlaylistEntry)]),
            () => ListBuilder<PlaylistEntry>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(PushRegistration)]),
            () => ListBuilder<PushRegistration>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(RadioDirectoryEntry),
            ]),
            () => ListBuilder<RadioDirectoryEntry>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(RadioStation)]),
            () => ListBuilder<RadioStation>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(RejectedListen)]),
            () => ListBuilder<RejectedListen>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Role)]),
            () => ListBuilder<Role>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Role)]),
            () => ListBuilder<Role>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(RuleField)]),
            () => ListBuilder<RuleField>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(RuleTagKey)]),
            () => ListBuilder<RuleTagKey>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(RuleNode)]),
            () => ListBuilder<RuleNode>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(RuleSort)]),
            () => ListBuilder<RuleSort>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Scrobbler)]),
            () => ListBuilder<Scrobbler>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SearchHit)]),
            () => ListBuilder<SearchHit>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SearchHit)]),
            () => ListBuilder<SearchHit>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SearchHit)]),
            () => ListBuilder<SearchHit>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SearchHit)]),
            () => ListBuilder<SearchHit>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SearchHit)]),
            () => ListBuilder<SearchHit>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ServerSyncEvent)]),
            () => ListBuilder<ServerSyncEvent>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SkipSpan)]),
            () => ListBuilder<SkipSpan>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ChapterMark)]),
            () => ListBuilder<ChapterMark>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(BookPart)]),
            () => ListBuilder<BookPart>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Subscription)]),
            () => ListBuilder<Subscription>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(SyncedLine)]),
            () => ListBuilder<SyncedLine>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(TimelineBoundary)]),
            () => ListBuilder<TimelineBoundary>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(TranscriptCue)]),
            () => ListBuilder<TranscriptCue>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(UserAccount)]),
            () => ListBuilder<UserAccount>(),
          ))
        .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
