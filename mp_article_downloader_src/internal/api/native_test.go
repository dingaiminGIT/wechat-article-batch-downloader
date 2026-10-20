package api

import (
	"github.com/gin-gonic/gin"
	"mp_article_batch_downloader/internal/nativebridge"
	"net/http/httptest"
	"testing"
)

func TestNativeLocalOnly(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/connect", nativeLocalOnly, func(c *gin.Context) { c.Status(200) })
	for _, tc := range []struct {
		remote, origin string
		want           int
	}{{"127.0.0.1:8888", "", 200}, {"127.0.0.1:8888", "https://example.com", 403}, {"192.168.1.4:8888", "", 403}} {
		req := httptest.NewRequest("POST", "/connect", nil)
		req.RemoteAddr = tc.remote
		if tc.origin != "" {
			req.Header.Set("Origin", tc.origin)
		}
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != tc.want {
			t.Fatal(tc, w.Code)
		}
	}
}
func TestNativePageRequiresExplicitEnd(t *testing.T) {
	if _, e := nativeArchivePage(nativebridge.Page{}, 0); e == nil {
		t.Fatal("missing paging accepted")
	}
	end := 1
	if _, e := nativeArchivePage(nativebridge.Page{IsEnd: &end, Profile: "p"}, 0); e == nil {
		t.Fatal("empty first page accepted")
	}
	more := 0
	p, e := nativeArchivePage(nativebridge.Page{IsEnd: &more, Profile: "p", NextCursor: "A", Articles: []nativebridge.Article{{Title: "a", URL: "https://mp.weixin.qq.com/s?__biz=b&mid=1&idx=1&sn=a"}, {Title: "a", URL: "https://mp.weixin.qq.com/s?__biz=b&mid=1&idx=1&sn=b"}}}, 0)
	if e != nil || len(p.Articles) != 2 || p.Articles[0].ID != p.Articles[1].ID {
		t.Fatal(p, e)
	}
}
