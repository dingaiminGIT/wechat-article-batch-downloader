import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const requests = [];
const noop = () => {};
const body = { appendChild: noop };
const document = {
  title: "测试公众号",
  cookie: "wxuin=123",
  head: { appendChild: noop },
  body,
  createElement() {
    return { style: {}, appendChild: noop };
  },
  querySelector() {
    return null;
  },
  querySelectorAll() {
    return [];
  },
  getElementById() {
    return null;
  },
};

const context = {
  URL,
  URLSearchParams,
  console,
  document,
  location: {
    hostname: "mp.weixin.qq.com",
    pathname: "/s",
    href: "https://mp.weixin.qq.com/s?__biz=MzTest&mid=1&idx=1&sn=abc",
    search: "?__biz=MzTest&mid=1&idx=1&sn=abc",
  },
  setTimeout: noop,
  setInterval: noop,
  clearInterval: noop,
  insert_channels_style: noop,
  RSSIcon: "",
  DownloadIcon8: "",
  APIServerProtocol: "http",
  FakeAPIServerAddr: "127.0.0.1:2122",
  WSServerProtocol: "ws",
  WXU: {
    config: { officialServerDisabled: false, officialServerRefreshToken: "" },
    Events: { OfficialAccountRefresh: "OfficialAccountRefresh" },
    emit: noop,
    log: noop,
    error: noop,
    observe_node: noop,
    onDOMContentLoaded: noop,
    onWindowLoaded: noop,
    async request(options) {
      requests.push(options);
      return [null, { ok: true }];
    },
  },
  cgiDataNew: {
    nick_name: "测试公众号",
    title: "测试文章",
  },
  nickname: "测试公众号",
  uin: "123",
  key: "credential-key",
  pass_ticket: "ticket",
  appmsg_token: "token",
};
context.window = context;

const source = fs.readFileSync(
  new URL("../mp_article_downloader_src/internal/interceptor/inject/src/officialaccount.js", import.meta.url),
  "utf8",
);
vm.runInNewContext(source, context, { filename: "officialaccount.js" });
await new Promise((resolve) => setImmediate(resolve));

const refreshes = requests.filter((request) => request.url.includes("/api/mp/refresh"));
assert.equal(refreshes.length, 1, "opening an article should register the account once");
assert.equal(refreshes[0].body.biz, "MzTest");
assert.equal(refreshes[0].body.nickname, "测试公众号");
console.log("officialaccount auto-registration: ok");
