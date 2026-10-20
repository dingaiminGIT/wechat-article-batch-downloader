package download

import (
	"fmt"
	"github.com/GopeedLab/gopeed/pkg/base"
	"path/filepath"
)

// Canceled article tasks remain as durable history; their output is never removed.
const ArticleCanceled base.Status = "canceled"

// ControlArticleBatch changes only pending tasks, under the scheduler lock.
// An exporting article is allowed to finish so multi-file output stays consistent.
func (d *Downloader) ControlArticleBatch(batchID, path, action string) (changed, finishing int, err error) {
	if batchID == "" || path == "" {
		return 0, 0, fmt.Errorf("missing batch identity")
	}
	if action != "pause" && action != "resume" && action != "stop" {
		return 0, 0, fmt.Errorf("invalid batch action")
	}
	d.lock.Lock()
	defer d.lock.Unlock()
	matches := func(t *Task) bool {
		return t != nil && t.Protocol == "officialaccount" && t.Meta != nil && t.Meta.Req != nil && t.Meta.Opts != nil && t.Meta.Req.Labels["batch_id"] == batchID && filepath.Clean(t.Meta.Opts.Path) == filepath.Clean(path)
	}
	found := false
	for _, t := range d.tasks {
		if matches(t) {
			found = true
			if action == "resume" && t.Status == ArticleCanceled {
				return 0, 0, fmt.Errorf("该批次已终止，请重新选择文章创建新下载")
			}
		}
	}
	if !found {
		return 0, 0, ErrTaskNotFound
	}
	for _, t := range d.tasks {
		if !matches(t) {
			continue
		}
		if t.Status == base.DownloadStatusRunning {
			finishing++
			continue
		}
		if t.Status == base.DownloadStatusDone || t.Status == ArticleCanceled {
			continue
		}
		if action == "resume" {
			if t.Status != base.DownloadStatusPause && t.Status != base.DownloadStatusError {
				continue
			}
			if d.remainRunningCount() > 0 {
				if err = d.doStart(t); err != nil {
					return
				}
			} else {
				t.updateStatus(base.DownloadStatusWait)
				d.waitTasks = append(d.waitTasks, t)
			}
			changed++
			continue
		}
		target := base.DownloadStatusPause
		if action == "stop" {
			target = ArticleCanceled
		}
		if t.Status == target {
			continue
		}
		t.statusLock.Lock()
		t.updateStatus(target)
		t.timer.Pause()
		err = d.storage.Put(bucketTask, t.ID, t.clone())
		t.statusLock.Unlock()
		if err != nil {
			return
		}
		changed++
	}
	// Remove paused/canceled work from the scheduler without touching other batches.
	waiting := d.waitTasks[:0]
	for _, t := range d.waitTasks {
		if t.Status == base.DownloadStatusWait {
			waiting = append(waiting, t)
		}
	}
	d.waitTasks = waiting
	return
}
