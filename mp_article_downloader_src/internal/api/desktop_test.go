package api

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	downloadpkg "github.com/GopeedLab/gopeed/pkg/download"
	"mp_article_batch_downloader/internal/archive"
	"mp_article_batch_downloader/internal/officialaccount"
)

func TestParseMsgListPageEmptyTerminal(t *testing.T) {
	// A successful getmsg response can have no general_msg_list on its final page.
	page, err := parseMsgListPage(&officialaccount.OfficialMsgListResp{MsgCount: 0, HasMore: 0, NextOffset: 10})
	if err != nil {
		t.Fatalf("empty terminal page failed: %v", err)
	}
	if page.More || len(page.Articles) != 0 {
		t.Fatalf("unexpected terminal page: %+v", page)
	}
}

func TestParseMsgListPageDoesNotAcceptMissingArticles(t *testing.T) {
	for _, response := range []officialaccount.OfficialMsgListResp{
		{MsgCount: 1, HasMore: 1, NextOffset: 10},
		{MsgCount: 1, HasMore: 1, NextOffset: 10, MsgList: `{"list":[`},
		{MsgCount: 1, HasMore: 0, NextOffset: 10, MsgList: `{"list":[]}`},
	} {
		if _, err := parseMsgListPage(&response); err == nil {
			t.Fatalf("accepted incomplete article list: %+v", response)
		}
	}
}

