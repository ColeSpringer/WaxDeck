package service

import (
	"context"
	"path/filepath"

	"github.com/colespringer/waxbin/model"
)

// The roles a file plays for its item (model.ItemFileRef.Role): the
// primary owns the item's metadata, a part is one of a book's files in
// reading order, and an alternate is a copy of the item's audio or
// another encoding of its recording, listed after the parts.
const (
	fileRolePrimary   = "primary"
	fileRoleAlternate = "alternate"
)

// Why an alternate is one: the same audio as one of its item's files, or
// another encoding of its recording.
const (
	copyReasonSameAudio     = "same-audio"
	copyReasonOtherEncoding = "other-encoding"
)

// ItemFileDTO is one file behind an item, as its caller may see it.
type ItemFileDTO struct {
	FilePID string
	Role    string
	Name    string
	// Path is the file's display path, for administrators only.
	Path       string
	SizeBytes  int64
	Codec      string
	Container  string
	Bitrate    int
	SampleRate int
	BitDepth   int
	DurationMS int64
	LibraryPID string
	// Reason says why an alternate is one, empty for the item's own files
	// or when its row could not be read.
	Reason string
}

// itemFile is one file behind an item with its catalog row, nil when the
// row could not be read.
type itemFile struct {
	ref  model.ItemFileRef
	file *model.File
}

// libraryGranted reports whether the caller may see the library.
func libraryGranted(uc *UserCtx, lib model.PID) bool {
	return uc.AllLibraries || uc.Libraries[string(lib)]
}

// visibleItemFiles reads the files behind an item that sit in libraries
// the caller may see, with their rows: the primary or a book's parts,
// then the copies, which can sit in another library than the item's.
func (l *Library) visibleItemFiles(ctx context.Context, uc *UserCtx, pid model.PID) ([]itemFile, error) {
	refs, err := l.lib.ItemFiles(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]itemFile, 0, len(refs))
	for _, ref := range refs {
		if !libraryGranted(uc, ref.LibraryPID) {
			continue
		}
		f, err := l.readFile(ctx, ref.FilePID)
		if err != nil {
			l.log.Debug("reading an item's file", "item", string(pid), "file", string(ref.FilePID), "err", err)
			f = nil
		}
		out = append(out, itemFile{ref: ref, file: f})
	}
	return out, nil
}

// readFile reads one file's row.
func (l *Library) readFile(ctx context.Context, pid model.PID) (*model.File, error) {
	if l.fileReadHook != nil {
		return l.fileReadHook(ctx, pid)
	}
	return l.lib.File(ctx, pid)
}

// ItemFiles lists the files behind one visible item: its own, then its
// copies, leaving out a copy in a library the caller cannot see. It
// takes the right download-info takes, which already names the files;
// paths are administrators' only.
func (l *Library) ItemFiles(ctx context.Context, uc *UserCtx, apiItemPID string) ([]ItemFileDTO, error) {
	if !uc.Admin && !uc.Download {
		return nil, &Error{Kind: KindForbidden, Msg: "this account cannot read an item's files"}
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return nil, err
	}
	files, err := l.visibleItemFiles(ctx, uc, it.PID)
	if err != nil {
		return nil, err
	}
	return itemFileDTOs(files, uc.Admin), nil
}

// itemFileDTOs maps an item's files, naming each copy's reason by
// whether its audio is one of the item's own files'.
func itemFileDTOs(files []itemFile, admin bool) []ItemFileDTO {
	own := map[string]bool{}
	for _, f := range files {
		if f.ref.Role != fileRoleAlternate && f.file != nil && f.file.EssenceHash != "" {
			own[f.file.EssenceHash] = true
		}
	}
	out := make([]ItemFileDTO, 0, len(files))
	for _, f := range files {
		d := ItemFileDTO{
			FilePID: string(f.ref.FilePID), Role: f.ref.Role, Name: filepath.Base(f.ref.DisplayPath),
			LibraryPID: entityAPIPID(PrefixLibrary, f.ref.LibraryPID),
		}
		if admin {
			d.Path = f.ref.DisplayPath
		}
		if r := f.file; r != nil {
			d.SizeBytes, d.Codec, d.Container = r.Size, r.Codec, r.Container
			d.Bitrate, d.SampleRate, d.BitDepth, d.DurationMS = r.Bitrate, r.SampleRate, r.BitDepth, r.DurationMS
			if f.ref.Role == fileRoleAlternate {
				d.Reason = copyReasonOtherEncoding
				if own[r.EssenceHash] {
					d.Reason = copyReasonSameAudio
				}
			}
		}
		out = append(out, d)
	}
	return out
}
