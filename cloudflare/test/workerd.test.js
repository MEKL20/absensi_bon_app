import test from "node:test";
import assert from "node:assert/strict";
import { Miniflare } from "miniflare";
import { readFileSync } from "node:fs";
import { build } from "esbuild";
import { hashPassword } from "../src/crypto.js";
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
  const mf = new Miniflare({
    modules: true,
    script: bundle.outputFiles[0].text,
    compatibilityDate: "2026-08-06",
    d1Databases: { DB: "db" },
    r2Buckets: { PHOTOS: "photos" },
    bindings: { BUSINESS_TIMEZONE: "Asia/Jakarta" },
    modulesRules: [{ type: "ESModule", include: ["**/*.js"] }],
  });
  try {
    const db = await mf.getD1Database("DB");
    const sql = readFileSync(
      new URL("../migrations/0001_initial.sql", import.meta.url),
      "utf8",
    );
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
    for (const [id, role] of [
      ["owner", "owner"],
      ["alice", "employee"],
    ])
      await db
        .prepare(
          "INSERT INTO users(id,name,username,password_hash,role,created_at) VALUES(?,?,?,?,?,?)",
        )
        .bind(id, id, id, hash, role, new Date().toISOString())
        .run();
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
    const owner = await login("owner"),
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
