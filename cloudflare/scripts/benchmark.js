import { performance } from "node:perf_hooks";
import { hashPassword, verifyPassword } from "../src/crypto.js";
const password = "local benchmark password; not an account";
const start = performance.now(),
  cpuStart = process.cpuUsage();
const hash = await hashPassword(password);
const hashMs = performance.now() - start;
const verifyStart = performance.now();
if (!(await verifyPassword(password, hash)))
  throw new Error("Credential round-trip failed");
const verifyMs = performance.now() - verifyStart;
const cpu = process.cpuUsage(cpuStart);
console.log(
  JSON.stringify(
    {
      runtime: process.version,
      scheme: "PBKDF2-SHA256 standard 600000 iterations, WebCrypto",
      hashMs: Number(hashMs.toFixed(2)),
      verifyMs: Number(verifyMs.toFixed(2)),
      combinedProcessCpuMs: Number(((cpu.user + cpu.system) / 1000).toFixed(2)),
      note: "Local Node measurement; validate actual Worker CPU before deployment. Free 10ms/request is not assumed viable.",
    },
    null,
    2,
  ),
);
