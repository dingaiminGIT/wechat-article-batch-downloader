//go:build darwin

package system

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var networkRun = func(args ...string) ([]byte, error) {
	return exec.Command("/usr/sbin/networksetup", args...).CombinedOutput()
}

// Keep the two protocols independently: they may have different upstream settings.
type proxySnapshot struct {
	Device      string
	HTTP, HTTPS *network_proxy_info
	Owner       ProxySettings
}

func snapshotPath() string {
	if d := os.Getenv("MP_ARCHIVE_DATA"); d != "" {
		return filepath.Join(d, "proxy-snapshot.json")
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".config", "mp-article-batch-downloader", "proxy-snapshot.json")
}
func setProxy(device string, secure bool, info *network_proxy_info) error {
	set, state := "-setwebproxy", "-setwebproxystate"
	if secure {
		set, state = "-setsecurewebproxy", "-setsecurewebproxystate"
	}
	if info.Server != "" && info.Port != "" && info.Port != "0" {
		if out, err := networkRun(set, device, info.Server, info.Port); err != nil {
			return fmt.Errorf("设置代理失败: %s", out)
		}
	}
	enabled := "off"
	if info.Enabled {
		enabled = "on"
	}
	if out, err := networkRun(state, device, enabled); err != nil {
		return fmt.Errorf("切换代理失败: %s", out)
	}
	return nil
}
func isOwned(info *network_proxy_info, owner ProxySettings) bool {
	return info != nil && info.Server == owner.Hostname && info.Port == owner.Port
}
func restoreSnapshot() error {
	b, err := os.ReadFile(snapshotPath())
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var s proxySnapshot
	if err = json.Unmarshal(b, &s); err != nil {
		return err
	}
	if s.HTTP == nil || s.HTTPS == nil {
		return fmt.Errorf("代理备份不完整")
	}
	for _, pair := range []struct {
		secure bool
		info   *network_proxy_info
	}{{false, s.HTTP}, {true, s.HTTPS}} {
		cur, e := read_network_proxy(s.Device, pair.secure)
		if e != nil {
			return e
		}
		// Do not overwrite changes made by another proxy application while we ran.
		if isOwned(cur, s.Owner) {
			if e = setProxy(s.Device, pair.secure, pair.info); e != nil {
				return e
			}
		}
	}
	return os.Remove(snapshotPath())
}
func enable_proxy(args ProxySettings) error {
	args = merge_default_settings(args)
	if err := restoreSnapshot(); err != nil {
		return err
	}
	h, e := read_network_proxy(args.Device, false)
	if e != nil {
		return e
	}
	s, e := read_network_proxy(args.Device, true)
	if e != nil {
		return e
	}
	// A dead instance of this tool must not be restored as an enabled proxy.
	for _, info := range []*network_proxy_info{h, s} {
		if isOwned(info, args) {
			conn, err := net.DialTimeout("tcp", net.JoinHostPort(args.Hostname, args.Port), 300*time.Millisecond)
			if err != nil {
				info.Enabled = false
			} else {
				conn.Close()
				return fmt.Errorf("代理端口已被占用")
			}
		}
	}
	snap := proxySnapshot{Device: args.Device, HTTP: h, HTTPS: s, Owner: args}
	b, _ := json.Marshal(snap)
	if e = os.MkdirAll(filepath.Dir(snapshotPath()), 0700); e != nil {
		return e
	}
	if e = os.WriteFile(snapshotPath(), b, 0600); e != nil {
		return e
	}
	desired := &network_proxy_info{Enabled: true, Server: args.Hostname, Port: args.Port}
	if e = setProxy(args.Device, false, desired); e != nil {
		_ = restoreSnapshot()
		return e
	}
	if e = setProxy(args.Device, true, desired); e != nil {
		_ = restoreSnapshot()
		return e
	}
	return nil
}
func disable_proxy(args ProxySettings) error { return restoreSnapshot() }

func fetch_cur_proxy(args ProxySettings) (*ProxySettings, error) {
	device := args.Device
	if device == "" {
		if port, err := get_network_interfaces(); err == nil && port != nil {
			device = port.Port
		}
	}
	if device == "" {
		device = "Wi-Fi"
	}
	webProxy, err := read_network_proxy(device, false)
	if err != nil {
		return nil, err
	}
	if webProxy.Enabled && webProxy.Server != "" && webProxy.Port != "" {
		return &ProxySettings{
			Device:   device,
			Hostname: webProxy.Server,
			Port:     webProxy.Port,
		}, nil
	}
	secureProxy, err := read_network_proxy(device, true)
	if err != nil {
		return nil, err
	}
	if secureProxy.Enabled && secureProxy.Server != "" && secureProxy.Port != "" {
		return &ProxySettings{
			Device:   device,
			Hostname: secureProxy.Server,
			Port:     secureProxy.Port,
		}, nil
	}
	return nil, nil
}

type network_proxy_info struct {
	Enabled bool
	Server  string
	Port    string
}

func read_network_proxy(device string, secure bool) (*network_proxy_info, error) {
	command := "-getwebproxy"
	if secure {
		command = "-getsecurewebproxy"
	}
	output, err := networkRun(command, device)
	if err != nil {
		return nil, fmt.Errorf("读取系统代理失败，%v", err)
	}
	info := &network_proxy_info{}
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		parts := strings.SplitN(strings.TrimSpace(line), ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(parts[0]))
		value := strings.TrimSpace(parts[1])
		switch key {
		case "enabled":
			info.Enabled = strings.EqualFold(value, "yes")
		case "server":
			info.Server = value
		case "port":
			info.Port = value
		}
	}
	return info, nil
}

func get_network_interfaces() (*HardwarePort, error) {
	// 获取所有硬件端口信息
	cmd := exec.Command("networksetup", "-listallhardwareports")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("执行 networksetup 命令失败: %v", err)
	}
	// 解析硬件端口信息
	var ports []HardwarePort
	lines := strings.Split(string(output), "\n")

	var cur_port HardwarePort
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Hardware Port:") {
			if cur_port.Port != "" {
				ports = append(ports, cur_port)
			}
			cur_port = HardwarePort{}
			cur_port.Port = strings.TrimPrefix(line, "Hardware Port: ")
		} else if strings.HasPrefix(line, "Device:") {
			cur_port.Device = strings.TrimPrefix(line, "Device: ")
		}
	}
	if cur_port.Port != "" {
		ports = append(ports, cur_port)
	}
	// 获取网络接口信息
	cmd = exec.Command("scutil", "--nwi")
	output, err = cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("执行 scutil 命令失败: %v", err)
	}
	// 使用正则解析接口信息
	re := regexp.MustCompile(`Network interfaces{0,1}: ([0-9a-zA-Z]{1,})`)
	matches := re.FindStringSubmatch(string(output))
	// 将接口信息与硬件端口匹配
	if len(matches) >= 2 {
		for i := range ports {
			if ports[i].Device == matches[1] {
				return &ports[i], nil
			}
		}
	}
	return nil, fmt.Errorf("未找到硬件端口信息")
}
