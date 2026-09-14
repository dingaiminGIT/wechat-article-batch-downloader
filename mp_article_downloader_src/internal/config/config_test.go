package config

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/viper"
)

func TestNewUsesConfigPathFromEnv(t *testing.T) {
	t.Cleanup(viper.Reset)

	configPath := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(configPath, []byte("proxy:\n  hostname: 0.0.0.0\n"), 0644); err != nil {
		t.Fatal(err)
	}
	t.Setenv(EnvConfigPath, configPath)

	cfg := New("test", "")

	if cfg.FullPath != configPath {
		t.Fatalf("FullPath = %q, want %q", cfg.FullPath, configPath)
	}
	if cfg.RootDir != filepath.Dir(configPath) {
		t.Fatalf("RootDir = %q, want %q", cfg.RootDir, filepath.Dir(configPath))
	}
	if cfg.Filename != filepath.Base(configPath) {
		t.Fatalf("Filename = %q, want %q", cfg.Filename, filepath.Base(configPath))
	}
	if !cfg.Existing {
		t.Fatal("Existing = false, want true")
	}
}

func TestLoadCertFilesCreatesExplicitCertificateBeforeLegacyFallback(t *testing.T) {
	t.Cleanup(viper.Reset)
	home := t.TempDir()
	t.Setenv("HOME", home)

	legacyCert := []byte("legacy mitmproxy certificate")
	legacyKey := []byte("legacy mitmproxy key")
	legacyDir := filepath.Join(home, ".mitmproxy")
	if err := os.MkdirAll(legacyDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(legacyDir, "mitmproxy-ca-cert.pem"), legacyCert, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(legacyDir, "mitmproxy-ca.pem"), legacyKey, 0600); err != nil {
		t.Fatal(err)
	}

	certPath := filepath.Join(home, ".config", "mp-article-batch-downloader", "certs", "root-ca.pem")
	keyPath := filepath.Join(home, ".config", "mp-article-batch-downloader", "certs", "root-ca-key.pem")
	viper.Set("cert.file", certPath)
	viper.Set("cert.key", keyPath)
	viper.Set("cert.name", "MP Article Batch Downloader Local CA")

	loaded, err := LoadCertFiles()
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Name == "mitmproxy" || bytes.Equal(loaded.Cert, legacyCert) {
		t.Fatal("explicit desktop certificate was replaced by the legacy mitmproxy certificate")
	}
	for _, path := range []string{certPath, keyPath} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("configured certificate file %s was not created: %v", path, err)
		}
	}
}

func TestLoadCertFilesDoesNotHideIncompleteExplicitPairWithLegacyFallback(t *testing.T) {
	t.Cleanup(viper.Reset)
	home := t.TempDir()
	t.Setenv("HOME", home)
	legacyDir := filepath.Join(home, ".mitmproxy")
	if err := os.MkdirAll(legacyDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(legacyDir, "mitmproxy-ca-cert.pem"), []byte("legacy cert"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(legacyDir, "mitmproxy-ca.pem"), []byte("legacy key"), 0600); err != nil {
		t.Fatal(err)
	}

	certPath := filepath.Join(home, "desktop", "root-ca.pem")
	keyPath := filepath.Join(home, "desktop", "root-ca-key.pem")
	if err := os.MkdirAll(filepath.Dir(certPath), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(certPath, []byte("incomplete"), 0644); err != nil {
		t.Fatal(err)
	}
	viper.Set("cert.file", certPath)
	viper.Set("cert.key", keyPath)

	if _, err := LoadCertFiles(); err == nil {
		t.Fatal("expected incomplete explicit certificate files to fail instead of using legacy mitmproxy files")
	}
}
