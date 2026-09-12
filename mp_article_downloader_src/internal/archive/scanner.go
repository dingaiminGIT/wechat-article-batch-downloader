// Package archive owns resumable history scans, independently of the article webview.
package archive

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type Article struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	URL       string `json:"url"`
	Digest    string `json:"digest"`
	Published int64  `json:"published"`
}
type Options struct {
	Biz    string `json:"biz"`
	Mode   string `json:"mode"`
	Limit  int    `json:"limit"`
	After  int64  `json:"after"`
	Before int64  `json:"before"`
	Resume bool   `json:"resume"`
}
type Scan struct {
	Options  Options   `json:"options"`
	Status   string    `json:"status"`
	Message  string    `json:"message"`
	Offset   int       `json:"offset"`
	Pages    int       `json:"pages"`
	Articles []Article `json:"articles"`
	Updated  int64     `json:"updated"`
}
type Page struct {
	Articles []Article
	More     bool
	Next     int
}
type Fetch func(string, int) (Page, error)
type Manager struct {
	mu    sync.Mutex
	scans map[string]*Scan
	stops map[string]chan struct{}
	dir   string
	fetch Fetch
	delay time.Duration
}

func New(dir string, fetch Fetch) *Manager {
	m := &Manager{scans: map[string]*Scan{}, stops: map[string]chan struct{}{}, dir: dir, fetch: fetch, delay: 800 * time.Millisecond}
	entries, _ := filepath.Glob(filepath.Join(dir, "*.json"))
	for _, path := range entries {
		b, e := os.ReadFile(path)
		if e != nil {
			continue
		}
		var s Scan
		if json.Unmarshal(b, &s) == nil && s.Options.Biz != "" {
			if s.Status == "running" {
				s.Status = "paused"
				s.Message = "上次读取已中断，可从断点继续"
			}
			m.scans[s.Options.Biz] = &s
		}
	}
	return m
}
func (m *Manager) save(s *Scan) error {
	s.Updated = time.Now().UnixMilli()
	if err := os.MkdirAll(m.dir, 0700); err != nil {
		return err
	}
	b, err := json.Marshal(s)
	if err != nil {
		return err
	}
	p := filepath.Join(m.dir, ID(s.Options.Biz)+".json")
	if err = os.WriteFile(p+".tmp", b, 0600); err != nil {
		return err
	}
	return os.Rename(p+".tmp", p)
}
func (m *Manager) Get(biz string) Scan {
	m.mu.Lock()
	defer m.mu.Unlock()
	s := m.scans[biz]
	if s == nil {
		return Scan{Status: "idle", Articles: []Article{}}
	}
	copy := *s
	copy.Articles = append([]Article{}, s.Articles...)
	return copy
}
func (m *Manager) Start(o Options) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if o.Biz == "" {
		return fmt.Errorf("请先在微信里打开公众号文章")
	}
	if o.Resume {
		if previous := m.scans[o.Biz]; previous != nil {
			o = previous.Options
			o.Resume = true
		}
	}
	if o.Mode != "all" && o.Mode != "recent" && o.Mode != "date" {
		return fmt.Errorf("请选择读取范围")
	}
	if o.Mode == "recent" && (o.Limit < 1 || o.Limit > 10000) {
		return fmt.Errorf("篇数须在 1–10000 之间")
	}
	if o.Mode == "date" && (o.After <= 0 || o.Before < o.After) {
		return fmt.Errorf("日期范围无效")
	}
	if len(m.stops) > 0 {
		return fmt.Errorf("已有公众号正在读取，请先暂停")
	}
	s := m.scans[o.Biz]
	if !o.Resume || s == nil {
		s = &Scan{Options: o, Articles: []Article{}}
		m.scans[o.Biz] = s
	}
	if o.Resume && s.Status == "complete" {
		return fmt.Errorf("已完成读取，请重新读取以获取新增文章")
	}
	s.Status = "running"
	s.Message = "正在读取历史文章"
	if err := m.save(s); err != nil {
		s.Status = "error"
		return err
	}
	stop := make(chan struct{})
	m.stops[o.Biz] = stop
	go m.run(s, stop)
	return nil
}
func (m *Manager) Pause(biz string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if ch := m.stops[biz]; ch != nil {
		select {
		case <-ch:
		default:
			close(ch)
		}
	}
}
func (m *Manager) Close() {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, ch := range m.stops {
		select {
		case <-ch:
		default:
			close(ch)
		}
	}
}
func (m *Manager) run(s *Scan, stop chan struct{}) {
	defer func() { m.mu.Lock(); delete(m.stops, s.Options.Biz); m.mu.Unlock() }()
	finish := func(status, msg string) {
		m.mu.Lock()
		defer m.mu.Unlock()
		s.Status = status
		s.Message = msg
		_ = m.save(s)
	}
	seen := map[string]bool{}
	for _, a := range s.Articles {
		seen[a.ID] = true
	}
	for {
		select {
		case <-stop:
			finish("paused", "已暂停，继续时从已保存的断点读取")
			return
		default:
		}
		p, err := m.fetch(s.Options.Biz, s.Offset)
		if err != nil {
			finish("error", "读取未完成："+err.Error()+"。请在微信重新打开文章后继续。")
			return
		}
		select {
		case <-stop:
			finish("paused", "已暂停，当前页将于继续时重新读取")
			return
		default:
		}
		m.mu.Lock()
		s.Pages++
		for _, a := range p.Articles {
			if a.ID == "" {
				a.ID = ID(a.URL)
			}
			if seen[a.ID] {
				continue
			}
			seen[a.ID] = true
			if s.Options.Mode == "date" && (a.Published < s.Options.After || a.Published > s.Options.Before) {
				continue
			}
			if s.Options.Mode == "recent" && len(s.Articles) >= s.Options.Limit {
				break
			}
			s.Articles = append(s.Articles, a)
		}
		done := !p.More || s.Options.Mode == "recent" && len(s.Articles) >= s.Options.Limit
		badOffset := p.More && p.Next <= s.Offset
		if !badOffset {
			s.Offset = p.Next
		}
		s.Message = fmt.Sprintf("已读取 %d 页，找到 %d 篇文章", s.Pages, len(s.Articles))
		err = m.save(s)
		m.mu.Unlock()
		if err != nil {
			finish("error", "保存读取进度失败："+err.Error())
			return
		}
		if done {
			finish("complete", fmt.Sprintf("已完成所选范围的读取，共 %d 篇文章", len(s.Articles)))
			return
		}
		if badOffset {
			finish("error", "微信未返回有效的下一页，历史读取尚未完成")
			return
		}
		select {
		case <-stop:
			finish("paused", "已暂停，可从断点继续")
			return
		case <-time.After(m.delay):
		}
	}
}
func ID(s string) string { sum := sha256.Sum256([]byte(s)); return hex.EncodeToString(sum[:])[:16] }
func StableURL(raw string) string {
	u, e := url.Parse(html.UnescapeString(raw))
	if e != nil {
		return ""
	}
	if u.Hostname() != "mp.weixin.qq.com" {
		return ""
	}
	u.Scheme = "https"
	u.Fragment = ""
	q := u.Query()
	stable := url.Values{}
	keys := []string{"__biz", "mid", "idx", "sn"}
	if u.Path == "/mp/appmsg/show" {
		keys = []string{"__biz", "appmsgid", "itemidx", "sign"}
	}
	for _, k := range keys {
		if q.Get(k) != "" {
			stable.Set(k, q.Get(k))
		}
	}
	u.RawQuery = stable.Encode()
	return u.String()
}
func SafeName(s string) string {
	s = strings.Map(func(r rune) rune {
		if r < 32 || strings.ContainsRune(`/\:*?"<>|`, r) {
			return '_'
		}
		return r
	}, s)
	r := []rune(strings.Trim(s, " ."))
	if len(r) > 70 {
		r = r[:70]
	}
	if len(r) == 0 {
		return "公众号"
	}
	return string(r)
}
