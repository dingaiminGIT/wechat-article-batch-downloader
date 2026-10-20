package archive

import (
	"strings"
	"testing"
	"time"
)

func TestNativeCursorPersistsAndResumes(t *testing.T) {
	dir := t.TempDir()
	fail := true
	fetch := func(s Scan) (Page, error) {
		if s.Cursor == "" {
			return Page{Source: "native", Profile: "account-A", NextCursor: "cursor-A", Next: 1, More: true, Articles: []Article{{ID: "a"}}}, nil
		}
		if s.Cursor != "cursor-A" || s.Profile != "account-A" {
			t.Errorf("checkpoint lost: %+v", s)
		}
		if fail {
			return Page{}, UserError("原生连接已断开")
		}
		return Page{Source: "native", Profile: "account-A", Next: 2, Articles: []Article{{ID: "a"}, {ID: "b"}}}, nil
	}
	m := NewWithCursor(dir, fetch)
	m.delay = time.Millisecond
	_ = m.Start(Options{Biz: "x", Mode: "all"})
	s := awaitStatus(t, m, "x", "paused")
	if s.Cursor != "cursor-A" || s.Profile != "account-A" || len(s.Articles) != 1 || !strings.Contains(s.Message, "原生连接已断开") {
		t.Fatal(s)
	}
	fail = false
	m = NewWithCursor(dir, fetch)
	m.delay = time.Millisecond
	_ = m.Start(Options{Biz: "x", Mode: "all", Resume: true})
	s = awaitStatus(t, m, "x", "complete")
	if len(s.Articles) != 2 {
		t.Fatal(s)
	}
}
func TestNativeCursorCyclePauses(t *testing.T) {
	m := NewWithCursor(t.TempDir(), func(s Scan) (Page, error) {
		next := "A"
		if s.Cursor == "A" {
			next = "B"
		}
		return Page{Source: "native", Profile: "p", NextCursor: next, More: true, Next: s.Offset + 1, Articles: []Article{{ID: string(rune('a' + s.Offset))}}}, nil
	})
	m.delay = time.Millisecond
	_ = m.Start(Options{Biz: "x", Mode: "all"})
	s := awaitStatus(t, m, "x", "paused")
	if s.Pages != 3 || s.Cursor != "B" {
		t.Fatal(s)
	}
}
func TestNativePauseDoesNotAdvanceInFlight(t *testing.T) {
	entered, release := make(chan struct{}), make(chan struct{})
	m := NewWithCursor(t.TempDir(), func(s Scan) (Page, error) {
		close(entered)
		<-release
		return Page{Source: "native", Profile: "p", NextCursor: "A", More: true, Next: 1, Articles: []Article{{ID: "a"}}}, nil
	})
	_ = m.Start(Options{Biz: "x", Mode: "all"})
	<-entered
	m.Pause("x")
	close(release)
	s := awaitStatus(t, m, "x", "paused")
	if s.Cursor != "" || len(s.Articles) != 0 {
		t.Fatal(s)
	}
}
