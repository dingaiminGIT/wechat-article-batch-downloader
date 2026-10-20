// Real local bootstrap/cleanup smoke check; does not read any article or miniapp data.
import { spawn } from "node:child_process";
import { once } from "node:events";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { randomBytes } from "node:crypto";
import assert from "node:assert/strict";
const root =
  process.env.NATIVE_RESOURCE_ROOT ||
  path.resolve("dist/公众号文章下载器.app/Contents/Resources/native");
const data = await fs.mkdtemp(path.join(os.tmpdir(), "mp-native-smoke-"));
const token = randomBytes(24).toString("hex");
const child = spawn(path.join(root, "node"), [path.join(root, "bridge.mjs")], {
  env: { ...process.env, MP_NATIVE_DATA: data, MP_NATIVE_TOKEN: token },
  stdio: ["ignore", "pipe", "pipe"],
});
child.stderr.on("data", () => {});
const exited = once(child, "exit");
try {
  const line = await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(Error("helper startup timeout")), 8000);
    child.stdout.once("data", (b) => {
      clearTimeout(t);
      resolve(b.toString().split("\n")[0]);
    });
    child.once("error", reject);
  });
  const { port } = JSON.parse(line),
    base = `http://127.0.0.1:${port}`;
  const request = async (route, body, origin) => {
    const r = await fetch(base + route, {
      method: body ? "POST" : "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        ...(origin ? { Origin: origin } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(55000),
    });
    return { status: r.status, data: await r.json() };
  };
  assert.equal((await fetch(base + "/status")).status, 403);
  assert.equal(
    (await request("/status", null, "https://example.invalid")).status,
    403,
  );
  assert.equal((await request("/status")).data.state, "stopped");
  console.log(
    JSON.stringify({
      authentication: "passed",
      origin_rejection: "passed",
      initial_state: "stopped",
    }),
  );
  const connected = await request("/connect", {});
  if (connected.data.error) throw Error(connected.data.error);
  assert(
    ["waiting_miniapp", "waiting_profile", "ready"].includes(
      connected.data.state,
    ),
  );
  console.log(
    JSON.stringify({
      bootstrap: "passed",
      state: connected.data.state,
      ready: connected.data.ready,
    }),
  );
  assert.equal((await request("/disconnect", {})).data.state, "stopped");
  assert.equal(
    await fs.access(path.join(data, "bridge-token.json")).then(
      () => true,
      () => false,
    ),
    false,
  );
  console.log(
    JSON.stringify({ disconnect: "passed", ephemeral_token_removed: true }),
  );
} finally {
  child.kill("SIGTERM");
  await Promise.race([exited, new Promise((r) => setTimeout(r, 7000))]);
  if (child.exitCode === null) {
    child.kill("SIGKILL");
    await exited;
  }
  await fs.rm(data, { recursive: true, force: true });
}
