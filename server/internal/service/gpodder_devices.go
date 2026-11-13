package service

import (
	"cmp"
	"context"
	"fmt"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The device pass-throughs. The gpodder tables live in the server DB;
// these wrappers exist so the adapter stays on the service layer like
// every other surface.

// GpodderUpsertDevice creates or updates one of the user's devices and
// stamps it seen. Empty caption or type leave the stored value unchanged;
// a fresh device with no type stores as "other". A device id runs to 128
// bytes and is never this server's own, and a caption is cut at 256.
//
// An account keeps 50 devices, and a new one past that takes the slot of
// the least recently seen that holds nothing; when all of them hold
// something, of the least recently seen of all, whose shows stay followed,
// and the inbox says which device went (the first few in a day by name).
func (l *Podcasts) GpodderUpsertDevice(ctx context.Context, uc *UserCtx, deviceID, caption, devType string) error {
	if len(deviceID) > GpodderMaxDeviceIDLen {
		return errInvalid(fmt.Sprintf("a device id is at most %d bytes", GpodderMaxDeviceIDLen))
	}
	if deviceID == GpodderOwnDevice {
		return errInvalid(`the device id "` + GpodderOwnDevice + `" is this server's own`)
	}
	caption = truncateUTF8(caption, gpodderMaxCaptionLen)
	now := time.Now().UnixNano()
	evicted, err := l.db.RegisterGpodderDevice(ctx, wdb.GpodderDevice{
		UserID: uc.ID, DeviceID: deviceID, Caption: caption, Type: devType,
		CreatedAtNS: now, UpdatedAtNS: now,
	}, gpodderMaxDevices)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if evicted != nil {
		l.log.Info("gpodder device removed to make room", "user", uc.ID, "removed", evicted.DeviceID,
			"for", deviceID, "kept", evicted.Kept)
	}
	if evicted != nil && evicted.Held {
		l.noteGpodderEviction(ctx, uc, cmp.Or(caption, deviceID), evicted)
	}
	return nil
}

// noteGpodderEviction tells the account that a device which kept
// something made room for another: by name for the first few in a day,
// then once that more are going, so a client minting a device per launch
// files a handful of rows rather than one each.
func (l *Podcasts) noteGpodderEviction(ctx context.Context, uc *UserCtx, newcomer string, evicted *wdb.GpodderEviction) {
	defer l.lockMembership(uc.ID)()
	filed, err := l.db.CountNotificationsSince(ctx, uc.ID, "gpodder-device-removed",
		time.Now().Add(-gpodderEvictionWindow).UnixNano())
	if err != nil {
		l.log.Warn("reading the inbox for a gpodder notice", "err", err)
		return
	}
	switch {
	case filed < gpodderEvictionsNamed:
		removed := cmp.Or(evicted.Caption, evicted.DeviceID)
		l.Integrations.EmitNotificationFor(ctx, "gpodder-device-removed", "Podcast app removed: "+removed, fmt.Sprintf(
			"To make room for %s, %s, the least recently seen of this account's %d podcast app devices, was removed. What it kept followed stays followed.",
			newcomer, removed, gpodderMaxDevices), "", []string{uc.ID})
	case filed == gpodderEvictionsNamed:
		l.Integrations.EmitNotificationFor(ctx, "gpodder-device-removed", "Podcast apps removed", fmt.Sprintf(
			"More of this account's %d podcast app devices are being removed, each to make room for a new one; what they kept followed stays followed. A day's first %d are named here, the rest are not.",
			gpodderMaxDevices, gpodderEvictionsNamed), "", []string{uc.ID})
	}
}

// GpodderSeeDevice stamps a registered device as seen, for a device that
// reads without uploading: least recently seen is what decides which
// device makes room for a new one.
func (l *Podcasts) GpodderSeeDevice(ctx context.Context, uc *UserCtx, deviceID string) {
	if err := l.db.SeeGpodderDevice(ctx, uc.ID, deviceID, time.Now().UnixNano()); err != nil {
		l.log.Warn("stamping a gpodder device seen", "err", err)
	}
}

// GpodderDevice is one device an account registered.
type GpodderDevice struct {
	DeviceID string
	Caption  string
	Type     string
}

// GpodderDevices lists the user's devices.
func (l *Podcasts) GpodderDevices(ctx context.Context, uc *UserCtx) ([]GpodderDevice, error) {
	rows, err := l.db.GpodderDevicesByUser(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	devs := make([]GpodderDevice, len(rows))
	for i, d := range rows {
		devs[i] = GpodderDevice{DeviceID: d.DeviceID, Caption: d.Caption, Type: d.Type}
	}
	return devs, nil
}

// GpodderDeviceExists reports whether the user has registered the
// device (explicitly or through an upload's auto-create).
func (l *Podcasts) GpodderDeviceExists(ctx context.Context, uc *UserCtx, deviceID string) (bool, error) {
	ok, err := l.db.GpodderDeviceExists(ctx, uc.ID, deviceID)
	if err != nil {
		return false, &Error{Kind: KindInternal, Err: err}
	}
	return ok, nil
}
