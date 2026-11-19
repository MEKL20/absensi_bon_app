import test from "node:test";
import assert from "node:assert/strict";
import { pbkdf2Sync } from "node:crypto";
import {
  derivePassword,
  hashPassword,
  matchesSetupToken,
  sha256,
  verifyPassword,
} from "../src/crypto.js";
test("setup digest comparison hashes the token and rejects malformed lengths", async () => {
  const token = "random setup token";
  assert.equal(await matchesSetupToken(token, await sha256(token)), true);
  assert.equal(await matchesSetupToken("different", await sha256(token)), false);
  assert.equal(await matchesSetupToken(token, "a".repeat(63)), false);
  assert.equal(await matchesSetupToken(undefined, await sha256(token)), false);
});
test("standard PBKDF2-SHA256 matches published vector and native Node 600k", async () => {
  assert.equal(
    await derivePassword("password", "73616c74", 1),
    "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
  );
  const salt = "0123456789abcdef0123456789abcdef";
  assert.equal(
    await derivePassword("vector password", salt),
    pbkdf2Sync(
      "vector password",
      Buffer.from(salt, "hex"),
      600000,
      32,
      "sha256",
    ).toString("hex"),
  );
  const hash = await hashPassword("another secure test password");
  assert.equal(
    await verifyPassword("another secure test password", hash),
    true,
  );
  assert.equal(await verifyPassword("incorrect", hash), false);
  assert.equal(await verifyPassword("x", "invalid"), false);
});
