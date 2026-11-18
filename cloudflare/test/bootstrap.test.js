import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { ownerBootstrapSql } from "../scripts/bootstrap-sql.js";
test("owner bootstrap SQL safely quotes values and never replaces an owner", () => {
  const db = new DatabaseSync(":memory:");
  db.exec(
    readFileSync(
      new URL("../migrations/0001_initial.sql", import.meta.url),
      "utf8",
    ),
  );
  const details = {
    id: "initial",
    name: "O'Brien",
    username: "owner",
    passwordHash: "salted-hash",
    createdAt: new Date().toISOString(),
  };
  db.exec(ownerBootstrapSql(details));
  db.exec(ownerBootstrapSql({ ...details, id: "second", username: "second" }));
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM users").get().n, 1);
  assert.equal(db.prepare("SELECT name FROM users").get().name, "O'Brien");
  db.close();
});