func TestParseAuthorHistoryProducesArchivePage(t *testing.T) {
	page, err := parseAuthorHistory(&officialaccount.ArticleHistoryResponse{
		Pages: 2,
		Articles: []officialaccount.Article{
			{Mid: "1", Title: "第一篇", URL: "https://mp.weixin.qq.com/s?__biz=x&mid=1&idx=1&sn=a&key=secret", PublishTime: 1700000000},
			{Mid: "2", Title: "无效地址", URL: "https://example.com/article"},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if page.ReadPages != 2 || len(page.Articles) != 1 || page.Articles[0].Published != 1700000000 {
		t.Fatalf("unexpected page: %+v", page)
	}
	if strings.Contains(page.Articles[0].URL, "key=") {
		t.Fatalf("credential leaked into stable URL: %s", page.Articles[0].URL)
	}
}

func TestDesktopArchiveFallsBackToAuthorCursorHistory(t *testing.T) {
	legacyCalls := 0
	authorCalls := 0
	page, err := fetchDesktopArchivePage(
		func(string, int) (*officialaccount.OfficialMsgListResp, error) {
			legacyCalls++
			return &officialaccount.OfficialMsgListResp{}, nil
		},
		func(string) (*officialaccount.ArticleHistoryResponse, error) {
			authorCalls++
			return &officialaccount.ArticleHistoryResponse{Pages: 2, Articles: []officialaccount.Article{{
				Mid: "1", Title: "来自作者列表", URL: "https://mp.weixin.qq.com/s?__biz=x&mid=1&idx=1&sn=a",
			}}}, nil
		},
		"x",
		0,
	)
	if err != nil {
		t.Fatal(err)
	}
	if legacyCalls != 2 || authorCalls != 1 || page.ReadPages != 2 || len(page.Articles) != 1 {
		t.Fatalf("fallback failed: page=%+v legacy=%d author=%d", page, legacyCalls, authorCalls)
	}
}

func TestDesktopArchiveDoesNotAcceptTwoEmptySources(t *testing.T) {
	_, err := fetchDesktopArchivePage(
		func(string, int) (*officialaccount.OfficialMsgListResp, error) {
			return &officialaccount.OfficialMsgListResp{}, nil
		},
		func(string) (*officialaccount.ArticleHistoryResponse, error) {
			return &officialaccount.ArticleHistoryResponse{Pages: 1}, nil
		},
		"x",
		0,
	)
	if err == nil {
		t.Fatal("accepted empty legacy and author histories as complete")
	}
}

func TestArchiveCompletesAfterOneArticleAndEmptyTerminal(t *testing.T) {
	first := `{"list":[{"comm_msg_info":{"datetime":1700000000},"app_msg_ext_info":{"title":"第一篇","content_url":"https://mp.weixin.qq.com/s?__biz=x&mid=1&idx=1&sn=a"}}]}`
	m := archive.New(t.TempDir(), func(_ string, offset int) (archive.Page, error) {
		return fetchArchivePage(func(_ string, offset int) (*officialaccount.OfficialMsgListResp, error) {
			switch offset {
			case 0:
				return &officialaccount.OfficialMsgListResp{MsgCount: 1, HasMore: 1, NextOffset: 10, MsgList: first}, nil
			case 10:
				return &officialaccount.OfficialMsgListResp{MsgCount: 0, HasMore: 0, NextOffset: 10}, nil
			default:
				return nil, errors.New("unexpected offset")
			}
		}, "x", offset)
	})
	defer m.Close()
	if err := m.Start(archive.Options{Biz: "x", Mode: "all"}); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		scan := m.Get("x")
		if scan.Status == "complete" {
			if len(scan.Articles) != 1 || scan.Articles[0].Title != "第一篇" || scan.Pages != 2 {
				t.Fatalf("unexpected scan result: %+v", scan)
			}
			return
		}
		if scan.Status == "error" {
			t.Fatalf("scan failed: %+v", scan)
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("scan did not complete: %+v", m.Get("x"))
}

func TestFetchArchivePageRetriesMalformedList(t *testing.T) {
	calls := 0
	page, err := fetchArchivePage(func(string, int) (*officialaccount.OfficialMsgListResp, error) {
		calls++
		if calls == 1 {
			return &officialaccount.OfficialMsgListResp{MsgCount: 1, HasMore: 1, NextOffset: 10, MsgList: `{"list":[`}, nil
		}
		return &officialaccount.OfficialMsgListResp{MsgCount: 0, HasMore: 0, NextOffset: 10}, nil
	}, "x", 10)
	if err != nil || page.More || calls != 3 {
		t.Fatalf("retry failed: page=%+v err=%v calls=%d", page, err, calls)
	}
}

func TestFetchArchivePageRecoversFromTransientEmptyPage(t *testing.T) {
	calls := 0
	article := `{"list":[{"app_msg_ext_info":{"title":"下一篇","content_url":"https://mp.weixin.qq.com/s?__biz=x&mid=2&idx=1&sn=b"}}]}`
	page, err := fetchArchivePage(func(string, int) (*officialaccount.OfficialMsgListResp, error) {
		calls++
		if calls == 1 {
			return &officialaccount.OfficialMsgListResp{MsgCount: 0, HasMore: 0, NextOffset: 10}, nil
		}
		return &officialaccount.OfficialMsgListResp{MsgCount: 1, HasMore: 1, NextOffset: 20, MsgList: article}, nil
	}, "x", 10)
	if err != nil || !page.More || len(page.Articles) != 1 || page.Articles[0].Title != "下一篇" || calls != 2 {
		t.Fatalf("transient empty page truncated the scan: page=%+v err=%v calls=%d", page, err, calls)
	}
}

func TestFetchArchivePageRejectsUnconfirmedEmptyPage(t *testing.T) {
	calls := 0
	_, err := fetchArchivePage(func(string, int) (*officialaccount.OfficialMsgListResp, error) {
		calls++
		return &officialaccount.OfficialMsgListResp{MsgCount: 0, HasMore: 0, NextOffset: 10 + calls}, nil
	}, "x", 10)
	if err == nil || calls != 3 {
		t.Fatalf("unconfirmed empty page was accepted: err=%v calls=%d", err, calls)
	}
}

func summaryTask(t *testing.T, path, status string, created time.Time, labels map[string]string) *downloadpkg.Task {
	t.Helper()
	payload := map[string]any{
		"status":    status,
		"createdAt": created,
		"updatedAt": created.Add(time.Minute),
		"meta": map[string]any{
			"req":  map[string]any{"url": "officialaccount://test", "labels": labels},
			"opts": map[string]any{"path": path},
		},
	}
	b, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	var task downloadpkg.Task
	if err = json.Unmarshal(b, &task); err != nil {
		t.Fatal(err)
	}
	return &task
}

func TestSummarizeDownloadBatchesKeepsRestoredFailure(t *testing.T) {
	created := time.Unix(300, 0)
	task := summaryTask(t, "/downloads/account", "pause", created, map[string]string{"batch_id": "batch"})
	summaries := summarizeDownloadBatches([]*downloadpkg.Task{task}, map[string]string{task.ID: "文章已被微信限制，正文无法查看"})
	if len(summaries) != 1 || summaries[0].Failed != 1 || summaries[0].Paused != 0 {
		t.Fatalf("restored failure was misclassified: %+v", summaries)
	}
}

func TestFastBatchVerificationStopsRemainingQueue(t *testing.T) {
	task := summaryTask(t, "/downloads/account", "error", time.Now(), map[string]string{"batch_id": "fast-batch", "download_mode": "fast"})
	for _, message := range []string{"微信公众号凭证已失效或触发访问验证", "微信要求完成访问验证，请在微信中打开文章后重试"} {
		event := &downloadpkg.Event{Key: downloadpkg.EventKeyError, Task: task, Err: errors.New(message)}
		if got := fastBatchVerificationID(event); got != "fast-batch" {
			t.Fatalf("got batch %q for %q", got, message)
		}
	}
	task.Meta.Req.Labels["download_mode"] = "safe"
	event := &downloadpkg.Event{Key: downloadpkg.EventKeyError, Task: task, Err: errors.New("微信要求完成访问验证")}
	if got := fastBatchVerificationID(event); got != "" {
		t.Fatalf("safe batch should not trigger automatic pause: %q", got)
	}
}

func TestSummarizeDownloadBatchesUsesLatestBatchAndTotalHint(t *testing.T) {
	old := time.Unix(100, 0)
	latest := time.Unix(200, 0)
	labels := map[string]string{"batch_id": "new", "batch_total": "5", "batch_started_at": "200000"}
	summaries := summarizeDownloadBatches([]*downloadpkg.Task{
		summaryTask(t, "/downloads/account", "done", old, nil),
		summaryTask(t, "/downloads/account", "running", latest, labels),
		summaryTask(t, "/downloads/account", "error", latest.Add(time.Second), labels),
	}, nil)
	if len(summaries) != 1 {
		t.Fatalf("got %d summaries", len(summaries))
	}
	s := summaries[0]
	if s.BatchID != "new" || s.Total != 5 || s.Running != 1 || s.Failed != 1 || s.Completed != 0 {
		t.Fatalf("unexpected summary: %+v", s)
	}
	if s.StartedAt != 200000 || s.FinishedAt != 0 {
		t.Fatalf("unexpected timing: %+v", s)
	}
}
