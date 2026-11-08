package api

import (
	"context"
	"errors"
	"github.com/mneme-blog/mneme/server/internal/blobs"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type interruptedMediaDelete struct {
	blobs.Store
	remaining int
	partial   bool
}

func (s *interruptedMediaDelete) DeletePrefix(ctx context.Context, prefix string) (int, error) {
	if s.remaining > 0 {
		s.remaining--
		if s.partial {
			_, _ = s.Store.DeletePrefix(ctx, prefix+"0")
		}
		return 0, errors.New("public synthetic storage interruption: NEVER expose this detail")
	}
	return s.Store.DeletePrefix(ctx, prefix)
}
func TestMediaSweepFailureIsNotAcknowledgedAndRetryPreservesOwnerObjectBoundaries(t *testing.T) {
	for _, partial := range []bool{false, true} {
		t.Run(map[bool]string{false: "before sweep", true: "partial sweep"}[partial], func(t *testing.T) {
			ctx := context.Background()
			memory := blobs.NewMemory()
			owner, id := "public-owner", "0123456789abcdef"
			targets := []string{chunkKey(owner, id, 0), chunkKey(owner, id, 99)}
			keep := []string{chunkKey("another-owner", id, 0), chunkKey(owner, id+"extra", 0), chunkKey(owner, "anothermedia01234", 0)}
			for _, key := range append(targets, keep...) {
				if err := memory.Put(ctx, key, []byte("public opaque ciphertext")); err != nil {
					t.Fatal(err)
				}
			}
			server := New(nil, &interruptedMediaDelete{Store: memory, remaining: 1, partial: partial}, testConfig())
			attempt := func() *httptest.ResponseRecorder {
				response := httptest.NewRecorder()
				server.finishMediaDeletion(response, httptest.NewRequest(http.MethodDelete, "/v1/media/"+id, nil), owner, id)
				return response
			}
			failed := attempt()
			if failed.Code != 500 {
				t.Fatalf("failed sweep falsely acknowledged: %d", failed.Code)
			}
			if strings.Contains(failed.Body.String(), "NEVER expose") {
				t.Fatal("private storage detail exposed")
			}
			if _, err := memory.Get(ctx, targets[1]); err != nil {
				t.Fatal("unremoved chunk must remain for retry", err)
			}
			for retry := 0; retry < 2; retry++ {
				if response := attempt(); response.Code != 204 {
					t.Fatalf("retry %d status %d", retry, response.Code)
				}
			}
			for _, key := range targets {
				if _, err := memory.Get(ctx, key); !errors.Is(err, blobs.ErrNotFound) {
					t.Fatalf("target survived retry: %s %v", key, err)
				}
			}
			for _, key := range keep {
				if _, err := memory.Get(ctx, key); err != nil {
					t.Fatalf("unrelated owner/object erased: %s %v", key, err)
				}
			}
		})
	}
}
func TestMediaDeletionWithoutConfiguredStorageRetainsClientRetryIntent(t *testing.T) {
	server := New(nil, blobs.Disabled{}, testConfig())
	response := httptest.NewRecorder()
	server.finishMediaDeletion(response, httptest.NewRequest(http.MethodDelete, "/v1/media/0123456789abcdef", nil), "public-owner", "0123456789abcdef")
	if response.Code != 503 {
		t.Fatalf("unconfigured deletion falsely acknowledged: %d", response.Code)
	}
}
