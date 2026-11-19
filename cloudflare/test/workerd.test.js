import test from "node:test";
import assert from "node:assert/strict";
import { Miniflare } from "miniflare";
import { readFileSync } from "node:fs";
import { build } from "esbuild";
import { hashPassword, randomToken, sha256 } from "../src/crypto.js";
test("actual Workers runtime accepts credential KDF, D1 batch guards and private R2", async () => {
  const bundle = await build({
    entryPoints: [
      new URL("../src/index.js", import.meta.url).pathname.replace(
        /^\/([A-Z]:)/,
        "$1",
      ),
    ],
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
  });
  const setupToken = randomToken(),
    digest = await sha256(setupToken);
  const mf = new Miniflare({
    modules: true,
    script: bundle.outputFiles[0].text,
    compatibilityDate: "2026-08-06",
    d1Databases: { DB: "db" },
    r2Buckets: { PHOTOS: "photos" },
    bindings: {
      BUSINESS_TIMEZONE: "Asia/Jakarta",
      OWNER_SETUP_TOKEN_SHA256: digest.toUpperCase(),
    },
    modulesRules: [{ type: "ESModule", include: ["**/*.js"] }],
  });
  try {
    const db = await mf.getD1Database("DB");
    const sql = ["0001_initial.sql", "0002_workspace.sql"]
      .map((file) =>
        readFileSync(new URL("../migrations/" + file, import.meta.url), "utf8"),
      )
      .join("\n");
    // D1 exec is line-oriented; statements include a trigger so use the SQLite migration as one script through prepare.
    const statements = sql.split(/;\s*\n/);
    let trigger = "";
    for (const chunk of statements) {
      if (!chunk.trim()) continue;
      if (chunk.includes("CREATE TRIGGER")) {
        if (chunk.trim().endsWith("END")) await db.prepare(chunk).run();
        else trigger = chunk + ";";
        continue;
      }
      if (trigger) {
        trigger += chunk + ";";
        if (chunk.trim().endsWith("END")) {
          await db.prepare(trigger).run();
          trigger = "";
        }
        continue;
      }
      await db.prepare(chunk).run();
    }
    const hash = await hashPassword("workerd password for test");
    await db
      .prepare(
        "INSERT INTO users(id,name,username,password_hash,role,created_at) VALUES('alice','alice','alice',?,'employee',?)",
      )
      .bind(hash, new Date().toISOString())
      .run();
    const workspace = async () => {
      const response = await mf.dispatchFetch("https://example/v1/workspace");
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("cache-control"), "no-store");
      return response.json();
    };
    const before = await workspace();
    assert.match(before.id, /^[0-9a-f]{32}$/);
    assert.deepEqual(before, {
      id: before.id,
      name: "Absensi & Bon",
      ready: false,
    });
    const claim = async (
      token,
      username = "OWNER",
      workspaceName = "Test Workspace",
    ) => {
      const response = await mf.dispatchFetch(
        "https://example/v1/setup/owner",
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            setupToken: token,
            name: "Claimed Owner",
            username,
            password: "workerd password for test",
            workspaceName,
          }),
        },
      );
      const text = await response.text();
      assert.equal(
        text.includes(setupToken) || text.toLowerCase().includes(digest),
        false,
      );
      return { status: response.status, data: JSON.parse(text) };
    };
    for (const bad of [
      undefined,
      "",
      42,
      digest,
      setupToken + " ",
      randomToken(),
    ]) {
      const response = await claim(bad);
      assert.equal(response.status, 401);
      assert.equal(response.data.error.code, "invalid_setup_token");
    }
    assert.equal(
      (await claim(setupToken, "alice")).data.error.code,
      "username_taken",
    );
    assert.deepEqual(await workspace(), before);
    assert.equal(
      (await db.prepare("SELECT count(*) AS n FROM sessions").first()).n,
      0,
    );

    const claims = await Promise.all([
      claim(setupToken, "OWNER", "First Workspace"),
      claim(setupToken, "SECOND", "Second Workspace"),
    ]);
    assert.deepEqual(claims.map(({ status }) => status).sort(), [201, 409]);
    const winner = claims.find(({ status }) => status === 201).data;
    assert.equal(
      claims.find(({ status }) => status === 409).data.error.code,
      "workspace_claimed",
    );
    assert.deepEqual(winner.user, {
      id: winner.user.id,
      name: "Claimed Owner",
      username: winner.user.username,
      role: "owner",
      active: true,
    });
    assert.match(winner.token, /^[0-9a-f]{64}$/);
    assert.deepEqual(await workspace(), {
      id: before.id,
      name:
        winner.user.username === "owner"
          ? "First Workspace"
          : "Second Workspace",
      ready: true,
    });
    assert.equal(
      (await claim(setupToken)).data.error.code,
      "workspace_claimed",
    );
    assert.equal(
      (
        await db
          .prepare("SELECT count(*) AS n FROM users WHERE role='owner'")
          .first()
      ).n,
      1,
    );
    const session = await db
      .prepare("SELECT token_hash,user_id FROM sessions")
      .all();
    assert.deepEqual(session.results, [
      { token_hash: await sha256(winner.token), user_id: winner.user.id },
    ]);
    const me = await mf.dispatchFetch("https://example/v1/auth/me", {
      headers: { authorization: "Bearer " + winner.token },
    });
    assert.deepEqual(await me.json(), { ok: true, user: winner.user });
    const login = async (username) => {
      const response = await mf.dispatchFetch("https://example/v1/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          username,
          password: "workerd password for test",
        }),
      });
      assert.equal(response.status, 200);
      return (await response.json()).token;
    };
    const owner = await login(winner.user.username),
      alice = await login("alice");
    const request = async (path, token, body, key) => {
      const response = await mf.dispatchFetch("https://example" + path, {
        method: "POST",
        headers: {
          authorization: "Bearer " + token,
          "content-type": "application/json",
          "Idempotency-Key": key,
        },
        body: JSON.stringify(body),
      });
      return { status: response.status, data: await response.json() };
    };
    const bon = await request(
      "/v1/bon",
      alice,
      { amount: 100 },
      "workerd-create",
    );
    assert.equal(bon.status, 201);
    const path = "/v1/bon/" + bon.data.record.id + "/actions";
    assert.equal(
      (await request(path, owner, { action: "approve" }, "workerd-approve"))
        .status,
      200,
    );
    assert.equal(
      (await request(path, owner, { action: "disburse" }, "workerd-disburse"))
        .status,
      200,
    );
    const repayment = await Promise.all([
      request(path, owner, { action: "repay", amount: 70 }, "workerd-repay-1"),
      request(path, owner, { action: "repay", amount: 70 }, "workerd-repay-2"),
    ]);
    assert.deepEqual(repayment.map((x) => x.status).sort(), [200, 409]);
    const form = new FormData();
    form.set("kind", "check_in");
    form.set(
      "photo",
      new Blob(
        [new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0])],
        { type: "application/octet-stream" },
      ),
      "camera.dat",
    );
    const serialized = new Request("https://example/", {
      method: "POST",
      body: form,
    });
    const encoded = await serialized.arrayBuffer();
    const attendance = await mf.dispatchFetch("https://example/v1/attendance", {
      method: "POST",
      headers: {
        authorization: "Bearer " + alice,
        "Idempotency-Key": "workerd-photo",
        "content-type": serialized.headers.get("content-type"),
      },
      body: encoded,
    });
    assert.equal(attendance.status, 201);
    const photoPath = (await attendance.json()).record.photoPath;
    const photo = await mf.dispatchFetch("https://example" + photoPath, {
      headers: { authorization: "Bearer " + alice },
    });
    assert.equal(photo.status, 200);
    assert.equal(photo.headers.get("content-type"), "image/png");
  } finally {
    await mf.dispose();
  }
});
