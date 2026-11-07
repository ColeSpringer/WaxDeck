import '../models.dart';

/// Organize profiles, plans and history.
abstract interface class OrganizeApi {
  /// `GET /organize/profiles`: the file organization profiles, and how
  /// many libraries they can lay out.
  Future<OrganizeProfiles> listOrganizeProfiles();

  /// `PUT /organize/profiles/{name}`: saves a profile; an empty
  /// template inherits. A null [compilationFolder] files compilations
  /// under Various Artists, an empty one under their own tagged album
  /// artist.
  Future<OrganizeProfile> putOrganizeProfile(
    String name, {
    String musicTemplate = '',
    String audiobookTemplate = '',
    String podcastTemplate = '',
    bool tagWrite = false,
    String? compilationFolder,
  });

  /// `DELETE /organize/profiles/{name}`: deletes a saved profile.
  Future<void> deleteOrganizeProfile(String name);

  /// `POST /organize/profiles/preview`: an unsaved profile's samples.
  Future<OrganizeSample> previewOrganizeProfile({
    String? name,
    String musicTemplate = '',
    String audiobookTemplate = '',
    String podcastTemplate = '',
    String? compilationFolder,
  });

  /// `POST /organize/preview`: dry-runs [profile], or each library's
  /// own when null, over [itemPids] or every managed library.
  Future<OrganizePlan> previewOrganize({
    String? profile,
    List<String>? itemPids,
  });

  /// `POST /organize/apply`: applies the moves, as [previewOrganize].
  Future<OrganizeReport> applyOrganize({
    String? profile,
    List<String>? itemPids,
  });

  /// `GET /organize/history`: a page of the organize runs, and undos of
  /// them, the catalog's journal still holds, newest first, after
  /// [cursor].
  Future<OrganizeHistoryPage> listOrganizeHistory({String? cursor, int? limit});

  /// `POST /organize/undo`: moves back what the run [jobPid] moved,
  /// reported as an applied pass.
  Future<OrganizeReport> undoOrganize(String jobPid);
}
