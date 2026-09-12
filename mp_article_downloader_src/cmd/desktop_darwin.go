//go:build darwin

package cmd

import (
	"context"
	"fmt"
	"github.com/spf13/cobra"
	"mp_article_batch_downloader/pkg/certificate"
	"mp_article_batch_downloader/pkg/system"
	"os"
	"os/exec"
	"strconv"
	"time"
)

func init() {
	root_cmd.AddCommand(&cobra.Command{Use: "desktop-prepare", RunE: func(cmd *cobra.Command, args []string) error {
		f, e := os.CreateTemp("", "mp-archive-cert-*.pem")
		if e != nil {
			return e
		}
		defer os.Remove(f.Name())
		if _, e = f.Write(CertFiles.Cert); e != nil {
			f.Close()
			return e
		}
		f.Close()
		if exec.Command("/usr/bin/security", "verify-cert", "-c", f.Name()).Run() == nil {
			return nil
		}
		if e = certificate.InstallCertificate(CertFiles.Cert); e != nil {
			return fmt.Errorf("首次使用需要管理员授权以信任本机连接证书: %w", e)
		}
		return nil
	}})
	root_cmd.AddCommand(&cobra.Command{Use: "desktop-recover", RunE: func(cmd *cobra.Command, args []string) error { return system.DisableProxy(system.ProxySettings{}) }})
}
func watchDesktopParent(ctx context.Context, stop context.CancelFunc) {
	pid, e := strconv.Atoi(os.Getenv("MP_ARCHIVE_PARENT"))
	if e != nil || pid <= 1 {
		return
	}
	go func() {
		t := time.NewTicker(time.Second)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				if os.Getppid() != pid {
					stop()
					return
				}
			}
		}
	}()
}
