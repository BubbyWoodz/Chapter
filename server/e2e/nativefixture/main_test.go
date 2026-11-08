//go:build integrationfixture

// SPDX-License-Identifier: AGPL-3.0-or-later
package main

import "testing"

func TestFixtureDSNAllowsOnlyDisposableDatabase(t *testing.T) {
	valid := "postgres://runner@127.0.0.1:55432/chapter_native_test?sslmode=disable"
	if !safeFixtureDSN(valid) {
		t.Fatal("isolated fixture DSN refused")
	}
	for _, dsn := range []string{
		"postgres://runner@production:55432/chapter_native_test?sslmode=disable",
		"postgres://runner@127.0.0.1:5432/chapter_native_test?sslmode=disable",
		"postgres://runner@127.0.0.1:55432/user_test?sslmode=disable",
		valid + "&host=production", valid + "&dbname=production", valid + "#fragment",
		"postgres://runner:password@127.0.0.1:55432/chapter_native_test?sslmode=disable",
		"postgres://runner@127.0.0.1:55432/chapter_native_test?sslmode=disable&sslmode=disable",
		"postgres://runner@127.0.0.1:55432/%63hapter_native_test?sslmode=disable",
		"postgresql://runner@127.0.0.1:55432/chapter_native_test?sslmode=disable",
	} {
		if safeFixtureDSN(dsn) {
			t.Errorf("unsafe fixture DSN accepted: %s", dsn)
		}
	}
}
