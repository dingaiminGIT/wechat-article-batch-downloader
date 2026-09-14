# 公众号文章下载器 · macOS 应用

[下载最新版 macOS 应用（Apple Silicon）](https://github.com/dingaiminGIT/wechat-article-batch-downloader/releases/latest/download/MPArticleDownloader-macOS-arm64.zip)

本机开发版安装到 `~/Applications/公众号文章下载器.app`，可在启动台或 Spotlight 搜索“公众号文章下载器”。这是独立的原生 SwiftUI 应用，内置 Go 下载后端，不需要打开终端。

## 第一次使用

1. 打开应用，点击“连接微信”。首次使用需要点击“信任并连接”，将本机生成的连接证书加入当前用户的信任列表，不需要管理员密码。
2. 在电脑微信中打开目标公众号的一篇文章。无需管理这个公众号。
3. 从左侧选择识别到的公众号，选择最近若干篇、全部历史或日期范围，点击“读取文章”。
4. 选择安全或快速模式，下载所选或全部读取结果。
5. 在“下载中心”查看完成数、总数、执行时间和平均速度，完成后直接打开该公众号目录。

历史接口可能要求重新打开微信文章、更新临时凭证或完成微信自身的访问验证；应用不会保证不可访问的文章或失效凭证可以下载。

## 功能

- 原生侧栏、文章列表、标题/摘要搜索和多选下载。
- 历史扫描由 Go 后台执行，按公众号保存页码、文章与状态。支持暂停和断点继续。
- 明确区分完整读取、暂停和失败，保留已经读取的结果。
- 每批最多 50 篇添加任务，按稳定文章标识跳过重复内容；同一批重复提交不会重新创建正在执行的任务。
- 下载中心按公众号展示最新批次，显示 `已完成/总数`、失败数、下载模式、开始与结束时间、总耗时和平均速度。
- 安全模式每秒最多读取一篇；快速模式约每秒两篇，短暂访问验证会自动降速重试，持续受限时暂停剩余任务。
- 正在导出的单篇文章按篇完成，不提供虚假的即时暂停；停止添加任务不会撤销已经加入队列的文章。
- HTML、Markdown、TXT、JSONL 导出；设置中可选择目录、打包 ZIP、打开诊断目录。
- 应用不需要管理员权限运行下载；首次连接只写入当前用户的证书信任设置。
- HTTP/HTTPS 代理分别备份和恢复；不覆盖运行期间其他代理软件作出的更改。后台监测应用父进程，应用异常退出后会执行收尾。

## 文件和端口

- 默认输出：`~/Downloads/公众号文章归档/`
- 应用数据与诊断：`~/Library/Application Support/MPArticleDownloader/`
- API：`127.0.0.1:2132`；代理：`127.0.0.1:2133`
- 旧命令行版仍使用原有的 `2122/2123` 与原目录，彼此的数据不会覆盖。
- 本机安装脚本会合并旧版 `mp.json` 中的公众号记录，新版同名记录优先。旧文件保持原状，临时凭证过期后仍需重新获取。

关闭窗口会保留应用运行；从应用菜单“退出”会停止后台并恢复网络配置。更换导出位置后，重新打开应用生效。

## 构建和验证

```bash
./script/build_and_run.sh --install
./script/build_and_run.sh --verify
python3 script/verify_desktop.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macos
GOROOT=/opt/homebrew/opt/go/libexec /opt/homebrew/bin/go -C mp_article_downloader_src test -race ./internal/archive ./internal/api ./pkg/certificate ./pkg/system
```

Codex 的 Run 按钮已配置。`--build-only` 只构建，`--install` 安装到当前用户的 Applications。当前公开安装包面向 Apple Silicon Mac，使用 ad-hoc 签名，尚未经过 Apple 公证。

详细验证记录见 `VERIFICATION.md`。
