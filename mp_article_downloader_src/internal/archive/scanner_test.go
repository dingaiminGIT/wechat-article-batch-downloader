package archive

import (
	"errors"
	"os"
	"sync/atomic"
	"testing"
	"time"
)

func awaitStatus(t *testing.T, m *Manager, biz, status string) Scan {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		s := m.Get(biz)
		if s.Status == status {
			return s
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("wanted %s, got %+v", status, m.Get(biz))
	return Scan{}
}
func TestStableURL(t *testing.T) {
	a := StableURL("https://mp.weixin.qq.com/s?__biz=x&amp;mid=1&amp;idx=1&amp;key=SECRET#rd")
	b := StableURL("http://mp.weixin.qq.com/s?idx=1&mid=1&__biz=x&pass_ticket=other")
	if a != b || ID(a) != ID(b) {
		t.Fatal(a, b)
	}
	if StableURL("https://example.com/s") != "" {
		t.Fatal("accepted external URL")
	}
	legacyA := StableURL("http://mp.weixin.qq.com/mp/appmsg/show?__biz=x&appmsgid=1001&itemidx=1&sign=aaa&key=SECRET")
	legacyB := StableURL("http://mp.weixin.qq.com/mp/appmsg/show?__biz=x&appmsgid=1002&itemidx=1&sign=bbb&pass_ticket=SECRET")
	if legacyA == legacyB || ID(legacyA) == ID(legacyB) {
		t.Fatal("collapsed distinct legacy articles", legacyA, legacyB)
	}
	if legacyA != "https://mp.weixin.qq.com/mp/appmsg/show?__biz=x&appmsgid=1001&itemidx=1&sign=aaa" {
		t.Fatal("unexpected legacy URL", legacyA)
	}
}
func TestPartialFailureResumesPersistedOffset(t *testing.T) {
	dir := t.TempDir()
	var fail atomic.Bool
	fail.Store(true)
	fetch := func(biz string, offset int) (Page, error) {
		if offset == 0 {
			return Page{Articles: []Article{{ID: "a", Title: "one"}}, More: true, Next: 10}, nil
		}
		if fail.Load() {
			return Page{}, errors.New("expired")
		}
		return Page{Articles: []Article{{ID: "a"}, {ID: "b", Title: "two"}}, Next: 20}, nil
	}
	m := New(dir, fetch)
	m.delay = time.Millisecond
	if e := m.Start(Options{Biz: "x", Mode: "all"}); e != nil {
		t.Fatal(e)
	}
	s := awaitStatus(t, m, "x", "error")
	if len(s.Articles) != 1 || s.Offset != 10 {
		t.Fatalf("lost checkpoint: %+v", s)
	}
	fail.Store(false)
	m2 := New(dir, fetch)
	if e := m2.Start(Options{Biz: "x", Mode: "all", Resume: true}); e != nil {
		t.Fatal(e)
	}
	s = awaitStatus(t, m2, "x", "complete")
	if len(s.Articles) != 2 {
		t.Fatal(s)
	}
}
func TestDateRangeAndRecentLimit(t *testing.T) {
	for _, mode := range []string{"date", "recent"} {
		m := New(t.TempDir(), func(string, int) (Page, error) {
			return Page{Articles: []Article{{ID: "a", Published: 30}, {ID: "b", Published: 20}, {ID: "c", Published: 10}}}, nil
		})
		if err := m.Start(Options{Biz: "x", Mode: mode, Limit: 2, After: 15, Before: 25}); err != nil {
			t.Fatal(err)
		}
		s := awaitStatus(t, m, "x", "complete")
		want := 2
		if mode == "date" {
			want = 1
		}
		if len(s.Articles) != want {
			t.Fatal(s)
		}
	}
}
func TestPauseInFlightPreservesPage(t *testing.T) {
	gate := make(chan struct{})
	entered := make(chan struct{})
	m := New(t.TempDir(), func(string, int) (Page, error) {
		close(entered)
		<-gate
		return Page{Articles: []Article{{ID: "a"}}, Next: 10}, nil
	})
	if e := m.Start(Options{Biz: "x", Mode: "all"}); e != nil {
		t.Fatal(e)
	}
	<-entered
	m.Pause("x")
	close(gate)
	s := awaitStatus(t, m, "x", "paused")
	if len(s.Articles) != 0 || s.Offset != 0 {
		t.Fatal(s)
	}
}
func TestBadOffsetNotComplete(t *testing.T) {
	m := New(t.TempDir(), func(string, int) (Page, error) { return Page{More: true, Next: 0}, nil })
	_ = m.Start(Options{Biz: "x", Mode: "all"})
	awaitStatus(t, m, "x", "error")
}
func TestDiskFailureDoesNotLaunchScan(t *testing.T) {
	p := t.TempDir() + "/file"
	_ = os.WriteFile(p, []byte("x"), 0600)
	m := New(p, func(string, int) (Page, error) { t.Error("must not fetch"); return Page{}, nil })
	if m.Start(Options{Biz: "x", Mode: "all"}) == nil {
		t.Fatal("ignored persistence failure")
	}
}
