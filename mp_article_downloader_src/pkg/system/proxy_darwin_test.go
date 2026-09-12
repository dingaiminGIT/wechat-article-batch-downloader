//go:build darwin

package system

import (
	"fmt"
	"os"
	"strings"
	"testing"
)

func TestProxyOwnershipKeepsProtocolsSeparate(t *testing.T) {
	owner := ProxySettings{Hostname: "127.0.0.1", Port: "2133"}
	if !isOwned(&network_proxy_info{Server: "127.0.0.1", Port: "2133", Enabled: true}, owner) {
		t.Fatal("not owned")
	}
	if isOwned(&network_proxy_info{Server: "127.0.0.1", Port: "7897", Enabled: true}, owner) {
		t.Fatal("would overwrite another proxy")
	}
	if isOwned(nil, owner) {
		t.Fatal("nil")
	}
}
func TestProxyRestoreAndExternalChanges(t *testing.T) {
	for _, external := range []bool{false, true} {
		t.Run(fmt.Sprint(external), func(t *testing.T) {
			t.Setenv("MP_ARCHIVE_DATA", t.TempDir())
			old := networkRun
			defer func() { networkRun = old }()
			state := map[bool]network_proxy_info{false: {Enabled: true, Server: "proxy.company", Port: "8080"}, true: {Enabled: false, Server: "secure.company", Port: "8443"}}
			networkRun = func(args ...string) ([]byte, error) {
				secure := strings.Contains(args[0], "secure")
				v := state[secure]
				switch args[0] {
				case "-getwebproxy", "-getsecurewebproxy":
					on := "No"
					if v.Enabled {
						on = "Yes"
					}
					return []byte(fmt.Sprintf("Enabled: %s\nServer: %s\nPort: %s\n", on, v.Server, v.Port)), nil
				case "-setwebproxy", "-setsecurewebproxy":
					v.Server = args[2]
					v.Port = args[3]
					v.Enabled = true
				default:
					v.Enabled = args[2] == "on"
				}
				state[secure] = v
				return nil, nil
			}
			owner := ProxySettings{Device: "Wi-Fi", Hostname: "127.0.0.1", Port: "2133"}
			if e := enable_proxy(owner); e != nil {
				t.Fatal(e)
			}
			if external {
				state[true] = network_proxy_info{Enabled: true, Server: "other.app", Port: "7897"}
			}
			if e := disable_proxy(owner); e != nil {
				t.Fatal(e)
			}
			if state[false].Server != "proxy.company" || !state[false].Enabled {
				t.Fatal(state)
			}
			if external {
				if state[true].Server != "other.app" {
					t.Fatal("overwrote external change")
				}
			} else if state[true].Enabled || state[true].Server != "secure.company" {
				t.Fatal(state)
			}
			if _, e := os.Stat(snapshotPath()); !os.IsNotExist(e) {
				t.Fatal("snapshot not cleared")
			}
		})
	}
}
