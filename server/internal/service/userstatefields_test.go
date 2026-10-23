package service

import (
	"context"
	"go/ast"
	"go/parser"
	"go/token"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// waxbinSourceDir is where the WaxBin module in use keeps its source.
func waxbinSourceDir(t *testing.T) string {
	t.Helper()
	goTool, err := exec.LookPath("go")
	if err != nil {
		t.Skipf("no go tool to find WaxBin's source with: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, goTool, "list", "-m", "-f", "{{.Dir}}", "github.com/colespringer/waxbin").Output()
	if err != nil {
		t.Fatalf("locating the WaxBin module: %v", err)
	}
	dir := strings.TrimSpace(string(out))
	if dir == "" {
		t.Fatal("the WaxBin module has no source directory here")
	}
	return dir
}

// needsUserColumns is the names of the columns WaxBin's field table marks
// `NeedsUser: true`, read from the Go source of the table itself.
func needsUserColumns(t *testing.T, path string) []string {
	t.Helper()
	file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
	if err != nil {
		t.Fatalf("reading WaxBin's field table: %v", err)
	}
	var names []string
	ast.Inspect(file, func(n ast.Node) bool {
		entry, ok := n.(*ast.KeyValueExpr)
		if !ok {
			return true
		}
		key, ok := entry.Key.(*ast.BasicLit)
		if !ok || key.Kind != token.STRING {
			return true
		}
		column, ok := entry.Value.(*ast.CompositeLit)
		if !ok {
			return true
		}
		for _, element := range column.Elts {
			setting, ok := element.(*ast.KeyValueExpr)
			if !ok {
				continue
			}
			field, isIdent := setting.Key.(*ast.Ident)
			value, valueIsIdent := setting.Value.(*ast.Ident)
			if isIdent && valueIsIdent && field.Name == "NeedsUser" && value.Name == "true" {
				name, err := strconv.Unquote(key.Value)
				if err != nil {
					t.Fatalf("reading the name of a column in WaxBin's field table: %v", err)
				}
				names = append(names, name)
			}
		}
		return true
	})
	slices.Sort(names)
	return names
}

// A smart playlist is handed over as a fixed list when its rule reads the
// owner's own state, and which fields do is WaxBin's to say: its store
// marks them in a table it keeps to itself, and nothing it exports answers
// the question (docs/upstream-requests.md asks for something that does).
// userStateFields is the copy WaxDeck keeps meanwhile, so this reads the
// table itself, from the WaxBin in use, and fails when a bump adds a field
// that reads per-user state, or renames or drops one, until the copy is
// brought up to it.
func TestUserStateFieldsMatchTheEngine(t *testing.T) {
	t.Parallel()
	path := filepath.Join(waxbinSourceDir(t), "store", "sqlite", "fields.go")
	engine := needsUserColumns(t, path)
	if len(engine) == 0 {
		t.Fatalf("found no per-user columns in %s: either WaxBin moved its field table or this reading of it is out of date", path)
	}

	ours := make([]string, 0, len(userStateFields))
	for name := range userStateFields {
		ours = append(ours, name)
	}
	slices.Sort(ours)
	for _, name := range engine {
		if !userStateFields[name] {
			t.Errorf("WaxBin's %s reads per-user state and userStateFields does not list it: a rule over it would be handed over unfixed", name)
		}
	}
	for _, name := range ours {
		if !slices.Contains(engine, name) {
			t.Errorf("userStateFields lists %s, which WaxBin's field table no longer marks as reading per-user state", name)
		}
	}
}
