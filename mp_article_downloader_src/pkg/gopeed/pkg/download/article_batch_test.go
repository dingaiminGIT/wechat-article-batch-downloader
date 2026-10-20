package download

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/GopeedLab/gopeed/internal/fetcher"
	"github.com/GopeedLab/gopeed/pkg/base"
	oa "github.com/GopeedLab/gopeed/pkg/officialaccount"
)

func batchTestTask(id, batch, path string, status base.Status) *Task {
	t := NewTask()
	t.ID, t.Protocol, t.Status = id, "officialaccount", status
	t.Meta = &fetcher.FetcherMeta{Req: &base.Request{URL: "officialaccount://test", Labels: map[string]string{"batch_id": batch}}, Opts: &base.Options{Name: id, Path: path}}
	t.Progress = &Progress{}
	initTask(t)
	return t
}

// Uses the real queue, fetcher, exporter and persistent store, but supplies local
// HTML rather than issuing requests to WeChat or writing to the user's library.
func TestArticleBatchControlsRealExportQueue(t *testing.T) {
	dir := t.TempDir()
	d := NewDownloader(&DownloaderConfig{Storage: NewBoltStorage(filepath.Join(dir, "db")), StorageDir: dir})
	if err := d.Setup(); err != nil {
		t.Fatal(err)
	}
	cfg, _ := d.GetConfig()
	cfg.MaxRunning = 1
	if err := d.PutConfig(cfg); err != nil {
		t.Fatal(err)
	}
	previous := oa.NativeHTMLProvider
	defer func() { oa.NativeHTMLProvider = previous }()
	defer d.Close()
	entered := make(chan string, 4)
	release := make(chan struct{}, 4)
	done := make(chan *Event, 4)
	oa.NativeHTMLProvider = func(url string) ([]byte, bool, error) {
		entered <- url
		<-release
		return []byte(`<html><div id="js_content">Fixture body</div><script>window.cgiDataNew = {title:"Fixture",content_noencode:"<p>Batch control fixture body</p>",nick_name:"Fixture",page_type:0};</script></html>`), true, nil
	}
	defer func() {
		for i := 0; i < 4; i++ {
			select {
			case release <- struct{}{}:
			default:
			}
		}
	}()
	d.Listener(func(e *Event) {
		if e.Key == EventKeyFinally {
			done <- e
		}
	})
	path := filepath.Join(dir, "articles")
	for _, name := range []string{"first", "second", "third"} {
		_, err := d.CreateDirect(&base.Request{URL: "officialaccount://https://mp.weixin.qq.com/s/" + name, Labels: map[string]string{"batch_id": "fixture", "download_mode": "fast"}}, &base.Options{Path: path, Name: name + ".html"})
		if err != nil {
			t.Fatal(err)
		}
	}
	waitRequest := func() {
		t.Helper()
		select {
		case <-entered:
		case <-time.After(5 * time.Second):
			t.Fatal("export did not start")
		}
	}
	waitDone := func() {
		t.Helper()
		select {
		case e := <-done:
			if e.Err != nil {
				t.Fatal(e.Err)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("export did not finish")
		}
	}
	waitRequest()
	if changed, finishing, err := d.ControlArticleBatch("fixture", path, "pause"); err != nil || changed != 2 || finishing != 1 {
		t.Fatalf("pause %d %d %v", changed, finishing, err)
	}
	release <- struct{}{}
	waitDone()
	select {
	case <-entered:
		t.Fatal("paused queue unexpectedly fetched next article")
	case <-time.After(150 * time.Millisecond):
	}
	if changed, _, err := d.ControlArticleBatch("fixture", path, "resume"); err != nil || changed != 2 {
		t.Fatalf("resume %d %v", changed, err)
	}
	waitRequest()
	if changed, finishing, err := d.ControlArticleBatch("fixture", path, "stop"); err != nil || changed != 1 || finishing != 1 {
		t.Fatalf("stop %d %d %v", changed, finishing, err)
	}
	release <- struct{}{}
	waitDone()
	select {
	case <-entered:
		t.Fatal("terminated queue unexpectedly fetched next article")
	case <-time.After(150 * time.Millisecond):
	}
	files, err := filepath.Glob(filepath.Join(path, "html", "*.html"))
	if err != nil || len(files) != 2 {
		t.Fatalf("expected two complete exports, got %v: %v", files, err)
	}
	if _, _, err = d.ControlArticleBatch("fixture", path, "resume"); err == nil {
		t.Fatal("terminated batch resumed")
	}
	var stored []*Task
	if err = d.storage.List(bucketTask, &stored); err != nil {
		t.Fatal(err)
	}
	completed, canceled := 0, 0
	for _, task := range stored {
		if task.Status == base.DownloadStatusDone {
			completed++
		}
		if task.Status == ArticleCanceled {
			canceled++
		}
	}
	if completed != 2 || canceled != 1 {
		t.Fatalf("persistent state done=%d canceled=%d", completed, canceled)
	}
}

func TestArticleBatchPauseResumeStopIsolationAndPersistence(t *testing.T) {
	dir := t.TempDir()
	s := NewBoltStorage(filepath.Join(dir, "db"))
	defer s.Close()
	if err := s.Setup([]string{bucketTask, bucketSave, bucketConfig}); err != nil {
		t.Fatal(err)
	}
	d := NewDownloader(&DownloaderConfig{Storage: s, StorageDir: dir, DownloaderStoreConfig: &base.DownloaderStoreConfig{MaxRunning: 1}})
	path := filepath.Join(dir, "articles")
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(path, "saved.txt")
	if err := os.WriteFile(file, []byte("saved content"), 0600); err != nil {
		t.Fatal(err)
	}
	running := batchTestTask("running", "target", path, base.DownloadStatusRunning)
	pending := batchTestTask("pending", "target", path, base.DownloadStatusWait)
	done := batchTestTask("done", "target", path, base.DownloadStatusDone)
	other := batchTestTask("other", "other", path, base.DownloadStatusWait)
	otherPath := batchTestTask("other-path", "target", filepath.Join(dir, "other"), base.DownloadStatusWait)
	d.tasks = []*Task{running, pending, done, other, otherPath}
	d.waitTasks = []*Task{pending, other, otherPath}
	changed, finishing, err := d.ControlArticleBatch("target", path, "pause")
	if err != nil || changed != 1 || finishing != 1 {
		t.Fatalf("pause: %d %d %v", changed, finishing, err)
	}
	if pending.Status != base.DownloadStatusPause || running.Status != base.DownloadStatusRunning || done.Status != base.DownloadStatusDone || other.Status != base.DownloadStatusWait || otherPath.Status != base.DownloadStatusWait || len(d.waitTasks) != 2 {
		t.Fatal("pause affected wrong tasks")
	}
	changed, _, err = d.ControlArticleBatch("target", path, "resume")
	if err != nil || changed != 1 || pending.Status != base.DownloadStatusWait || len(d.waitTasks) != 3 {
		t.Fatalf("resume: %d %v", changed, err)
	}
	changed, finishing, err = d.ControlArticleBatch("target", path, "stop")
	if err != nil || changed != 1 || finishing != 1 || pending.Status != ArticleCanceled || len(d.waitTasks) != 2 {
		t.Fatalf("stop: %d %d %v", changed, finishing, err)
	}
	if _, _, err = d.ControlArticleBatch("target", path, "resume"); err == nil {
		t.Fatal("stopped batch must be terminal")
	}
	if err = d.doStart(pending); err != nil || pending.Status != ArticleCanceled {
		t.Fatal("generic scheduler restarted terminated task")
	}
	var stored Task
	if ok, err := s.Get(bucketTask, pending.ID, &stored); err != nil || !ok || stored.Status != ArticleCanceled {
		t.Fatal("termination not persisted", err)
	}
	if b, err := os.ReadFile(file); err != nil || string(b) != "saved content" {
		t.Fatal("saved output changed")
	}
	for _, args := range [][3]string{{"", path, "stop"}, {"target", "", "pause"}, {"target", path, "invalid"}, {"unknown", path, "stop"}} {
		if _, _, err = d.ControlArticleBatch(args[0], args[1], args[2]); err == nil {
			t.Fatal("invalid identity/action accepted", args)
		}
	}
}
