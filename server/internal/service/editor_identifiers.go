package service

import (
	"cmp"
	"context"
	"errors"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// Upstream stores identifier values unvalidated; the spec promises the
// server format-checks them, so the checks live here.
var (
	editorISRCRe    = regexp.MustCompile(`^[A-Za-z]{2}[A-Za-z0-9]{3}[0-9]{7}$`)
	editorASINRe    = regexp.MustCompile(`^[A-Za-z0-9]{10}$`)
	editorBarcodeRe = regexp.MustCompile(`^([0-9]{8}|[0-9]{12,14})$`)
	editorMBIDRe    = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
)

func validISRC(s string) bool { return editorISRCRe.MatchString(s) }

func validASIN(s string) bool { return editorASINRe.MatchString(s) }

func validBarcode(s string) bool { return editorBarcodeRe.MatchString(s) }

func validMBID(s string) bool { return editorMBIDRe.MatchString(s) }

// validISBN checks a 10 or 13 digit ISBN, hyphens and spaces ignored,
// including its checksum. ISBN-10 allows the X check digit.
func validISBN(s string) bool {
	cleaned := strings.Map(func(r rune) rune {
		if r == '-' || r == ' ' {
			return -1
		}
		return r
	}, s)
	switch len(cleaned) {
	case 10:
		sum := 0
		for i, r := range cleaned {
			var v int
			switch {
			case r >= '0' && r <= '9':
				v = int(r - '0')
			case (r == 'X' || r == 'x') && i == 9:
				v = 10
			default:
				return false
			}
			sum += (10 - i) * v
		}
		return sum%11 == 0
	case 13:
		sum := 0
		for i, r := range cleaned {
			if r < '0' || r > '9' {
				return false
			}
			w := 1
			if i%2 == 1 {
				w = 3
			}
			sum += w * int(r-'0')
		}
		return sum%10 == 0
	default:
		return false
	}
}

// validYear reports whether s is the non-negative integer WaxBin's year field
// accepts; any other value fails the whole edit, so an enrich pass drops it.
func validYear(s string) bool {
	s = strings.TrimSpace(s)
	if s == "" {
		return false
	}
	n, err := strconv.Atoi(s)
	return err == nil && n >= 0
}

// validateIdentifierField rejects a malformed identifier value; the
// empty string always passes (it clears the field).
func validateIdentifierField(name, value string) error {
	if value == "" {
		return nil
	}
	bad := false
	switch name {
	case "isrc":
		bad = !validISRC(value)
	case "isbn":
		bad = !validISBN(value)
	case "asin":
		bad = !validASIN(value)
	case "barcode":
		bad = !validBarcode(value)
	case "mbid":
		bad = !validMBID(value)
	}
	if bad {
		return errInvalid(name + " is not a valid identifier: " + value)
	}
	return nil
}

// validateFieldEdits checks a scalar edit against the kind's vocabulary
// and the write-back policy (episodes never write back).
func validateFieldEdits(it *model.ItemView, fields map[string]string, writeBack bool) error {
	if len(fields) == 0 {
		return errInvalid("at least one field edit is required")
	}
	if writeBack && it.Kind == model.KindEpisode {
		return errInvalid("podcast episodes never write back to files; edits are database-only by upstream design")
	}
	allowed := map[string]bool{}
	for _, f := range editorFieldsForKind(it.Kind) {
		allowed[f.Name] = true
	}
	for name, value := range fields {
		if !allowed[name] {
			return errInvalid("field " + name + " is not editable on a " + mediaTypeForKind(it.Kind) + " item" +
				bookOnlyHint(it.Kind, slices.ContainsFunc(editorBookFields, func(f EditableFieldDTO) bool { return f.Name == name })))
		}
		if err := validateIdentifierField(name, value); err != nil {
			return err
		}
	}
	return nil
}

// editOutcomeFromWriteBack converts an upstream write-back error into
// result failures; any other error passes through classified.
func editOutcomeFromWriteBack(err error) (EditOutcomeDTO, error) {
	if err == nil {
		return EditOutcomeDTO{}, nil
	}
	var wbe *waxbin.WriteBackError
	if errors.As(err, &wbe) {
		return EditOutcomeDTO{Failures: writeBackFailures(wbe)}, nil
	}
	return EditOutcomeDTO{}, classify(err)
}

// WriteBackFailuresFor is a write-back's failures as uc may read them:
// whole for an administrator; for anyone else only the files in
// libraries they are granted, each by its name, worded without the
// server's paths or a library's operations. A file is placed by its pid,
// so narrowing twice changes nothing.
func (l *Editor) WriteBackFailuresFor(ctx context.Context, uc *UserCtx, fs []WriteBackFailureDTO) []WriteBackFailureDTO {
	if uc.Admin || len(fs) == 0 {
		return fs
	}
	out := make([]WriteBackFailureDTO, 0, len(fs))
	for _, f := range fs {
		if f.FilePID != "" && !l.fileGranted(ctx, uc, model.PID(f.FilePID)) {
			continue
		}
		f.Reason = l.Ingest.failureWords(f.Reason)
		if f.Path != "" {
			f.Path = filepath.Base(f.Path)
		}
		out = append(out, f)
	}
	return out
}

// fileGranted reports whether a file sits in a library uc is granted; a
// file the catalog cannot place is not.
func (l *Editor) fileGranted(ctx context.Context, uc *UserCtx, pid model.PID) bool {
	if uc.AllLibraries {
		return true
	}
	f, err := l.lib.File(ctx, pid)
	if err != nil {
		return false
	}
	lib, err := l.Grants.libraryForPath(ctx, cmp.Or(f.DisplayPath, string(f.Path)))
	return err == nil && lib != "" && libraryGranted(uc, model.PID(lib))
}

func writeBackFailures(wbe *waxbin.WriteBackError) []WriteBackFailureDTO {
	out := make([]WriteBackFailureDTO, 0, len(wbe.Failures))
	for _, f := range wbe.Failures {
		out = append(out, WriteBackFailureDTO{
			FilePID: string(f.FilePID), Path: f.Path, Reason: f.Reason,
		})
	}
	return out
}
