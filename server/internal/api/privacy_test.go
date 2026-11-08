package api

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPublicProtocolInfo(t *testing.T) {
	cfg := testConfig()
	cfg.RequireApproval = true
	r := httptest.NewRecorder()
	New(nil, nil, cfg).Routes().ServeHTTP(r, httptest.NewRequest(http.MethodGet, "/v1/info", nil))
	if r.Code != 200 {
		t.Fatalf("status %d", r.Code)
	}
	var info map[string]any
	if err := json.Unmarshal(r.Body.Bytes(), &info); err != nil {
		t.Fatal(err)
	}
	if info["protocol"] != float64(1) || info["owner_authorized_registration"] != true || info["require_approval"] != true || info["max_push_entries"] != float64(500) {
		t.Fatalf("unexpected info %v", info)
	}
	if len(info) != 7 {
		t.Fatal("review every public info field for privacy")
	}
}

func TestRequestLogsDoNotExposeIdentifiersOrInputs(t *testing.T) {
	var logs bytes.Buffer
	previous := log.Writer()
	log.SetOutput(&logs)
	defer log.SetOutput(previous)
	srv := New(nil, nil, testConfig()).Routes()
	for _, path := range []string{"/v1/media/private-record/chunks/7?ticket=top-secret", "/unknown/private-title?token=top-secret"} {
		srv.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, path, nil))
	}
	// An invalid JSON unknown-field error normally echoes the attacker-controlled
	// field name. That name can itself contain a phrase or title.
	srv.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/v1/register", strings.NewReader(`{"private-title":true}`)))
	for _, secret := range []string{"private-record", "private-title", "top-secret", "chunks/7"} {
		if strings.Contains(logs.String(), secret) {
			t.Fatalf("sensitive input reached logs: %s", secret)
		}
	}
	if !strings.Contains(logs.String(), "GET /v1/media/{id}/chunks/{n}") || !strings.Contains(logs.String(), "unmatched route") {
		t.Fatal("missing safe route diagnostics")
	}
}
