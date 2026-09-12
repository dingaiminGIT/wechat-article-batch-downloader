package officialaccount

import "testing"

func TestNormalizeMsgPaginationUsesForwardOffset(t *testing.T) {
	tests := []struct {
		name   string
		data   OfficialMsgListResp
		offset int
		more   int
	}{
		{name: "wechat flag is stale", data: OfficialMsgListResp{HasMore: 0, MsgCount: 10, NextOffset: 20}, offset: 10, more: 1},
		{name: "empty terminal page", data: OfficialMsgListResp{HasMore: 1, MsgCount: 0, NextOffset: 20}, offset: 20, more: 0},
		{name: "non advancing page", data: OfficialMsgListResp{HasMore: 1, MsgCount: 10, NextOffset: 20}, offset: 20, more: 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			normalizeMsgPagination(&tt.data, tt.offset)
			if tt.data.HasMore != tt.more {
				t.Fatalf("HasMore = %d, want %d", tt.data.HasMore, tt.more)
			}
		})
	}
}
