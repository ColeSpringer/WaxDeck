package service

import (
	"context"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// stubFlowJobs is a FlowJobs whose only interesting answers are the jobs
// gate and the live detector version; the job-running methods are inert.
type stubFlowJobs struct {
	jobs    bool
	version string
}

func (s stubFlowJobs) JobsSupported() bool            { return s.jobs }
func (s stubFlowJobs) SilenceDetectorVersion() string { return s.version }
func (stubFlowJobs) AnalyzeSilence(context.Context, string) (flow.SilenceAnalysis, error) {
	return flow.SilenceAnalysis{}, nil
}
func (stubFlowJobs) CreateMergeJob(context.Context, []string, []string, string) (string, error) {
	return "", nil
}
func (stubFlowJobs) CreateSplitJob(context.Context, string, []int64, string, string) (string, error) {
	return "", nil
}
func (stubFlowJobs) JobStatus(context.Context, string) (string, float64, int, string, error) {
	return "", 0, 0, "", nil
}
func (stubFlowJobs) DownloadJobResult(context.Context, string, int, string) error { return nil }

func TestSilenceMapStale(t *testing.T) {
	cases := []struct {
		name  string
		flow  FlowJobs
		mapDV string
		want  bool
	}{
		{"detector moved on", stubFlowJobs{jobs: true, version: "v2"}, "v1", true},
		{"detector unchanged", stubFlowJobs{jobs: true, version: "v2"}, "v2", false},
		{"live version unknown", stubFlowJobs{jobs: true, version: ""}, "v1", false},
		{"jobs unavailable", stubFlowJobs{jobs: false, version: "v2"}, "v1", false},
		{"no jobs bridge", nil, "v1", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			l := &Library{flowJobs: tc.flow}
			got := l.silenceMapStale(wdb.SilenceMap{DetectorVersion: tc.mapDV})
			if got != tc.want {
				t.Fatalf("silenceMapStale = %v, want %v", got, tc.want)
			}
		})
	}
}
