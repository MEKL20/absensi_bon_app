import {
  hashPassword,
  verifyPassword,
  sha256,
  randomToken,
  matchesSetupToken,
  DUMMY_HASH,
} from "./crypto.js";
const USER_COLUMNS = "id,name,username,role,active";
const BON_COLUMNS =
  "b.id,b.employee_id AS employeeId,u.name AS employeeName,b.amount,b.note,b.status,b.repaid_amount AS repaidAmount,b.created_at AS createdAt";
const ATTENDANCE_COLUMNS =
  "a.id,a.employee_id AS employeeId,u.name AS employeeName,a.kind,a.recorded_at AS recordedAt,CASE WHEN a.photo_key IS NULL THEN NULL ELSE '/v1/attendance/' || a.id || '/photo' END AS photoPath";
class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
const fail = (status, code, message) => {
  throw new ApiError(status, code, message);
};
const reply = (data, status = 200) =>
  Response.json(data, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
const ok = (data, status) => reply({ ok: true, ...data }, status);
const stmt = (env, sql, ...args) => env.DB.prepare(sql).bind(...args);
const first = (env, sql, ...args) => stmt(env, sql, ...args).first();
const all = async (env, sql, ...args) =>
  (await stmt(env, sql, ...args).all()).results;
const publicUser = (u) => ({ ...u, active: !!u.active });
const owner = (u) => {
  if (u.role !== "owner") fail(403, "forbidden", "Owner access required.");
};
const employee = (u) => {
  if (u.role !== "employee")
    fail(403, "forbidden", "Employee access required.");
};
const now = () => new Date().toISOString();
function sessionExpiry(env) {
  return new Date(
    Date.now() +
      integerConfig(env, "SESSION_TTL_SECONDS", 86400, 300, 2592000) * 1000,
  ).toISOString();
}
function integerConfig(env, key, fallback, min, max) {
  const n = Number(env[key] ?? fallback);
  if (!Number.isSafeInteger(n) || n < min || n > max)
    throw new Error("Invalid configuration: " + key);
  return n;
}
function username(value) {
  if (typeof value !== "string" || !/^[a-zA-Z0-9._-]{3,64}$/.test(value))
    fail(
      400,
      "invalid_input",
      "Username must contain 3–64 letters, numbers, dots, underscores or hyphens.",
    );
  return value.toLowerCase();
}
function name(value) {
  if (typeof value !== "string" || !value.trim() || value.trim().length > 100)
    fail(400, "invalid_input", "Name must contain 1–100 characters.");
  return value.trim();
}
function password(value) {
  if (typeof value !== "string" || value.length < 12 || value.length > 128)
    fail(400, "invalid_input", "Password must contain 12–128 characters.");
  return value;
}
async function limitedBody(request, max) {
  const reader = request.body?.getReader();
  if (!reader) fail(400, "invalid_input", "Request body required.");
  let size = 0;
  const chunks = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      await reader.cancel();
      fail(413, "body_too_large", "Request body too large.");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let pos = 0;
  for (const c of chunks) {
    bytes.set(c, pos);
    pos += c.length;
  }
  return bytes;
}
async function json(request, allowed) {
  if (
    !request.headers
      .get("content-type")
      ?.toLowerCase()
      .startsWith("application/json")
  )
    fail(415, "invalid_content_type", "JSON required.");
  let data;
  try {
    data = JSON.parse(
      new TextDecoder().decode(await limitedBody(request, 8192)),
    );
  } catch (e) {
    if (e instanceof ApiError) throw e;
    fail(400, "invalid_input", "Invalid JSON.");
  }
  if (
    !data ||
    typeof data !== "object" ||
    Array.isArray(data) ||
    Object.keys(data).some((k) => !allowed.includes(k))
  )
    fail(400, "invalid_input", "Unexpected request fields.");
  return data;
}
function businessDate(env, time = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: env.BUSINESS_TIMEZONE || "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(time);
}
function pagination(url) {
  const number = (k, def, min, max) => {
    const raw = url.searchParams.get(k);
    const n = raw === null ? def : Number(raw);
    if (
      !/^\d+$/.test(String(raw ?? def)) ||
      !Number.isSafeInteger(n) ||
      n < min ||
      n > max
    )
      fail(400, "invalid_input", "Invalid pagination.");
    return n;
  };
  const limit = number("limit", 20, 1, 100),
    offset = number("offset", 0, 0, 100000);
  const dates = {};
  for (const k of ["from", "to"]) {
    const v = url.searchParams.get(k);
    if (v !== null) {
      if (
        !/^\d{4}-\d{2}-\d{2}$/.test(v) ||
        !Number.isFinite(Date.parse(v)) ||
        new Date(v).toISOString().slice(0, 10) !== v
      )
        fail(400, "invalid_input", "Dates must be YYYY-MM-DD.");
      dates[k] = v;
    }
  }
  if (dates.from && dates.to && dates.from > dates.to)
    fail(400, "invalid_input", "Invalid date range.");
  return { limit, offset, ...dates };
}
async function authenticate(request, env) {
  const token = request.headers
    .get("authorization")
    ?.match(/^Bearer ([0-9a-f]{64})$/)?.[1];
  if (!token) fail(401, "unauthorized", "Authentication required.");
  const tokenHash = await sha256(token);
  const u = await first(
    env,
    "SELECT u." +
      USER_COLUMNS.split(",").join(",u.") +
      " FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? AND u.active=1",
    tokenHash,
    now(),
  );
  if (!u) fail(401, "unauthorized", "Authentication required.");
  return { ...publicUser(u), tokenHash };
}
async function login(request, env) {
  const data = await json(request, ["username", "password"]);
  const account =
    typeof data.username === "string"
      ? data.username.toLowerCase().slice(0, 128)
      : "";
  const ip = request.headers.get("CF-Connecting-IP") || "local";
  const stamp = Date.now(),
    window = 900000;
  const keys = await Promise.all(
    ["ip:" + ip, "account:" + account].map(sha256),
  );
  const results = await env.DB.batch(
    keys.map((key) =>
      stmt(
        env,
        "INSERT INTO login_limits(key,window_start,attempts) VALUES(?,?,1) ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN window_start<=? THEN 1 ELSE attempts+1 END,window_start=CASE WHEN window_start<=? THEN excluded.window_start ELSE window_start END RETURNING attempts",
        key,
        stamp,
        stamp - window,
        stamp - window,
      ),
    ),
  );
  if (
    results[0].results[0].attempts > 30 ||
    results[1].results[0].attempts > 10
  )
    fail(429, "login_limited", "Unable to sign in. Try again later.");
  const u = await first(env, "SELECT * FROM users WHERE username=?", account);
  const supplied =
    typeof data.password === "string" && data.password.length <= 128
      ? data.password
      : "";
  const valid = await verifyPassword(supplied, u?.password_hash || DUMMY_HASH);
  if (!valid || !u?.active)
    fail(401, "invalid_credentials", "Invalid username or password.");
  const token = randomToken(),
    created = now(),
    expires = sessionExpiry(env);
  // Guard against a concurrent password reset/deactivation while the expensive KDF is running.
  const result = await stmt(
    env,
    "INSERT INTO sessions(token_hash,user_id,expires_at,created_at) SELECT ?,id,?,? FROM users WHERE id=? AND active=1 AND password_hash=?",
    await sha256(token),
    expires,
    created,
    u.id,
    u.password_hash,
  ).run();
  if (result.meta.changes !== 1)
    fail(401, "invalid_credentials", "Invalid username or password.");
  return ok({
    token,
    user: publicUser(
      Object.fromEntries(USER_COLUMNS.split(",").map((k) => [k, u[k]])),
    ),
  });
}
async function workspace(env) {
  const row = await first(
    env,
    "SELECT workspace_id AS id,workspace_name AS name,claimed_at FROM workspace_setup WHERE id=1",
  );
  if (!row) fail(503, "setup_unavailable", "Workspace is unavailable.");
  return { id: row.id, name: row.name, ready: row.claimed_at !== null };
}
async function setupOwner(request, env) {
  const digest = env.OWNER_SETUP_TOKEN_SHA256;
  if (
    typeof digest !== "string" ||
    digest.length !== 64 ||
    !/^[0-9a-f]{64}$/i.test(digest)
  )
    fail(503, "setup_unavailable", "Owner setup is unavailable.");
  const data = await json(request, [
    "setupToken",
    "name",
    "username",
    "password",
    "workspaceName",
  ]);
  if (!(await matchesSetupToken(data.setupToken, digest.toLowerCase())))
    fail(401, "invalid_setup_token", "Invalid setup token.");
  const rejectClaimed = async () => {
    if ((await workspace(env)).ready)
      fail(
        409,
        "workspace_claimed",
        "Workspace has already been claimed. Sign in instead.",
      );
  };
  await rejectClaimed();
  const id = crypto.randomUUID(),
    ownerName = name(data.name),
    account = username(data.username),
    workspaceName = name(data.workspaceName),
    hash = await hashPassword(password(data.password)),
    token = randomToken(),
    created = now();
  // The owner insert sets claimed_at via trigger. Each following write requires the previous write to win.
  let inserted;
  try {
    [inserted] = await env.DB.batch([
      stmt(
        env,
        "INSERT INTO users(id,name,username,password_hash,role,created_at) SELECT ?,?,?,?,'owner',? FROM workspace_setup WHERE id=1 AND claimed_at IS NULL ON CONFLICT(username) DO NOTHING RETURNING id",
        id,
        ownerName,
        account,
        hash,
        created,
      ),
      stmt(
        env,
        "UPDATE workspace_setup SET workspace_name=? WHERE id=1 AND changes()=1",
        workspaceName,
      ),
      stmt(
        env,
        "INSERT INTO sessions(token_hash,user_id,expires_at,created_at) SELECT ?,?,?,? WHERE changes()=1",
        await sha256(token),
        id,
        sessionExpiry(env),
        created,
      ),
    ]);
  } catch (error) {
    await rejectClaimed();
    throw error;
  }
  if (inserted.results.length !== 1) {
    await rejectClaimed();
    fail(409, "username_taken", "Username is already in use.");
  }
  return ok(
    {
      token,
      user: {
        id,
        name: ownerName,
        username: account,
        role: "owner",
        active: true,
      },
    },
    201,
  );
}
async function existingReceipt(env, actor, key, fingerprint) {
  const row = await first(
    env,
    "SELECT * FROM idempotency WHERE actor_id=? AND key=?",
    actor,
    key,
  );
  if (!row) return null;
  if (row.fingerprint !== fingerprint)
    fail(
      409,
      "idempotency_conflict",
      "Idempotency key was used for a different request.",
    );
  if (!row.response)
    fail(409, "request_in_progress", "Request is still processing.");
  return ok(JSON.parse(row.response), row.status);
}
async function mutation(request, env, user, payload, build) {
  const key = request.headers.get("Idempotency-Key");
  if (!key || !/^[A-Za-z0-9._:-]{8,128}$/.test(key))
    fail(
      400,
      "idempotency_required",
      "Provide an Idempotency-Key containing 8–128 safe characters.",
    );
  const fingerprint = await sha256(
    request.method +
      " " +
      new URL(request.url).pathname +
      " " +
      JSON.stringify(payload),
  );
  const previous = await existingReceipt(env, user.id, key, fingerprint);
  if (previous) return previous;
  const claim = crypto.randomUUID(),
    created = now();
  const transaction = await build(claim, created);
  const active =
    "EXISTS(SELECT 1 FROM idempotency WHERE actor_id=? AND key=? AND claim=?)";
  const guardArgs = [user.id, key, claim];
  const operations = [
    stmt(
      env,
      "INSERT INTO idempotency(actor_id,key,fingerprint,claim,status,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(actor_id,key) DO NOTHING",
      user.id,
      key,
      fingerprint,
      claim,
      transaction.status || 200,
      created,
    ),
    ...transaction.statements(active, guardArgs),
  ];
  try {
    await env.DB.batch(operations);
  } catch (error) {
    const receipt = await existingReceipt(env, user.id, key, fingerprint);
    if (receipt) {
      await transaction.onDuplicate?.();
      return receipt;
    }
    await transaction.onFailure?.(error);
    const text = String(error);
    if (/constraint|attendance_order/i.test(text))
      fail(
        409,
        "state_conflict",
        "Request conflicts with the current record state.",
      );
    throw error;
  }
  const row = await first(
    env,
    "SELECT * FROM idempotency WHERE actor_id=? AND key=?",
    user.id,
    key,
  );
  if (row?.claim !== claim) await transaction.onDuplicate?.();
  return await existingReceipt(env, user.id, key, fingerprint);
}
function receipt(env, claim, data) {
  return stmt(
    env,
    "UPDATE idempotency SET response=? WHERE claim=?",
    JSON.stringify(data),
    claim,
  );
}
function transitionGuard(env, claim) {
  return stmt(
    env,
    "INSERT INTO mutation_guards(claim,valid) SELECT ?,CASE WHEN changes()=1 THEN 1 ELSE 0 END WHERE EXISTS(SELECT 1 FROM idempotency WHERE claim=?)",
    claim,
    claim,
  );
}
async function listRecords(env, user, url, type) {
  const p = pagination(url),
    attendance = type === "attendance",
    alias = attendance ? "a" : "b",
    time = attendance ? "recorded_at" : "created_at";
  const conditions = [],
    args = [];
  if (user.role === "employee") {
    conditions.push(alias + ".employee_id=?");
    args.push(user.id);
  }
  if (p.from) {
    conditions.push(alias + "." + time + ">=?");
    args.push(p.from + "T00:00:00.000Z");
  }
  if (p.to) {
    conditions.push(alias + "." + time + "<?");
    args.push(new Date(Date.parse(p.to) + 86400000).toISOString());
  }
  const where = conditions.length ? " WHERE " + conditions.join(" AND ") : "";
  const rows = await all(
    env,
    "SELECT " +
      (attendance ? ATTENDANCE_COLUMNS : BON_COLUMNS) +
      " FROM " +
      type +
      " " +
      alias +
      " JOIN users u ON u.id=" +
      alias +
      ".employee_id" +
      where +
      " ORDER BY " +
      alias +
      "." +
      time +
      " DESC," +
      alias +
      ".id DESC LIMIT ? OFFSET ?",
    ...args,
    p.limit + 1,
    p.offset,
  );
  const hasMore = rows.length > p.limit;
  return {
    [type]: rows.slice(0, p.limit),
    pagination: {
      limit: p.limit,
      offset: p.offset,
      hasMore,
      nextOffset: hasMore ? p.offset + p.limit : null,
    },
  };
}
async function attendanceCreate(request, env, user) {
  employee(user);
  const contentType = request.headers.get("content-type") || "";
  if (!contentType.startsWith("multipart/form-data;"))
    fail(415, "invalid_content_type", "Multipart form data required.");
  const raw = await limitedBody(request, 2 * 1024 * 1024 + 16384);
  let form;
  try {
    form = await new Request(request.url, {
      method: "POST",
      headers: { "content-type": contentType },
      body: raw,
    }).formData();
  } catch {
    fail(400, "invalid_input", "Invalid multipart form.");
  }
  if (
    [...form.keys()].some((k) => !["kind", "photo"].includes(k)) ||
    form.getAll("kind").length !== 1 ||
    form.getAll("photo").length !== 1
  )
    fail(400, "invalid_input", "Only kind and photo are accepted.");
  const kind = form.get("kind"),
    photo = form.get("photo");
  if (
    !["check_in", "check_out"].includes(kind) ||
    !photo ||
    typeof photo === "string"
  )
    fail(400, "invalid_input", "Kind and photo required.");
  if (photo.size < 12 || photo.size > 2 * 1024 * 1024)
    fail(400, "invalid_photo", "Photo must be at most 2 MiB.");
  const bytes = new Uint8Array(await photo.arrayBuffer());
  const mime =
    bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255
      ? "image/jpeg"
      : bytes
            .slice(0, 8)
            .every((v, i) => v === [137, 80, 78, 71, 13, 10, 26, 10][i])
        ? "image/png"
        : new TextDecoder().decode(bytes.slice(0, 4)) === "RIFF" &&
            new TextDecoder().decode(bytes.slice(8, 12)) === "WEBP"
          ? "image/webp"
          : null;
  if (!mime || !["", mime, "application/octet-stream"].includes(photo.type))
    fail(
      400,
      "invalid_photo",
      "Photo must be a JPEG, PNG or WebP image with matching content.",
    );
  return mutation(
    request,
    env,
    user,
    { kind, photoHash: await sha256(bytes) },
    async (claim, created) => {
      const id = crypto.randomUUID(),
        photoKey = "attendance/" + user.id + "/" + id;
      await stmt(
        env,
        "INSERT INTO photo_uploads(photo_key,state,lease_until) VALUES(?,'pending',?)",
        photoKey,
        Math.floor(Date.now() / 1000) + 3600,
      ).run();
      await env.PHOTOS.put(photoKey, bytes, {
        httpMetadata: { contentType: mime },
      });
      const result = {
        record: {
          id,
          employeeId: user.id,
          employeeName: user.name,
          kind,
          recordedAt: created,
          photoPath: "/v1/attendance/" + id + "/photo",
        },
      };
      return {
        status: 201,
        statements: (guard, args) => [
          stmt(
            env,
            "INSERT INTO attendance(id,employee_id,kind,recorded_at,business_date,photo_key,photo_type) SELECT ?,?,?,?,?,?,? WHERE " +
              guard,
            id,
            user.id,
            kind,
            created,
            businessDate(env),
            photoKey,
            mime,
            ...args,
          ),
          receipt(env, claim, result),
        ],
        onDuplicate: () => abandonPhoto(env, photoKey),
        onFailure: async (error) => {
          // Delete only when SQLite definitively rolled back; transport failures may have committed.
          if (/constraint|attendance_order/i.test(String(error)))
            await abandonPhoto(env, photoKey);
        },
      };
    },
  );
}
async function bonCreate(request, env, user) {
  employee(user);
  const data = await json(request, ["amount", "note"]);
  const amount = data.amount,
    note = data.note ?? "";
  if (
    !Number.isSafeInteger(amount) ||
    amount <= 0 ||
    amount >
      integerConfig(env, "MAX_BON_AMOUNT", 1000000000, 1, 1000000000000) ||
    typeof note !== "string" ||
    note.length > 500
  )
    fail(
      400,
      "invalid_input",
      "Amount must be a positive integer within the limit; note at most 500 characters.",
    );
  return mutation(
    request,
    env,
    user,
    { amount, note },
    async (claim, created) => {
      const id = crypto.randomUUID();
      return {
        status: 201,
        statements: (guard, args) => [
          stmt(
            env,
            "INSERT INTO bon(id,employee_id,amount,note,created_at) SELECT ?,?,?,?,? WHERE " +
              guard,
            id,
            user.id,
            amount,
            note,
            created,
            ...args,
          ),
          stmt(
            env,
            "INSERT INTO bon_audit(id,bon_id,actor_id,action,amount,from_status,to_status,repaid_amount,created_at,claim) SELECT ?,?,?, 'create',?,NULL,'pending',0,?,? WHERE " +
              guard,
            crypto.randomUUID(),
            id,
            user.id,
            amount,
            created,
            claim,
            ...args,
          ),
          receipt(env, claim, {
            record: {
              id,
              employeeId: user.id,
              employeeName: user.name,
              amount,
              note,
              status: "pending",
              repaidAmount: 0,
              createdAt: created,
            },
          }),
        ],
      };
    },
  );
}
async function bonAction(request, env, user, id) {
  owner(user);
  const data = await json(request, ["action", "amount"]);
  if (
    !["approve", "reject", "disburse", "repay"].includes(data.action) ||
    (data.action === "repay"
      ? !Number.isSafeInteger(data.amount) || data.amount <= 0
      : data.amount !== undefined)
  )
    fail(400, "invalid_input", "Invalid action or repayment amount.");
  const action = data.action,
    amount = data.amount ?? 0;
  return mutation(
    request,
    env,
    user,
    { action, amount },
    async (claim, created) => {
      const target = await first(env, "SELECT * FROM bon WHERE id=?", id);
      if (!target) fail(404, "not_found", "Record not found.");
      const expected = {
          approve: "pending",
          reject: "pending",
          disburse: "approved",
          repay: "disbursed",
        }[action],
        next = {
          approve: "approved",
          reject: "rejected",
          disburse: "disbursed",
          repay: "disbursed",
        }[action];
      return {
        statements: (guard, args) => [
          stmt(
            env,
            "UPDATE bon SET status=CASE WHEN ?='repay' AND repaid_amount+?=amount THEN 'repaid' ELSE ? END,repaid_amount=repaid_amount+? WHERE id=? AND status=? AND (?!='repay' OR ?<=amount-repaid_amount) AND " +
              guard,
            action,
            amount,
            next,
            action === "repay" ? amount : 0,
            id,
            expected,
            action,
            amount,
            ...args,
          ),
          transitionGuard(env, claim),
          stmt(
            env,
            "INSERT INTO bon_audit(id,bon_id,actor_id,action,amount,from_status,to_status,repaid_amount,created_at,claim) SELECT ?,id,?,?,?, ?,status,repaid_amount,?,? FROM bon WHERE id=? AND " +
              guard,
            crypto.randomUUID(),
            user.id,
            action,
            action === "disburse" ? target.amount : amount,
            expected,
            created,
            claim,
            id,
            ...args,
          ),
          stmt(
            env,
            "UPDATE idempotency SET response=(SELECT json_object('record',json_object('id',b.id,'employeeId',b.employee_id,'employeeName',u.name,'amount',b.amount,'note',b.note,'status',b.status,'repaidAmount',b.repaid_amount,'createdAt',b.created_at)) FROM bon b JOIN users u ON u.id=b.employee_id WHERE b.id=?) WHERE claim=?",
            id,
            claim,
          ),
        ],
      };
    },
  );
}
async function employees(request, env, user, id) {
  owner(user);
  if (request.method === "GET" && !id) {
    const { limit, offset } = pagination(new URL(request.url));
    const rows = await all(
      env,
      "SELECT " +
        USER_COLUMNS +
        " FROM users WHERE role='employee' ORDER BY name,id LIMIT ? OFFSET ?",
      limit + 1,
      offset,
    );
    const hasMore = rows.length > limit;
    return ok({
      employees: rows.slice(0, limit).map(publicUser),
      pagination: {
        limit,
        offset,
        hasMore,
        nextOffset: hasMore ? offset + limit : null,
      },
    });
  }
  if (request.method === "POST" && !id) {
    const data = await json(request, ["name", "username", "password"]);
    const u = {
      id: crypto.randomUUID(),
      name: name(data.name),
      username: username(data.username),
      role: "employee",
      active: true,
    };
    const hash = await hashPassword(password(data.password));
    try {
      await stmt(
        env,
        "INSERT INTO users(id,name,username,password_hash,role,created_at) VALUES(?,?,?,?,?,?)",
        u.id,
        u.name,
        u.username,
        hash,
        "employee",
        now(),
      ).run();
    } catch (e) {
      if (/unique/i.test(String(e)))
        fail(409, "username_taken", "Username unavailable.");
      throw e;
    }
    return ok({ user: u }, 201);
  }
  if (request.method === "PATCH" && id) {
    const data = await json(request, ["name", "active", "password"]);
    if (!Object.keys(data).length)
      fail(400, "invalid_input", "Provide an employee update.");
    const u = await first(
      env,
      "SELECT " + USER_COLUMNS + " FROM users WHERE id=? AND role='employee'",
      id,
    );
    if (!u) fail(404, "not_found", "Employee not found.");
    if (data.active !== undefined && typeof data.active !== "boolean")
      fail(400, "invalid_input", "Active must be a boolean.");
    const fields = [],
      args = [];
    if (data.name !== undefined) {
      fields.push("name=?");
      args.push(name(data.name));
    }
    if (data.active !== undefined) {
      fields.push("active=?");
      args.push(data.active ? 1 : 0);
    }
    if (data.password !== undefined) {
      fields.push("password_hash=?");
      args.push(await hashPassword(password(data.password)));
    }
    const operations = [
      stmt(
        env,
        "UPDATE users SET " +
          fields.join(",") +
          " WHERE id=? AND role='employee'",
        ...args,
        id,
      ),
    ];
    if (data.password !== undefined || data.active !== undefined)
      operations.push(stmt(env, "DELETE FROM sessions WHERE user_id=?", id));
    await env.DB.batch(operations);
    return ok({
      user: publicUser(
        await first(
          env,
          "SELECT " + USER_COLUMNS + " FROM users WHERE id=?",
          id,
        ),
      ),
    });
  }
  fail(404, "not_found", "Route not found.");
}
async function dashboard(env, user) {
  const scope = user.role === "employee" ? " AND employee_id=?" : "",
    args = user.role === "employee" ? [user.id] : [];
  const employeeCount =
    user.role === "owner"
      ? (
          await first(
            env,
            "SELECT COUNT(*) AS n FROM users WHERE role='employee' AND active=1",
          )
        ).n
      : 1;
  const checkedInCount = (
    await first(
      env,
      "SELECT COUNT(*) AS n FROM attendance_state a JOIN users u ON u.id=a.employee_id WHERE a.last_kind='check_in' AND u.active=1" +
        scope,
      ...args,
    )
  ).n;
  const summary = await first(
    env,
    "SELECT SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) AS pendingBonCount,COALESCE(SUM(CASE WHEN status='disbursed' THEN amount-repaid_amount ELSE 0 END),0) AS outstandingAmount FROM bon WHERE 1=1" +
      scope,
    ...args,
  );
  return ok({
    summary: {
      employeeCount,
      checkedInCount,
      pendingBonCount: summary.pendingBonCount || 0,
      outstandingAmount: summary.outstandingAmount,
    },
    attendance: (
      await listRecords(
        env,
        user,
        new URL("https://internal/?limit=10"),
        "attendance",
      )
    ).attendance,
    bon: (
      await listRecords(env, user, new URL("https://internal/?limit=10"), "bon")
    ).bon,
  });
}
async function route(request, env) {
  const url = new URL(request.url),
    path = url.pathname,
    method = request.method;
  if (method === "GET" && path === "/v1/workspace")
    return reply(await workspace(env));
  if (method === "POST" && path === "/v1/setup/owner")
    return setupOwner(request, env);
  if (method === "POST" && path === "/v1/auth/login")
    return login(request, env);
  const user = await authenticate(request, env);
  if (method === "GET" && path === "/v1/auth/me") {
    const { tokenHash, ...safe } = user;
    return ok({ user: safe });
  }
  if (method === "POST" && path === "/v1/auth/logout") {
    await stmt(
      env,
      "DELETE FROM sessions WHERE token_hash=?",
      user.tokenHash,
    ).run();
    return ok({});
  }
  if (method === "GET" && path === "/v1/dashboard") return dashboard(env, user);
  const employeePath = path.match(/^\/v1\/employees(?:\/([^/]+))?$/);
  if (employeePath) return employees(request, env, user, employeePath[1]);
  if (method === "GET" && path === "/v1/attendance")
    return ok(await listRecords(env, user, url, "attendance"));
  if (method === "POST" && path === "/v1/attendance")
    return attendanceCreate(request, env, user);
  const photo = path.match(/^\/v1\/attendance\/([^/]+)\/photo$/);
  if (method === "GET" && photo) {
    const row = await first(
      env,
      "SELECT * FROM attendance WHERE id=?" +
        (user.role === "employee" ? " AND employee_id=?" : ""),
      photo[1],
      ...(user.role === "employee" ? [user.id] : []),
    );
    if (!row?.photo_key) fail(404, "not_found", "Photo not found.");
    const object = await env.PHOTOS.get(row.photo_key);
    if (!object) fail(404, "not_found", "Photo not found.");
    return new Response(object.body, {
      headers: {
        "Content-Type": row.photo_type,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
        "Content-Disposition": "inline",
      },
    });
  }
  if (method === "GET" && path === "/v1/bon")
    return ok(await listRecords(env, user, url, "bon"));
  if (method === "POST" && path === "/v1/bon")
    return bonCreate(request, env, user);
  const action = path.match(/^\/v1\/bon\/([^/]+)\/actions$/);
  if (method === "POST" && action)
    return bonAction(request, env, user, action[1]);
  fail(404, "not_found", "Route not found.");
}
async function abandonPhoto(env, key) {
  const result = await stmt(
    env,
    "UPDATE photo_uploads SET state='deleting',checked_at=0 WHERE photo_key=? AND state='pending' AND NOT EXISTS(SELECT 1 FROM attendance WHERE photo_key=?)",
    key,
    key,
  ).run();
  if (result.meta.changes === 1) await env.PHOTOS.delete(key);
}
async function reconcileUploads(env) {
  const seconds = Math.floor(Date.now() / 1000);
  // The state change races atomically with the attendance trigger: a committed reference always wins.
  await stmt(
    env,
    "UPDATE photo_uploads SET state='deleting' WHERE state='pending' AND lease_until<? AND NOT EXISTS(SELECT 1 FROM attendance WHERE attendance.photo_key=photo_uploads.photo_key)",
    seconds,
  ).run();
  const rows = await all(
    env,
    "SELECT photo_key FROM photo_uploads WHERE state='deleting' AND checked_at<? ORDER BY checked_at LIMIT 100",
    seconds - 86400,
  );
  for (const row of rows) {
    const reference = await first(
      env,
      "SELECT id FROM attendance WHERE photo_key=?",
      row.photo_key,
    );
    if (reference) continue;
    await env.PHOTOS.delete(row.photo_key);
    // Keep a tombstone and retry daily: an interrupted PUT may have arrived after a previous delete.
    await stmt(
      env,
      "UPDATE photo_uploads SET checked_at=? WHERE photo_key=? AND state='deleting'",
      seconds,
      row.photo_key,
    ).run();
  }
}
export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      if (!(error instanceof ApiError))
        console.error("Backend operation failed", error?.name);
      return Response.json(
        {
          ok: false,
          error: {
            code: error instanceof ApiError ? error.code : "internal_error",
            message:
              error instanceof ApiError
                ? error.message
                : "Unable to process request.",
          },
        },
        {
          status: error instanceof ApiError ? error.status : 500,
          headers: {
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
          },
        },
      );
    }
  },
  async scheduled(event, env) {
    const stamp = now();
    await env.DB.batch([
      stmt(env, "DELETE FROM sessions WHERE expires_at<=?", stamp),
      stmt(
        env,
        "DELETE FROM login_limits WHERE window_start<?",
        Date.now() - 86400000,
      ),
    ]);
    await reconcileUploads(env);
    const days = integerConfig(env, "PHOTO_RETENTION_DAYS", 0, 0, 36500);
    if (!days) return;
    const cutoff = new Date(Date.now() - days * 86400000).toISOString();
    const rows = await all(
      env,
      "SELECT id,photo_key FROM attendance WHERE recorded_at<? AND photo_key IS NOT NULL LIMIT 100",
      cutoff,
    );
    for (const row of rows) {
      await env.PHOTOS.delete(row.photo_key);
      await stmt(
        env,
        "UPDATE attendance SET photo_key=NULL WHERE id=? AND photo_key=?",
        row.id,
        row.photo_key,
      ).run();
    }
  },
};
