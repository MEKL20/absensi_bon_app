import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createInterface } from "node:readline/promises";
import { hashPassword } from "../src/crypto.js";
import { ownerBootstrapSql } from "./bootstrap-sql.js";
const output = resolve(process.cwd(), "bootstrap-owner.sql");
const rl = createInterface({ input: process.stdin, output: process.stdout });
let secret = "";
try {
  if (!process.stdin.isTTY)
    throw new Error(
      "Run interactively: password input is hidden and never read from command arguments.",
    );
  const name = (await rl.question("Owner display name: ")).trim();
  const username = (await rl.question("Owner username: ")).trim().toLowerCase();
  if (!name || name.length > 100 || !/^[a-z0-9._-]{3,64}$/.test(username))
    throw new Error("Invalid name or username.");
  rl.close();
  secret = await hidden("Owner password (12–128 characters): ");
  const confirm = await hidden("Confirm password: ");
  if (secret.length < 12 || secret.length > 128 || secret !== confirm)
    throw new Error("Password length or confirmation invalid.");
  const hash = await hashPassword(secret);
  secret = "";
  const sql = ownerBootstrapSql({
    id: crypto.randomUUID(),
    name,
    username,
    passwordHash: hash,
    createdAt: new Date().toISOString(),
  });
  await writeFile(output, sql, { flag: "wx", mode: 0o600 });
  console.log(
    "Created ignored bootstrap-owner.sql with a salted credential hash. Apply locally, then remove it.",
  );
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  secret = "";
  rl.close();
}
function hidden(prompt) {
  return new Promise((resolve, reject) => {
    process.stdout.write(prompt);
    let value = "";
    process.stdin.setRawMode(true);
    process.stdin.resume();
    const finish = () => {
      process.stdin.off("data", onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write("\n");
    };
    const onData = (chunk) => {
      for (const char of chunk.toString("utf8")) {
        if (char === "\u0003") {
          finish();
          reject(new Error("Cancelled."));
          return;
        }
        if (char === "\r" || char === "\n") {
          finish();
          resolve(value);
          return;
        }
        if (char === "\u007f" || char === "\b") {
          value = value.slice(0, -1);
        } else if (char >= " " && value.length < 129) {
          value += char;
        }
      }
    };
    process.stdin.on("data", onData);
  });
}
