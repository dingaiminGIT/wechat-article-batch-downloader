# mp_article_downloader_src

公众号文章批量下载器源码目录。

核心流程：本地 HTTPS 代理拦截微信桌面端打开的公众号文章页，向 `mp.weixin.qq.com` 的文章 HTML 注入前端面板；前端面板调用本地 API 获取历史文章列表，并创建 `officialaccount://` 下载任务；下载器抓取文章内容后输出 HTML、Markdown、纯文本和图片资源。

常用入口：

- `cmd/`: 命令行入口。
- `internal/interceptor/`: 本地代理和页面注入。
- `internal/interceptor/inject/src/officialaccount.js`: 公众号批量下载面板。
- `internal/officialaccount/`: 公众号凭证和历史消息接口。
- `pkg/gopeed/pkg/officialaccount/`: 公众号文章抓取和格式导出。
