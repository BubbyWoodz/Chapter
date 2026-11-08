package api

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"os"
	"testing"
)

// CI supplies signatures produced by the actual Apple CryptoKit implementation.
// Use the relay's real domain builders/verifier; deterministic signature equality
// would incorrectly reject CryptoKit's valid hedged Ed25519 signatures.
func TestNativeAppleAuthenticationInterop(t *testing.T) {
	path := os.Getenv("CHAPTER_NATIVE_OUTPUT")
	if path == "" {
		t.Skip("Apple-produced fixture supplied by native CI only")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Registration       map[string]string `json:"registration"`
		Challenge          string            `json:"challenge"`
		ChallengeSignature string            `json:"challengeSignature"`
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	decode := func(value string) []byte {
		t.Helper()
		bytes, err := base64.StdEncoding.DecodeString(value)
		if err != nil {
			t.Fatal(err)
		}
		return bytes
	}
	r := fixture.Registration
	owner, device, signer := decode(r["owner_pubkey"]), decode(r["device_pubkey"]), decode(r["owner_sign_pubkey"])
	if len(owner) != 32 || len(device) != 32 || len(signer) != 32 {
		t.Fatal("invalid public key framing")
	}
	if !ed25519.Verify(device, registerMessage(owner, device), decode(r["signature"])) {
		t.Fatal("native device registration rejected")
	}
	if !ed25519.Verify(signer, bindDeviceMessage(owner, signer, device), decode(r["owner_signature"])) {
		t.Fatal("native owner binding rejected")
	}
	challenge := decode(fixture.Challenge)
	if len(challenge) != 32 || !ed25519.Verify(device, challenge, decode(fixture.ChallengeSignature)) {
		t.Fatal("native challenge response rejected")
	}
	if ed25519.Verify(device, append([]byte("wrong-domain:"), challenge...), decode(fixture.ChallengeSignature)) {
		t.Fatal("signature accepted for different message")
	}
}
