package officialaccountdownload

import (
	"errors"
	"testing"
	"time"
)

func TestNativeFastGateAndNoVerificationRetry(t *testing.T) {
	previous := NativeHTMLProvider
	defer func() { NativeHTMLProvider = previous }()
	var calls []time.Time
	NativeHTMLProvider = func(string) ([]byte, bool, error) {
		calls = append(calls, time.Now())
		return nil, true, errors.New("微信要求完成访问验证")
	}
	client := &OfficialAccountDownload{ArticleRequestInterval: FastArticleRequestInterval}
	for i := 0; i < 2; i++ {
		if _, err := client.Scrape("https://mp.weixin.qq.com/s/test"); err == nil {
			t.Fatal("verification must stop the request")
		}
	}
	if len(calls) != 2 {
		t.Fatalf("verification was retried: %d calls", len(calls))
	}
	if elapsed := calls[1].Sub(calls[0]); elapsed < 950*time.Millisecond {
		t.Fatalf("native fast gate too short: %v", elapsed)
	}
}

func TestNativeArticleRequestInterval(t *testing.T) {
	for _, tc := range []struct{ requested, want time.Duration }{
		{0, 2 * time.Second}, {-1, 2 * time.Second},
		{FastArticleRequestInterval, time.Second}, {time.Nanosecond, time.Second},
		{time.Second, 2 * time.Second},
	} {
		if got := nativeArticleRequestInterval(tc.requested); got != tc.want {
			t.Fatalf("requested=%v got=%v want=%v", tc.requested, got, tc.want)
		}
	}
}
