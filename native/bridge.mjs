// Local read-only public-account adapter. No follow/unfollow or generic RPC API.
import http from "node:http";
import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import { spawn, execFileSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const debuggerRoot =
  process.env.MP_NATIVE_DEBUGGER || path.join(root, "debugger");
const require = createRequire(import.meta.url);
const WebSocket = require(path.join(debuggerRoot, "node_modules/ws"));
const dataRoot = process.env.MP_NATIVE_DATA;
const auth = process.env.MP_NATIVE_TOKEN;
if (!dataRoot || !auth) throw Error("Missing private runtime configuration");
fs.mkdirSync(dataRoot, { recursive: true, mode: 0o700 });
const hash = (s) => createHash("sha256").update(s).digest("hex");
const run = (cmd, args) => {
  try {
    return execFileSync(cmd, args, {
      encoding: "utf8",
      timeout: 8000,
      maxBuffer: 8 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch {
    throw Error("无法确认微信安装或登录状态，请登录微信后重试");
  }
};
function identity() {
  const pids = run("/usr/bin/pgrep", ["-x", "WeChat"]).split(/\s+/);
  if (pids.length !== 1) throw Error("请只打开一个微信并完成登录");
  const pid = pids[0];
  if (
    run("/bin/ps", ["-p", pid, "-o", "comm="]) !==
    "/Applications/WeChat.app/Contents/MacOS/WeChat"
  )
    throw Error("微信安装路径不匹配");
  const start = run("/bin/ps", ["-p", pid, "-o", "lstart="]);
  const roots = new Set(
    run("/usr/sbin/lsof", ["-a", "-p", pid, "-Fn"])
      .split("\n")
      .map(
        (s) =>
          s.match(
            /^n(.+\/com\.tencent\.xinWeChat\/Data\/Documents\/xwechat_files\/[^/]+\/db_storage)\//,
          )?.[1],
      )
      .filter(Boolean),
  );
  if (roots.size !== 1)
    throw Error("无法唯一确认登录账号，请完全退出微信后重新登录");
  const profile = hash([...roots][0]);
  return { profile, session: hash(`${profile}:${pid}:${start}`) };
}
let bound = null,
  attachedHost = null,
  child = null,
  cdp = null,
  lastState = {
    ready: false,
    state: "stopped",
    message: "请连接原生读取通道",
    accounts: [],
  },
  cacheAt = 0;
const publicAccounts = new Map();
const profileDiscoveryAt = new Map();
let shuttingDown = false,
  operation = Promise.resolve();
function checkAttachedHost(host) {
  if (!host) return;
  try {
    if (run("/bin/ps", ["-p", host.pid, "-o", "lstart="]) === host.start) return;
  } catch {}
  throw Error("微信网页进程已重启，请重新连接原生通道，再重新打开腾讯文档小程序，停在首页即可");
}
function guard() {
  const current = identity();
  if (!bound || current.session !== bound.session)
    throw Error("微信会话已变化，请重新连接原生通道");
  checkAttachedHost(attachedHost);
  return current;
}
async function preflight() {
  const m = JSON.parse(
    fs.readFileSync(path.join(root, "compatibility.json"), "utf8"),
  );
  const helper =
    "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/";
  const plist = (p, key) =>
    run("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, p]);
  if (
    process.arch !== m.architecture ||
    plist(
      "/Applications/WeChat.app/Contents/Info.plist",
      "CFBundleShortVersionString",
    ) !== m.wechat_version ||
    plist(helper + "Info.plist", "CFBundleVersion") !== m.wmpf_build
  )
    throw Error(
      `当前仅支持微信 ${m.wechat_version} / ${m.wmpf_build}，请等待适配，不会修改微信`,
    );
  const digest = async (p) => {
    const h = createHash("sha256");
    for await (const chunk of fs.createReadStream(p)) h.update(chunk);
    return h.digest("hex");
  };
  if (
    (await digest(
      helper +
        "Frameworks/WeChatAppEx Framework.framework/WeChatAppEx Framework",
    )) !== m.framework_sha256
  )
    throw Error("微信组件指纹不匹配，已停止连接");
  if ((await digest(helper + "MacOS/WeChatAppEx")) !== m.prepared_helper_sha256)
    throw Error(
      "此本机预览版要求已准备的微信诊断环境；不会自动改签名或关闭系统保护",
    );
}
class CDP {
  constructor(token) {
    this.seq = 0;
    this.pending = new Map();
    this.socket = new WebSocket(
      `ws://127.0.0.1:62000/?token=${encodeURIComponent(token)}`,
    );
    this.ready = new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(Error("原生连接超时")), 5000);
      this.socket.once("open", () => {
        clearTimeout(t);
        resolve();
      });
      this.socket.once("error", () => {
        clearTimeout(t);
        reject(Error("原生连接不可用"));
      });
    });
    this.socket.on("message", (raw) => {
      let m;
      try {
        m = JSON.parse(raw);
      } catch {
        return;
      }
      const key = `${m.sessionId || ""}:${m.id}`,
        p = this.pending.get(key);
      if (!p) return;
      this.pending.delete(key);
      clearTimeout(p.timer);
      m.error ? p.reject(Error("微信调试请求失败")) : p.resolve(m.result);
    });
    this.socket.on("close", () => this.clear());
    this.socket.on("error", () => {});
  }
  clear() {
    for (const p of this.pending.values()) {
      clearTimeout(p.timer);
      p.reject(Error("原生连接已断开"));
    }
    this.pending.clear();
  }
  close() {
    this.clear();
    this.socket.close();
  }
  async call(method, params = {}, sessionId = "", timeout = 8000) {
    await this.ready;
    return new Promise((resolve, reject) => {
      const id = ++this.seq,
        key = `${sessionId}:${id}`,
        timer = setTimeout(() => {
          this.pending.delete(key);
          reject(Error("微信响应超时；请保留小程序和公众号主页"));
        }, timeout);
      this.pending.set(key, { resolve, reject, timer });
      this.socket.send(
        JSON.stringify({
          id,
          method,
          params,
          ...(sessionId ? { sessionId } : {}),
        }),
      );
    });
  }
  async evaluate(target, expression) {
    const { sessionId } = await this.call("Target.attachToTarget", {
      targetId: target.targetId,
      flatten: true,
    });
    try {
      const r = await this.call(
        "Runtime.evaluate",
        { expression, awaitPromise: true, returnByValue: true },
        sessionId,
        22000,
      );
      if (r.exceptionDetails) throw Error("微信页面执行失败");
      return r.result?.value;
    } finally {
      await this.call("Target.detachFromTarget", { sessionId }).catch(() => {});
    }
  }
}
const nativeTarget = (t) =>
  /^weixin:\/\/resourceid\/Subscription(?:Profile|Disorder)\//.test(t.url);
const articleTarget = (t) =>
  /^https?:\/\/mp\.weixin\.qq\.com\/s(?:\?|\/)/.test(t.url);
async function freePort(port) {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.once("error", () => resolve(false));
    s.listen(port, "127.0.0.1", () => s.close(() => resolve(true)));
  });
}
async function disconnect() {
  if (cdp) {
    cdp.close();
    cdp = null;
  }
  if (child) {
    const p = child;
    child = null;
    p.kill("SIGTERM");
    await Promise.race([
      new Promise((r) => p.once("exit", r)),
      new Promise((r) => setTimeout(r, 4000)),
    ]);
    if (p.exitCode === null) p.kill("SIGKILL");
  }
  bound = null;
  attachedHost = null;
  publicAccounts.clear();
  profileDiscoveryAt.clear();
  cacheAt = 0;
  fs.rmSync(path.join(dataRoot, "bridge-token.json"), { force: true });
  lastState = {
    ready: false,
    state: "stopped",
    message: "原生通道已停止",
    accounts: [],
  };
}
async function connect() {
  if (child && bound) {
    try {
      guard();
      return await status(true);
    } catch {
      await disconnect();
    }
  }
  await preflight();
  bound = identity();
  for (const p of [9421, 62000])
    if (!(await freePort(p))) {
      bound = null;
      throw Error("其他微信诊断工具占用连接端口，请关闭后重试");
    }
  const token = randomBytes(32).toString("hex");
  fs.writeFileSync(
    path.join(dataRoot, "bridge-token.json"),
    JSON.stringify({ token }),
    { mode: 0o600 },
  );
  child = spawn(process.execPath, [path.join(debuggerRoot, "build/index.js")], {
    cwd: debuggerRoot,
    env: { ...process.env, WECHAT_DATA_ROOT: dataRoot },
    stdio: ["ignore", "pipe", "pipe"],
  });
  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(Error("微信连接组件启动超时")),
        35000,
      );
      const finish = (e) => {
        clearTimeout(timeout);
        e ? reject(e) : resolve();
      };
      let tail = "";
      child.stdout.on("data", (b) => {
        tail = (tail + b.toString()).slice(-8000);
        const loaded = tail.match(/\[frida\] script loaded, WMPF version: \d+, pid: (\d+)/);
        if (loaded) {
          try {
            attachedHost = { pid: loaded[1], start: run("/bin/ps", ["-p", loaded[1], "-o", "lstart="]) };
            finish();
          } catch { finish(Error("微信网页进程已退出，请重新连接")); }
        }
      });
      child.stderr.on("data", () => {});
      child.once("error", () => finish(Error("无法启动微信连接组件")));
      child.once("exit", () =>
        finish(Error("微信连接组件退出，请检查本机环境")),
      );
    });
    cdp = new CDP(token);
    await cdp.ready;
    return await status(true);
  } catch (e) {
    await disconnect();
    throw e;
  }
}
function discoverPublicAccount() {
  const c = window.cgiDataNew || {},
    old = window.cgiData || {};
  const biz = String(
    window.biz ||
      window.__biz ||
      c.biz ||
      new URLSearchParams(location.search).get("__biz") ||
      "",
  );
  const username = [
    c.user_name,
    old.user_name,
    window.user_name,
    window.userName,
    window.username,
  ].find((x) => typeof x === "string" && /^gh_[a-zA-Z0-9]+$/.test(x));
  const nickname = String(
    c.nick_name ||
      window.nickname ||
      document.querySelector("#js_name")?.textContent ||
      "",
  ).trim();
  return biz && username && nickname ? { biz, username, nickname } : null;
}
function discoverNativeProfile() {
  const u = new URL(location.href);
  if (!/^weixin:\/\/resourceid\/SubscriptionProfile\//.test(u.href)) return null;
  const username = u.searchParams.get("userName");
  return /^gh_[a-zA-Z0-9]+$/.test(username || "")
    ? { username, nickname: document.title.trim() }
    : null;
}
function accountFromProfilePage(info, page) {
  if (!info || !page || page.error || page.username !== info.username) return null;
  const values = new Set();
  for (const article of page.articles || []) {
    try {
      const u = new URL(article.url);
      const biz = u.searchParams.get("__biz");
      if (u.hostname !== "mp.weixin.qq.com" || !/^[A-Za-z0-9+/=]+$/.test(biz || "")) return null;
      values.add(biz);
    } catch { return null; }
  }
  if (values.size !== 1 || !(page.name || info.nickname)) return null;
  return { biz: [...values][0], username: info.username, nickname: page.name || info.nickname };
}
async function status(force = false) {
  if (!child || !cdp) return lastState;
  if (!force && Date.now() - cacheAt < 4000) return lastState;
  try {
    guard();
    const h = await cdp.call("LocalBridge.status", {}, "", 2500);
    if (!h.connected) {
      lastState = {
        ready: false,
        state: "waiting_miniapp",
        message:
          "连接组件已启动，请在微信打开腾讯文档小程序，停在首页即可；若仍未连接，请关闭小程序后重新打开，无需打开或编辑文档",
        accounts: [],
      };
      cacheAt = Date.now();
      return lastState;
    }
    const { targetInfos } = await cdp.call("Target.getTargets");
    for (const t of targetInfos.filter(articleTarget).slice(0, 12)) {
      const a = await cdp
        .evaluate(t, `(${discoverPublicAccount.toString()})()`)
        .catch(() => null);
      if (a) publicAccounts.set(a.biz, a);
    }
    // Native profile windows have a public gh_ userName, even when no article
    // from that account is open. Resolve its biz from one validated list page.
    // At most one discovery request per poll, with retry backoff per account.
    for (const t of targetInfos.filter(t => /^weixin:\/\/resourceid\/SubscriptionProfile\//.test(t.url)).slice(0, 12)) {
      const info = await cdp.evaluate(t, `(${discoverNativeProfile.toString()})()`).catch(() => null);
      if (!info || [...publicAccounts.values()].some(a => a.username === info.username)) continue;
      if (Date.now() - (profileDiscoveryAt.get(info.username) || 0) < 30000) continue;
      profileDiscoveryAt.set(info.username, Date.now());
      const page = await cdp.evaluate(t, `(${profileRequest.toString()})(${JSON.stringify(info.username)},"")`).catch(() => null);
      guard();
      const a = accountFromProfilePage(info, page);
      if (a) publicAccounts.set(a.biz, a);
      break;
    }
    const ready = targetInfos.some(nativeTarget);
    lastState = {
      ready,
      state: ready ? "ready" : "waiting_profile",
      message: ready
        ? "原生读取已就绪；请保留小程序和公众号主页窗口"
        : "请在微信打开公众号主页（点击文章里的公众号名称）",
      profile: bound.profile,
      article_ready: targetInfos.some(articleTarget),
      accounts: [...publicAccounts.values()],
    };
    cacheAt = Date.now();
    return lastState;
  } catch (e) {
    lastState = {
      ready: false,
      state: "disconnected",
      message: e.message,
      accounts: [],
    };
    cacheAt = Date.now();
    return lastState;
  }
}
function profileRequest(username, offset) {
  return new Promise((resolve) => {
    let settled = false;
    const done = (v) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(v);
      }
    };
    const timer = setTimeout(
      () => done({ error: "微信原生列表响应超时" }),
      16000,
    );
    if (!window.WeixinJSBridge) {
      done({ error: "公众号主页连接不可用" });
      return;
    }
    const req = {
      BizUserName: username,
      ActionType: offset ? 1 : 0,
      PageSize: 10,
      BizSessionID: Math.floor(Date.now() / 1000),
      Scene: 207,
      UsePlainTopic: true,
      PreLoad: 0,
      FilterPicText: true,
      BaseRequest: {
        SessionKey: "",
        Uin: 0,
        DeviceID: "",
        ClientVersion: 0,
        DeviceType: "",
        Scene: 0,
      },
    };
    if (offset) req.Offset = offset;
    WeixinJSBridge.invoke(
      "H5ExtTransfer",
      {
        cgi_cmdid: 5814,
        url: "/cgi-bin/mmbiz-bin/bizattr/bizprofilev2h5",
        scope: "subscriptions",
        webcgi_header: [],
        cgi_type: 0,
        webcgi_method: 1,
        req_json: JSON.stringify(req),
      },
      (r) => {
        try {
          const d = JSON.parse(r?.jsapi_resp?.resp_json || "{}");
          if (r?.err_msg !== "H5ExtTransfer:ok" || d.BaseResponse?.Ret !== 0) {
            done({
              error: "微信拒绝了列表请求，请稍后重新连接",
              ack: r?.err_msg,
              ret: d.BaseResponse?.Ret,
            });
            return;
          }
          if (d.AccountInfo?.UserName !== username) {
            done({ error: "返回公众号不匹配，已停止" });
            return;
          }
          if (d.FuncFlagWording?.some((x) => x.JumpUrl)) {
            done({ error: "公众号存在迁移或跳转，请在微信确认后重新读取" });
            return;
          }
          const articles = (d.MsgList?.Msg || [])
            .flatMap((m) =>
              (m.AppMsg?.DetailInfo || []).map((a) => {
                let u;
                try {
                  u = new URL(a.ContentUrl || a.Url);
                  if (u.hostname !== "mp.weixin.qq.com") return null;
                  u.protocol = "https:";
                  u.hash = "";
                  for (const k of [...u.searchParams.keys()])
                    if (!["__biz", "mid", "idx", "sn"].includes(k))
                      u.searchParams.delete(k);
                } catch {
                  return null;
                }
                return {
                  title: a.Title || "",
                  url: u.href,
                  digest: a.Digest || "",
                  published: Number(
                    m.BaseInfo?.DateTime || m.AppMsg?.BaseInfo?.CreateTime || 0,
                  ),
                };
              }),
            )
            .filter((a) => a && a.title);
          done({
            articles,
            next_cursor: d.MsgList?.PagingInfo?.Offset || "",
            is_end: d.MsgList?.PagingInfo?.IsEnd,
            username,
            name: d.AccountInfo?.NickName,
          });
        } catch {
          done({ error: "微信列表响应格式变化，已保存进度" });
        }
      },
    );
  });
}
async function page(body) {
  if (!cdp) throw Error("请先连接原生读取通道");
  const current = guard();
  if (body.profile && body.profile !== current.profile)
    throw Error("此断点属于另一个微信账号，请重新读取");
  if (!/^[A-Za-z0-9+/=]+$/.test(body.biz || "")) throw Error("公众号标识无效");
  const username = publicAccounts.get(body.biz)?.username || body.username;
  if (!/^gh_[a-zA-Z0-9]+$/.test(username || ""))
    throw Error(
      "尚未识别公众号原生标识，请在微信打开该公众号文章后点击刷新连接",
    );
  const { targetInfos } = await cdp.call("Target.getTargets");
  const target =
    targetInfos.find((t) =>
      /^weixin:\/\/resourceid\/SubscriptionProfile\//.test(t.url),
    ) || targetInfos.find(nativeTarget);
  if (!target) throw Error("公众号主页已关闭，请重新打开后继续");
  const d = await cdp.evaluate(
    target,
    `(${profileRequest.toString()})(${JSON.stringify(username)},${JSON.stringify(body.cursor || "")})`,
  );
  guard();
  if (!d || d.error) throw Error(d?.error || "原生列表没有返回结果");
  if (d.is_end !== 0 && d.is_end !== 1)
    throw Error("微信未明确返回分页结束状态，已保存进度");
  if (d.is_end === 0 && (!d.next_cursor || d.next_cursor === body.cursor))
    throw Error("微信翻页游标没有推进，已暂停");
  if (!body.cursor && d.articles.length === 0)
    throw Error("首屏没有文章，不能确认历史为空，请稍后重试");
  return { ...d, profile: current.profile };
}
async function articleHTML(body) {
  if (!cdp) throw Error("请先连接原生读取通道");
  guard();
  let url;
  try {
    url = new URL(body.url);
  } catch {
    throw Error("文章地址无效");
  }
  if (
    url.hostname !== "mp.weixin.qq.com" ||
    url.protocol !== "https:" ||
    !/^\/s(?:\/|$)/.test(url.pathname)
  )
    throw Error("只允许微信公众号文章地址");
  for (const k of [...url.searchParams.keys()])
    if (!["__biz", "mid", "idx", "sn"].includes(k)) url.searchParams.delete(k);
  const { targetInfos } = await cdp.call("Target.getTargets");
  const target = targetInfos.find(articleTarget);
  if (!target) throw Error("请保留一篇微信文章正文窗口，以读取文章内容");
  const verificationMessage = "微信要求完成访问验证，已暂停。请在微信打开目标公众号的一篇正文；如有验证请手动完成，再重试。";
  const expression = `(async()=>{try{const response=await fetch(${JSON.stringify(url.href)},{credentials:'include',signal:AbortSignal.timeout(16000)});if(response.status!==200)return {error:'微信正文返回异常状态'};if(new URL(response.url).hostname!=='mp.weixin.qq.com'||response.url.includes('captcha'))return {error:${JSON.stringify(verificationMessage)}};const html=await response.text();if(html.includes('poc_token')&&(html.includes('TCaptcha')||html.includes('secitptpage/template/verify')))return {error:${JSON.stringify(verificationMessage)}};if(html.length>12000000)return {error:'文章内容超过本机预览版限制'};return {html}}catch{return {error:'微信正文读取失败，请保持文章窗口和小程序打开'}}})()`;
  const data = await cdp.evaluate(target, expression);
  guard();
  if (!data || data.error) throw Error(data?.error || "微信没有返回正文");
  return data;
}
const server = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "no-store");
  if (req.headers.origin || req.headers.authorization !== `Bearer ${auth}`) {
    res.writeHead(403);
    res.end("{}");
    return;
  }
  let text = "";
  for await (const b of req) {
    text += b;
    if (text.length > 16000) {
      res.writeHead(413);
      res.end("{}");
      return;
    }
  }
  const work = async () => {
    try {
      const body = text ? JSON.parse(text) : {};
      let data;
      if (req.url === "/connect" && req.method === "POST")
        data = await connect();
      else if (req.url === "/status" && req.method === "GET")
        data = await status();
      else if (req.url === "/page" && req.method === "POST")
        data = await page(body);
      else if (req.url === "/html" && req.method === "POST")
        data = await articleHTML(body);
      else if (req.url === "/disconnect" && req.method === "POST") {
        await disconnect();
        data = lastState;
      } else throw Error("无效操作");
      res.end(JSON.stringify(data));
    } catch (e) {
      res.end(JSON.stringify({ error: e.message }));
    }
  };
  operation = operation.then(work, work);
});
server.listen(0, "127.0.0.1", () =>
  console.log(JSON.stringify({ port: server.address().port })),
);
async function stop() {
  if (shuttingDown) return;
  shuttingDown = true;
  await disconnect();
  server.close();
  process.exit(0);
}
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
const parent = process.ppid;
setInterval(() => {
  if (process.ppid !== parent) void stop();
}, 2000).unref();
