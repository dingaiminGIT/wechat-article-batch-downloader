# 原生连接组件

本目录的 bridge.mjs 是公众号归档的只读控制层，只提供连接状态、公开账号识别、历史分页、文章正文读取和断开连接，不提供关注、取关或通用代码执行接口。

debugger/ 复用 WMPFDebugger，固定上游提交 1d9f6e03a24dcd39baa223e25a883a85b84bd303，并保留本机项目已有的回环监听、CDP 令牌验证、健康检查与退出清理补丁。许可证 GPL-2.0-only；完整源代码及许可证随包放在 third-party-source/WMPFDebugger/。它作为独立进程运行，未链接进下载器 Go 程序。

node 为现有本机运行时；Node.js 及 frida、ws 等依赖的原始许可证保留在运行时依赖目录。下载器自身仍遵循仓库 LICENSE（MIT + Commons Clause），本机预览交付不等于获得商业再分发授权。

本预览版不会重签微信、自动安装证书、关闭 SIP 或扩大系统权限。兼容性指纹不匹配即拒绝连接。
