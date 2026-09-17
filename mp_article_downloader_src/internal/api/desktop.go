package api

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	downloadpkg "github.com/GopeedLab/gopeed/pkg/download"
	"github.com/gin-gonic/gin"
	"mp_article_batch_downloader/internal/archive"
	"mp_article_batch_downloader/internal/officialaccount"
	result "mp_article_batch_downloader/internal/util"
)

type downloadBatchSummary struct {
	Path       string `json:"path"`
	BatchID    string `json:"batch_id"`
	Total      int    `json:"total"`
	Completed  int    `json:"completed"`
	Running    int    `json:"running"`
	Queued     int    `json:"queued"`
	Failed     int    `json:"failed"`
	Paused     int    `json:"paused"`
	Missing    int    `json:"missing"`
	StartedAt  int64  `json:"started_at"`
	FinishedAt int64  `json:"finished_at"`
	Mode       string `json:"mode,omitempty"`
}

func summarizeDownloadBatches(tasks []*downloadpkg.Task, taskErrors map[string]string) []downloadBatchSummary {
	type batchKey struct{ path, id string }
	groups := map[batchKey]*downloadBatchSummary{}
	counts := map[batchKey]int{}
	for _, task := range tasks {
		if task == nil || task.Meta == nil || task.Meta.Opts == nil {
			continue
		}
		path := filepath.Clean(task.Meta.Opts.Path)
		if path == "." || path == "" {
			continue
		}
		labels := map[string]string{}
		if task.Meta.Req != nil && task.Meta.Req.Labels != nil {
			labels = task.Meta.Req.Labels
		}
		batchID := labels["batch_id"]
		key := batchKey{path: path, id: batchID}
		summary := groups[key]
		if summary == nil {
			summary = &downloadBatchSummary{Path: path, BatchID: batchID, Mode: labels["download_mode"]}
			groups[key] = summary
		}
		if summary.Mode == "" && labels["download_mode"] != "" {
			summary.Mode = labels["download_mode"]
		}
		counts[key]++
		if counts[key] > summary.Total {
			summary.Total = counts[key]
		}
		if hint, err := strconv.Atoi(labels["batch_total"]); err == nil && hint > summary.Total {
			summary.Total = hint
		}
		started := task.CreatedAt.UnixMilli()
		if value, err := strconv.ParseInt(labels["batch_started_at"], 10, 64); err == nil && value > 0 {
			started = value
		}
		if summary.StartedAt == 0 || started < summary.StartedAt {
			summary.StartedAt = started
		}
		updated := task.UpdatedAt.UnixMilli()
		if updated > summary.FinishedAt {
			summary.FinishedAt = updated
		}
		switch string(task.Status) {
		case "done":
			if exists, _ := taskOutputFilesExist(task); exists {
				summary.Completed++
			} else {
				summary.Missing++
			}
		case "running":
			summary.Running++
		case "ready", "wait":
			summary.Queued++
		case "error":
			summary.Failed++
		case "pause":
			// Gopeed restores failed tasks as paused after an app restart but
			// preserves their error. Keep showing those as failures so the batch
			// result does not change merely because the app was reopened.
			if taskErrors[task.ID] != "" {
				summary.Failed++
			} else {
				summary.Paused++
			}
		}
	}
	latest := map[string]*downloadBatchSummary{}
	for _, summary := range groups {
		current := latest[summary.Path]
		if current == nil || summary.StartedAt > current.StartedAt {
			copy := *summary
			latest[summary.Path] = &copy
		}
	}
	result := make([]downloadBatchSummary, 0, len(latest))
	for _, summary := range latest {
		if summary.Running+summary.Queued > 0 {
			summary.FinishedAt = 0
		}
		result = append(result, *summary)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].StartedAt > result[j].StartedAt })
	return result
}

