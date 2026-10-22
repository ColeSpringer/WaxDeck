package subsonic

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Music folders are the caller's music libraries, under ids that stay
// put. A browse that names one with musicFolderId sees that library's
// tracks alone, and an album belongs to every folder holding one of its
// tracks.

func (h *Handler) getMusicFolders(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	folders, err := h.svc.MusicFolders(r.Context(), uc)
	if err != nil {
		h.failFromService(w, r, err, "listing music folders failed")
		return
	}
	out := &musicFolders{Folders: make([]musicFolder, 0, len(folders))}
	for _, f := range folders {
		out.Folders = append(out.Folders, musicFolder{ID: f.ID, Name: f.Name})
	}
	h.ok(w, r, envelope{MusicFolders: out})
}

// scopedIndex is the caller's index, narrowed to the music folder the
// request names when it names one. A folder that is unknown, gone, or
// not the caller's is error 70. False means the failure is written.
func (h *Handler) scopedIndex(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) (*index, bool) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return nil, false
	}
	raw := strings.TrimSpace(r.Form.Get("musicFolderId"))
	if raw == "" {
		return idx, true
	}
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		h.fail(w, r, 70, "no such music folder")
		return nil, false
	}
	lib, err := h.svc.MusicFolderLibrary(r.Context(), uc, id)
	if err != nil {
		h.failFromService(w, r, err, "no such music folder")
		return nil, false
	}
	return idx.cut(lib), true
}

// cut is the index of one library's tracks, built from the whole index
// once and held on it, so it lives and dies with its caller's whole index
// and never takes a place in the grant-set cache. A caller has a cut for
// each music library at most.
func (idx *index) cut(libraryPID string) *index {
	idx.cutsMu.Lock()
	defer idx.cutsMu.Unlock()
	if c := idx.cuts[libraryPID]; c != nil {
		return c
	}
	var rows []track
	for _, tr := range idx.tracks {
		if tr.LibraryPID == libraryPID {
			rows = append(rows, tr)
		}
	}
	c := buildIndex(rows, idx.facts)
	c.tail, c.folder = idx.tail, libraryPID
	if idx.cuts == nil {
		idx.cuts = map[string]*index{}
	}
	idx.cuts[libraryPID] = c
	return c
}
