(() => {
  var style = document.createElement("style");
  style.textContent = `
    #wechat-tools-container {
      position: fixed;
      top: 12px;
      right: 12px;
      z-index: 9999;
      display: flex;
      flex-direction: column;
      gap: 12px;
      width: 160px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    }
    #__wx_channels_credentials__,
    #__wx_channels_curl__,
    #__wx_channels_api__ {
      padding: 12px;
      background-color: var(--weui-BG-2, #fff);
      color: var(--weui-FG-0, #000);
      border-radius: 8px;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
      font-size: 11px;
      line-height: 1.4;
      cursor: pointer;
      transition: all 0.2s;
      backdrop-filter: blur(10px);
      text-align: center;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #__wx_channels_credentials__:hover,
    #__wx_channels_curl__:hover,
    #__wx_channels_api__:hover {
      opacity: 1;
      transform: translateY(-2px);
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    }
    @media (prefers-color-scheme: dark) {
      #__wx_channels_credentials__,
      #__wx_channels_curl__,
      #__wx_channels_api__ {
        background-color: var(--weui-BG-2, #2c2c2c);
        color: var(--weui-FG-0, #fff);
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
      }
    }
    #__mp_article_batch_panel__ {
      position: fixed;
      right: 18px;
      bottom: 22px;
      z-index: 2147483647;
      width: 318px;
      box-sizing: border-box;
      padding: 14px;
      border: 1px solid rgba(15, 23, 42, 0.12);
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.96);
      color: #172018;
      box-shadow: 0 14px 36px rgba(15, 23, 42, 0.18);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif;
      font-size: 13px;
      line-height: 1.45;
    }
    #__mp_article_batch_panel__ * {
      box-sizing: border-box;
    }
    #__mp_article_batch_panel__ .mp-batch-title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      margin-bottom: 10px;
      font-weight: 700;
      font-size: 14px;
    }
    #__mp_article_batch_panel__ .mp-batch-account {
      color: #52605a;
      font-size: 12px;
      margin-bottom: 10px;
      word-break: break-all;
    }
    #__mp_article_batch_panel__ .mp-batch-row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
      margin-bottom: 8px;
    }
    #__mp_article_batch_panel__ .mp-batch-row.single {
      grid-template-columns: 1fr;
    }
    #__mp_article_batch_panel__ button {
      height: 32px;
      border: 1px solid #d2d9d4;
      border-radius: 7px;
      background: #fff;
      color: #172018;
      cursor: pointer;
      font-size: 13px;
    }
    #__mp_article_batch_panel__ button.primary {
      border-color: #1f7a4d;
      background: #1f7a4d;
      color: #fff;
    }
    #__mp_article_batch_panel__ button:disabled {
      cursor: not-allowed;
      opacity: 0.55;
    }
    #__mp_article_batch_panel__ input,
    #__mp_article_batch_panel__ select {
      width: 100%;
      height: 32px;
      border: 1px solid #d2d9d4;
      border-radius: 7px;
      padding: 0 8px;
      background: #fbfbfa;
      color: #172018;
      font-size: 13px;
    }
    #__mp_article_batch_panel__ .mp-batch-status {
      min-height: 34px;
      margin-top: 8px;
      color: #52605a;
      white-space: pre-wrap;
    }
    #__mp_article_batch_panel__ .mp-batch-list {
      max-height: 180px;
      overflow: auto;
      margin-top: 8px;
      border-top: 1px solid #e4e9e5;
      padding-top: 8px;
    }
    #__mp_article_batch_panel__ .mp-batch-item {
      display: block;
      margin: 0 0 6px;
      color: #2d3831;
      font-size: 12px;
      overflow-wrap: anywhere;
    }
    #__mp_article_batch_panel__ .mp-batch-item-main {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    #__mp_article_batch_panel__ .mp-batch-item-meta {
      display: block;
      color: #6b746f;
      font-size: 11px;
    }
  `;
  function insert_style() {
    document.head.appendChild(style);
  }
  function get_api_origin() {
    if (typeof APIServerProtocol !== "undefined" && typeof FakeAPIServerAddr !== "undefined") {
      return APIServerProtocol + "://" + FakeAPIServerAddr;
    }
    if (WXU && WXU.config && WXU.config.apiServerHostname) {
      var origin = `${WXU.config.apiServerProtocol}://${WXU.config.apiServerHostname}`;
      if (WXU.config.apiServerPort !== 80) {
        origin += `:${WXU.config.apiServerPort}`;
      }
      return origin;
    }
    return "http://127.0.0.1:2122";
  }
  function get_ws_origin() {
    if (typeof WSServerProtocol !== "undefined" && typeof FakeAPIServerAddr !== "undefined") {
      return WSServerProtocol + "://" + FakeAPIServerAddr;
    }
    var apiOrigin = get_api_origin();
    return apiOrigin.replace(/^http:/, "ws:").replace(/^https:/, "wss:");
  }
  async function submit_credential(acct) {
    if (!acct.biz || !acct.key) {
      return;
    }
    WXU.emit(WXU.Events.OfficialAccountRefresh, acct);
    var origin = get_api_origin();
    var [err, res] = await WXU.request({
      method: "POST",
      url: `${origin}/api/mp/refresh?token=${
        WXU.config.officialServerRefreshToken ?? ""
      }`,
      body: acct,
    });
    if (err) {
      WXU.error({
        msg: err.message,
      });
      return;
    }
  }

  async function handle_api_call(msg, socket) {
    var { id, key, data } = msg;
    function resp(body) {
      socket.send(
        JSON.stringify({
          id,
          data: body,
        }),
      );
    }
    if (key === "key:fetch_account_home") {
      var [error, res] = await fetchAccountHome(data);
      if (error) {
        resp({
          errCode: 1001,
          errMsg: error.message,
        });
        return;
      }
      resp({
        errCode: 0,
        data: res,
      });
      return;
    }
    resp({
      errCode: 1000,
      errMsg: "未匹配的key",
      payload: msg,
    });
  }
  function connect(acct) {
    return new Promise((resolve, reject) => {
      if (window.__mp_article_batch_ws_connected) {
        resolve(true);
        return;
      }
      const ws = new WebSocket(get_ws_origin() + "/ws/mp");
      let ping_timer = null;
      ws.onopen = () => {
        window.__mp_article_batch_ws_connected = true;
        WXU.log({
          msg: "ws/mp connected",
        });
        submit_credential(acct);
        var page_title = document.title || acct.nickname || "公众号页面";
        try {
          ws.send(
            JSON.stringify({
              type: "ping",
              data: page_title,
            }),
          );
        } catch (e) {
          // ...
        }
        ping_timer = setInterval(() => {
          console.log("[]ping");
          if (ws.readyState === 1) {
            try {
              ws.send(
                JSON.stringify({
                  type: "ping",
                  data: page_title,
                }),
              );
            } catch (e) {
              // ...
            }
          }
        }, 5 * 1000);
        resolve(true);
      };
      ws.onclose = () => {
        window.__mp_article_batch_ws_connected = false;
        console.log("ws/mp disconnected");
        if (ping_timer) {
          clearInterval(ping_timer);
          ping_timer = null;
        }
      };
      ws.onerror = (e) => {
        console.error("ws/mp error", e);
        reject(e);
      };
      ws.onmessage = (ev) => {
        const [err, msg] = WXU.parseJSON(ev.data);
        if (err) {
          return;
        }
        if (msg.type === "api_call") {
          handle_api_call(msg.data, ws);
        }
      };
    });
  }
  async function fetchAccountHome(params) {
    console.log("[]fetchAccountHome", params);
    return new Promise((resolve) => {
      window.location.href = params.refresh_uri;
      resolve([null, params.refresh_uri]);
    });
  }
  function render_rss_button(acct) {
    var $btn = document.createElement("div");
    $btn.style.cssText = `position: relative; top: -3px; width: 16px; height: 16px; margin-left: 6px; cursor: pointer;`;
    $btn.innerHTML = RSSIcon;
    $btn.onclick = function () {
      var origin = (() => {
        if (WXU.config.officialRemoteServerHostname) {
          origin = `${WXU.config.officialRemoteServerProtocol}://${WXU.config.officialRemoteServerHostname}`;
          if (WXU.config.officialRemoteServerPort != 80) {
            origin += `:${WXU.config.officialRemoteServerPort}`;
          }
          return origin;
        }
        if (WXU.config.apiServerHostname) {
          origin = `${WXU.config.apiServerProtocol}://${WXU.config.apiServerHostname}`;
          if (WXU.config.apiServerPort != 80) {
            origin += `:${WXU.config.apiServerPort}`;
          }
          return origin;
        }
        return "";
      })();
      if (origin === "") {
        return;
      }
      var url = `${origin}/rss/mp?biz=${acct.biz}`;
      WXU.copy(url);
      WXU.toast("RSS 地址已复制");
    };
    return $btn;
  }
  function render_download_button(opt, dialog$) {
    var $btn = document.createElement("div");
    // $btn.className = "sns_opr_btn sns_write_comment_btn bar-expand-hotarea js_wx_tap_highlight wx_tap_link";
    $btn.style.cssText = `display: flex; align-items: center; margin-left: 16px; font-size: 14px; cursor: pointer;`;
    var text = `<span class="sns_opr_gap" style="margin-left: 1px">下载</span>`;
    if (opt.type === 2) {
      $btn.style.cssText = `display: flex; align-items: center; flex-direction: column; margin-left: 4px; font-size: 14px; cursor: pointer;`;
      var text = `<span class="" style="width: 39px; text-align: center; font-size: 12px;">下载</span>`;
    }
    $btn.innerHTML = `<span style="position: relative; top: -6px; width: 24px; height: 24px; font-size: 24px;">${DownloadIcon8}</span>${text}`;
    $btn.onclick = async function () {
      var [err, data] = await WXU.request({
        method: "POST",
        url: "https://" + FakeAPIServerAddr + "/api/task/create2",
        body: {
          url: `officialaccount://${window.location.href}`,
          // filename: document.title,
        },
      });
      if (err) {
        WXU.error({
          msg: err.message,
        });
        return;
      }
      // WXU.toast("开始下载");
      dialog$.show();
    };
    return $btn;
  }
  function html_text_length(html) {
    var box = document.createElement("div");
    box.innerHTML = html || "";
    return (box.innerText || box.textContent || "").replace(/\s+/g, "").length;
  }
  function collect_current_article() {
    var data = window.cgiDataNew || {};
    var container = document.querySelector("#js_content, .rich_media_content");
    var cgiContent = data.content_noencode || "";
    var domContent = container ? container.innerHTML || "" : "";
    var content = cgiContent;
    if (html_text_length(domContent) > html_text_length(cgiContent) + 50) {
      content = domContent;
    }
    var title =
      data.title ||
      document.querySelector("#activity-name, .rich_media_title")?.textContent ||
      document.title ||
      "article";
    var nickname =
      data.nick_name ||
      window.nickname ||
      document.querySelector("#js_name, .rich_media_meta_nickname")?.textContent ||
      "";
    var publishTime =
      window.createTime ||
      data.create_time ||
      document.querySelector("#publish_time")?.textContent ||
      "";
    var images = [];
    if (Array.isArray(data.picture_page_info_list)) {
      data.picture_page_info_list.forEach(function (item) {
        if (item && item.cdn_url) images.push(item.cdn_url);
      });
    }
    return {
      url: window.location.href,
      title: String(title || "").trim(),
      content,
      author: data.author || "",
      author_nickname: String(nickname || "").trim(),
      author_avatar: data.round_head_img || data.hd_head_img || "",
      author_id: data.user_name || "",
      publish_time: String(publishTime || "").trim(),
      page_type: data.page_type || 0,
      images,
      filename: safe_filename(title),
      dir: safe_filename(nickname || "公众号文章"),
    };
  }
  async function export_current_article() {
    var article = collect_current_article();
    if (!article.content) {
      WXU.error({ msg: "当前页面没有可导出的文章正文" });
      return;
    }
    var [err, data] = await WXU.request({
      method: "POST",
      url: `${get_api_origin()}/api/mp/article/export_current`,
      body: article,
    });
    if (err) {
      WXU.error({ msg: err.message });
      return;
    }
    if (data && data.mode === "preview") {
      WXU.toast("已导出预览内容；当前页面未提供付费全文");
      return;
    }
    WXU.toast("当前页导出成功");
  }
  function safe_filename(name) {
    return String(name || "untitled")
      .replace(/[\\/:*?"<>|#%&{}$!'@+=`~，。！？、；：”“‘’（）【】《》]/g, " ")
      .replace(/\s+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 80) || "article";
  }
  function escape_html(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }
  function format_bytes(bytes) {
    var n = Number(bytes || 0);
    if (!Number.isFinite(n) || n <= 0) return "0 B";
    var units = ["B", "KB", "MB", "GB"];
    var i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n = n / 1024;
      i += 1;
    }
    return `${n >= 10 || i === 0 ? n.toFixed(0) : n.toFixed(1)} ${units[i]}`;
  }
  function get_task_name(task) {
    return task.name || task?.meta?.opts?.name || task?.meta?.res?.name || task.id || "task";
  }
  function get_task_total(task) {
    return Number(task?.meta?.res?.size || task?.meta?.res?.files?.[0]?.size || 0);
  }
  function render_task_status(task) {
    var progress = task.progress || {};
    var downloaded = Number(progress.downloaded || 0);
    var total = get_task_total(task);
    var status = task.files_exist ? "done" : task.status || "";
    var parts = [status];
    if (total > 0) {
      parts.push(`${Math.min(100, Math.round((downloaded / total) * 100))}%`);
      parts.push(`${format_bytes(downloaded)}/${format_bytes(total)}`);
    } else if (downloaded > 0) {
      parts.push(format_bytes(downloaded));
    }
    if (Number(progress.speed || 0) > 0) {
      parts.push(`${format_bytes(progress.speed)}/s`);
    }
    if (task.files_exist === true) {
      parts.push("文件已存在");
    } else if (task.status === "done" && task.files_exist === false) {
      parts.push("文件不存在");
    }
    var path = task?.meta?.opts?.path || "";
    if (path) parts.push(path);
    return parts.filter(Boolean).join(" · ");
  }
  function normalize_article_url(url) {
    if (!url) return "";
    var cleaned = String(url).replace(/&amp;/g, "&").replace(/\\\//g, "/");
    if (cleaned.startsWith("//")) return "https:" + cleaned;
    if (cleaned.startsWith("/")) return "https://mp.weixin.qq.com" + cleaned;
    return cleaned;
  }
  function parse_msg_list(data) {
    var raw = data && data.general_msg_list;
    if (!raw && data && data.MsgList) raw = data.MsgList;
    if (!raw && data && data.msg_list) raw = data.msg_list;
    if (!raw) return [];
    var parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    var list = parsed.list || [];
    var articles = [];
    list.forEach(function (item) {
      var publishTime = item.comm_msg_info && item.comm_msg_info.datetime ? item.comm_msg_info.datetime : "";
      var ext = item.app_msg_ext_info || {};
      var candidates = [ext].concat(ext.multi_app_msg_item_list || []);
      candidates.forEach(function (msg) {
        if (!msg || !msg.title) return;
        var url = normalize_article_url(msg.content_url || msg.url || "");
        if (!url) return;
        articles.push({
          title: msg.title,
          digest: msg.digest || "",
          author: msg.author || "",
          url,
          publishTime,
        });
      });
    });
    return articles;
  }
  function find_biz_from_page() {
    var params = new URLSearchParams(location.search);
    var biz = params.get("__biz") || window.biz || window.__biz || "";
    if (biz) return biz;
    for (var anchor of document.querySelectorAll("a[href]")) {
      try {
        var url = new URL(anchor.href || anchor.getAttribute("href"), location.href);
        biz = url.searchParams.get("__biz");
        if (biz) return biz;
      } catch (e) {
        // ignore malformed href
      }
    }
    return "";
  }
  function scan_visible_articles() {
    var articles = [];
    var seen = {};
    var clean = function (value) {
      return String(value || "").replace(/\s+/g, " ").trim();
    };
    document.querySelectorAll("a[href]").forEach(function (anchor) {
      var href = normalize_article_url(anchor.href || anchor.getAttribute("href") || "");
      if (!href || (!href.includes("mp.weixin.qq.com/s") && !href.includes("__biz="))) return;
      var title =
        clean(anchor.innerText || anchor.textContent || anchor.getAttribute("title")) ||
        clean(anchor.closest("[role='link'], li, .weui_media_box, .album__item, .js_post")?.innerText) ||
        "article";
      if (seen[href]) return;
      seen[href] = true;
      articles.push({
        title,
        url: href,
        source: "visible-page",
      });
    });
    return articles;
  }
  async function fetch_mp_articles(acct, maxPages, onProgress) {
    var all = [];
    var offset = 0;
    var seen = {};
    var apiError = null;
    if (acct && acct.biz) {
      await submit_credential(acct);
    } else {
      var visibleOnly = scan_visible_articles();
      onProgress(`未识别到公众号 biz，已读取当前页面可见文章：${visibleOnly.length} 篇`);
      return visibleOnly;
    }
    for (var page = 0; page < maxPages; page += 1) {
      onProgress(`正在读取第 ${page + 1}/${maxPages} 页，已发现 ${all.length} 篇`);
      var url = `${get_api_origin()}/api/mp/msg/list?biz=${encodeURIComponent(acct.biz)}&offset=${offset}`;
      var [err, data] = await WXU.request({ method: "GET", url });
      if (err) {
        apiError = err;
        break;
      }
      var items = parse_msg_list(data);
      items.forEach(function (article) {
        var key = article.url;
        if (seen[key]) return;
        seen[key] = true;
        all.push(article);
      });
      if (!data || !data.can_msg_continue || !data.next_offset || data.next_offset === offset) {
        break;
      }
      offset = data.next_offset;
    }
    if (all.length === 0) {
      var visible = scan_visible_articles();
      if (visible.length > 0) {
        onProgress(`历史列表读取失败，已改用当前页面可见文章：${visible.length} 篇`);
        return visible;
      }
    }
    if (apiError && all.length === 0) throw apiError;
    return all;
  }
  async function create_article_task(article, index, dir, onExists) {
    var prefix = String(index + 1).padStart(4, "0");
    var filename = `${prefix}-${safe_filename(article.title)}`;
    var [err, data] = await WXU.request({
      method: "POST",
      url: `${get_api_origin()}/api/task/create2`,
      body: {
        url: `officialaccount://${article.url}`,
        filename,
        dir,
        on_exists: onExists,
        extra: {
          title: article.title || "",
          source: "mp-batch-panel",
          publish_time: String(article.publishTime || ""),
        },
      },
    });
    if (err) {
      if (String(err.message || "").includes("已存在")) {
        return { skipped: true, filename };
      }
      throw err;
    }
    return { ...(data || {}), filename };
  }
  function render_batch_panel(acct) {
    if (!acct) return;
    if (document.querySelector("#__mp_article_batch_panel__")) return;
    var defaultSubdir = safe_filename(acct.nickname || "公众号文章");
    var panel = document.createElement("div");
    panel.id = "__mp_article_batch_panel__";
    panel.innerHTML = `
      <div class="mp-batch-title">
        <span>公众号批量下载</span>
        <button data-action="hide" title="隐藏">隐藏</button>
      </div>
      <div class="mp-batch-account">${escape_html(acct.nickname || "当前公众号")}<br>${escape_html(acct.biz || "未识别 biz，将尝试读取当前页可见文章")}</div>
      <div class="mp-batch-row single">
        <input data-role="subdir" type="text" value="${escape_html(defaultSubdir)}" title="保存子目录">
      </div>
      <div class="mp-batch-row single">
        <select data-role="onExists" title="已有文件处理">
          <option value="skip">已有则跳过</option>
          <option value="overwrite">覆盖重下</option>
        </select>
      </div>
      <div class="mp-batch-row">
        <input data-role="maxPages" type="number" min="1" max="100" value="20" title="最多读取页数">
        <button data-action="scan">读取文章</button>
      </div>
      <div class="mp-batch-row">
        <button class="primary" data-action="download" disabled>批量下载</button>
        <button data-action="records">下载记录</button>
      </div>
      <div class="mp-batch-status" data-role="status">先点“读取文章”。每页约 10 篇；默认保存到下载目录下的“${escape_html(defaultSubdir)}”子目录。</div>
      <div class="mp-batch-list" data-role="list"></div>
    `;
    var state = { articles: [], currentTaskNames: [] };
    var recordsTimer = null;
    var status = panel.querySelector('[data-role="status"]');
    var list = panel.querySelector('[data-role="list"]');
    var scanBtn = panel.querySelector('[data-action="scan"]');
    var downloadBtn = panel.querySelector('[data-action="download"]');
    function setStatus(text) {
      status.textContent = text;
    }
    function setBusy(busy) {
      scanBtn.disabled = busy;
      downloadBtn.disabled = busy || state.articles.length === 0;
    }
    panel.querySelector('[data-action="hide"]').onclick = function () {
      panel.style.display = "none";
    };
    panel.querySelector('[data-action="records"]').onclick = function () {
      fetch_task_records().catch(function (error) {
        setStatus(`读取下载记录失败：${error.message || error}`);
      });
    };
    async function fetch_task_records() {
      if (recordsTimer) {
        clearTimeout(recordsTimer);
        recordsTimer = null;
      }
      try {
        setBusy(true);
        var [err, data] = await WXU.request({
          method: "GET",
          url: `${get_api_origin()}/api/task/list?status=all&page=1&page_size=1000`,
        });
        if (err) throw err;
        var tasks = Array.isArray(data) ? data : data?.tasks || data?.list || [];
        var subdir = safe_filename(panel.querySelector('[data-role="subdir"]').value || defaultSubdir);
        tasks = tasks.filter(function (task) {
          var path = task?.meta?.opts?.path || "";
          var name = task?.meta?.opts?.name || get_task_name(task);
          if (!path.endsWith("/" + subdir)) return false;
          if (state.currentTaskNames.length === 0) return true;
          return state.currentTaskNames.includes(name);
        });
        var total = tasks.length;
        var active = tasks.some((task) => !task.files_exist && ["ready", "wait", "running"].includes(task.status));
        setStatus(`下载记录：${tasks.length}/${total} 个任务${active ? "，5 秒后自动刷新" : ""}`);
        list.innerHTML = tasks
          .slice(0, 1000)
          .map(function (task, index) {
            return `<span class="mp-batch-item"><span class="mp-batch-item-main">${index + 1}. ${escape_html(get_task_name(task))}</span><span class="mp-batch-item-meta">${escape_html(render_task_status(task))}</span></span>`;
          })
          .join("");
        if (active) {
          recordsTimer = setTimeout(function () {
            fetch_task_records().catch(function (error) {
              setStatus(`自动刷新下载记录失败：${error.message || error}`);
            });
          }, 5000);
        }
      } finally {
        setBusy(false);
      }
    }
    scanBtn.onclick = async function () {
      try {
        setBusy(true);
        list.innerHTML = "";
        var maxPages = Number(panel.querySelector('[data-role="maxPages"]').value || 10);
        state.articles = await fetch_mp_articles(acct, maxPages, setStatus);
        downloadBtn.disabled = state.articles.length === 0;
        setStatus(`读取完成：${state.articles.length} 篇`);
        list.innerHTML = state.articles
          .slice(0, 200)
          .map((article, index) => `<span class="mp-batch-item">${index + 1}. ${escape_html(article.title)}</span>`)
          .join("");
      } catch (error) {
        setStatus(`读取失败：${error.message || error}`);
      } finally {
        setBusy(false);
      }
    };
    downloadBtn.onclick = async function () {
      try {
        setBusy(true);
        var ok = 0;
        var skipped = 0;
        var subdir = safe_filename(panel.querySelector('[data-role="subdir"]').value || defaultSubdir);
        var onExists = panel.querySelector('[data-role="onExists"]').value || "skip";
        state.currentTaskNames = [];
        for (var i = 0; i < state.articles.length; i += 1) {
          setStatus(`正在创建下载任务 ${i + 1}/${state.articles.length}\n${state.articles[i].title}`);
          var result = await create_article_task(state.articles[i], i, subdir, onExists);
          if (result && result.filename) state.currentTaskNames.push(result.filename);
          if (result && result.skipped) {
            skipped += 1;
          } else {
            ok += 1;
          }
        }
        setStatus(`本次处理 ${state.articles.length} 篇：新建 ${ok} 个，跳过 ${skipped} 个。保存子目录：${subdir}`);
        await fetch_task_records();
      } catch (error) {
        setStatus(`下载任务创建失败：${error.message || error}`);
      } finally {
        setBusy(false);
      }
    };
    document.body.appendChild(panel);
  }
  function insert_rss_button(acct) {
    if (!acct.biz || !acct.key) {
      return;
    }
    var $wraps = document.querySelectorAll(".wx_follow_media");
    var $container = $wraps[$wraps.length - 1];
    console.log("$container", $container);
    var $btn = render_rss_button(acct);
    $container.appendChild($btn);
  }
  function DownloaderPanel(props) {
    return View({}, [
      Dialog({ store: props.dialog$ }, [DownloaderPanelView({})]),
    ]);
  }
  function insert_download_button() {
    var $wraps = document.querySelectorAll(".interaction_bar");
    var $container = $wraps[$wraps.length - 1];
    if (window.cgiDataNew.page_type === 2) {
      $container = $wraps[0];
    }
    if (!$container || !$container.lastElementChild) {
      return;
    }
    const dialog$ = new Timeless.ui.DialogCore({
      offsetY: 4,
    });
    var $btn = render_download_button(
      { type: window.cgiDataNew.page_type },
      dialog$,
    );
    const { DropdownMenu, Menu, MenuItem } = WUI;
    const dropdown$ = DropdownMenu({
      $trigger: $btn,
      zIndex: 99999,
      children: [
        // MenuItem({
        //   label: "下载markdown",
        //   onClick() {
        //     dropdown$.hide();
        //   },
        // }),
        MenuItem({
          label: "导出当前页",
          async onClick() {
            await export_current_article();
            dropdown$.hide();
          },
        }),
        MenuItem({
          label: "复制文章HTML",
          onClick() {
            const content = window.cgiDataNew.content_noencode;
            if (!content) {
              WXU.toast("文章HTML为空，请使用「复制页面HTML」");
              return;
            }
            WXU.copy(content);
            WXU.toast("复制成功");
            dropdown$.hide();
          },
        }),
        MenuItem({
          label: "复制页面HTML",
          onClick() {
            const content = window.body.innerHTML;
            WXU.copy(content);
            WXU.toast("复制成功");
            dropdown$.hide();
          },
        }),
        MenuItem({
          label: "下载记录",
          onClick() {
            dialog$.show();
            dropdown$.hide();
          },
        }),
      ],
    });
    dropdown$.ui.$trigger.onMouseEnter(() => {
      dropdown$.show();
    });
    dropdown$.ui.$trigger.onMouseLeave(() => {
      if (dropdown$.isHover) {
        return;
      }
      dropdown$.hide();
    });
    $container.insertBefore($btn, $container.lastElementChild);
    const panel$ = DownloaderPanel({ dialog$ });
    setTimeout(() => {
      document.body.appendChild(panel$.render());
    }, 0);
  }
  window.insert_download_button = insert_download_button;
  function build_article_credentials() {
    const params = new URLSearchParams(window.location.search);
    const biz = params.get("__biz") || window.biz || window.__biz || "";
    const mid = params.get("mid") || "";
    const idx = params.get("idx") || "";
    const sn = params.get("sn") || "";
    return {
      nickname: (() => {
        if (window.nickname) return window.nickname;
        if (window.cgiData?.nick_name) return window.cgiData.nick_name;
        if (window.cgiDataNew?.nick_name) return window.cgiDataNew.nick_name;
        return document.title || "";
      })(),
      avatar_url: (() => {
        if (window.headimg) return window.headimg;
        if (window.cgiData?.round_head_img) return window.cgiData.round_head_img;
        if (window.cgiData?.hd_head_img) return window.cgiData.hd_head_img;
        if (window.cgiDataNew?.round_head_img) return window.cgiDataNew.round_head_img;
        if (window.cgiDataNew?.hd_head_img) return window.cgiDataNew.hd_head_img;
        return "";
      })(),
      biz,
      uin: window.uin,
      key: window.key,
      refresh_uri: biz && mid && idx && sn ? `https://mp.weixin.qq.com/s?__biz=${biz}&mid=${mid}&idx=${idx}&sn=${sn}` : location.href,
      pass_ticket: window.pass_ticket,
      appmsg_token: window.appmsg_token,
      cookie: document.cookie || "",
      cookie_expiration: Math.floor(Date.now() / 1000) + 24 * 60 * 60,
    };
  }
  function build_page_account() {
    return {
      nickname: document.title || "当前公众号",
      biz: find_biz_from_page(),
      refresh_uri: location.href,
    };
  }
  async function main() {
    if (location.pathname === "/s") {
      var _OfficialAccountCredentials = build_article_credentials();
      WXU.observe_node(".wx_follow_media", () => {
        setTimeout(() => {
          insert_style();
          // insert_rss_button(_OfficialAccountCredentials);
          connect(_OfficialAccountCredentials).catch(function (err) {
            console.log("mp websocket connect failed", err);
          });
          render_batch_panel(_OfficialAccountCredentials);
          if (window.cgiDataNew) insert_download_button();
        }, 800);
      });
      setTimeout(function () {
        insert_style();
        render_batch_panel(_OfficialAccountCredentials);
      }, 1500);
      return;
    }
    if (location.hostname === "mp.weixin.qq.com") {
      setTimeout(function () {
        insert_style();
        render_batch_panel(build_page_account());
      }, 1200);
    }
  }
  function boot_official_account_tools() {
    if (WXU.config.officialServerDisabled) {
      return;
    }
    main().catch(function (err) {
      console.log("mp tools main failed", err);
    });
  }
  function ensure_mp_batch_panel() {
    if (WXU.config.officialServerDisabled || location.hostname !== "mp.weixin.qq.com") {
      return;
    }
    if (document.querySelector("#__mp_article_batch_panel__")) {
      return;
    }
    insert_style();
    render_batch_panel(location.pathname === "/s" ? build_article_credentials() : build_page_account());
  }
  insert_channels_style();
  boot_official_account_tools();
  WXU.onDOMContentLoaded(boot_official_account_tools);
  WXU.onWindowLoaded(boot_official_account_tools);
  setTimeout(ensure_mp_batch_panel, 800);
  setTimeout(ensure_mp_batch_panel, 2000);
  setInterval(ensure_mp_batch_panel, 5000);
})();
