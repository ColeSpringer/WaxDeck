package api

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// absentULID is a well-formed id nobody holds: older than any id a
// harness mints.
const absentULID = "01JZX5N8QW3F4V9T2B7KD3M9R6"

// absentPID is a well-formed API pid of the given prefix that nobody
// holds.
func absentPID(prefix string) string { return prefix + "-" + absentULID }

// TestNotFoundAnswers pins what each operation answers, byte for byte,
// for a well-formed pid nobody holds: 404 not-found, with a sentence
// naming what is missing.
func TestNotFoundAnswers(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	var (
		tr, al, ar, bk = absentPID("tr"), absentPID("al"), absentPID("ar"), absentPID("bk")
		pc, ep, lb, jb = absentPID("pc"), absentPID("ep"), absentPID("lb"), absentPID("jb")
		us, iv, ap, tk = absentPID("us"), absentPID("iv"), absentPID("ap"), absentPID("tk")
		up, ub, rv, bu = absentPID("up"), absentPID("ub"), absentPID("rv"), absentPID("bu")
		th, rs, rw     = absentPID("th"), absentPID("rs"), absentPID("rw")
		// MergeDuplicates names two artists, neither held.
		ar2 = "ar-01JZX5N8QW3F4V9T2B7KD3M9R7"
	)
	rows := []struct {
		op, method, path string
		// body goes as JSON, or as it stands when it is []byte.
		body any
		want string
	}{
		{"RestoreTrashEntry", "POST", "/admin/trash/" + th + "/restore", nil, "no trash entry with id " + th},
		{"SetLibraryReadOnly", "PUT", "/libraries/" + lb + "/read-only", map[string]any{"readOnly": true}, "no library with pid " + lb},
		{"SetLibraryFolderFallback", "PUT", "/libraries/" + lb + "/folder-fallback", map[string]any{"folderFallback": true}, "no library with pid " + lb},
		{"SetLibraryMedia", "PUT", "/libraries/" + lb + "/media", map[string]any{"media": "music"}, "no library with pid " + lb},
		{"RemoveLibrary", "DELETE", "/libraries/" + lb, nil, "no library with pid " + lb},
		{"StreamToolTaskEvents", "GET", "/tools/tasks/" + tk + "/events", nil, "no task with id " + tk},
		{"GetBackup", "GET", "/admin/backups/" + bu, nil, "no backup with id " + bu},
		{"DeleteBackup", "DELETE", "/admin/backups/" + bu, nil, "no backup with id " + bu},
		{"StageRestore", "POST", "/admin/backups/" + bu + "/restore", nil, "no backup with id " + bu},
		{"GetStagedRestore", "GET", "/admin/backups/restore", nil, "no restore is staged"},
		{"CancelStagedRestore", "DELETE", "/admin/backups/restore", nil, "no restore is staged"},

		{"EnrichItem", "POST", "/items/" + tr + "/enrich", map[string]any{"want": []string{"fields"}}, "no item with pid " + tr},
		{"PreviewEnrichItem", "POST", "/items/" + tr + "/enrich/preview", map[string]any{"want": []string{"fields"}}, "no item with pid " + tr},

		{"GetAlbum", "GET", "/albums/" + al, nil, "no album with pid " + al},
		{"GetItem", "GET", "/items/" + tr, nil, "no item with pid " + tr},
		{"GetItemArt", "GET", "/items/" + tr + "/art", nil, "no artwork for pid " + tr},
		{"GetItemArtRoles", "GET", "/items/" + tr + "/art-roles", nil, "no artwork for pid " + tr},
		{"GetItemLyrics", "GET", "/items/" + tr + "/lyrics", nil, "no lyrics for pid " + tr},
		{"GetJob", "GET", "/jobs/" + jb, nil, "no job with pid " + jb},
		{"GetPlayInfo", "GET", "/items/" + tr + "/play-info", nil, "no item with pid " + tr},
		{"GetPlayState", "GET", "/items/" + tr + "/play-state", nil, "no item with pid " + tr},
		{"PutPlayState", "PUT", "/items/" + tr + "/play-state", map[string]any{"positionMs": 1000}, "no item with pid " + tr},

		{"MergeDuplicates", "POST", "/library/duplicates/merge", map[string]any{"entityType": "artist", "survivorPid": ar, "loserPids": []string{ar2}}, "no such entity"},

		{"RevokeUserSessions", "DELETE", "/users/" + us + "/sessions", nil, "no user with id " + us},
		{"GetUser", "GET", "/users/" + us, nil, "no user with id " + us},
		{"UpdateUser", "PATCH", "/users/" + us, map[string]any{"displayName": "Nobody"}, "no user with id " + us},
		{"DeleteUser", "DELETE", "/users/" + us, nil, "no user with id " + us},
		{"SetPassword", "PUT", "/users/" + us + "/password", map[string]any{"newPassword": testPassword}, "no user with id " + us},
		{"SetStar", "PUT", "/items/" + tr + "/star", map[string]any{"starred": true}, "no item with pid " + tr},
		{"SetPlayed", "PUT", "/items/" + tr + "/played", map[string]any{"played": true}, "no item with pid " + tr},
		{"SetRating", "PUT", "/items/" + tr + "/rating", map[string]any{"rating": 80}, "no item with pid " + tr},
		{"GetArtistPlayState", "GET", "/artists/" + ar + "/play-state", nil, "no artist with pid " + ar},
		{"SetArtistStar", "PUT", "/artists/" + ar + "/star", map[string]any{"starred": true}, "no artist with pid " + ar},
		{"SetArtistRating", "PUT", "/artists/" + ar + "/rating", map[string]any{"rating": 80}, "no artist with pid " + ar},
		{"GetAlbumPlayState", "GET", "/albums/" + al + "/play-state", nil, "no album with pid " + al},
		{"SetAlbumStar", "PUT", "/albums/" + al + "/star", map[string]any{"starred": true}, "no album with pid " + al},
		{"SetAlbumRating", "PUT", "/albums/" + al + "/rating", map[string]any{"rating": 80}, "no album with pid " + al},
		// A play-state route says its own noun, whatever kind the pid names.
		{"GetAlbumPlayState of an artist pid", "GET", "/albums/" + ar + "/play-state", nil, "no album with pid " + ar},
		{"SetArtistStar of a track pid", "PUT", "/artists/" + tr + "/star", map[string]any{"starred": true}, "no artist with pid " + tr},

		{"GetRadioStationLogo", "GET", "/radio/stations/" + rs + "/logo", nil, "no logo for station " + rs},
		{"GetRadioNowPlayingArt", "GET", "/radio/stations/" + rs + "/now-playing-art?v=0123456789abcdef0123456789abcdef", nil, "no now-playing artwork for station " + rs},
		{"GetRadioSavedSongArt", "GET", "/radio/saved/" + rw + "/art", nil, "no artwork for saved song " + rw},

		{"GetItemFiles", "GET", "/items/" + tr + "/files", nil, "no item with pid " + tr},

		{"GetItemMetadata", "GET", "/items/" + tr + "/metadata", nil, "no item with pid " + tr},
		{"EditItemMetadata", "PATCH", "/items/" + tr + "/metadata", map[string]any{"fields": map[string]string{"title": "Nothing"}}, "no item with pid " + tr},
		{"CommitItemMetadata", "POST", "/items/" + tr + "/metadata/commit", map[string]any{"fields": map[string]string{"title": "Nothing"}}, "no item with pid " + tr},
		{"SetItemCredits", "PUT", "/items/" + tr + "/credits", map[string]any{"role": "composer", "names": []string{"Nobody"}}, "no item with pid " + tr},
		{"SetItemLyrics", "PUT", "/items/" + tr + "/lyrics", map[string]any{"plain": "nothing"}, "no item with pid " + tr},
		{"ClearItemLyrics", "DELETE", "/items/" + tr + "/lyrics", nil, "no item with pid " + tr},
		{"SetBookChapters", "PUT", "/books/" + bk + "/chapters", map[string]any{"chapters": []map[string]any{{"startMs": 0, "title": "One"}}}, "no book with pid " + bk},
		{"SetItemArtwork", "PUT", "/items/" + tr + "/artwork", tinyPNG(t), "no item with pid " + tr},
		{"ClearItemArtwork", "DELETE", "/items/" + tr + "/artwork", nil, "no item with pid " + tr},
		{"SetEntityArtwork", "PUT", "/entities/album/" + al + "/artwork", tinyPNG(t), "no album with pid " + al},
		{"ClearEntityArtwork", "DELETE", "/entities/album/" + al + "/artwork", nil, "no album with pid " + al},
		{"GetEntityArtworkLock", "GET", "/entities/album/" + al + "/artwork/lock", nil, "no album with pid " + al},
		{"SetEntityArtworkLock", "PUT", "/entities/album/" + al + "/artwork/lock", map[string]any{"locked": true}, "no album with pid " + al},
		{"SetItemTag", "PUT", "/items/" + tr + "/tags/mood", map[string]any{"values": []string{"calm"}}, "no item with pid " + tr},
		{"ClearItemTag", "DELETE", "/items/" + tr + "/tags/mood", nil, "no item with pid " + tr},
		{"SetItemAcquisition", "PUT", "/items/" + tr + "/acquisition", map[string]any{"sourceType": "manual"}, "no item with pid " + tr},
		{"ClearItemAcquisition", "DELETE", "/items/" + tr + "/acquisition", nil, "no item with pid " + tr},
		{"SetItemLocks", "PUT", "/items/" + tr + "/locks", map[string]any{"fields": []string{"title"}, "locked": true}, "no item with pid " + tr},
		{"EditEntity", "PATCH", "/entities/artist/" + ar, map[string]any{"edits": map[string]string{"sort": "Nobody"}}, "no artist with pid " + ar},
		{"RenameEntity", "POST", "/entities/artist/" + ar + "/rename", map[string]any{"fields": map[string]string{"name": "Nobody"}}, "no artist with pid " + ar},
		{"GetEntityCuration", "GET", "/entities/album/" + al + "/curation", nil, "no album with pid " + al},
		{"DetachItem", "POST", "/items/" + tr + "/detach", nil, "no item with pid " + tr},
		{"SetReleaseStatus", "PUT", "/items/" + tr + "/release-status", map[string]any{"unofficial": true}, "no item with pid " + tr},

		{"GetPodcast", "GET", "/podcasts/" + pc, nil, "no show with pid " + pc},
		{"UnsubscribePodcast", "DELETE", "/podcasts/" + pc, nil, "no show with pid " + pc},
		{"ListEpisodes", "GET", "/podcasts/" + pc + "/episodes", nil, "no show with pid " + pc},
		{"GetEpisode", "GET", "/episodes/" + ep, nil, "no episode with pid " + ep},
		{"RefreshPodcast", "POST", "/podcasts/" + pc + "/refresh", nil, "no show with pid " + pc},
		{"FetchEpisode", "POST", "/episodes/" + ep + "/fetch", nil, "no episode with pid " + ep},
		{"RemoveEpisodeDownload", "DELETE", "/episodes/" + ep + "/fetch", nil, "no episode with pid " + ep},
		{"GetBook", "GET", "/books/" + bk, nil, "no book with pid " + bk},
		{"GetBookResume", "GET", "/books/" + bk + "/resume", nil, "no book with pid " + bk},
		{"PutBookSettings", "PUT", "/books/" + bk + "/settings", map[string]any{"speed": 1.5}, "no book with pid " + bk},
		{"ListBookmarks", "GET", "/books/" + bk + "/bookmarks", nil, "no book with pid " + bk},
		{"CreateBookmark", "POST", "/books/" + bk + "/bookmarks", map[string]any{"positionMs": 1000}, "no book with pid " + bk},
		{"GetSkipMap", "GET", "/items/" + tr + "/skip-map", nil, "no item with pid " + tr},
		{"GetWaveform", "GET", "/items/" + tr + "/waveform", nil, "no item with pid " + tr},

		{"GetReviewEntry", "GET", "/review/queue/" + rv, nil, "no such review entry"},
		{"DecideReviewEntry", "POST", "/review/queue/" + rv + "/decide", map[string]any{"action": "skip"}, "no such review entry"},
		{"RevertReviewEntry", "POST", "/review/queue/" + rv + "/revert", nil, "no such review entry"},
		{"ReidentifyReviewEntry", "POST", "/review/queue/" + rv + "/identify", nil, "no such review entry"},
		{"GetLibraryMatching", "GET", "/libraries/" + lb + "/matching", nil, "no such library"},
		{"SetLibraryMatching", "PUT", "/libraries/" + lb + "/matching", map[string]any{"mode": "auto", "singlesAutoApply": false}, "no such library"},

		{"ApproveSignupRequest", "POST", "/users/requests/" + us + "/approve", nil, "no user with id " + us},
		{"RejectSignupRequest", "POST", "/users/requests/" + us + "/reject", nil, "no user with id " + us},
		{"RevokeInvite", "DELETE", "/invites/" + iv, nil, "no invite with id " + iv},

		{"GetDownloadInfo", "GET", "/items/" + tr + "/download-info", nil, "no item with pid " + tr},
		{"RevokeAppPassword", "DELETE", "/users/me/app-passwords/" + ap, nil, "no app password with id " + ap},

		{"MergeBook", "POST", "/books/" + bk + "/merge", nil, "no book with pid " + bk},
		{"SplitBook", "POST", "/books/" + bk + "/split", nil, "no book with pid " + bk},
		{"SplitCueRip", "POST", "/items/" + tr + "/split-cue", nil, "no item with pid " + tr},
		{"GetToolTask", "GET", "/tools/tasks/" + tk, nil, "no task with id " + tk},
		{"DeleteToolTask", "DELETE", "/tools/tasks/" + tk, nil, "no task with id " + tk},

		{"GetUpload", "GET", "/uploads/" + up, nil, "no such upload"},
		{"DeleteUpload", "DELETE", "/uploads/" + up, nil, "no such upload"},
		{"PutUploadData", "PUT", "/uploads/" + up + "/data?offset=0", []byte("chunk"), "no such upload"},
		{"CompleteUpload", "POST", "/uploads/" + up + "/complete", nil, "no such upload"},
		{"CompleteUploadBatch", "POST", "/uploads/batches/" + ub + "/complete", nil, "no such upload batch"},
		{"RematchItem", "POST", "/items/" + tr + "/rematch", nil, "no item with pid " + tr},
	}
	for _, r := range rows {
		t.Run(r.op, func(t *testing.T) {
			var (
				body        io.Reader
				contentType string
			)
			switch b := r.body.(type) {
			case nil:
			case []byte:
				body, contentType = bytes.NewReader(b), "application/octet-stream"
			default:
				raw, err := json.Marshal(b)
				if err != nil {
					t.Fatal(err)
				}
				body, contentType = bytes.NewReader(raw), "application/json"
			}
			req, err := http.NewRequest(r.method, h.ts.URL+"/api/v1"+r.path, body)
			if err != nil {
				t.Fatal(err)
			}
			if contentType != "" {
				req.Header.Set("Content-Type", contentType)
			}
			req.Header.Set("Authorization", "Bearer "+h.token)
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatal(err)
			}
			got, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			want, _ := json.Marshal(Error{Code: "not-found", Message: r.want})
			if resp.StatusCode != http.StatusNotFound || string(got) != string(want)+"\n" {
				t.Fatalf("%s %s = %d %s, want 404 %s", r.method, r.path, resp.StatusCode, got, want)
			}
		})
	}
}

