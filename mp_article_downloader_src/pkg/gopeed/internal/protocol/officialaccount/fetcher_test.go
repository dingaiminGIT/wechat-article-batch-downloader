package officialaccountdownload

import (
	"testing"
	"time"

	"github.com/GopeedLab/gopeed/pkg/base"
	officialaccountdownload "github.com/GopeedLab/gopeed/pkg/officialaccount"
)

func TestArticleRequestInterval(t *testing.T) {
	if got := articleRequestInterval(&base.Request{}); got != 0 {
		t.Fatalf("safe mode should use package default, got %v", got)
	}
	request := &base.Request{Labels: map[string]string{"download_mode": "fast"}}
	got := articleRequestInterval(request)
	if got != officialaccountdownload.FastArticleRequestInterval {
		t.Fatalf("unexpected fast interval: %v", got)
	}
	if got != 500*time.Millisecond {
		t.Fatalf("fast interval should be 500 ms, got %v", got)
	}
}
