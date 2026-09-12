package api

import (
	"encoding/json"
	"errors"
	"testing"
	"time"

	downloadpkg "github.com/GopeedLab/gopeed/pkg/download"
)

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
