import crypto from "node:crypto";

export function parseBearerToken(headerValue) {
  if (!headerValue || typeof headerValue !== "string") return null;
  const match = headerValue.match(/^Bearer\s+(.+)$/i);
  const token = match?.[1]?.trim();
  return token ? token : null;
}

export function hashDeviceToken(token, pepper = "") {
  return crypto
    .createHash("sha256")
    .update(`${pepper}${token}`, "utf8")
    .digest("hex");
}

export function makeSessionToken() {
  return `noop_sess_${crypto.randomBytes(32).toString("base64url")}`;
}

export function makePasswordHash(password, salt = crypto.randomBytes(16).toString("base64url")) {
  const hash = crypto.pbkdf2Sync(password, salt, 210_000, 32, "sha256").toString("base64url");
  return { salt, hash };
}

export function verifyPassword(password, salt, expectedHash) {
  if (!password || !salt || !expectedHash) return false;
  const { hash } = makePasswordHash(password, salt);
  const actual = Buffer.from(hash);
  const expected = Buffer.from(expectedHash);
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}
