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
