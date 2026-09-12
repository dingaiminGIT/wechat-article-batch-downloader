package officialaccountdownload

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

func TestIsWeChatVerificationPage(t *testing.T) {
	requestURL, _ := url.Parse("https://mp.weixin.qq.com/mp/wappoc_appmsgcaptcha")
	if !isWeChatVerificationPage(&http.Response{Request: &http.Request{URL: requestURL}}, nil) {
		t.Fatal("captcha redirect should be recognized")
	}
	if !isWeChatVerificationPage(nil, []byte(`<script src="https://captcha.gtimg.com/TCaptcha.js"></script><script>var poc_token="x"</script>`)) {
		t.Fatal("captcha HTML should be recognized")
	}
	if isWeChatVerificationPage(nil, []byte(`<div id="js_content">article</div>`)) {
		t.Fatal("article HTML must not be recognized as verification")
	}
}

func TestIsWeChatAccessVerificationError(t *testing.T) {
	for _, message := range []string{
		"微信要求完成访问验证，请在微信中打开文章后重试",
		"微信公众号凭证已失效或触发访问验证",
	} {
		if !isWeChatAccessVerificationError(fmt.Errorf("%s", message)) {
			t.Fatalf("verification error was not recognized: %s", message)
		}
	}
	if isWeChatAccessVerificationError(fmt.Errorf("微信返回 HTTP 500")) {
		t.Fatal("ordinary HTTP error must not be retried as verification")
	}
}

func TestClassifyUnavailableArticlePage(t *testing.T) {
	tests := []struct {
		html string
		want string
	}{
		{`<p>此内容因违规无法查看</p>`, "文章已被微信限制"},
		{`<p>该内容已被发布者删除</p>`, "文章已被发布者删除"},
		{`<script>var poc_token="x"</script>`, "触发访问验证"},
	}
	for _, test := range tests {
		err := classifyUnavailableArticlePage(test.html)
		if err == nil || !strings.Contains(err.Error(), test.want) {
			t.Fatalf("classify %q: got %v, want %q", test.html, err, test.want)
		}
	}
	if err := classifyUnavailableArticlePage(`<div id="js_content">正文</div>`); err != nil {
		t.Fatalf("ordinary article was rejected: %v", err)
	}
}

func TestAppendArticleJSONLConcurrent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "style_corpus.jsonl")
	const count = 40
	var wait sync.WaitGroup
	errCh := make(chan error, count)
	for index := 0; index < count; index++ {
		wait.Add(1)
		go func(index int) {
			defer wait.Done()
			errCh <- appendArticleJSONL(path, ArticleExportRecord{
				Title: "article",
				URL:   fmt.Sprintf("https://mp.weixin.qq.com/s/%d", index),
			})
		}(index)
	}
	wait.Wait()
	close(errCh)
	for err := range errCh {
		if err != nil {
			t.Fatalf("append failed: %v", err)
		}
	}

	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	seen := make(map[string]bool, count)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var record ArticleExportRecord
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			t.Fatalf("invalid JSONL record: %v", err)
		}
		seen[record.URL] = true
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if len(seen) != count {
		t.Fatalf("got %d records, want %d", len(seen), count)
	}
}

func TestAppendArticleJSONLReplacesDuplicateURL(t *testing.T) {
	path := filepath.Join(t.TempDir(), "style_corpus.jsonl")
	url := "https://mp.weixin.qq.com/s/same"
	if err := appendArticleJSONL(path, ArticleExportRecord{Title: "旧标题", URL: url}); err != nil {
		t.Fatal(err)
	}
	if err := appendArticleJSONL(path, ArticleExportRecord{Title: "新标题", URL: url}); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	var records []ArticleExportRecord
	for scanner.Scan() {
		var record ArticleExportRecord
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			t.Fatal(err)
		}
		records = append(records, record)
	}
	if len(records) != 1 || records[0].Title != "新标题" {
		t.Fatalf("duplicate was not replaced: %+v", records)
	}
}

func TestImageBytesCachesSuccessfulDownload(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		response.Header().Set("Content-Type", "image/png")
		_, _ = response.Write([]byte("image-data"))
	}))
	defer server.Close()

	downloader := &OfficialAccountDownload{}
	for index := 0; index < 2; index++ {
		data, mimeType, err := downloader.imageBytes(server.URL + "/same-image")
		if err != nil {
			t.Fatal(err)
		}
		if string(data) != "image-data" || mimeType != "image/png" {
			t.Fatalf("unexpected cached image: %q %q", data, mimeType)
		}
	}
	if requests.Load() != 1 {
		t.Fatalf("image requested %d times, want 1", requests.Load())
	}
}

func TestExportArticleDownloadsImageOnceForMarkdownAndHTML(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		response.Header().Set("Content-Type", "image/png")
		_, _ = response.Write([]byte("shared-image"))
	}))
	defer server.Close()

	article := &WechatOfficialArticle{
		Title:          "测试文章",
		AuthorNickname: "测试公众号",
		Content:        `<p>正文</p><img data-src="` + server.URL + `/image.png">`,
	}
	directory := t.TempDir()
	if err := (&OfficialAccountDownload{}).ExportArticle(article, "https://mp.weixin.qq.com/s/test", directory, "0001-test", false); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != 1 {
		t.Fatalf("image requested %d times, want 1", requests.Load())
	}
	for _, path := range []string{
		filepath.Join(directory, "html", "0001-test.html"),
		filepath.Join(directory, "markdown", "0001-test.md"),
		filepath.Join(directory, "text", "0001-test.txt"),
	} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("missing export %s: %v", path, err)
		}
	}
}
