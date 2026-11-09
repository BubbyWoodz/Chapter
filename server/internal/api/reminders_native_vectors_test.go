// SPDX-License-Identifier: AGPL-3.0-or-later
package api

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

// Golden vectors for the native iOS reminders client (apps/ios ChapterReminders): which
// reminder_id values PUT /v1/reminders accepts, which fire_at strings it parses (and to
// what instant), and how GET /v1/reminders formats fire_at. They use the handler's own
// recordIDRe, time.Parse(time.RFC3339) and Format(time.RFC3339). Regenerate with
// CHAPTER_WRITE_VECTORS=1 go test ./internal/api -run TestNativeReminderVectors
func TestNativeReminderVectors(t *testing.T) {
	type idCase struct {
		ID string `json:"id"`
		OK bool   `json:"ok"`
	}
	type parseCase struct {
		In    string `json:"in"`
		OK    bool   `json:"ok"`
		Unix  int64  `json:"unix,omitempty"`
		Nanos int    `json:"nanos,omitempty"`
	}
	type formatCase struct {
		Unix  int64  `json:"unix"`
		Nanos int    `json:"nanos"`
		Out   string `json:"out"`
	}
	ids := []string{"r1", "daily-writing", "a.b:c_d-e", "", ".", "..", "a/b", "a b", "é", "%2e", string(make([]byte, 128)), "x?y"}
	long := ""
	for len(long) < 128 {
		long += "a"
	}
	ids = append(ids, long, long+"a")
	fires := []string{
		"2026-11-09T14:00:00Z", "2026-11-09T14:00:00.123456789Z", "2026-11-09T14:00:00.1Z", "2026-11-09T06:00:00-08:00",
		"2026-11-09T14:00:00+00:00", "2026-11-09T14:00:00z", "2026-11-09t14:00:00Z", "2026-11-09 14:00:00Z", "2026-11-09T14:00Z",
		"2026-11-09T14:00:00", "2026-02-29T00:00:00Z", "2024-02-29T00:00:00Z", "2026-04-31T00:00:00Z", "2026-11-09T24:00:00Z",
		"2026-11-09T23:59:60Z", "2026-13-01T00:00:00Z", "2026-11-09T14:00:00+24:00", "2026-11-09T14:00:00+23:59", "2026-11-09T14:00:00+0800",
		"0000-01-01T00:00:00Z", "9999-12-31T23:59:59Z", "+12026-11-09T14:00:00Z", "2026-11-09T14:00:00.Z", "2026-11-09T14:00:00,5Z",
		"2026-1-09T14:00:00Z", "", "2026-11-09T14:00:00Z ", " 2026-11-09T14:00:00Z", "2026-11-09T14:00:00.1234567891Z", "2026-11-09T14:00:00-00:00",
		"2026-11-09T14:00:00+24:59", "2026-11-09T14:00:00+25:00", "2026-11-09T14:00:00+23:60", "2026-11-09T14:00:00-24:00", "2026-11-09T14:00:00+00:61",
		"2026-11-09T14:00:00+24:60", "2026-11-09T14:00:00+05:30", "2026-00-10T00:00:00Z", "2026-11-00T00:00:00Z", "1900-02-29T00:00:00Z",
		"2000-02-29T00:00:00Z", "2026-11-09T14:00:00+5:30", "\u0662\u0660\u0662\u0666-11-09T14:00:00Z", "2026-11-09T14:00:00.123456789012345678901234567890Z",
		"2026-11-09T14:00:00+00:00:00", "2026-11-09T14:00:00ZZ",
	}
	formats := []formatCase{{Unix: 1794232800}, {Unix: 1794232800, Nanos: 999999999}, {Unix: -1, Nanos: 500000000}, {Unix: 0}, {Unix: -1}, {Unix: 253402300799}, {Unix: -62135596800}, {Unix: 951782400}}
	var fixture struct {
		IDs     []idCase     `json:"ids"`
		Parse   []parseCase  `json:"parse"`
		Formats []formatCase `json:"formats"`
	}
	for _, id := range ids {
		fixture.IDs = append(fixture.IDs, idCase{ID: id, OK: recordIDRe.MatchString(id)})
	}
	for _, in := range fires {
		c := parseCase{In: in}
		if at, err := time.Parse(time.RFC3339, in); err == nil {
			c.OK, c.Unix, c.Nanos = true, at.Unix(), at.Nanosecond()
		}
		fixture.Parse = append(fixture.Parse, c)
	}
	for _, f := range formats {
		f.Out = time.Unix(f.Unix, int64(f.Nanos)).UTC().Format(time.RFC3339)
		fixture.Formats = append(fixture.Formats, f)
	}
	path := filepath.Join("..", "..", "..", "apps", "ios", "ChapterCore", "Tests", "ChapterCoreTests", "Fixtures", "reminders.json")
	if os.Getenv("CHAPTER_WRITE_VECTORS") == "1" {
		raw, err := json.MarshalIndent(fixture, "", " ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, append(raw, '\n'), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var saved = fixture
	saved.IDs, saved.Parse, saved.Formats = nil, nil, nil
	if err := json.Unmarshal(raw, &saved); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(saved, fixture) {
		t.Fatal("native reminder vectors are stale; regenerate with CHAPTER_WRITE_VECTORS=1")
	}
}
