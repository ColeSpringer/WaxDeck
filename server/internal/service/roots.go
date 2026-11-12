package service

import (
	"sync"
	"sync/atomic"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Roots is the library roots: creating, removing and probing them,
// watching them for changes, listing the libraries, and the bridge that
// hands them to the streaming engine.
type Roots struct {
	*core
	// roots is the root table, rebuilt from the catalog and swapped under
	// rootsMu (read it through libraryRoots); refreshMu keeps an older read
	// from landing after a newer one. configRoots are the configured ones.
	roots       []Root
	rootsBuilt  bool
	rootsMu     sync.RWMutex
	refreshMu   sync.Mutex
	configRoots []Root
	// refreshHook runs in a test between a refresh's read of the catalog
	// and its store of the table, under refreshMu; nothing in the server
	// sets it.
	refreshHook func()
	// rootsLeftOut are configured roots the catalog refused, warned of once.
	rootsLeftOut sync.Map
	// rootReach and rootProbe are what the console says of the roots
	// beyond the catalog's policy (rootstate.go); removals the libraries
	// the console removes (rootremove.go); creates the ones it is adding
	// (rootcreate.go).
	rootReach rootReach
	rootProbe rootProbe
	removals  rootRemovals
	creates   rootCreates
	// rootProbeEvery is Config.RootProbeEvery.
	rootProbeEvery time.Duration
	// podcastRootName is Config.PodcastRootName, the name the episode
	// download library is mounted under for the streaming sidecar.
	podcastRootName string
	// flowRoots is the streaming sidecar's runtime-root surface, wired
	// after construction (the bridge needs this service as its resolver).
	flowRoots atomic.Pointer[FlowRootSync]
	// flowSyncMu serializes teaching the bridge: WaxFlow refuses a root
	// name it already maps, and two teachers could both see one as new.
	// flowRefused holds the paths it refused by name, not offered again,
	// each with flowOutages, the times the engine went away, as of its
	// offer.
	flowSyncMu  sync.Mutex
	flowRefused map[string]flowRefusal
	flowOutages atomic.Uint64
	// streaming is the streaming engine's state as the bridge last said
	// (SetEngineState), nil before anything was said.
	streaming atomic.Pointer[EngineState]
	// startupScan is whether this start scans every library, which takes
	// back what a removal the last stop cut short let go of.
	startupScan bool
	// watchQueue holds the event-touched directories waiting out their
	// settle window; watchScans carries settled batches to the scan
	// worker, so scans never run on the event loop; watchNudge wakes
	// the library watcher to re-arm over a fresh root table after a
	// runtime library create; watchReady closes once the first arm
	// pass finishes, so a test can order its drop after the watches
	// exist.
	watchQueue     *watchPending
	watchScans     chan []string
	watchNudge     chan struct{}
	watchReady     chan struct{}
	watchReadyOnce sync.Once
	// watchRecheck is Config.WatchRecheck.
	watchRecheck time.Duration
	// watchScanHook runs as the watcher scans a settled directory, or lets
	// go of one a catalog scan covered, in a test; nothing in the server
	// sets it.
	watchScanHook func(dir string, scanned bool)
	// watchArmHook runs as a watcher pass starts arming its roots (false)
	// and once they are armed (true), in a test; nothing in the server
	// sets it. Atomic, since a test sets it while the watcher runs.
	watchArmHook atomic.Pointer[func(armed bool)]
	// watchLookHook runs at each stage of a look at a root, before its
	// stat ("stat"), its walk ("walk"), each watch a rewalk prunes
	// ("prune") and each create it arms ("arm"), and on the loop as a
	// renamed directory's watch drops ("drop") and as a create is queued
	// for a root's look ("queue");
	// watchMountsHook stands in for the mount-table read; watchCheckHook
	// runs once the watcher has acted on a look's answer;
	// watchLookWait stands in for how long a pass waits for its looks;
	// watcher is the running kernel watcher, for a test to drop a watch
	// the way an unmount does. Tests only, like the hooks above.
	watchLookHook   atomic.Pointer[func(stage, path string)]
	watchMountsHook atomic.Pointer[func() (string, error)]
	watchCheckHook  atomic.Pointer[func(root string)]
	watchLookWait   atomic.Int64
	watcher         atomic.Pointer[fsnotify.Watcher]
}

func newRoots(c *core, cfg Config) *Roots {
	return &Roots{
		core:            c,
		configRoots:     cfg.Roots,
		startupScan:     cfg.ScanOnStart,
		podcastRootName: cfg.PodcastRootName,
		rootProbeEvery:  cfg.RootProbeEvery,
		watchQueue:      newWatchPending(cfg.WatchSettle),
		watchRecheck:    cfg.WatchRecheck,
		watchScans:      make(chan []string, 1),
		watchNudge:      make(chan struct{}, 1),
		watchReady:      make(chan struct{}),
	}
}
