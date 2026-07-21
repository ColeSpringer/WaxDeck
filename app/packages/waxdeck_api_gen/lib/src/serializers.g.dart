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
          ..add($ReviewEntry.serializer)
          ..add($User.serializer)
          ..add(AcquisitionFormat.serializer)
          ..add(AcquisitionRequest.serializer)
          ..add(AppPasswordCreate.serializer)
          ..add(AppPasswordCreated.serializer)
          ..add(AppPasswordList.serializer)
          ..add(BookDetail.serializer)
          ..add(BookMergeRequest.serializer)
          ..add(BookPart.serializer)
          ..add(BookResume.serializer)
          ..add(BookSettings.serializer)
          ..add(BookSplitRequest.serializer)
          ..add(BootstrapRequest.serializer)
          ..add(BootstrapStatus.serializer)
          ..add(BulkEdit.serializer)
          ..add(BulkEditResult.serializer)
          ..add(CandidateComponent.serializer)
          ..add(CandidatePairing.serializer)
          ..add(CandidateSummary.serializer)
          ..add(CastPreflight.serializer)
          ..add(CastPreflightBase.serializer)
          ..add(CatalogSyncEntry.serializer)
          ..add(CatalogSyncPage.serializer)
          ..add(ChapterMark.serializer)
          ..add(ChaptersEdit.serializer)
          ..add(CoverageCount.serializer)
          ..add(Credit.serializer)
          ..add(CreditsEdit.serializer)
          ..add(CueSplitRequest.serializer)
          ..add(CustomTag.serializer)
          ..add(DeviceSession.serializer)
          ..add(DeviceSessionKindEnum.serializer)
          ..add(DiscoveryList.serializer)
          ..add(DownloadFile.serializer)
          ..add(DownloadInfo.serializer)
          ..add(DuplicateEntity.serializer)
          ..add(DuplicateGroup.serializer)
          ..add(DuplicateGroups.serializer)
          ..add(DuplicateWarning.serializer)
          ..add(EditableField.serializer)
          ..add(EnrichItemRequest.serializer)
          ..add(EnrichItemRequestWantEnum.serializer)
          ..add(EnrichItemResult.serializer)
          ..add(EnrichmentCoverage.serializer)
          ..add(EnrichmentProvider.serializer)
          ..add(EnrichmentRunRequest.serializer)
          ..add(EnrichmentRunResult.serializer)
          ..add(EnrichmentStatus.serializer)
          ..add(EntityCuratedField.serializer)
          ..add(EntityCuration.serializer)
          ..add(EntityEdit.serializer)
          ..add(EntityTypeFields.serializer)
          ..add(Episode.serializer)
          ..add(EpisodePage.serializer)
          ..add(Error.serializer)
          ..add(FieldProvenance.serializer)
          ..add(Health.serializer)
          ..add(HealthFixRequest.serializer)
          ..add(HealthFixResult.serializer)
          ..add(HealthIssue.serializer)
          ..add(HealthIssuePage.serializer)
          ..add(HealthRuleCount.serializer)
          ..add(HealthSummary.serializer)
          ..add(Item.serializer)
          ..add(ItemMetadata.serializer)
          ..add(ItemPage.serializer)
          ..add(Job.serializer)
          ..add(KindFields.serializer)
          ..add(LastfmConnectStart.serializer)
          ..add(Libraries.serializer)
          ..add(LibraryAccess.serializer)
          ..add(LibraryAccessModeEnum.serializer)
          ..add(LibraryMatching.serializer)
          ..add(LibraryMatchingModeEnum.serializer)
          ..add(LinkedIdentity.serializer)
          ..add(ListenBrainzConnect.serializer)
          ..add(ListenIngestResult.serializer)
          ..add(ListenReport.serializer)
          ..add(ListenSession.serializer)
          ..add(ListenSessionSource_Enum.serializer)
          ..add(LocksEdit.serializer)
          ..add(LocksResult.serializer)
          ..add(LoginRequest.serializer)
          ..add(LoginResponse.serializer)
          ..add(Lyrics.serializer)
          ..add(LyricsEdit.serializer)
          ..add(LyricsState.serializer)
          ..add(M3uImport.serializer)
          ..add(M3uImportResult.serializer)
          ..add(MediaType.serializer)
          ..add(MergeRequest.serializer)
          ..add(MergeRequestEntityTypeEnum.serializer)
          ..add(MergeResult.serializer)
          ..add(MetadataEdit.serializer)
          ..add(MetadataEditResult.serializer)
          ..add(MetadataFields.serializer)
          ..add(ModelLibrary.serializer)
          ..add(NotificationConfig.serializer)
          ..add(NotificationConfigUpdate.serializer)
          ..add(OidcExchangeRequest.serializer)
          ..add(OidcProvider.serializer)
          ..add(OidcProviders.serializer)
          ..add(OpmlImport.serializer)
          ..add(OpmlImportEntry.serializer)
          ..add(OpmlImportResult.serializer)
          ..add(OrganizeAction.serializer)
          ..add(OrganizeFailure.serializer)
          ..add(OrganizePlan.serializer)
          ..add(OrganizeProfile.serializer)
          ..add(OrganizeProfiles.serializer)
          ..add(OrganizeReport.serializer)
          ..add(OrganizeRequest.serializer)
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
          ..add(ReleaseStatusEdit.serializer)
          ..add(RematchResult.serializer)
          ..add(ReviewBulkDecision.serializer)
          ..add(ReviewBulkDecisionActionEnum.serializer)
          ..add(ReviewBulkOutcome.serializer)
          ..add(ReviewBulkResult.serializer)
          ..add(ReviewCandidate.serializer)
          ..add(ReviewDecideResult.serializer)
          ..add(ReviewDecision.serializer)
          ..add(ReviewDecisionActionEnum.serializer)
          ..add(ReviewEntryDetail.serializer)
          ..add(ReviewEntryPage.serializer)
          ..add(ReviewStats.serializer)
          ..add(ReviewTrack.serializer)
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
          ..add(TagEdit.serializer)
          ..add(TagEditResult.serializer)
          ..add(TimelineBoundary.serializer)
          ..add(TimelineCreate.serializer)
          ..add(TimelineInfo.serializer)
          ..add(ToolTask.serializer)
          ..add(ToolTaskPage.serializer)
          ..add(Transcript.serializer)
          ..add(TranscriptCue.serializer)
          ..add(UpgradeGroup.serializer)
          ..add(UpgradeGroups.serializer)
          ..add(UpgradeMember.serializer)
          ..add(UpgradeResolveRequest.serializer)
          ..add(UpgradeResolveResult.serializer)
          ..add(Upload.serializer)
          ..add(UploadCreate.serializer)
          ..add(UploadPage.serializer)
          ..add(UserAccount.serializer)
          ..add(UserCreate.serializer)
          ..add(UserPage.serializer)
          ..add(UserUpdate.serializer)
          ..add(WriteBackFailure.serializer)
          ..add(WriteBackIssue.serializer)
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
              const FullType(CandidateComponent),
            ]),
            () => ListBuilder<CandidateComponent>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(CandidatePairing)]),
            () => ListBuilder<CandidatePairing>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(int)]),
            () => ListBuilder<int>(),
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
            const FullType(BuiltList, const [const FullType(DuplicateEntity)]),
            () => ListBuilder<DuplicateEntity>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(DuplicateGroup)]),
            () => ListBuilder<DuplicateGroup>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(EditableField)]),
            () => ListBuilder<EditableField>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(EditableField)]),
            () => ListBuilder<EditableField>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(EditableField)]),
            () => ListBuilder<EditableField>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(EnrichItemRequestWantEnum),
            ]),
            () => ListBuilder<EnrichItemRequestWantEnum>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(EnrichmentProvider),
            ]),
            () => ListBuilder<EnrichmentProvider>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [
              const FullType(EntityCuratedField),
            ]),
            () => ListBuilder<EntityCuratedField>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(EpisodeSummary)]),
            () => ListBuilder<EpisodeSummary>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(HealthIssue)]),
            () => ListBuilder<HealthIssue>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(HealthRuleCount)]),
            () => ListBuilder<HealthRuleCount>(),
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
            const FullType(BuiltList, const [const FullType(KindFields)]),
            () => ListBuilder<KindFields>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(EntityTypeFields)]),
            () => ListBuilder<EntityTypeFields>(),
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
            const FullType(BuiltList, const [const FullType(OrganizeAction)]),
            () => ListBuilder<OrganizeAction>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(OrganizeFailure)]),
            () => ListBuilder<OrganizeFailure>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(OrganizeProfile)]),
            () => ListBuilder<OrganizeProfile>(),
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
            const FullType(BuiltList, const [
              const FullType(ReviewBulkOutcome),
            ]),
            () => ListBuilder<ReviewBulkOutcome>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ReviewCandidate)]),
            () => ListBuilder<ReviewCandidate>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ReviewTrack)]),
            () => ListBuilder<ReviewTrack>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ReviewEntry)]),
            () => ListBuilder<ReviewEntry>(),
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
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(WriteBackFailure)]),
            () => ListBuilder<WriteBackFailure>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, const [
              const FullType(String),
              const FullType(String),
            ]),
            () => MapBuilder<String, String>(),
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
            const FullType(BuiltList, const [const FullType(ToolTask)]),
            () => ListBuilder<ToolTask>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(TranscriptCue)]),
            () => ListBuilder<TranscriptCue>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(UpgradeGroup)]),
            () => ListBuilder<UpgradeGroup>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(UpgradeMember)]),
            () => ListBuilder<UpgradeMember>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Upload)]),
            () => ListBuilder<Upload>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(UserAccount)]),
            () => ListBuilder<UserAccount>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(WriteBackFailure)]),
            () => ListBuilder<WriteBackFailure>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, const [
              const FullType(String),
              const FullType(String),
            ]),
            () => MapBuilder<String, String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, const [
              const FullType(String),
              const FullType(String),
            ]),
            () => MapBuilder<String, String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltMap, const [
              const FullType(String),
              const FullType(String),
            ]),
            () => MapBuilder<String, String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(String)]),
            () => ListBuilder<String>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(FieldProvenance)]),
            () => ListBuilder<FieldProvenance>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(Credit)]),
            () => ListBuilder<Credit>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ChapterMark)]),
            () => ListBuilder<ChapterMark>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(CustomTag)]),
            () => ListBuilder<CustomTag>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(WriteBackIssue)]),
            () => ListBuilder<WriteBackIssue>(),
          ))
        .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
