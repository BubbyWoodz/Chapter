//go:build integrationfixture

// Test-only loopback TLS host: real relay/router/Postgres migrations, memory media.
// Never part of the release server; never accepts a non-test database name.
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/mneme-blog/mneme/server/internal/api"
	"github.com/mneme-blog/mneme/server/internal/blobs"
	"github.com/mneme-blog/mneme/server/internal/config"
	"github.com/mneme-blog/mneme/server/internal/store"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "native fixture:", err)
		os.Exit(1)
	}
}
func run() error {
	dsn := os.Getenv("TEST_DATABASE_URL")
	parsed, err := url.Parse(dsn)
	if err != nil || parsed == nil || (!strings.HasSuffix(parsed.Path, "_test") || (parsed.Hostname() != "127.0.0.1" && parsed.Hostname() != "localhost") || parsed.Port() != "55432") || os.Getenv("CHAPTER_NATIVE_FIXTURE") != "1" {
		return fmt.Errorf("explicit fixture opt-in and *_test database required")
	}
	root := os.Getenv("CHAPTER_FIXTURE_DIR")
	if root == "" {
		return fmt.Errorf("CHAPTER_FIXTURE_DIR required")
	}
	if err = os.MkdirAll(root, 0700); err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	st, err := store.New(ctx, dsn)
	if err != nil {
		return err
	}
	defer st.Close()
	if err = st.Migrate(ctx); err != nil {
		return err
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return err
	}
	cert := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: "Chapter disposable test CA"}, NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	der, err := x509.CreateCertificate(rand.Reader, cert, cert, &key.PublicKey, key)
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(root, "root.pem"), pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0600); err != nil {
		return err
	}
	listener, err := net.Listen("tcp", "127.0.0.1:55443")
	if err != nil {
		return err
	}
	tlsListener := tls.NewListener(listener, &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}})
	server := &http.Server{Handler: api.New(st, blobs.NewMemory(), config.Config{SessionTTL: time.Hour}).Routes(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 2 * time.Minute, WriteTimeout: 2 * time.Minute}
	if err = os.WriteFile(filepath.Join(root, "ready"), []byte("https://localhost:55443"), 0600); err != nil {
		return err
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	err = server.Serve(tlsListener)
	if err == http.ErrServerClosed {
		return nil
	}
	return err
}
