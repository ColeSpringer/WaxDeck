package api

import (
	"context"
	"crypto/subtle"
	"net/http"
	"net/url"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The similarity worker API. Workers authenticate with a
// server-configured token, never a user credential: they are a
// server-level integration and see every item regardless of library
// visibility. The audio pull is a raw media route (ServeAnalysisAudio)
// authenticated with the same token.

// workerPaths are the strict routes the worker token (and only the
// worker token) opens. Session credentials are refused here: worker
// endpoints ignore visibility, so a user session must never reach
// them.
var workerPaths = map[string]bool{
	"/api/v1/similarity/work":       true,
	"/api/v1/similarity/embeddings": true,
}

// workerAuthorized reports whether the request carries a configured
// worker token as its bearer.
func (s *Server) workerAuthorized(r *http.Request) bool {
	h := r.Header.Get("Authorization")
	if len(h) <= 7 || !strings.EqualFold(h[:7], "bearer ") {
		return false
	}
	presented := []byte(h[7:])
	for _, t := range s.workerTokens {
		if subtle.ConstantTimeCompare(presented, []byte(t)) == 1 {
			return true
		}
	}
	return false
}

type ctxWorkerKey struct{}

func workerFromContext(ctx context.Context) bool {
	ok, _ := ctx.Value(ctxWorkerKey{}).(bool)
	return ok
}

// requireWorker guards the strict worker handlers (belt and braces
// behind the middleware's path routing).
func requireWorker(ctx context.Context) error {
	if !workerFromContext(ctx) {
		return &service.Error{Kind: service.KindInternal, Msg: "worker endpoint reached without worker auth"}
	}
	return nil
}

func (s *Server) GetSimilarityStatus(ctx context.Context, _ GetSimilarityStatusRequestObject) (GetSimilarityStatusResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	st, err := s.svc.SimilarityStatusFor(ctx, uc)
	if err != nil {
		return nil, err
	}
	out := SimilarityStatus{
		Enabled:        st.Enabled,
		EmbeddedTracks: st.EmbeddedTracks,
		TotalTracks:    st.TotalTracks,
		CoveragePct:    float32(st.CoveragePct),
		QueueDepth:     st.QueueDepth,
	}
	if st.Model != "" {
		out.Model = ptr(st.Model)
		out.Dims = ptr(st.Dims)
	}
	if !st.LastIngestAt.IsZero() {
		out.LastIngestAt = ptr(st.LastIngestAt)
	}
	return GetSimilarityStatus200JSONResponse(out), nil
}

// workerIdlePollSeconds is the sleep an idle worker is told to take.
const workerIdlePollSeconds = 60

func (s *Server) PullSimilarityWork(ctx context.Context, req PullSimilarityWorkRequestObject) (PullSimilarityWorkResponseObject, error) {
	if err := requireWorker(ctx); err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 10, 50)
	if !ok {
		return nil, &service.Error{Kind: service.KindInvalid, Msg: "limit must be between 1 and 50"}
	}
	work, err := s.svc.LeaseSimilarityWork(ctx, limit)
	if err != nil {
		return nil, err
	}
	out := SimilarityWorkPage{Items: []SimilarityWorkItem{}, RetryAfterSeconds: workerIdlePollSeconds}
	for _, w := range work {
		item := SimilarityWorkItem{
			Pid:        w.PID,
			Essence:    w.Essence,
			AudioUrl:   "/media/analysis/" + url.PathEscape(w.PID),
			DurationMs: w.DurationMs,
			MediaType:  MediaType(w.MediaType),
		}
		if w.LocalPath != "" {
			item.LocalPath = ptr(w.LocalPath)
		}
		out.Items = append(out.Items, item)
	}
	return PullSimilarityWork200JSONResponse(out), nil
}

func (s *Server) ReportEmbeddings(ctx context.Context, req ReportEmbeddingsRequestObject) (ReportEmbeddingsResponseObject, error) {
	if err := requireWorker(ctx); err != nil {
		return nil, err
	}
	if req.Body == nil || len(req.Body.Embeddings) == 0 {
		return ReportEmbeddings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "embeddings must not be empty"))}, nil
	}
	if len(req.Body.Embeddings) > 100 {
		return ReportEmbeddings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "at most 100 embeddings per report"))}, nil
	}
	if req.Body.Dims < 8 || req.Body.Dims > 4096 {
		return ReportEmbeddings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "dims must be between 8 and 4096"))}, nil
	}
	if req.Body.Model == "" || len(req.Body.Model) > 128 {
		return ReportEmbeddings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "model must be between 1 and 128 characters"))}, nil
	}
	batch := make([]service.EmbeddingUpload, 0, len(req.Body.Embeddings))
	for _, e := range req.Body.Embeddings {
		batch = append(batch, service.EmbeddingUpload{PID: e.Pid, Essence: e.Essence, Vector: e.Vector})
	}
	res, err := s.svc.IngestEmbeddings(ctx, req.Body.Model, req.Body.Dims, batch)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return ReportEmbeddings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	out := EmbeddingIngestResult{Accepted: res.Accepted, Replaced: res.Replaced}
	if len(res.Rejected) > 0 {
		rej := make([]RejectedEmbedding, 0, len(res.Rejected))
		for _, r := range res.Rejected {
			re := RejectedEmbedding{Code: r.Code, Message: r.Message}
			if r.PID != "" {
				re.Pid = ptr(r.PID)
			}
			if r.Essence != "" {
				re.Essence = ptr(r.Essence)
			}
			rej = append(rej, re)
		}
		out.Rejected = &rej
	}
	return ReportEmbeddings200JSONResponse(out), nil
}

// ServeAnalysisAudio is the raw /media/analysis/{pid} route: worker
// token in, decode-ready audio out (16 kHz mono, gain untouched, WAV
// or FLAC). Needs the streaming engine; without it workers use local
// paths or wait.
func (s *Server) ServeAnalysisAudio(w http.ResponseWriter, r *http.Request) {
	if !s.workerAuthorized(r) {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a worker token is required")
		return
	}
	if s.bridge == nil {
		writeError(w, http.StatusServiceUnavailable, "feature-unavailable",
			"the streaming engine is not configured; use local-path analysis or configure WAXDECK_FLOW_URL")
		return
	}
	s.bridge.ServeAnalysisAudio(w, r, r.PathValue("pid"))
}