func parseMsgListPage(r *officialaccount.OfficialMsgListResp) (archive.Page, error) {
	if r == nil {
		return archive.Page{}, fmt.Errorf("微信未返回文章列表")
	}
	p := archive.Page{More: r.HasMore != 0, Next: r.NextOffset}
	if strings.TrimSpace(r.MsgList) == "" {
		if r.MsgCount == 0 && !p.More {
			return p, nil
		}
		return archive.Page{}, fmt.Errorf("微信返回的文章列表为空，但本页仍应有文章")
	}
	type item struct {
		Title  string            `json:"title"`
		URL    string            `json:"content_url"`
		Digest string            `json:"digest"`
		Multi  []json.RawMessage `json:"multi_app_msg_item_list"`
	}
	var raw struct {
		List []struct {
			Info struct {
				Time int64 `json:"datetime"`
			} `json:"comm_msg_info"`
			Ext item `json:"app_msg_ext_info"`
		} `json:"list"`
	}
	if e := json.Unmarshal([]byte(r.MsgList), &raw); e != nil {
		return archive.Page{}, fmt.Errorf("微信返回的文章列表不完整：%w", e)
	}
	if r.MsgCount > 0 && len(raw.List) == 0 {
		return archive.Page{}, fmt.Errorf("微信标记本页有 %d 条消息，但文章列表为空", r.MsgCount)
	}
	for _, msg := range raw.List {
		items := []item{msg.Ext}
		for _, b := range msg.Ext.Multi {
			var child item
			if json.Unmarshal(b, &child) == nil {
				items = append(items, child)
			}
		}
		for _, a := range items {
			u := archive.StableURL(a.URL)
			if u == "" || a.Title == "" {
				continue
			}
			p.Articles = append(p.Articles, archive.Article{ID: archive.ID(u), Title: a.Title, URL: u, Digest: a.Digest, Published: msg.Info.Time})
		}
	}
	return p, nil
}

func fetchArchivePage(fetch func(string, int) (*officialaccount.OfficialMsgListResp, error), biz string, offset int) (archive.Page, error) {
	var emptyOffset int
	var emptySeen bool
	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		r, err := fetch(biz, offset)
		if err != nil {
			return archive.Page{}, err
		}
		page, err := parseMsgListPage(r)
		if err == nil {
			// A zero-count page might be the real end or a transient empty reply.
			// Confirm it at the same requested offset before marking a scan complete.
			if r.MsgCount == 0 && !page.More && len(page.Articles) == 0 {
				if emptySeen && r.NextOffset == emptyOffset {
					return page, nil
				}
				emptySeen = true
				emptyOffset = r.NextOffset
				lastErr = fmt.Errorf("微信返回空页，尚不能确认历史已读完")
			} else {
				return page, nil
			}
		} else {
			emptySeen = false
			lastErr = err
		}
		if attempt < 2 {
			time.Sleep(time.Duration(attempt+1) * 300 * time.Millisecond)
		}
	}
	return archive.Page{}, lastErr
}

func (c *APIClient) setupDesktop() {
	c.archive = archive.New(filepath.Join(c.cfg.RootDir, "scans"), func(biz string, offset int) (archive.Page, error) {
		page, err := fetchArchivePage(c.official.FetchMsgList, biz, offset)
		if err != nil {
			c.logger.Warn().Str("biz", biz).Int("offset", offset).Err(err).Msg("archive page failed")
		}
		return page, err
	})
	c.engine.POST("/api/desktop/queue", func(ctx *gin.Context) {
		var items []DownloadTaskPayload
		if ctx.ShouldBindJSON(&items) != nil || len(items) > 50 {
			result.Err(ctx, 400, "每批最多 50 篇文章")
			return
		}
		created, skipped, failed := 0, 0, 0
		for _, item := range items {
			_, err := c.createDownloadTask(item)
			if err == nil {
				created++
			} else if e, ok := err.(*taskCreateError); ok && e.code == 409 {
				skipped++
			} else {
				failed++
			}
		}
		result.Ok(ctx, gin.H{"created": created, "skipped": skipped, "failed": failed})
	})
	c.engine.GET("/api/desktop/info", func(ctx *gin.Context) {
		result.Ok(ctx, gin.H{"app": "mp-archive-desktop", "version": 1, "download_dir": c.cfg.DownloadDir})
	})
	c.engine.GET("/api/desktop/download-summary", func(ctx *gin.Context) {
		c.taskErrorMu.Lock()
		taskErrors := make(map[string]string, len(c.taskErrors))
		for id, message := range c.taskErrors {
			taskErrors[id] = message
		}
		c.taskErrorMu.Unlock()
		result.Ok(ctx, summarizeDownloadBatches(c.downloader.GetTasks(), taskErrors))
	})
	c.engine.GET("/api/desktop/scan", func(ctx *gin.Context) { result.Ok(ctx, c.archive.Get(ctx.Query("biz"))) })
	c.engine.POST("/api/desktop/scan", func(ctx *gin.Context) {
		var o archive.Options
		if ctx.ShouldBindJSON(&o) != nil {
			result.Err(ctx, 400, "参数无效")
			return
		}
		if e := c.archive.Start(o); e != nil {
			result.Err(ctx, 400, e.Error())
			return
		}
		result.Ok(ctx, c.archive.Get(o.Biz))
	})
	c.engine.POST("/api/desktop/scan/pause", func(ctx *gin.Context) {
		var o archive.Options
		if ctx.ShouldBindJSON(&o) != nil {
			result.Err(ctx, 400, "参数无效")
			return
		}
		c.archive.Pause(o.Biz)
		result.Ok(ctx, nil)
	})
}

