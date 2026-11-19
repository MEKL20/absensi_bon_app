const encoder = new TextEncoder();
export const HASH_ITERATIONS = 600000;
export const bytesToHex = (bytes) =>
  Array.from(new Uint8Array(bytes), (n) =>
    n.toString(16).padStart(2, "0"),
  ).join("");
export const randomToken = () =>
  bytesToHex(crypto.getRandomValues(new Uint8Array(32)));
export async function sha256(value) {
  return bytesToHex(
    await crypto.subtle.digest(
      "SHA-256",
      typeof value === "string" ? encoder.encode(value) : value,
    ),
  );
}
export async function matchesSetupToken(token, digest) {
  if (typeof token !== "string" || token.length < 1 || token.length > 256)
    return false;
  const actual = encoder.encode(await sha256(token));
  const expected = encoder.encode(digest);
  if (crypto.subtle.timingSafeEqual)
    return crypto.subtle.timingSafeEqual(actual, expected);
  let difference = 0;
  for (let i = 0; i < actual.length; i++) difference |= actual[i] ^ expected[i];
  return difference === 0;
}
export async function derivePassword(
  password,
  salt,
  iterations = HASH_ITERATIONS,
) {
  const bytes = encoder.encode(password),
    saltBytes = Uint8Array.from(salt.match(/../g), (part) =>
      parseInt(part, 16),
    );
  const key = await crypto.subtle.importKey("raw", bytes, "PBKDF2", false, [
    "deriveBits",
  ]);
  return bytesToHex(
    await crypto.subtle.deriveBits(
      { name: "PBKDF2", hash: "SHA-256", iterations, salt: saltBytes },
      key,
      256,
    ),
  );
}
export async function hashPassword(password) {
  const salt = bytesToHex(crypto.getRandomValues(new Uint8Array(16)));
  return (
    "pbkdf2-sha256$v1$600000$" +
    salt +
    "$" +
    (await derivePassword(password, salt))
  );
}
export async function verifyPassword(password, encoded) {
  const parts = encoded.split("$");
  if (
    parts.length !== 5 ||
    parts[0] !== "pbkdf2-sha256" ||
    parts[1] !== "v1" ||
    parts[2] !== "600000" ||
    !/^[0-9a-f]{32}$/.test(parts[3]) ||
    !/^[0-9a-f]{64}$/.test(parts[4])
  )
    return false;
  const actual = await derivePassword(password, parts[3]);
  let diff = 0;
  for (let i = 0; i < actual.length; i++)
    diff |= actual.charCodeAt(i) ^ parts[4].charCodeAt(i);
  return diff === 0;
}
export const DUMMY_HASH =
  "pbkdf2-sha256$v1$600000$00000000000000000000000000000000$" + "0".repeat(64);
