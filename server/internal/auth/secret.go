// Package auth holds the server-side key machinery and the media-token
// scheme. Media tokens are short-TTL HMAC query tokens that make stream
// URLs playable by clients that cannot send headers (bare audio
// elements, cast devices, DLNA renderers).
package auth

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// secretLen is the size of the generated server secret in bytes.
const secretLen = 32

// SecretFileName is the keyfile written beside the databases when no
// secret is configured. Backups should exclude it by default: an
// archive holding both the databases and this file is
// plaintext-equivalent for every credential the key protects.
const SecretFileName = "secret.key"

// LoadOrCreateSecret resolves the server secret: the WAXDECK_SECRET_KEY
// environment variable when set (hex-encoded), otherwise a keyfile in
// dataDir, generated on first run with 0600 permissions.
func LoadOrCreateSecret(dataDir string) ([]byte, error) {
	if env := os.Getenv("WAXDECK_SECRET_KEY"); env != "" {
		key, err := hex.DecodeString(strings.TrimSpace(env))
		if err != nil {
			return nil, fmt.Errorf("auth: WAXDECK_SECRET_KEY is not valid hex: %w", err)
		}
		if len(key) < 16 {
			return nil, fmt.Errorf("auth: WAXDECK_SECRET_KEY is %d bytes; want at least 16", len(key))
		}
		return key, nil
	}

	path := filepath.Join(dataDir, SecretFileName)
	if raw, err := os.ReadFile(path); err == nil {
		key, err := hex.DecodeString(strings.TrimSpace(string(raw)))
		if err != nil || len(key) < 16 {
			return nil, fmt.Errorf("auth: keyfile %s is corrupt; refusing to guess", path)
		}
		return key, nil
	} else if !os.IsNotExist(err) {
		return nil, fmt.Errorf("auth: reading keyfile: %w", err)
	}

	key := make([]byte, secretLen)
	if _, err := rand.Read(key); err != nil {
		return nil, fmt.Errorf("auth: generating secret: %w", err)
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, fmt.Errorf("auth: creating data dir: %w", err)
	}
	// Write-temp then rename so a crash cannot leave a half-written key.
	tmp, err := os.CreateTemp(dataDir, SecretFileName+".tmp-")
	if err != nil {
		return nil, fmt.Errorf("auth: writing keyfile: %w", err)
	}
	defer os.Remove(tmp.Name())
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return nil, fmt.Errorf("auth: keyfile permissions: %w", err)
	}
	if _, err := tmp.WriteString(hex.EncodeToString(key) + "\n"); err != nil {
		tmp.Close()
		return nil, fmt.Errorf("auth: writing keyfile: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return nil, fmt.Errorf("auth: syncing keyfile: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return nil, fmt.Errorf("auth: closing keyfile: %w", err)
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		return nil, fmt.Errorf("auth: installing keyfile: %w", err)
	}
	return key, nil
}
