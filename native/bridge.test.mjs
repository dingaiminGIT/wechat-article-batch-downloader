import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
const source = fs.readFileSync(
  new URL("./bridge.mjs", import.meta.url),
  "utf8",
);
const profileSource = source.slice(
  source.indexOf("function profileRequest("),
  source.indexOf("async function page("),
);
test("renderer restart is reported instead of waiting for a miniapp forever", () => {
  const context = { run: () => "new start" };
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf("function checkAttachedHost("), source.indexOf("function guard(")), context);
  assert.throws(() => context.checkAttachedHost({ pid: "123", start: "old start" }), /网页进程已重启/);
  assert.doesNotThrow(() => context.checkAttachedHost({ pid: "123", start: "new start" }));
  context.run = () => { throw Error("gone"); };
  assert.throws(() => context.checkAttachedHost({ pid: "123", start: "old start" }), /网页进程已重启/);
  assert.doesNotThrow(() => context.checkAttachedHost(null));
});
test("native profile discovery uses public userName and rejects non-profile pages", () => {
  const context = { URL, location: { href: "weixin://resourceid/SubscriptionProfile/profile.html?userName=gh_example" }, document: { title: "Example" } };
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf("function discoverNativeProfile()"), source.indexOf("async function status(")), context);
  assert.equal(context.discoverNativeProfile().username, "gh_example");
  context.location.href = "https://example.invalid/?userName=gh_example";
  assert.equal(context.discoverNativeProfile(), null);
  const info = { username: "gh_example", nickname: "Example" };
  const page = { username: "gh_example", name: "Example", articles: [{ url: "https://mp.weixin.qq.com/s?__biz=abc&mid=1" }] };
  assert.equal(context.accountFromProfilePage(info, page).biz, "abc");
  assert.equal(context.accountFromProfilePage(info, { ...page, username: "gh_other" }), null);
  assert.equal(context.accountFromProfilePage(info, { ...page, articles: [] }), null);
  assert.equal(context.accountFromProfilePage(info, { ...page, articles: [...page.articles, { url: "https://mp.weixin.qq.com/s?__biz=other" }] }), null);
});
async function invoke(response) {
  let request;
  const context = {
    URL,
    setTimeout,
    clearTimeout,
    window: { WeixinJSBridge: true },
    WeixinJSBridge: {
      invoke(method, params, callback) {
        request = { method, ...params };
        callback(response);
      },
    },
  };
  vm.createContext(context);
  vm.runInContext(profileSource, context);
  const value = await context.profileRequest("gh_example", "cursor");
  return { value, request };
}
const success = (extra = {}) => ({
  err_msg: "H5ExtTransfer:ok",
  jsapi_resp: {
    resp_json: JSON.stringify({
      BaseResponse: { Ret: 0 },
      AccountInfo: { UserName: "gh_example", NickName: "fixture" },
      MsgList: {
        PagingInfo: { Offset: "next", IsEnd: 0 },
        Msg: [
          {
            BaseInfo: { DateTime: 123 },
            AppMsg: {
              DetailInfo: [
                {
                  Title: "one",
                  ContentUrl:
                    "https://mp.weixin.qq.com/s?__biz=test&mid=1&idx=1&sn=x&key=SECRET",
                },
              ],
            },
          },
        ],
      },
      ...extra,
    }),
  },
});
test("native profile returns normalized public links and cursor", async () => {
  const { value, request } = await invoke(success());
  assert.equal(value.articles.length, 1);
  assert(!value.articles[0].url.includes("SECRET"));
  assert.equal(value.next_cursor, "next");
  assert.equal(request.scope, "subscriptions");
  assert.equal(JSON.parse(request.req_json).Offset, "cursor");
});
test("bridge fail is an error, never an empty success", async () => {
  const { value } = await invoke({ err_msg: "H5ExtTransfer:fail" });
  assert(value.error);
  assert.equal(value.articles, undefined);
});
test("nonzero native return and malformed data stop", async () => {
  assert((await invoke(success({ BaseResponse: { Ret: -1 } }))).value.error);
  assert(
    (
      await invoke({
        err_msg: "H5ExtTransfer:ok",
        jsapi_resp: { resp_json: "not-json" },
      })
    ).value.error,
  );
});
test("wrong account and migration stop", async () => {
  assert(
    (await invoke(success({ AccountInfo: { UserName: "gh_other" } }))).value
      .error,
  );
  assert(
    (
      await invoke(
        success({ FuncFlagWording: [{ JumpUrl: "https://example.invalid" }] }),
      )
    ).value.error,
  );
});
