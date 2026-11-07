package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/restore"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// stagedRestore is what applying a staged restore did, for the steps that
// settle what it replaced.
type stagedRestore struct {
	applied    bool
	report     *restore.Report
	casualties []service.SealedCasualty
	liveMints  int64
}

// applyStagedRestore applies the staged restore, when one is marked.
func applyStagedRestore(dataDir string, log *slog.Logger) (stagedRestore, error) {
	// A staged restore applies before anything opens a database: the
	// marker survives any failure here, so a crash retries at the next
	// start and a refusing error leaves the operator in charge.
	restoreCasualties := stagedCasualties(dataDir)
	// Read before the swap: the restored database carries an older count.
	liveMints := service.PeekCatalogMints(dataDir)
	restoreApplied, restoreReport, err := restore.Apply(dataDir, log, service.VetRestore)
	if err != nil {
		return stagedRestore{}, fmt.Errorf("applying staged restore: %w", err)
	}
	if restoreApplied {
		log.Info("restore applied", "backup", restoreReport.BackupID, "archive", restoreReport.FileName)
	}
	return stagedRestore{applied: restoreApplied, report: restoreReport, casualties: restoreCasualties, liveMints: liveMints}, nil
}

// settleStore settles what a restore or an interrupted backup left in the
// store.
func settleStore(ctx context.Context, store *db.DB, staged stagedRestore, log *slog.Logger) error {
	if staged.applied {
		// Fresh stream generations mint at open; every outstanding
		// client cursor answers sync-reset instead of silently reading
		// the restored history.
		if err := service.ResetSyncAfterRestore(ctx, store, staged.liveMints); err != nil {
			return err
		}
	}
	if n, err := store.FailStaleRunningBackups(ctx, time.Now().UnixNano()); err != nil {
		log.Warn("sweeping stale backups", "err", err)
	} else if n > 0 {
		log.Info("marked interrupted backups failed", "count", n)
	}
	return nil
}

// startBackups prepares backups and starts the runner the returned channel
// wakes.
func startBackups(ctx context.Context, group *supervise.Group, svc *service.Library, dataDir string, sealer *auth.Sealer,
	staged stagedRestore, log *slog.Logger) (*service.Backups, chan string) {
	backups := service.NewBackups(svc, dataDir, keyProber(sealer))
	backups.SweepTempFiles()
	if staged.applied {
		if err := backups.PostRestoreSweep(ctx, service.RestoreReportLike{
			BackupID:   staged.report.BackupID,
			FileName:   staged.report.FileName,
			SetAside:   staged.report.SetAside,
			Casualties: staged.casualties,
		}); err != nil {
			log.Warn("post-restore sweep", "err", err)
		}
	}
	backupWake := make(chan string, 8)
	group.Go(ctx, "backup-runner", func(ctx context.Context) error {
		sweep := time.NewTicker(time.Minute)
		defer sweep.Stop()
		for {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case id := <-backupWake:
				if err := backups.Run(ctx, id); err != nil && ctx.Err() == nil {
					log.Warn("backup run", "backup", id, "err", err)
				}
			case <-sweep.C:
				// A wake dropped by a full channel leaves a claimed row
				// running with nobody on it; the sweep picks it up.
				rows, err := backups.List(ctx)
				if err != nil {
					continue
				}
				for _, row := range rows {
					if row.State == "running" {
						if err := backups.Run(ctx, row.ID); err != nil && ctx.Err() == nil {
							log.Warn("backup run", "backup", row.ID, "err", err)
						}
					}
				}
			}
		}
	})
	return backups, backupWake
}

// stagedCasualties reads the sealed-credential casualty list out of the
// restore marker before Apply consumes it, so the post-restore sweep
// can record exactly what went pending re-auth.
func stagedCasualties(dataDir string) []service.SealedCasualty {
	raw, err := os.ReadFile(filepath.Join(dataDir, "restore-staged.json"))
	if err != nil {
		return nil
	}
	var doc struct {
		SealedCasualties []service.SealedCasualty `json:"sealedCasualties"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil
	}
	return doc.SealedCasualties
}

// keyProber answers the restore preflight: whether this host's key
// opens the archive's sealed credentials, and which credentials break
// when it does not. It reads the archive's own waxdeck.db snapshot,
// never the live one.
func keyProber(sealer *auth.Sealer) service.KeyProber {
	return func(ctx context.Context, waxdeckDBPath string) (bool, bool, []service.SealedCasualty) {
		conn, err := sql.Open("sqlite", "file:"+waxdeckDBPath+"?mode=ro")
		if err != nil {
			return true, false, nil
		}
		defer conn.Close()
		type sealedRow struct {
			kind, name string
			blob       []byte
		}
		var rows []sealedRow
		if r, err := conn.QueryContext(ctx, `
			SELECT ap.label, u.username, ap.secret_enc
			FROM app_passwords ap LEFT JOIN users u ON u.id = ap.user_id`); err == nil {
			mark := len(rows)
			for r.Next() {
				var label, username sql.NullString
				var blob []byte
				if r.Scan(&label, &username, &blob) == nil {
					rows = append(rows, sealedRow{"app-password", username.String + "/" + label.String, blob})
				}
			}
			r.Close()
			// An iteration that broke mid-stream contributes nothing, like
			// the query failing outright: a half-read table must not pass
			// for the whole casualty list.
			if r.Err() != nil {
				rows = rows[:mark]
			}
		}
		if r, err := conn.QueryContext(ctx, `
			SELECT sc.service, u.username, sc.sealed_secret
			FROM scrobble_connections sc LEFT JOIN users u ON u.id = sc.user_id`); err == nil {
			mark := len(rows)
			for r.Next() {
				var svcName, username sql.NullString
				var blob []byte
				if r.Scan(&svcName, &username, &blob) == nil {
					rows = append(rows, sealedRow{"scrobble-connection", username.String + "/" + svcName.String, blob})
				}
			}
			r.Close()
			if r.Err() != nil {
				rows = rows[:mark]
			}
		}
		// The err == nil idiom doubles as version tolerance: an archive
		// from before notification targets simply lacks the table and
		// contributes nothing.
		if r, err := conn.QueryContext(ctx, `
			SELECT nt.kind, nt.label, u.username, nt.sealed_config
			FROM notification_targets nt LEFT JOIN users u ON u.id = nt.user_id`); err == nil {
			mark := len(rows)
			for r.Next() {
				var kind, label, username sql.NullString
				var blob []byte
				if r.Scan(&kind, &label, &username, &blob) == nil {
					owner := username.String
					if owner == "" {
						owner = "server"
					}
					name := owner + "/" + kind.String
					if label.String != "" {
						name += "/" + label.String
					}
					rows = append(rows, sealedRow{"notification-target", name, blob})
				}
			}
			r.Close()
			if r.Err() != nil {
				rows = rows[:mark]
			}
		}
		if len(rows) == 0 {
			return true, true, nil
		}
		if _, err := sealer.Open(rows[0].blob); err == nil {
			return true, true, nil
		}
		casualties := make([]service.SealedCasualty, 0, len(rows))
		for _, row := range rows {
			casualties = append(casualties, service.SealedCasualty{Kind: row.kind, Name: row.name})
		}
		return true, false, casualties
	}
}