func (c *APIClient) loadTaskErrors() {
	c.taskErrors = map[string]string{}
	b, e := os.ReadFile(filepath.Join(c.cfg.RootDir, "task-errors.json"))
	if e == nil {
		_ = json.Unmarshal(b, &c.taskErrors)
	}
	if c.taskErrors == nil {
		c.taskErrors = map[string]string{}
	}
}
func (c *APIClient) recordTaskError(evt *downloadpkg.Event) {
	if evt.Key != downloadpkg.EventKeyError && evt.Key != downloadpkg.EventKeyStart && evt.Key != downloadpkg.EventKeyDone && evt.Key != downloadpkg.EventKeyDelete {
		return
	}
	c.taskErrorMu.Lock()
	defer c.taskErrorMu.Unlock()
	if evt.Err != nil {
		c.taskErrors[evt.Task.ID] = regexp.MustCompile(`https?://[^\s]+`).ReplaceAllString(evt.Err.Error(), "[文章地址]")
	} else {
		delete(c.taskErrors, evt.Task.ID)
	}
	b, _ := json.Marshal(c.taskErrors)
	p := filepath.Join(c.cfg.RootDir, "task-errors.json")
	if os.WriteFile(p+".tmp", b, 0600) == nil {
		_ = os.Rename(p+".tmp", p)
	}
}

func (c *APIClient) pauseFastBatchOnVerification(evt *downloadpkg.Event) {
	batchID := fastBatchVerificationID(evt)
	if batchID == "" {
		return
	}
	// Pause the rest of this fast batch after the first verification response.
	// Running exporters may still finish or fail, but queued articles are kept
	// for a later safe-mode retry instead of producing hundreds of failures.
	go func() {
		ids := make([]string, 0)
		for _, task := range c.downloader.GetTasks() {
			if task == nil || task.ID == evt.Task.ID || task.Meta == nil || task.Meta.Req == nil {
				continue
			}
			if task.Meta.Req.Labels["batch_id"] == batchID {
				ids = append(ids, task.ID)
			}
		}
		if len(ids) > 0 {
			_ = c.downloader.Pause(&downloadpkg.TaskFilter{IDs: ids})
		}
	}()
}

func fastBatchVerificationID(evt *downloadpkg.Event) string {
	if evt == nil || evt.Key != downloadpkg.EventKeyError || evt.Task == nil || evt.Err == nil || evt.Task.Meta == nil || evt.Task.Meta.Req == nil {
		return ""
	}
	labels := evt.Task.Meta.Req.Labels
	message := evt.Err.Error()
	if labels["download_mode"] != "fast" || (!strings.Contains(message, "访问验证") && !strings.Contains(message, "凭证已失效")) {
		return ""
	}
	return labels["batch_id"]
}
