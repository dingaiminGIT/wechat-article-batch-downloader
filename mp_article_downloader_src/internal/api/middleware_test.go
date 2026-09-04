package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCORSRejectsUntrustedBrowserOrigins(t *testing.T) {
	h := withCORS(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) }))
	for _, test := range []struct {
		origin string
		want   int
	}{
		{"https://mp.weixin.qq.com", http.StatusOK},
		{"http://127.0.0.1:2023", http.StatusOK},
		{"http://localhost:2023", http.StatusOK},
		{"https://example.com", http.StatusForbidden},
	} {
		req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:2023/", nil)
		req.Header.Set("Origin", test.origin)
		res := httptest.NewRecorder()
		h.ServeHTTP(res, req)
		if res.Code != test.want {
			t.Errorf("origin %s: got %d, want %d", test.origin, res.Code, test.want)
		}
	}
}