// An item in the trash keeps its row but not its files, so a route that
// reads its bytes answers it as missing, by the pid the caller sent, never
// in the catalog's words for a file pid nobody named: play-info on the
// engine path and on the direct one, download-info, a waveform, a book's
// skip map.
func TestATrashedItemAnswersByItsPid(t *testing.T) {
	t.Parallel()
	books := t.TempDir()
	if _, err := fixtures.GenerateM4B(filepath.Join(books, "Wren Vale", "Tide Book"), fixtures.Spec{
		Name: "Tide Book", Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Tide Book", "ALBUM": "Tide Book", "ARTIST": "Wren Vale", "ALBUMARTIST": "Wren Vale"},
	}); err != nil {
		t.Fatalf("generating the book: %v", err)
	}
	trashed := func(h *harness, query string) string {
		t.Helper()
		page := h.items(t, query)
		if len(page.Items) == 0 {
			t.Fatalf("no item for %s", query)
		}
		pid := page.Items[0].Pid
		wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
			"pids": []string{pid}, "mode": "trash",
		}), 200, "trash "+pid)
		return pid
	}
	missing := func(h *harness, pid, route string) {
		t.Helper()
		wantNotFound(t, h, "/items/"+pid+route, "no item with pid "+pid)
	}

	engine := newHarness(t, service.Root{Name: "books", Path: books})
	track := trashed(engine, "?mediaType=music&limit=1")
	for _, route := range []string{"/play-info", "/download-info", "/waveform"} {
		missing(engine, track, route)
	}
	missing(engine, trashed(engine, "?mediaType=audiobook"), "/skip-map")

	direct := newHarnessDirect(t)
	missing(direct, trashed(direct, "?mediaType=music&limit=1"), "/play-info")
}

// The commonest not-founds a client meets are about what an item lacks:
// lyrics, a cover. They name the item by the pid the caller sent. The demo
// library's tracks carry neither.
func TestWhatAnItemLacksAnswersByItsPid(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?mediaType=music&limit=1").Items[0].Pid
	wantNotFound(t, h, "/items/"+pid+"/lyrics", "no lyrics for pid "+pid)
	wantNotFound(t, h, "/items/"+pid+"/art", "no artwork for pid "+pid)
}

// wantNotFound asserts path answers 404 not-found with exactly message.
func wantNotFound(t *testing.T, h *harness, path, message string) {
	t.Helper()
	resp := get(t, h.ts, "/api/v1"+path, h.token)
	got, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	want, _ := json.Marshal(Error{Code: "not-found", Message: message})
	if resp.StatusCode != http.StatusNotFound || string(got) != string(want)+"\n" {
		t.Errorf("%s = %d %s, want 404 %s", path, resp.StatusCode, got, want)
	}
}
