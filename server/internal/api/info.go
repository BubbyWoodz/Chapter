package api

import "net/http"

// handleInfo is additive, unauthenticated discovery for direct native clients.
// Only protocol facts and public limits: no owner counts, tokens, internal URLs
// or deployment secrets. It does not promise proxy-only services are installed.
func (s *Server) handleInfo(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"protocol":                      1,
		"record_envelope":               1,
		"owner_authorized_registration": true,
		"require_approval":              s.cfg.RequireApproval,
		"max_push_entries":              maxPushEntries,
		"max_media_chunk_bytes":         2 << 20,
		"conflict_resolution":           "wall-clock-last-write-wins",
	})
}
