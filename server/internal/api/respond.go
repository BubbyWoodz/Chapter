package api

import (
	"encoding/json"
	"log"
	"net/http"
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("write json: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// writeInternalError answers a 500 with a generic message and logs the real
// error type server-side. Driver messages can contain identifiers or values,
// so routine logs retain only the safe route, operation and error type. More
// invasive diagnostics require a deliberate operator-controlled session.
func writeInternalError(w http.ResponseWriter, r *http.Request, msg string, err error) {
	log.Printf("%s: %s (%T)", requestRoute(r), msg, err)
	writeError(w, http.StatusInternalServerError, msg)
}

// decodeJSON reads a JSON body, rejecting unknown fields and oversized payloads.
//
// Neither callers nor routine logs receive the decoder message: unknown field
// names are attacker-controlled and may themselves contain sensitive text.
// Operators get only the error type; callers get one generic message.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 32<<20) // 32 MiB ceiling for an encrypted blob batch
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		log.Printf("decode %s: invalid body (%T)", requestRoute(r), err)
		writeError(w, http.StatusBadRequest, "invalid request body")
		return false
	}
	return true
}

// confirmed answers the 400 for a wrong or missing typed confirmation. Every
// destructive admin action enforces its word server-side — a stray request
// holding a valid token must not be able to destroy anything — and this keeps
// the message format identical across them.
func confirmed(w http.ResponseWriter, got, want string) bool {
	if got != want {
		writeError(w, http.StatusBadRequest, `confirmation required: {"confirm":"`+want+`"}`)
		return false
	}
	return true
}
