package metrics

import (
	"runtime"
	"sync"
	"time"
)

// GoRuntime registers process and Go runtime metrics on the registry:
// go_goroutines, go_memstats_alloc_bytes, go_memstats_heap_inuse_bytes,
// go_memstats_sys_bytes, go_gc_cycles_total, and process_start_time_seconds
// (captured once, at registration). The memstats-backed metrics share one
// runtime.ReadMemStats call per scrape. Call it at most once per registry;
// a second call panics on the duplicate names.
func (r *Registry) GoRuntime() {
	s := &memSampler{reg: r}
	r.GaugeFunc("go_goroutines", "Number of goroutines that currently exist.",
		func() float64 { return float64(runtime.NumGoroutine()) })
	r.GaugeFunc("go_memstats_alloc_bytes", "Bytes of allocated heap objects.",
		func() float64 { return s.snapshot().allocBytes })
	r.GaugeFunc("go_memstats_heap_inuse_bytes", "Bytes in in-use heap spans.",
		func() float64 { return s.snapshot().heapInuseBytes })
	r.GaugeFunc("go_memstats_sys_bytes", "Bytes of memory obtained from the OS.",
		func() float64 { return s.snapshot().sysBytes })
	r.registerFunc("go_gc_cycles_total", "Completed GC cycles since process start.", typeCounter,
		func() float64 { return s.snapshot().gcCycles })
	r.Gauge("process_start_time_seconds", "Start time of the process since the unix epoch in seconds.").
		Set(float64(time.Now().UnixNano()) / 1e9)
}

// memSampler caches one runtime.ReadMemStats result per scrape. The
// registry bumps scrapeSeq at the start of each exposition pass; the first
// memstats-backed metric rendered in that pass refreshes the cache and the
// rest reuse it.
type memSampler struct {
	reg *Registry

	mu  sync.Mutex
	seq uint64
	cur memSnapshot
}

type memSnapshot struct {
	allocBytes     float64
	heapInuseBytes float64
	sysBytes       float64
	gcCycles       float64
}

func (s *memSampler) snapshot() memSnapshot {
	seq := s.reg.scrapeSeq.Load()
	s.mu.Lock()
	defer s.mu.Unlock()
	// seq starts at 1 for the first scrape, so the zero-valued sampler
	// always refreshes on first use; seq == 0 means a call outside any
	// scrape, which always re-reads.
	if s.seq != seq || seq == 0 {
		var ms runtime.MemStats
		runtime.ReadMemStats(&ms)
		s.cur = memSnapshot{
			allocBytes:     float64(ms.Alloc),
			heapInuseBytes: float64(ms.HeapInuse),
			sysBytes:       float64(ms.Sys),
			gcCycles:       float64(ms.NumGC),
		}
		s.seq = seq
	}
	return s.cur
}
