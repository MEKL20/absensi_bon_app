import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import worker from "../src/index.js";
import { hashPassword, sha256 } from "../src/crypto.js";
const PASSWORD = "correct horse battery staple";
const sharedHash = await hashPassword(PASSWORD);
class SQLiteD1 {
  constructor() {
    this.db = new DatabaseSync(":memory:");
    this.db.exec(
      readFileSync(
        new URL("../migrations/0001_initial.sql", import.meta.url),
        "utf8",
      ),
    );
  }
  prepare(sql) {
    const db = this.db;
    let args = [];
    const statement = {
      bind(...values) {
        args = values;
        return statement;
      },
      async first() {
        return db.prepare(sql).get(...args) || null;
      },
      async all() {
        return { results: db.prepare(sql).all(...args) };
      },
      async run() {
        const prepared = db.prepare(sql);
        const results = prepared.columns().length ? prepared.all(...args) : [];
        if (!prepared.columns().length) prepared.run(...args);
        return {
          results,
          meta: {
            changes: Number(db.prepare("SELECT changes() AS n").get().n),
          },
        };
      },
      execute() {
        const prepared = db.prepare(sql);
        const results = prepared.columns().length ? prepared.all(...args) : [];
        if (!prepared.columns().length) prepared.run(...args);
        return {
          results,
          meta: {
            changes: Number(db.prepare("SELECT changes() AS n").get().n),
          },
        };
      },
    };
    return statement;
  }
  async batch(statements) {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const results = statements.map((s) => s.execute());
      this.db.exec("COMMIT");
      return results;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }
}
async function setup() {
  const env = {
    DB: new SQLiteD1(),
    PHOTOS: {
      objects: new Map(),
      async put(key, bytes) {
        this.objects.set(key, bytes);
      },
      async get(key) {
        const data = this.objects.get(key);
        return data ? { body: data } : null;
      },
      async delete(key) {
        this.objects.delete(key);
      },
    },
    BUSINESS_TIMEZONE: "Asia/Jakarta",
  };
  const tokens = {
    owner: "a".repeat(64),
    alice: "b".repeat(64),
    bob: "c".repeat(64),
  };
  for (const [id, token] of Object.entries(tokens)) {
    await env.DB.prepare(
      "INSERT INTO users(id,name,username,password_hash,role,active,created_at) VALUES(?,?,?,?,?,?,?)",
    )
      .bind(
        id,
        id,
        id,
        sharedHash,
        id === "owner" ? "owner" : "employee",
        1,
        new Date().toISOString(),
      )
      .run();
    await env.DB.prepare("INSERT INTO sessions VALUES(?,?,?,?)")
      .bind(
        await sha256(token),
        id,
        "2099-01-01T00:00:00.000Z",
        new Date().toISOString(),
      )
      .run();
  }
  const call = async (method, path, actor = "alice", body, key) => {
    const headers = {};
    if (actor) headers.authorization = "Bearer " + (tokens[actor] || actor);
    if (key) headers["Idempotency-Key"] = key;
    if (body !== undefined && !(body instanceof FormData)) {
      headers["content-type"] = "application/json";
      body = JSON.stringify(body);
    }
    const response = await worker.fetch(
      new Request("https://api.example" + path, { method, headers, body }),
      env,
    );
    let data;
    if (response.headers.get("content-type")?.includes("application/json"))
      data = await response.json();
    else data = new Uint8Array(await response.arrayBuffer());
    return { status: response.status, data };
  };
  return { env, call, tokens };
}
function photoForm(
  kind = "check_in",
  bytes = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]),
  mime = "image/png",
) {
  const form = new FormData();
  form.set("kind", kind);
  form.set("photo", new Blob([bytes], { type: mime }), "untrusted-name.exe");
  return form;
}
test("opaque sessions authenticate, expire, logout, and revoke on employee changes", async () => {
  const { env, call } = await setup();
  assert.equal((await call("GET", "/v1/auth/me", null)).status, 401);
  const login = await call("POST", "/v1/auth/login", null, {
    username: "ALICE",
    password: PASSWORD,
  });
  assert.equal(login.status, 200);
  assert.equal(login.data.user.active, true);
  assert.match(login.data.token, /^[0-9a-f]{64}$/);
  assert.equal(
    await env.DB.prepare("SELECT token_hash FROM sessions WHERE token_hash=?")
      .bind(login.data.token)
      .first(),
    null,
  );
  assert.equal(
    (await call("POST", "/v1/auth/logout", login.data.token)).status,
    200,
  );
  assert.equal(
    (await call("GET", "/v1/auth/me", login.data.token)).status,
    401,
  );
  await env.DB.prepare(
    "UPDATE sessions SET expires_at='2000-01-01T00:00:00.000Z' WHERE user_id='bob'",
  ).run();
  assert.equal((await call("GET", "/v1/auth/me", "bob")).status, 401);
  assert.equal(
    (
      await call("PATCH", "/v1/employees/alice", "owner", {
        password: "new secure password 123",
      })
    ).status,
    200,
  );
  assert.equal((await call("GET", "/v1/auth/me")).status, 401);
});
test("server enforces owner role and disallows owner escalation", async () => {
  const { call } = await setup();
  assert.equal((await call("GET", "/v1/employees")).status, 403);
  assert.equal(
    (
      await call("POST", "/v1/employees", "owner", {
        name: "Eve",
        username: "eve",
        password: PASSWORD,
        role: "owner",
      })
    ).status,
    400,
  );
  assert.equal(
    (await call("PATCH", "/v1/employees/owner", "owner", { active: false }))
      .status,
    404,
  );
  const created = await call("POST", "/v1/employees", "owner", {
    name: "Eve",
    username: "eve",
    password: PASSWORD,
  });
  assert.equal(created.status, 201);
  assert.equal(created.data.user.role, "employee");
  assert.equal(
    (
      await call("PATCH", "/v1/employees/" + created.data.user.id, "owner", {
        active: false,
      })
    ).data.user.active,
    false,
  );
  assert.equal(
    (await call("POST", "/v1/attendance", "owner", photoForm(), "owner-check"))
      .status,
    403,
  );
});
test("login limiter is persistent, atomic, and safe for unknown accounts", async () => {
  const { env, call } = await setup();
  await env.DB.prepare("INSERT INTO login_limits VALUES(?,?,10)")
    .bind(await sha256("account:missing"), Date.now())
    .run();
  const results = await Promise.all(
    Array.from({ length: 8 }, () =>
      call("POST", "/v1/auth/login", null, {
        username: "missing",
        password: PASSWORD,
      }),
    ),
  );
  assert.ok(results.every((r) => r.status === 429));
  assert.equal(
    (
      await env.DB.prepare("SELECT attempts FROM login_limits WHERE key=?")
        .bind(await sha256("account:missing"))
        .first()
    ).attempts,
    18,
  );
  const bad = await call("POST", "/v1/auth/login", null, {
    username: "alice",
    password: "wrong",
  });
  assert.deepEqual(bad.data, {
    ok: false,
    error: {
      code: "invalid_credentials",
      message: "Invalid username or password.",
    },
  });
});
test("bon is photo-free, scoped, paginated, and has actor/payload idempotency", async () => {
  const { env, call } = await setup();
  assert.equal(
    (
      await call(
        "POST",
        "/v1/bon",
        "alice",
        { amount: 100, note: "food", photo: "x" },
        "bon-0001",
      )
    ).status,
    400,
  );
  assert.equal(
    (await call("POST", "/v1/bon", "alice", { amount: 1 })).status,
    400,
  );
  for (const amount of [0, -1, 1.5, 1000000001])
    assert.equal(
      (await call("POST", "/v1/bon", "alice", { amount }, "invalid-amount"))
        .status,
      400,
    );
  const [a, b] = await Promise.all([
    call("POST", "/v1/bon", "alice", { amount: 100, note: "food" }, "bon-0001"),
    call("POST", "/v1/bon", "alice", { amount: 100, note: "food" }, "bon-0001"),
  ]);
  assert.equal(a.status, 201);
  assert.deepEqual(a, b);
  assert.equal(
    (await env.DB.prepare("SELECT COUNT(*) AS n FROM bon").first()).n,
    1,
  );
  assert.equal(
    (await env.DB.prepare("SELECT COUNT(*) AS n FROM bon_audit").first()).n,
    1,
  );
  assert.equal(
    (
      await call(
        "POST",
        "/v1/bon",
        "alice",
        { amount: 101, note: "food" },
        "bon-0001",
      )
    ).status,
    409,
  );
  assert.equal(
    (await call("POST", "/v1/bon", "bob", { amount: 22 }, "bon-0001")).status,
    201,
  );
  const own = await call("GET", "/v1/bon");
  assert.equal(own.data.bon.length, 1);
  assert.equal(own.data.bon[0].employeeId, "alice");
  assert.equal("photoPath" in own.data.bon[0], false);
  const owner = await call("GET", "/v1/bon?limit=1", "owner");
  assert.equal(owner.data.pagination.hasMore, true);
  assert.equal((await call("GET", "/v1/bon?limit=101")).status, 400);
  assert.equal((await call("GET", "/v1/bon?from=2026-02-30")).status, 400);
});
test("money actions and audit remain atomic under concurrent overpayment", async () => {
  const { env, call } = await setup();
  const created = await call(
    "POST",
    "/v1/bon",
    "alice",
    { amount: 100 },
    "money-create",
  );
  const path = "/v1/bon/" + created.data.record.id + "/actions";
  assert.equal(
    (await call("POST", path, "alice", { action: "approve" }, "self-action"))
      .status,
    403,
  );
  assert.equal(
    (
      await call(
        "POST",
        path,
        "owner",
        { action: "repay", amount: 1 },
        "wrong-state",
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await env.DB.prepare(
        "SELECT COUNT(*) AS n FROM idempotency WHERE key='wrong-state'",
      ).first()
    ).n,
    0,
  );
  assert.equal(
    (await call("POST", path, "owner", { action: "approve" }, "money-approve"))
      .status,
    200,
  );
  assert.equal(
    (await call("GET", "/v1/dashboard")).data.summary.outstandingAmount,
    0,
  );
  const disbursed = await call(
    "POST",
    path,
    "owner",
    { action: "disburse" },
    "money-disburse",
  );
  assert.equal(disbursed.status, 200);
  assert.equal(
    (await call("GET", "/v1/dashboard")).data.summary.outstandingAmount,
    100,
  );
  const payments = await Promise.all([
    call("POST", path, "owner", { action: "repay", amount: 70 }, "payment-one"),
    call("POST", path, "owner", { action: "repay", amount: 70 }, "payment-two"),
  ]);
  assert.deepEqual(payments.map((r) => r.status).sort(), [200, 409]);
  const audit = await env.DB.prepare(
    "SELECT * FROM bon_audit WHERE action='repay'",
  ).all();
  assert.equal(audit.results.length, 1);
  assert.equal(
    (await call("GET", "/v1/dashboard")).data.summary.outstandingAmount,
    30,
  );
  const repaid = await call(
    "POST",
    path,
    "owner",
    { action: "repay", amount: 30 },
    "payment-final",
  );
  assert.equal(repaid.data.record.status, "repaid");
  assert.equal(repaid.data.record.repaidAmount, 100);
  assert.deepEqual(
    await call(
      "POST",
      path,
      "owner",
      { action: "repay", amount: 30 },
      "payment-final",
    ),
    repaid,
  );
  assert.equal(
    (
      await call(
        "POST",
        path,
        "owner",
        { action: "disburse" },
        "disburse-again",
      )
    ).status,
    409,
  );
  assert.equal(
    (await call("GET", "/v1/dashboard", "bob")).data.summary.outstandingAmount,
    0,
  );
});
test("attendance validates upload, orders daily events and protects R2 photos", async () => {
  const { env, call } = await setup();
  assert.equal(
    (
      await call(
        "POST",
        "/v1/attendance",
        "alice",
        photoForm("check_out"),
        "checkout-first",
      )
    ).status,
    409,
  );
  assert.equal(env.PHOTOS.objects.size, 0);
  assert.equal(
    (
      await call(
        "POST",
        "/v1/attendance",
        "alice",
        photoForm("check_in", new Uint8Array(20)),
        "bad-image",
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await call(
        "POST",
        "/v1/attendance",
        "alice",
        photoForm("check_in", new Uint8Array(2 * 1024 * 1024 + 1)),
        "big-image",
      )
    ).status,
    400,
  );
  const checkin = await call(
    "POST",
    "/v1/attendance",
    "alice",
    photoForm(),
    "attendance-1",
  );
  assert.equal(checkin.status, 201);
  assert.equal(
    (await call("POST", "/v1/attendance", "alice", photoForm(), "attendance-2"))
      .status,
    409,
  );
  assert.deepEqual(
    await call("POST", "/v1/attendance", "alice", photoForm(), "attendance-1"),
    checkin,
  );
  const photo = checkin.data.record.photoPath;
  assert.equal((await call("GET", photo, "bob")).status, 404);
  assert.equal((await call("GET", photo, "owner")).status, 200);
  assert.equal((await call("GET", photo, null)).status, 401);
  assert.equal(env.PHOTOS.objects.size, 1);
  assert.equal(
    (await call("GET", "/v1/attendance", "bob")).data.attendance.length,
    0,
  );
  assert.equal(
    (
      await call(
        "POST",
        "/v1/attendance",
        "alice",
        photoForm("check_out"),
        "attendance-out",
      )
    ).status,
    201,
  );
  assert.equal(
    (await call("GET", "/v1/dashboard", "owner")).data.summary.checkedInCount,
    0,
  );
});
test("cron leaves photos by default; configured retention clears binary reference", async () => {
  const { env, call } = await setup();
  const result = await call(
    "POST",
    "/v1/attendance",
    "alice",
    photoForm(),
    "retention-one",
  );
  await env.DB.prepare(
    "UPDATE attendance SET recorded_at='2000-01-01T00:00:00.000Z'",
  ).run();
  await worker.scheduled({}, env);
  assert.equal(env.PHOTOS.objects.size, 1);
  env.PHOTO_RETENTION_DAYS = "30";
  await worker.scheduled({}, env);
  assert.equal(env.PHOTOS.objects.size, 0);
  assert.equal((await call("GET", result.data.record.photoPath)).status, 404);
  assert.equal(
    (await call("GET", "/v1/attendance")).data.attendance[0].photoPath,
    null,
  );
});

test("upload intents recover interrupted puts without deleting committed photos", async () => {
  const { env, call } = await setup();
  const accepted = await call(
    "POST",
    "/v1/attendance",
    "alice",
    photoForm(),
    "intent-accepted",
  );
  assert.equal(accepted.status, 201);
  await env.DB.prepare("UPDATE photo_uploads SET lease_until=0").run();
  await env.DB.prepare("INSERT INTO photo_uploads VALUES(?,'pending',0,0)")
    .bind("abandoned")
    .run();
  await env.PHOTOS.put("abandoned", new Uint8Array([1]));
  await worker.scheduled({}, env);
  assert.equal(env.PHOTOS.objects.has("abandoned"), false);
  assert.equal((await call("GET", accepted.data.record.photoPath)).status, 200);
  assert.throws(
    () =>
      env.DB.db
        .prepare(
          "INSERT INTO attendance VALUES('late','alice','check_out','2099-01-01T00:00:00.000Z','2099-01-01','abandoned','image/png')",
        )
        .run(),
    /photo_lease_constraint/,
  );
  // A late PUT cannot become an attendance record; the persistent tombstone catches it again.
  await env.PHOTOS.put("abandoned", new Uint8Array([1]));
  await env.DB.prepare(
    "UPDATE photo_uploads SET checked_at=0 WHERE photo_key='abandoned'",
  ).run();
  await worker.scheduled({}, env);
  assert.equal(env.PHOTOS.objects.has("abandoned"), false);
});
test("attendance alternates across midnight and supports another same-day pair", async () => {
  const { env, call } = await setup();
  assert.equal(
    (await call("POST", "/v1/attendance", "alice", photoForm(), "cross-day-in"))
      .status,
    201,
  );
  await env.DB.prepare(
    "UPDATE attendance SET business_date='2000-01-01',recorded_at='2000-01-01T12:00:00.000Z'",
  ).run();
  assert.equal(
    (await call("GET", "/v1/dashboard")).data.summary.checkedInCount,
    1,
  );
  assert.equal(
    (
      await call(
        "POST",
        "/v1/attendance",
        "alice",
        photoForm("check_out"),
        "cross-day-out",
      )
    ).status,
    201,
  );
  assert.equal(
    (
      await call(
        "POST",
        "/v1/attendance",
        "alice",
        photoForm(),
        "same-day-next",
      )
    ).status,
    201,
  );
  const duplicate = await Promise.all([
    call(
      "POST",
      "/v1/attendance",
      "alice",
      photoForm("check_out"),
      "simultaneous-1",
    ),
    call(
      "POST",
      "/v1/attendance",
      "alice",
      photoForm("check_out"),
      "simultaneous-2",
    ),
  ]);
  assert.deepEqual(duplicate.map((x) => x.status).sort(), [201, 409]);
});
test("employees endpoint is bounded and exposes continuation", async () => {
  const { call } = await setup();
  const result = await call("GET", "/v1/employees?limit=1", "owner");
  assert.equal(result.data.employees.length, 1);
  assert.equal(result.data.pagination.nextOffset, 1);
  assert.equal(
    (await call("GET", "/v1/employees?limit=1&offset=1", "owner")).data
      .pagination.hasMore,
    false,
  );
});
