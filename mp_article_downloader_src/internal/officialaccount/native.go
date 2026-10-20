package officialaccount

import "strings"

// Public identity only. A gh_ username is not the legacy author_id.
func (c *OfficialAccountClient) NativeUsername(biz string) string {
	acct_mu.Lock()
	defer acct_mu.Unlock()
	if a := accounts[biz]; a != nil {
		if a.Username != "" {
			return a.Username
		}
		if strings.HasPrefix(a.AuthorId, "gh_") {
			return a.AuthorId
		}
	}
	return ""
}
func (c *OfficialAccountClient) RememberNativeAccount(biz, username, nickname string) {
	if biz == "" || !strings.HasPrefix(username, "gh_") || nickname == "" {
		return
	}
	acct_mu.Lock()
	a := accounts[biz]
	if a != nil && a.Username == username && a.Nickname == nickname {
		acct_mu.Unlock()
		return
	}
	if a == nil {
		a = &OfficialAccount{Biz: biz}
		accounts[biz] = a
	}
	a.Username = username
	a.Nickname = nickname
	acct_mu.Unlock()
	save_accounts()
}
