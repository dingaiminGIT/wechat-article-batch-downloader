package certificate

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestLoadOrCreateDefaultPersistsPrivateCertificate(t *testing.T) {
	dir := t.TempDir()
	first, err := LoadOrCreateDefault(dir)
	if err != nil {
		t.Fatal(err)
	}
	second, err := LoadOrCreateDefault(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(first.Cert, second.Cert) || !bytes.Equal(first.PrivateKey, second.PrivateKey) {
		t.Fatal("expected the generated certificate to be reused")
	}
	info, err := os.Stat(filepath.Join(dir, "root-ca-key.pem"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("private key mode = %o, want 600", info.Mode().Perm())
	}
}

func TestLoadOrCreateUsesExactConfiguredPathsAndName(t *testing.T) {
	dir := t.TempDir()
	certPath := filepath.Join(dir, "custom", "desktop-ca.pem")
	keyPath := filepath.Join(dir, "private", "desktop-ca-key.pem")
	created, err := LoadOrCreate(certPath, keyPath, "Desktop Test CA")
	if err != nil {
		t.Fatal(err)
	}
	if created.Name != "Desktop Test CA" {
		t.Fatalf("Name = %q, want Desktop Test CA", created.Name)
	}
	for _, path := range []string{certPath, keyPath} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("configured certificate file %s was not created: %v", path, err)
		}
	}
	reloaded, err := LoadOrCreate(certPath, keyPath, "Desktop Test CA")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(created.Cert, reloaded.Cert) || !bytes.Equal(created.PrivateKey, reloaded.PrivateKey) {
		t.Fatal("expected the configured certificate to be reused")
	}
}

func TestLoadOrCreateRejectsIncompleteConfiguredPair(t *testing.T) {
	dir := t.TempDir()
	certPath := filepath.Join(dir, "root-ca.pem")
	keyPath := filepath.Join(dir, "root-ca-key.pem")
	if err := os.WriteFile(certPath, []byte("existing certificate"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadOrCreate(certPath, keyPath, "Test CA"); err == nil {
		t.Fatal("expected an incomplete configured certificate pair to fail")
	}
}
