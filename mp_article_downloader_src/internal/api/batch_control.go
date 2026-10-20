package api

import (
	"github.com/gin-gonic/gin"
	result "mp_article_batch_downloader/internal/util"
	"path/filepath"
	"strings"
)

func (c *APIClient) handleBatchControl(ctx *gin.Context) {
	var req struct {
		BatchID string `json:"batch_id"`
		Path    string `json:"path"`
		Action  string `json:"action"`
	}
	if ctx.ShouldBindJSON(&req) != nil || req.BatchID == "" || req.Path == "" {
		result.Err(ctx, 400, "缺少批次标识或目录")
		return
	}
	rel, err := filepath.Rel(c.cfg.DownloadDir, req.Path)
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		result.Err(ctx, 400, "目录不属于当前下载库")
		return
	}
	if req.Action != "pause" && req.Action != "resume" && req.Action != "stop" {
		result.Err(ctx, 400, "不支持的批次操作")
		return
	}
	c.batchControlMu.Lock()
	defer c.batchControlMu.Unlock()
	changed, finishing, err := c.downloader.ControlArticleBatch(req.BatchID, req.Path, req.Action)
	if err != nil {
		result.Err(ctx, 409, err.Error())
		return
	}
	result.Ok(ctx, gin.H{"changed": changed, "finishing": finishing})
}
