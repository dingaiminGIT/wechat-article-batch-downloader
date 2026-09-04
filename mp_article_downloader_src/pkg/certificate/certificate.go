package certificate

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

type CertFileAndKeyFile struct {
	Name       string
	Cert       []byte
	PrivateKey []byte
}

const DefaultCertificateName = "MP Article Batch Downloader Local CA"

// LoadOrCreateDefault creates one private root CA per user installation. The
// private key is never embedded in the binary or shared between users.
func LoadOrCreateDefault(dir string) (*CertFileAndKeyFile, error) {
	certPath := filepath.Join(dir, "root-ca.pem")
	keyPath := filepath.Join(dir, "root-ca-key.pem")
	certBytes, certErr := os.ReadFile(certPath)
	keyBytes, keyErr := os.ReadFile(keyPath)
	if certErr == nil && keyErr == nil {
		if err := os.Chmod(keyPath, 0600); err != nil {
			return nil, fmt.Errorf("protect certificate key: %w", err)
		}
		return &CertFileAndKeyFile{Name: DefaultCertificateName, Cert: certBytes, PrivateKey: keyBytes}, nil
	}
	if (certErr == nil) != (keyErr == nil) {
		return nil, fmt.Errorf("certificate files are incomplete in %s; remove both files and retry", dir)
	}
	if !os.IsNotExist(certErr) || !os.IsNotExist(keyErr) {
		return nil, fmt.Errorf("read certificate files: %v, %v", certErr, keyErr)
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, fmt.Errorf("create certificate directory: %w", err)
	}
	privateKey, err := rsa.GenerateKey(rand.Reader, 3072)
	if err != nil {
		return nil, fmt.Errorf("generate certificate key: %w", err)
	}
	serialLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, serialLimit)
	if err != nil {
		return nil, fmt.Errorf("generate certificate serial: %w", err)
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: DefaultCertificateName, Organization: []string{"Baiya Lab"}},
		NotBefore:             now.Add(-5 * time.Minute),
		NotAfter:              now.AddDate(5, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            0,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &privateKey.PublicKey, privateKey)
	if err != nil {
		return nil, fmt.Errorf("create certificate: %w", err)
	}
	certBytes = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyBytes = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privateKey)})
	if err := os.WriteFile(keyPath, keyBytes, 0600); err != nil {
		return nil, fmt.Errorf("write certificate key: %w", err)
	}
	if err := os.WriteFile(certPath, certBytes, 0644); err != nil {
		_ = os.Remove(keyPath)
		return nil, fmt.Errorf("write certificate: %w", err)
	}
	return &CertFileAndKeyFile{Name: DefaultCertificateName, Cert: certBytes, PrivateKey: keyBytes}, nil
}

type CertificateSubject struct {
	// label
	CN string
	// cenc
	OU string
	// hpky
	O string
	// hpky
	L string
	// subj
	S string
	// cenc
	C string
}
type Certificate struct {
	Thumbprint string
	Subject    CertificateSubject
}

// 获取所有证书
func FetchCertificates() ([]Certificate, error) {
	return fetchCertificates()
}

// 根据名称检查是否存在指定证书
func CheckHasCertificate(cert_name string) (bool, error) {
	certificates, err := fetchCertificates()
	if err != nil {
		return false, err
	}
	for _, cert := range certificates {
		if cert.Subject.CN == cert_name {
			return true, nil
		}
	}
	return false, nil
}

// 安装指定证书
func InstallCertificate(cert_data []byte) error {
	return installCertificate(cert_data)
}

// 卸载指定证书
func UninstallCertificate(name string) error {
	return uninstallCertificate(name)
}
