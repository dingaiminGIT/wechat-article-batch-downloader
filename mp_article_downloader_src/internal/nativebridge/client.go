// Package nativebridge controls a private, read-only WeChat sidecar process.
package nativebridge

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"
)

type Account struct {
	Biz      string `json:"biz"`
	Username string `json:"username"`
	Nickname string `json:"nickname"`
}
type Status struct {
	ArticleReady bool      `json:"article_ready"`
	Ready        bool      `json:"ready"`
	State        string    `json:"state"`
	Message      string    `json:"message"`
	Profile      string    `json:"profile,omitempty"`
	Accounts     []Account `json:"accounts"`
}
type Article struct {
	Title     string `json:"title"`
	URL       string `json:"url"`
	Digest    string `json:"digest"`
	Published int64  `json:"published"`
}
type Page struct {
	Articles   []Article `json:"articles"`
	NextCursor string    `json:"next_cursor"`
	IsEnd      *int      `json:"is_end"`
	Profile    string    `json:"profile"`
}
type Client struct {
	mu                   sync.Mutex
	cmd                  *exec.Cmd
	done                 chan struct{}
	address, token, data string
}

func New(data string) *Client { return &Client{data: filepath.Join(data, "native-runtime")} }
func (c *Client) start() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cmd != nil {
		select {
		case <-c.done:
			c.cmd = nil
		default:
			return nil
		}
	}
	exe, _ := os.Executable()
	root := filepath.Join(filepath.Dir(exe), "native")
	if override := os.Getenv("MP_NATIVE_RESOURCE_ROOT"); override != "" {
		root = override
	}
	node := filepath.Join(root, "node")
	script := filepath.Join(root, "bridge.mjs")
	if _, err := os.Stat(script); err != nil {
		return fmt.Errorf("安装包缺少原生读取组件，请使用完整的本机预览版")
	}
	if err := os.MkdirAll(c.data, 0700); err != nil {
		return err
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return err
	}
	c.token = hex.EncodeToString(raw)
	cmd := exec.Command(node, script)
	cmd.Env = append(os.Environ(), "MP_NATIVE_DATA="+c.data, "MP_NATIVE_TOKEN="+c.token)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = io.Discard
	if err = cmd.Start(); err != nil {
		return fmt.Errorf("原生组件无法启动：%w", err)
	}
	c.cmd = cmd
	c.done = make(chan struct{})
	done := c.done
	go func() { _ = cmd.Wait(); close(done) }()
	ready := make(chan string, 1)
	go func() {
		reader := bufio.NewScanner(stdout)
		if reader.Scan() {
			ready <- reader.Text()
		} else {
			ready <- ""
		}
		for reader.Scan() {
		}
	}()
	select {
	case line := <-ready:
		var info struct {
			Port int `json:"port"`
		}
		if json.Unmarshal([]byte(line), &info) != nil || info.Port < 1 || info.Port > 65535 {
			_ = cmd.Process.Kill()
			return fmt.Errorf("原生组件启动失败")
		}
		c.address = "http://127.0.0.1:" + strconv.Itoa(info.Port)
		return nil
	case <-time.After(8 * time.Second):
		_ = cmd.Process.Kill()
		return fmt.Errorf("原生组件启动超时")
	}
}
func (c *Client) call(method, route string, body any, out any) error {
	c.mu.Lock()
	address, token, cmd, done := c.address, c.token, c.cmd, c.done
	c.mu.Unlock()
	if cmd == nil {
		return fmt.Errorf("请先连接原生读取通道")
	}
	select {
	case <-done:
		return fmt.Errorf("原生连接组件已退出，请重新连接")
	default:
	}
	b, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(method, address+route, bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	client := http.Client{Timeout: 55 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("原生读取通道无响应，请重新连接")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("原生连接返回异常状态")
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 16*1024*1024))
	if err != nil {
		return err
	}
	var envelope struct {
		Error string `json:"error"`
	}
	if json.Unmarshal(data, &envelope) != nil {
		return fmt.Errorf("原生响应格式错误")
	}
	if envelope.Error != "" {
		return fmt.Errorf("%s", envelope.Error)
	}
	return json.Unmarshal(data, out)
}
func (c *Client) Connect() (Status, error) {
	var s Status
	if err := c.start(); err != nil {
		return s, err
	}
	err := c.call("POST", "/connect", nil, &s)
	return s, err
}
func (c *Client) Status() (Status, error) {
	c.mu.Lock()
	running := c.cmd != nil
	c.mu.Unlock()
	if !running {
		return Status{State: "stopped", Message: "请连接原生读取通道", Accounts: []Account{}}, nil
	}
	var s Status
	err := c.call("GET", "/status", nil, &s)
	return s, err
}
func (c *Client) Fetch(biz, username, cursor, profile string) (Page, error) {
	var p Page
	err := c.call("POST", "/page", map[string]string{"biz": biz, "username": username, "cursor": cursor, "profile": profile}, &p)
	return p, err
}
func (c *Client) HTML(url string) ([]byte, error) {
	var data struct {
		HTML string `json:"html"`
	}
	err := c.call("POST", "/html", map[string]string{"url": url}, &data)
	return []byte(data.HTML), err
}
func (c *Client) Running() bool { c.mu.Lock(); defer c.mu.Unlock(); return c.cmd != nil }
func (c *Client) Close() {
	c.mu.Lock()
	cmd, done := c.cmd, c.done
	c.cmd = nil
	c.address = ""
	c.mu.Unlock()
	if cmd == nil {
		return
	}
	_ = cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-done:
	case <-time.After(6 * time.Second):
		_ = cmd.Process.Kill()
		<-done
	}
}
