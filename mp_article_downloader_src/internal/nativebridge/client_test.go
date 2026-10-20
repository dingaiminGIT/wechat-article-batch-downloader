package nativebridge

import (
	"net/http"
	"net/http/httptest"
	"os/exec"
	"testing"
)

func TestPrivateRequestAndPageDecode(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" || r.URL.Path != "/page" || r.Method != "POST" {
			t.Error("missing private request authentication")
		}
		_, _ = w.Write([]byte(`{"articles":[{"title":"a","url":"https://mp.weixin.qq.com/s?__biz=b&mid=1&idx=1"}],"is_end":0,"next_cursor":"next","profile":"p"}`))
	}))
	defer server.Close()
	c := &Client{cmd: &exec.Cmd{}, done: make(chan struct{}), address: server.URL, token: "test-token"}
	p, e := c.Fetch("b", "gh_test", "", "p")
	if e != nil || p.IsEnd == nil || *p.IsEnd != 0 || p.NextCursor != "next" || len(p.Articles) != 1 {
		t.Fatal(p, e)
	}
}
func TestRemoteFailureIsNotEmptyPage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"error":"原生连接已断开"}`))
	}))
	defer server.Close()
	c := &Client{cmd: &exec.Cmd{}, done: make(chan struct{}), address: server.URL, token: "x"}
	if _, e := c.Fetch("b", "gh_test", "", ""); e == nil {
		t.Fatal("failure became empty success")
	}
}
func TestStoppedStatusDoesNotStartProcess(t *testing.T) {
	c := New(t.TempDir())
	s, e := c.Status()
	if e != nil || s.State != "stopped" || c.cmd != nil {
		t.Fatal(s, e)
	}
}
